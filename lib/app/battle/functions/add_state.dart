import 'package:chaldea/app/api/atlas.dart';
import 'package:chaldea/app/battle/models/battle.dart';
import 'package:chaldea/app/battle/utils/battle_utils.dart';
import 'package:chaldea/app/battle/utils/buff_utils.dart';
import 'package:chaldea/generated/l10n.dart';
import 'package:chaldea/models/db.dart';
import 'package:chaldea/models/gamedata/gamedata.dart';
import 'package:chaldea/utils/utils.dart';
import '../interactions/td_type_change_selector.dart';

class AddState {
  AddState._();

  static Future<void> addState(
    final BattleData battleData,
    final Buff buff,
    final int funcId,
    final DataVals dataVals,
    final List<BattleServantData> targets, {
    bool isPassive = false,
    final bool isShortBuff = false,
    final bool notActorPassive = false,
    final bool isCommandCode = false,
  }) async {
    final activator = battleData.activator;
    if (dataVals.ProcActive == 1) {
      isPassive = false;
    } else if (dataVals.ProcPassive == 1) {
      isPassive = true;
    }
    for (int i = 0; i < targets.length; i += 1) {
      final target = targets[i];
      final buffData = BuffData(buff, dataVals)
        ..actorUniqueId = activator?.uniqueId
        ..actorName = activator?.lBattleName
        ..notActorPassive = notActorPassive
        ..irremovable |= isPassive || notActorPassive;
      if (isShortBuff) {
        buffData.logicTurn -= 1;
      }
      // enemy Bazett may not contains niceSvt
      if (target.niceSvt?.script?.svtBuffTurnExtend == true || target.svtId == 1001100) {
        if (ConstData.constantStr.extendTurnBuffType.contains(buff.type.id)) {
          buffData.logicTurn += 1;
        }
      }

      if (buff.type.isTdTypeChange) {
        buffData.tdTypeChange = await getTypeChangeTd(battleData, target, buff);
      } else if (buff.type == BuffType.upDamageEventPoint) {
        final pointBuff = battleData.options.pointBuffs.values
            .firstWhereOrNull((pointBuff) => pointBuff.funcIds.isEmpty || pointBuff.funcIds.contains(funcId));
        if (pointBuff == null) {
          continue;
        }
        buffData.param += pointBuff.value;
      }

      await battleData.withBuff(buffData, () async {
        final convertBuff = target
            .getFirstBuffOnActions(battleData, [BuffAction.buffConvert])
            ?.buff
            .script
            .convert
            ?.convertBuffs
            .firstOrNull;
        if (convertBuff != null) {
          buffData.buff = convertBuff;
        }

        await battleData.withTarget(target, () async {
          if (await shouldAddState(battleData, dataVals, activator, target, isCommandCode) &&
              target.isBuffStackable(buffData.buff.buffGroup) &&
              checkSameBuffLimitNum(target, dataVals)) {
            target.addBuff(
              buffData,
              isPassive: isPassive || notActorPassive,
              isCommandCode: isCommandCode,
            );
            battleData.curFuncResults[target.uniqueId] = true;

            if (buff.type == BuffType.addMaxhp) {
              target.gainHp(battleData, dataVals.Value!);
            } else if (buff.type == BuffType.subMaxhp) {
              target.lossHp(dataVals.Value!);
            } else if (buff.type == BuffType.upMaxhp) {
              target.gainHp(battleData, toModifier(target.maxHp * dataVals.Value!).toInt());
            } else if (buff.type == BuffType.downMaxhp) {
              target.lossHp(toModifier(target.maxHp * dataVals.Value!).toInt());
            }
          }
        });
      });
    }
  }

  static bool checkSameBuffLimitNum(
    final BattleServantData target,
    final DataVals dataVals,
  ) {
    return dataVals.SameBuffLimitNum == null ||
        dataVals.SameBuffLimitNum! >
            target.countBuffWithTrait([NiceTrait(id: dataVals.SameBuffLimitTargetIndividuality!)]);
  }

