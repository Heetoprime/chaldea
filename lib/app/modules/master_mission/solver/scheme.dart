import 'package:flutter/material.dart';

import 'package:chaldea/app/descriptors/cond_target_num.dart';
import 'package:chaldea/models/models.dart';

class CustomMissionCond {
  CustomMissionType type;
  List<int> targetIds;
  bool _useAnd;
  set useAnd(bool v) => _useAnd = v;
  bool get useAnd => fixedLogicType ?? _useAnd;

  CustomMissionCond({
    required this.type,
    required this.targetIds,
    required bool useAnd,
  }) : _useAnd = useAnd;

  bool? get fixedLogicType {
    switch (type) {
      case CustomMissionType.trait:
      case CustomMissionType.questTrait:
        return null;
      case CustomMissionType.quest:
      case CustomMissionType.enemy:
      case CustomMissionType.enemyClass:
      case CustomMissionType.servantClass:
      case CustomMissionType.enemyNotServantClass:
        return false;
    }
  }

  CustomMissionCond copy() {
    return CustomMissionCond(
      type: type,
      targetIds: targetIds.toList(),
      useAnd: useAnd,
    );
  }

  @override
  int get hashCode => Object.hash(type, _useAnd, Object.hashAll(targetIds));

  @override
  bool operator ==(Object other) {
    return other is CustomMissionCond && other.hashCode == hashCode;
  }
}

class CustomMission {
  int count;

  /// only if [CustomMissionType.trait], can have multi conds and [condAnd]
  List<CustomMissionCond> conds;
  bool condAnd;
  bool enemyDeckOnly;

  final String? originDetail;

  CustomMission({
    required this.count,
    required this.conds,
    this.condAnd = false,
    this.enemyDeckOnly = true,
    this.originDetail,
  });

  static CustomMission? fromEventMission(EventMission? eventMission) {
    if (eventMission == null) return null;
    // only return the first clear condition
    for (final cond in eventMission.conds) {
      if (cond.missionProgressType != MissionProgressType.clear ||
          cond.condType != CondType.missionConditionDetail ||
          cond.details?.isNotEmpty != true) {
        continue;
      }
      List<CustomMissionCond> conds = [];
      for (final detail in cond.details!) {
        final type = kDetailCondMapping[detail.missionCondType];
        if (type == null) continue;
        if (type == CustomMissionType.quest && detail.targetIds.length == 1 && detail.targetIds.first == 0) {
          // any quest
          continue;
        }
        bool useAnd;
        switch (type) {
          case CustomMissionType.trait:
            if (detail.missionCondType == DetailCondType.enemyIndividualityKillNum.id) {
              useAnd = false;
            } else if (detail.missionCondType == DetailCondType.defeatEnemyIndividuality.id) {
              useAnd = true;
            } else {
              useAnd = true;
            }
            break;
          case CustomMissionType.questTrait:
            useAnd = false;
            break;
          case CustomMissionType.quest:
          case CustomMissionType.enemy:
          case CustomMissionType.enemyClass:
          case CustomMissionType.servantClass:
          case CustomMissionType.enemyNotServantClass:
            useAnd = false;
            break;
        }
        conds.add(CustomMissionCond(type: type, targetIds: detail.targetIds.toList(), useAnd: useAnd));
      }
      if (conds.isEmpty) continue;

      return CustomMission(
        count: cond.targetNum,
        conds: conds,
        condAnd: false,
        originDetail: '${eventMission.dispNo}. ${cond.conditionMessage}',
      );
    }
    return null;
  }

  CustomMission copy() {
    return CustomMission(
      count: count,
      conds: conds.map((e) => e.copy()).toList(),
      condAnd: condAnd,
      enemyDeckOnly: enemyDeckOnly,
      originDetail: originDetail,
    );
  }

