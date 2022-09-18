import 'dart:io';

/// `dart ./scripts/patch_before_build.dart ${{ matrix.target }} ${{ github.ref }}`
void main(List<String> args) {
  print('Patch before build, args=$args');
  _patchFlutterFadeInImage();

  final String target = args[0];
  final String ref = args[1];
  if (target == 'windows') {
    _patchWindows();
    return;
  } else if (target == 'linux') {
    _patchLinux();
  } else if (target == 'android' && ref == 'refs/heads/main') {
    _patchAndroidPreview();
  }
}

void _patchFlutterFadeInImage() {
  print('Patching flutter 3.3.1 FadeInImage bug...');
  print('Dart: ${Platform.resolvedExecutable}');
  final dartFp = Uri.file(Platform.resolvedExecutable);
  final targetFp = dartFp.replace(pathSegments: [
    ...dartFp.pathSegments.sublist(0, dartFp.pathSegments.length - 5),
    ...'packages/flutter/lib/src/widgets/fade_in_image.dart'.split('/')
  ]);
  print(targetFp.toFilePath());
  final targetFile = File(targetFp.toFilePath());
  assert(targetFile.existsSync());
  String content = targetFile.readAsStringSync();
  const s1 =
      '    if (widget.wasSynchronouslyLoaded || _placeholderOpacityAnimation!.isCompleted) {';
  const s2 = '''    if (widget.wasSynchronouslyLoaded ||
        (_placeholderOpacityAnimation?.isCompleted ?? true)) {''';
  assert(content.contains(s1));
  targetFile
      .writeAsStringSync(targetFile.readAsStringSync().replaceFirst(s1, s2));
  return;
}

void _patchWindows() {
  // print('patching quickjs.c');
  // final qjs = File(
  //     r'windows\flutter\ephemeral\.plugin_symlinks\flutter_qjs\cxx\quickjs\quickjs.c');
  // String contents = qjs.readAsStringSync();
  // contents = contents.replaceFirst('#pragma function (floor)',
  //     '#pragma function (floor)\n#pragma function (log2)');
  // qjs.writeAsStringSync(contents);
}

void _patchLinux() {
  print('remove just_audio_libwinmedia for linux');
  final pubspec = File('pubspec.yaml');
  String contents = pubspec.readAsStringSync();
  contents = contents.replaceFirst(
      'just_audio_libwinmedia', '# just_audio_libwinmedia');
  pubspec.writeAsStringSync(contents);
}

void _patchAndroidPreview() {
  final buildFile = File('android/app/build.gradle');
  print('Patching ${buildFile.path}...');
  String contents = buildFile.readAsStringSync();
  // all patches start with "// "
  List<String> patches = [
    '// applicationIdSuffix ".preview"',
    '// resValue "string", "app_name", "Chaldea Preview"'
  ];
  for (final patch in patches) {
    if (!contents.contains(patch)) {
      throw "app/build.gradle doesn't contain '$patch'";
    }
    contents = contents.replaceFirst(patch, patch.substring(2));
  }
  buildFile.writeAsStringSync(contents);
  print('set applicationIdSuffix=.preview and app_name=Chaldea Preview');
}