  static Future<bool> shouldAddState(
    final BattleData battleData,
    final DataVals dataVals,
    final BattleServantData? activator,
    final BattleServantData target,
    final bool isCommandCode,
  ) async {
    if (dataVals.ForceAddState == 1 || isCommandCode) {
      return true;
    }

    int functionRate = dataVals.Rate ?? 1000;
    if (functionRate < 0 && battleData.uniqueIdToFuncResultsList.lastOrNull?[target.uniqueId] != true) {
      return false;
    }

    functionRate = functionRate.abs();

    if (await target.hasBuffOnAction(battleData, BuffAction.avoidState)) {
      battleData.battleLogger.debug('${S.current.effect_target}: ${target.lBattleName} - ${S.current.battle_invalid}');
      return false;
    }

    final buffReceiveChance = await target.getBuffValueOnAction(battleData, BuffAction.resistanceState);
    final buffChanceDetails = ConstData.buffActions[BuffAction.grantState]!;
    final buffChance = await activator?.getBuffValueOnAction(battleData, BuffAction.grantState) ??
        capBuffValue(buffChanceDetails, 0, Maths.min(buffChanceDetails.maxRate));

    final activationRate = functionRate + buffChance;
    final resistRate = buffReceiveChance;

    final success = await battleData.canActivateFunction(activationRate - resistRate);

    final resultsString = success
        ? S.current.success
        : resistRate > 0
            ? 'GUARD'
            : 'MISS';

    battleData.battleLogger.debug('${S.current.effect_target}: ${target.lBattleName} - '
        '$resultsString'
        '${battleData.options.tailoredExecution ? '' : ' [($activationRate - $resistRate) vs ${battleData.options.threshold}]'}');

    return success;
  }

  static Future<NiceTd?> getTypeChangeTd(BattleData battleData, BattleServantData svt, Buff buff) async {
    final NiceTd? baseTd = svt.getBaseTD();
    if (baseTd == null) return null;
    if (!buff.type.isTdTypeChange) return null;
    final excludeTypes = baseTd.script?.excludeTdChangeTypes;
    final tdTypeChangeIDs = baseTd.script?.tdTypeChangeIDs;
    if (tdTypeChangeIDs == null || tdTypeChangeIDs.isEmpty) return null;

    final validCardTypes = <CardType>[CardType.arts, CardType.buster, CardType.quick];
    final cardIdTypeMap = {for (final c in validCardTypes) c.id: c};

    if (excludeTypes != null && excludeTypes.isNotEmpty) {
      validCardTypes.removeWhere((e) => excludeTypes.contains(e.id));
    }
    final tdExistTypes =
        cardIdTypeMap.entries.where((e) => e.key <= tdTypeChangeIDs.length).map((e) => e.value).toList();
    validCardTypes.removeWhere((e) => !tdExistTypes.contains(e));
    if (validCardTypes.isEmpty) return null;

    // in UI, Q/A/B order
    CardType? targetType;
    if (buff.type == BuffType.tdTypeChangeArts) {
      targetType = CardType.arts;
    } else if (buff.type == BuffType.tdTypeChangeBuster) {
      targetType = CardType.buster;
    } else if (buff.type == BuffType.tdTypeChangeQuick) {
      targetType = CardType.quick;
    } else if (buff.type == BuffType.tdTypeChange) {
      if (battleData.delegate?.tdTypeChange != null) {
        targetType = await battleData.delegate!.tdTypeChange!(svt, validCardTypes);
      } else if (battleData.mounted) {
        targetType = await TdTypeChangeSelector.show(battleData, validCardTypes);
        if (targetType != null) {
          battleData.replayDataRecord.tdTypeChanges.add(targetType);
        }
      }
    }
    NiceTd? targetTd;
    if (targetType != null && validCardTypes.contains(targetType)) {
      // start from Q/A/B=1/2/3 -> index 0/1/2
      final tdId = tdTypeChangeIDs.getOrNull(targetType.id - 1);
      if (tdId == null) return null;

      final List<NiceTd?> tds = svt.isPlayer
          ? (svt.playerSvtData?.svt?.noblePhantasms ?? [])
          : (svt.niceSvt?.noblePhantasms ?? [svt.niceEnemy?.noblePhantasm.noblePhantasm]);
      targetTd = tds.lastWhereOrNull((e) => e?.id == tdId);
      targetTd ??= await showEasyLoading(() => AtlasApi.td(tdId, svtId: svt.svtId), mask: true);
    }
    return targetTd;
  }
}