  Widget buildDescriptor(BuildContext context, {double? textScaleFactor}) {
    return CondTargetNumDescriptor(
      condType: CondType.missionConditionDetail,
      targetNum: count,
      targetIds: List.generate(conds.length, (index) => index),
      details: List.generate(conds.length, (index) {
        final cond = conds[index];
        return EventMissionConditionDetail(
          id: index,
          missionTargetId: 0,
          missionCondType: kDetailCondMappingReverse[cond.type] ?? -1,
          targetIds: cond.targetIds,
          logicType: 1,
          conditionLinkType: DetailMissionCondLinkType.missionStart,
          useAnd: cond.useAnd,
        );
      }),
      textScaleFactor: textScaleFactor ?? 0.9,
      useAnd: condAnd,
    );
  }

  static final Map<int, CustomMissionType> kDetailCondMapping = <DetailCondType, CustomMissionType>{
    DetailCondType.questClearNum1: CustomMissionType.quest,
    DetailCondType.questClearNum2: CustomMissionType.quest,
    DetailCondType.enemyKillNum: CustomMissionType.enemy,
    DetailCondType.targetQuestEnemyKillNum: CustomMissionType.enemy,
    DetailCondType.defeatEnemyIndividuality: CustomMissionType.trait,
    DetailCondType.enemyIndividualityKillNum: CustomMissionType.trait,
    DetailCondType.targetQuestEnemyIndividualityKillNum: CustomMissionType.enemy,
    DetailCondType.defeatServantClass: CustomMissionType.servantClass,
    DetailCondType.defeatEnemyClass: CustomMissionType.enemyClass,
    DetailCondType.defeatEnemyNotServantClass: CustomMissionType.enemyNotServantClass,
  }.map((key, value) => MapEntry(key.id, value));

  static final Map<CustomMissionType, int> kDetailCondMappingReverse = <CustomMissionType, DetailCondType>{
    CustomMissionType.quest: DetailCondType.questClearNum1,
    CustomMissionType.enemy: DetailCondType.enemyKillNum,
    CustomMissionType.trait: DetailCondType.defeatEnemyIndividuality,
    CustomMissionType.servantClass: DetailCondType.defeatServantClass,
    CustomMissionType.enemyClass: DetailCondType.defeatEnemyClass,
    CustomMissionType.enemyNotServantClass: DetailCondType.defeatEnemyNotServantClass,
    CustomMissionType.questTrait: DetailCondType.questClearIndividuality,
  }.map((key, value) => MapEntry(key, value.id));
}

class MissionSolverOptions {
  static const kTraumClassEnemyIds = [
    // Class enemies
    9943750, 9943760, 9943770, 9943780, 9943790, 9943800, 9943810,
    // 粛正騎士＠剣(近衛騎士), 黒武者(Class Saber)
    9936730, 9939610,
  ];

  bool addNotBasedOnSvtForTraum;
  MissionSolverOptions({
    this.addNotBasedOnSvtForTraum = false,
  });
}

class MissionSolution {
  final Map<int, int> result;
  final List<CustomMission> missions;
  final Map<int, QuestPhase> quests;
  final MissionSolverOptions options;
  final Region region;

  MissionSolution({
    required this.result,
    required this.missions,
    required List<QuestPhase> quests,
    required this.options,
    this.region = Region.jp,
  }) : quests = {for (final quest in quests) quest.id: quest};
}

enum CustomMissionType {
  trait,
  enemyClass,
  servantClass,
  enemyNotServantClass,
  enemy,
  quest,
  questTrait,
  ;

  bool get isQuestType => this == CustomMissionType.questTrait || this == CustomMissionType.quest;
  bool get isEnemyType => !isQuestType;
  bool get isTraitType => this == CustomMissionType.trait || this == CustomMissionType.questTrait;
  bool get isClassType =>
      this == CustomMissionType.enemyClass ||
      this == CustomMissionType.servantClass ||
      this == CustomMissionType.enemyNotServantClass;
}
