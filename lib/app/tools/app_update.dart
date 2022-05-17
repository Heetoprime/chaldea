import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:chaldea/app/api/hosts.dart';
import 'package:chaldea/generated/l10n.dart';
import 'package:chaldea/models/models.dart';
import 'package:chaldea/models/version.dart';
import 'package:chaldea/packages/app_info.dart';
import 'package:chaldea/packages/network.dart';
import 'package:chaldea/packages/packages.dart';
import 'package:chaldea/utils/utils.dart';
import 'package:chaldea/widgets/widgets.dart';

class AppUpdater {
  const AppUpdater._();

  static Completer<AppUpdateDetail?>? _checkCmpl;
  static Completer<String?>? _downloadCmpl;

  static Future<void> backgroundUpdate() async {
    if (network.unavailable) return;
    final detail = await check();
    if (detail == null) return;
    final savePath = await download(detail);
    if (savePath == null) return;
    final update =
        await showUpdateAlert(detail.release.version!, detail.release.body);
    if (update == true) installUpdate(savePath);
  }

  static Future<void> checkAppStoreUpdate() async {
    // use https and set UA, or the fetched info may be outdated
    // this http request always return iOS version result
    final response = await Dio()
        .get('https://itunes.apple.com/lookup?bundleId=$kPackageName',
            options: Options(responseType: ResponseType.plain, headers: {
              'User-Agent': "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
                  " AppleWebKit/537.36 (KHTML, like Gecko)"
                  " Chrome/88.0.4324.146"
                  " Safari/537.36 Edg/88.0.705.62"
            }));
    // print(response.data);
    final jsonData = jsonDecode(response.data.toString().trim());
    // logger.d(jsonData);
    final result = jsonData['results'][0];
    AppVersion? version = AppVersion.tryParse(result['version'] ?? '');
    if (version != null && version > AppInfo.version) {
      db.runtimeData.upgradableVersion = version;
    }
  }

  static Future showUpdateAlert(AppVersion version, String body) {
    return showDialog(
      context: kAppKey.currentContext!,
      useRootNavigator: false,
      builder: (context) {
        return SimpleCancelOkDialog(
          title: Text('v${version.versionString}'),
          content: Text(body),
          confirmText: S.current.update,
        );
      },
    );
  }

  static Future showInstallAlert(AppVersion version) {
    String body = 'Update downloaded.';
    if (PlatformU.isWindows || PlatformU.isLinux) {
      body += '\nExtract zip and replace the old version';
    }
    return showDialog(
      context: kAppKey.currentContext!,
      useRootNavigator: false,
      builder: (context) {
        return SimpleCancelOkDialog(
          title: Text('v${version.versionString}'),
          content: Text(body),
          confirmText: S.current.install,
        );
      },
    );
  }

  static Future<AppUpdateDetail?> check() async {
    if (_checkCmpl != null) return _checkCmpl!.future;
    _checkCmpl = Completer();
    latestAppRelease()
        .then((value) => _checkCmpl!.complete(value))
        .catchError((e, s) {
      logger.e('check app update failed', e, s);
      _checkCmpl!.complete(null);
    }).whenComplete(() => _checkCmpl = null);
    return _checkCmpl?.future;
  }

  static Future<String?> download(AppUpdateDetail detail) async {
    if (_downloadCmpl != null) return _downloadCmpl!.future;
    _downloadCmpl = Completer();
    _downloadFileWithCheck(detail)
        .then((value) => _downloadCmpl!.complete(value))
        .catchError((e, s) {
      logger.e('download app release failed', e, s);
      _downloadCmpl!.complete(null);
    }).whenComplete(() => _downloadCmpl = null);
    return _downloadCmpl?.future;
  }

