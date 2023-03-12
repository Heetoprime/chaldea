import 'package:chaldea/models/models.dart';

class CardDmgOption {
  EnemyData? enemyData;
  PlayerSvtData? playerSvtData;
  List<BuffPreset> buffs = [];
  Map<FuncType, int> superNPDmg = {};
}

class EnemyData {
  int svtId = 0;
  int limitCount = 0;
  List<int> individuality = [];
  SvtClass svtClass = SvtClass.ALL;
  Attribute attribute = Attribute.void_;
  int rarity = 0;
  int hp = 0;
}

class PlayerSvtData {
  Servant? svt;
  int ascensionPhase = 4;
  List<int> skillLvs = [10, 10, 10];
  List<int> skillStrengthenLvs = [1, 1, 1];
  List<int> appendLvs = [0, 0, 0];
  int npLv = 5;
  int npStrengthenLv = 1;
  int lv = -1; // -1=mlb, 90, 100, 120
  int atkFou = 1000;
  int hpFou = 1000;

  CraftEssence? ce;
  bool ceLimitBreak = false;
  int ceLv = 0;

  List<int> cardStrengthens = [0, 0, 0, 0, 0];
  List<int> commandCodeIds = [-1, -1, -1, -1, -1];

  PlayerSvtData.base();

  PlayerSvtData.fromSvt(this.svt);

  PlayerSvtData(final int svtId) : svt = db.gameData.servantsById[svtId];
}

class MysticCodeData {
  MysticCode mysticCode = db.gameData.mysticCodes[210]!;
  int level = 10;
}

class BuffPreset {
  int addAtk = 0;
}