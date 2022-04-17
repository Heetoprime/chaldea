import 'package:chaldea/app/tools/localized_base.dart';
import 'package:chaldea/generated/l10n.dart';
import 'package:chaldea/models/models.dart';
import 'package:chaldea/packages/split_route/split_route.dart';
import 'package:chaldea/widgets/widgets.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../home/subpage/account_page.dart';
import '../home/subpage/user_data_page.dart';
import 'import_fgo_simu_material_page.dart';
import 'import_https_page.dart';
import 'v1_backup.dart';

class ImportPageHome extends StatefulWidget {
  ImportPageHome({Key? key}) : super(key: key);

  @override
  _ImportPageHomeState createState() => _ImportPageHomeState();
}

class _ImportPageHomeState extends State<ImportPageHome> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const MasterBackButton(),
        title: Text(S.current.import_data),
      ),
      body: ListView(
        children: divideTiles([
          ListTile(
            title: Center(
                child: Text(S.current.cur_account + ': ' + db.curUser.name)),
            onTap: () {
              SplitRoute.push(context, AccountPage(), popDetail: true)
                  .then((_) {
                if (mounted) setState(() {});
              });
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: Text(LocalizedText.of(
                    chs: '本应用的备份',
                    jpn: 'このアプリのバックアップ',
                    eng: 'Chaldea App Backup',
                    kor: '칼데아 앱 백업') +
                ' (V2)'),
            subtitle: const Text('userdata.json/*.json'),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {
              router.push(child: UserDataPage());
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_backup_restore),
            title: const Text('Backup of Chaldea App(V1)'),
            subtitle: const Text('userdata.json/*.json'),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {
              router.push(child: OldVersionDataImport());
            },
          ),
          ListTile(
            leading: const Icon(Icons.http),
            title: Text(LocalizedText.of(
                chs: 'HTTPS抓包',
                jpn: 'HTTPSスニッフィング',
                eng: 'HTTPS Sniffing',
                kor: 'HTTPS 스나이핑')),
            subtitle: Text(LocalizedText.of(
                chs: '(国/台/日/美)借助抓包工具获取账号登陆时的数据',
                jpn: '(JP/NA/CN/TW)アカウントがログインしているときにデータを取得する',
                eng:
                    '(NA/JP/CN/TW)Capture the data when the account is logging in',
                kor: '(NA/JP/CN/TW)계정 로그인 시 데이터 캡쳐, KR은 지원하지 않습니다')),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {
              router.push(child: ImportHttpPage());
            },
          ),
          // ListTile(
          //   leading: const Icon(Icons.compare_arrows),
          //   title: Text(LocalizedText.of(
          //       chs: 'Guda数据',
          //       jpn: 'Gudaデータ',
          //       eng: 'Guda Data',
          //       kor: '구다 데이터')),
          //   subtitle: const Text('Guda@iOS'),
          //   trailing: const Icon(Icons.keyboard_arrow_right),
          //   onTap: () {
          //     SplitRoute.push(context, ImportGudaPage(), popDetail: true);
          //   },
          // ),
          ListTile(
            leading: const Icon(Icons.compare_arrows),
            title: const Text('FGO Simulator-Material'),
            subtitle: const Text('https://fgosim.github.io/Material/'),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {
              router.push(child: ImportFgoSimuMaterialPage());
            },
          ),

          const SHeader('Coming soon...'),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.screenshot),
            title: Text(LocalizedText.of(
                chs: '素材截图解析',
                jpn: 'アイテムのスクリーンショット',
                eng: 'Items Screenshots',
                kor: '아이템 스크린샷')),
            subtitle: Text(LocalizedText.of(
                chs: '个人空间 - 道具一览',
                jpn: 'マイルーム - 所持アイテム一覧',
                eng: 'My Room - Item List',
                kor: '마이룸 - 아이템 리스트')),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {},
          ),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.screenshot),
            title: Text(LocalizedText.of(
                chs: '主动技能截图解析',
                jpn: '保有スキルのスクリーンショット',
                eng: 'Active Skill Screenshots',
                kor: '액티브 스킬 스크린샷')),
            subtitle: Text(LocalizedText.of(
                chs: '强化 - 从者技能强化',
                jpn: '強化 - サーヴァントスキル強化 ',
                eng: 'Enhance - Skill',
                kor: '강화 - 서번트 스킬 강화')),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {},
          ),
          ListTile(
            enabled: false,
            leading: const Icon(Icons.screenshot),
            title: Text(LocalizedText.of(
                chs: '附加技能截图解析',
                jpn: 'アペンドスキルのスクリーンショット',
                eng: 'Append Skill Screenshots',
                kor: '어펜드 스킬 스크린샷')),
            subtitle: Text(LocalizedText.of(
                chs: '强化 - 被动技能强化',
                jpn: '強化 - アペンドスキル強化 ',
                eng: 'Enhance - Append Skill',
                kor: '강화 - 어펜드 스킬 강화')),
            trailing: const Icon(Icons.keyboard_arrow_right),
            onTap: () {},
          ),
        ], bottom: true),
      ),
    );
  }
}