  static Future<void> installUpdate(String fp) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (PlatformU.isAndroid) {
      final result = await OpenFile.open(fp);
      print('open result: ${result.type}, ${result.message}');
      // await InstallPlugin.installApk(saveFp, AppInfo.packageName);
    } else if (PlatformU.isLinux || PlatformU.isWindows) {
      final result = await OpenFile.open(dirname(fp));
      logger.d('open result: ${result.type}, ${result.message}');
    } else if (PlatformU.isApple) {
      launch(kAppStoreLink);
    }
  }

  static Future<AppUpdateDetail?> latestAppRelease() async {
    String? os;
    if (PlatformU.isAndroid) {
      os = 'android';
    } else if (PlatformU.isWindows) {
      os = 'windows';
    } else if (PlatformU.isLinux) {
      os = 'linux';
    } else if (kDebugMode) {
      os = 'windows';
    }
    if (os == null) return null;
    final releases = await _githubReleases('chaldea-center', 'chaldea');
    AppUpdateDetail? _latest;
    for (final release in releases) {
      if (release.version == null ||
          (release.version! <= AppInfo.version && !kDebugMode)) {
        continue;
      }
      final installer = release.assets.firstWhereOrNull(
          (e) => e.name.contains(os!) && !e.name.contains('sha1'));
      final checksum = release.assets.firstWhereOrNull(
          (e) => e.name.contains(os!) && e.name.contains('sha1'));
      if (installer == null || checksum == null) continue;
      if (_latest == null || _latest.release.version! < release.version!) {
        _latest = AppUpdateDetail(
            release: release, installer: installer, checksum: checksum);
      }
    }
    db.runtimeData.releaseDetail = _latest;
    return _latest;
  }

  static Future<String?> _downloadFileWithCheck(AppUpdateDetail detail) async {
    String checksum = (await Dio().get(detail.checksum.downloadUrl,
            options: Options(responseType: ResponseType.plain)))
        .data;
    checksum = checksum.toLowerCase();
    String savePath =
        joinPaths(db.paths.tempDir, 'installer', detail.installer.name);
    final file = File(savePath);
    if (await file.exists()) {
      final localChecksum =
          sha1.convert(await file.readAsBytes()).toString().toLowerCase();
      if (localChecksum == checksum) return savePath;
    }
    final resp = await Dio().get(detail.installer.downloadUrl,
        options: Options(responseType: ResponseType.bytes));
    final data = List<int>.from(resp.data);
    if (sha1.convert(data).toString().toLowerCase() == checksum) {
      file.createSync(recursive: true);
      await file.writeAsBytes(data);
      return savePath;
    } else {
      logger.e('checksum mismatch');
    }
    return null;
  }
}

class AppUpdateDetail {
  final _Release release;
  final _Asset installer;
  final _Asset checksum;

  AppUpdateDetail({
    required this.release,
    required this.installer,
    required this.checksum,
  });
}

Future<List<_Release>> _githubReleases(String org, String repo) async {
  final dio = Dio();
  final root = db.settings.proxyServer
      ? '${Hosts.kWorkerHostCN}/proxy/github/api.github.com'
      : 'https://api.github.com';
  final resp = await dio.get('$root/repos/$org/$repo/releases');
  return (resp.data as List).map((e) => _Release.fromJson(e)).toList();
}

class _Release {
  final String name;
  final DateTime publishedAt;
  final String body;
  final bool prerelease;
  final List<_Asset> assets;
  final AppVersion? version;
  _Release({
    required this.name,
    required this.publishedAt,
    required this.body,
    required this.prerelease,
    required this.assets,
  }) : version = AppVersion.tryParse(name) {
    for (var asset in assets) {
      asset.release = this;
    }
  }

  factory _Release.fromJson(Map data) {
    return _Release(
      name: data['name'],
      publishedAt: DateTime.parse(data['published_at']),
      body: (data['body'] as String).replaceAll('\r\n', '\n'),
      prerelease: data['prerelease'],
      assets: (data['assets'] as List).map((e) => _Asset.fromJson(e)).toList(),
    );
  }
}

class _Asset {
  final String name;
  final int size;
  final String browserDownloadUrl;

  late final _Release release;
  _Asset({
    required this.name,
    required this.size,
    required this.browserDownloadUrl,
  });

  String get downloadUrl {
    return db.settings.proxyServer ? proxyUrl : browserDownloadUrl;
  }

  String get proxyUrl {
    return browserDownloadUrl.replaceFirst('https://github.com/',
        Hosts.kWorkerHostCN + '/proxy/github/github.com/');
  }

  factory _Asset.fromJson(Map data) {
    return _Asset(
        name: data['name'],
        size: data['size'],
        browserDownloadUrl: data['browser_download_url']);
  }
}