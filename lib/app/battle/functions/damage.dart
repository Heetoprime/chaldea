import 'dart:math';

import 'package:chaldea/app/battle/models/battle.dart';
import 'package:chaldea/app/battle/models/command_card.dart';
import 'package:chaldea/app/battle/models/svt_entity.dart';
import 'package:chaldea/app/battle/utils/battle_utils.dart';
import 'package:chaldea/app/battle/utils/buff_utils.dart';
import 'package:chaldea/app/modules/battle/svt_option_editor.dart';
import 'package:chaldea/generated/l10n.dart';
import 'package:chaldea/models/db.dart';
import 'package:chaldea/models/gamedata/gamedata.dart';
import 'package:chaldea/utils/utils.dart';
import 'package:chaldea/widgets/widgets.dart';
import '../utils/_dialogs.dart';
import '../utils/battle_logger.dart';

enum NpSpecificMode { normal, individualSum, rarity }

class Damage {
  Damage._();

  static final List<BuffAction> powerMods = [
    BuffAction.damage,
    BuffAction.damageIndividuality,
    BuffAction.damageIndividualityActiveonly,
    BuffAction.damageEventPoint
  ];

  static Future<bool> damage(
    final BattleData battleData,
    final DataVals dataVals,
    final Iterable<BattleServantData> targets,
    final int chainPos,
    final bool isTypeChain,
    final bool isMightyChain,
    final CardType firstCardType, {
    final bool isPierceDefense = false,
    final bool checkHpRatio = false,
    final bool checkBuffTraits = false,
    final NpSpecificMode npSpecificMode = NpSpecificMode.normal,
  }) async {
    final functionRate = dataVals.Rate ?? 1000;
    if (functionRate < battleData.probabilityThreshold) {
      return false;
    }

    final activator = battleData.activator!;
    final currentCard = battleData.currentCard!;
    final List<AttackResultDetail> targetResults = [];
    for (final target in targets) {
      battleData.setTarget(target);

      final classAdvantage = await getClassRelation(battleData, activator, target);

      final additionDamageRate = checkHpRatio && dataVals.Target != null
          ? ((1 - activator.hp / activator.getMaxHp(battleData)) * dataVals.Target!).toInt()
          : 0;

      int specificAttackRate = 1000;
      if (!checkHpRatio && dataVals.Target != null) {
        if (npSpecificMode == NpSpecificMode.rarity) {
          final countTarget = dataVals.Target! == 1 ? activator : target; // need more sample
          final targetRarities = dataVals.TargetRarityList!;
          final useCorrection = targetRarities.contains(countTarget.rarity);
          if (useCorrection) {
            specificAttackRate = dataVals.Correction!;
          }
        } else if (npSpecificMode == NpSpecificMode.individualSum) {
          final countTarget = dataVals.Target! == 1 ? target : activator;
          final requiredTraits = dataVals.TargetList!.map((traitId) => NiceTrait(id: traitId)).toList();
          int useCount = checkBuffTraits
              ? countTarget.countBuffWithTrait(requiredTraits)
              : countTarget.countTrait(battleData, requiredTraits);
          if (dataVals.ParamAddMaxCount != null && dataVals.ParamAddMaxCount! > 0) {
            useCount = min(useCount, dataVals.ParamAddMaxCount!);
          }
          specificAttackRate = dataVals.Value2! + useCount * dataVals.Correction!;
        } else {
          final requiredTraits = [NiceTrait(id: dataVals.Target!)];
          final useCorrection = checkBuffTraits
              ? containsAnyTraits(
                  target.getBuffTraits(battleData, ignoreIrremovable: dataVals.IgnoreIndivUnreleaseable == 1),
                  requiredTraits)
              : containsAnyTraits(target.getTraits(battleData), requiredTraits);

          if (useCorrection) {
            specificAttackRate = dataVals.Correction!;
          }
        }
      }

      int specificAttackBuff = 0;
      for (final action in powerMods) {
        specificAttackBuff += await activator.getBuffValueOnAction(battleData, action);
      }

      final damageParameters = DamageParameters()
        ..attack = activator.attack + currentCard.cardStrengthen
        ..totalHits = Maths.sum(currentCard.cardDetail.hitsDistribution)
        ..damageRate = currentCard.isNP ? dataVals.Value! + additionDamageRate : 1000
        ..npSpecificAttackRate = specificAttackRate
        ..attackerClass = activator.svtClass
        ..defenderClass = target.svtClass
        ..classAdvantage = classAdvantage
        ..attackerAttribute = activator.attribute
        ..defenderAttribute = target.attribute
        ..isNp = currentCard.isNP
        ..chainPos = chainPos
        ..currentCardType = currentCard.cardType
        ..firstCardType = firstCardType
        ..isTypeChain = isTypeChain
        ..isMightyChain = isMightyChain
        ..isCritical = currentCard.isCritical
        ..cardBuff = await activator.getBuffValueOnAction(battleData, BuffAction.commandAtk)
        ..attackBuff = await activator.getBuffValueOnAction(battleData, BuffAction.atk)
        ..specificAttackBuff = specificAttackBuff
        ..criticalDamageBuff =
            currentCard.isCritical ? await activator.getBuffValueOnAction(battleData, BuffAction.criticalDamage) : 0
        ..npDamageBuff = currentCard.isNP ? await activator.getBuffValueOnAction(battleData, BuffAction.npdamage) : 0
        ..percentAttackBuff = await activator.getBuffValueOnAction(battleData, BuffAction.damageSpecial)
        ..damageAdditionBuff = await activator.getBuffValueOnAction(battleData, BuffAction.givenDamage)
        ..fixedRandom = battleData.fixedRandom;

      final atkNpParameters = AttackNpGainParameters();
      final defNpParameters = DefendNpGainParameters();
      final starParameters = StarParameters();

      if (activator.isPlayer) {
        atkNpParameters
          ..attackerNpCharge = currentCard.npGain
          ..defenderNpRate = target.enemyTdRate
          ..isNp = currentCard.isNP
          ..chainPos = chainPos
          ..currentCardType = currentCard.cardType
          ..firstCardType = firstCardType
          ..isMightyChain = isMightyChain
          ..isCritical = currentCard.isCritical
          ..cardBuff = await activator.getBuffValueOnAction(battleData, BuffAction.commandNpAtk)
          ..npGainBuff = await activator.getBuffValueOnAction(battleData, BuffAction.dropNp);

        starParameters
          ..attackerStarGen = activator.starGen
          ..defenderStarRate = target.enemyStarRate
          ..isNp = currentCard.isNP
          ..chainPos = chainPos
          ..currentCardType = currentCard.cardType
          ..firstCardType = firstCardType
          ..isMightyChain = isMightyChain
          ..isCritical = currentCard.isCritical
          ..cardBuff = await activator.getBuffValueOnAction(battleData, BuffAction.commandStarAtk)
          ..starGenBuff = await activator.getBuffValueOnAction(battleData, BuffAction.criticalPoint);
      } else {
        defNpParameters
          ..defenderNpCharge = target.defenceNpGain
          ..attackerNpRate = activator.enemyTdAttackRate
          ..npGainBuff = await target.getBuffValueOnAction(battleData, BuffAction.dropNp)
          ..defenseNpGainBuff = await target.getBuffValueOnAction(battleData, BuffAction.dropNpDamage);
      }

      final hasPierceDefense = await activator.hasBuffOnAction(battleData, BuffAction.pierceDefence);
      final skipDamage = await shouldSkipDamage(battleData, activator, target, currentCard);
      if (!skipDamage) {
        damageParameters
          ..cardResist = await target.getBuffValueOnAction(battleData, BuffAction.commandDef)
          ..defenseBuff = isPierceDefense || hasPierceDefense
              ? await target.getBuffValueOnAction(battleData, BuffAction.defencePierce)
              : await target.getBuffValueOnAction(battleData, BuffAction.defence)
          ..specificDefenseBuff = await target.getBuffValueOnAction(battleData, BuffAction.selfdamage)
          ..percentDefenseBuff = await target.getBuffValueOnAction(battleData, BuffAction.specialdefence)
          ..damageReductionBuff = await target.getBuffValueOnAction(battleData, BuffAction.receiveDamage);

        atkNpParameters.cardResist = await target.getBuffValueOnAction(battleData, BuffAction.commandNpDef);

        starParameters
          ..cardResist = await target.getBuffValueOnAction(battleData, BuffAction.commandStarDef)
          ..enemyStarGenResist = await target.getBuffValueOnAction(battleData, BuffAction.criticalStarDamageTaken);
      }

      final totalDamage = await adjustTotalDamage(battleData, damageParameters);
      int remainingDamage = totalDamage;

      int overkillCount = 0;
      final result = DamageResult();
      if (await activator.hasBuffOnAction(battleData, BuffAction.multiattack)) {
        currentCard.cardDetail.hitsDistribution.forEach((hit) {
          result.cardHits.add(hit);
          result.cardHits.add(hit);
        });
      } else {
        result.cardHits.addAll(currentCard.cardDetail.hitsDistribution);
      }
      final totalHits = Maths.sum(result.cardHits);
      for (int i = 0; i < result.cardHits.length; i += 1) {
        if (skipDamage) {
          result.damages.add(0);
        } else {
          final hitsPercentage = result.cardHits[i];
          final int hitDamage;
          if (i < result.cardHits.length - 1) {
            hitDamage = totalDamage * hitsPercentage ~/ totalHits;
          } else {
            hitDamage = remainingDamage;
          }

          result.damages.add(hitDamage);
          remainingDamage -= hitDamage;

          target.receiveDamage(hitDamage);
        }

        if (target.hp <= 0) {
          await activator.activateBuffOnAction(battleData, BuffAction.functionDeadattack);
          target.killedBy = activator;
          target.killedByCard = currentCard;
        }

        final isOverkill = target.hp < 0 || (!currentCard.isNP && target.isBuggedOverkill);
        result.overkillStates.add(isOverkill);
        if (isOverkill) {
          overkillCount += 1;
        }

        if (activator.isPlayer) {
          atkNpParameters.isOverkill = isOverkill;
          starParameters.isOverkill = isOverkill;
          final hitNpGain = calculateAttackNpGain(atkNpParameters);
          final previousNP = activator.np;
          activator.changeNP(hitNpGain);
          result.npGains.add(activator.np - previousNP);

          final hitStar = calculateStar(starParameters);
          result.stars.add(hitStar);
        }

        if (target.isPlayer) {
          defNpParameters.isOverkill = isOverkill;
          final hitNpGain = calculateDefendNpGain(defNpParameters);

          final previousNP = activator.np;
          target.changeNP(hitNpGain);
          result.defNpGains.add(activator.np - previousNP);
        }
      }

      battleData.battleLogger.debug(damageParameters.toString());
      if (activator.isPlayer) {
        battleData.battleLogger.debug(atkNpParameters.toString());
        battleData.battleLogger.debug(starParameters.toString());
      } else {
        battleData.battleLogger.debug(defNpParameters.toString());
      }
      final starString = activator.isPlayer
          ? '${S.current.critical_star}: ${(Maths.sum(result.stars) / 1000).toStringAsFixed(3)} - '
          : '';
      battleData.battleLogger.action('${activator.lBattleName} - ${currentCard.cardType.name.toUpperCase()} - '
          '${currentCard.isNP ? S.current.battle_np_card : S.current.battle_command_card} - '
          '${S.current.effect_target}: ${target.lBattleName} - '
          '${S.current.battle_damage}: $totalDamage - '
          '${S.current.battle_remaining_hp}: ${target.hp}/${target.maxHp} - '
          'NP: ${(Maths.sum(result.npGains) / 100).toStringAsFixed(2)}% - '
          '$starString'
          'Overkill: $overkillCount/${currentCard.cardDetail.hitsDistribution.length}');
      final hitStarString = activator.isPlayer ? ', ${S.current.critical_star}: ${result.stars}' : '';
      battleData.battleLogger.debug(
          '${S.current.details}: ${S.current.battle_damage}: ${result.damages}, NP: ${result.npGains}$hitStarString');

      battleData.changeStar(toModifier(Maths.sum(result.stars)));

      target.removeBuffWithTrait(NiceTrait(id: Trait.buffSleep.id));

      target.addAccumulationDamage(totalDamage - remainingDamage);
      target.attacked = true;

      battleData.unsetTarget();
      targetResults.add(AttackResultDetail(
        target: target,
        damageParams: damageParameters,
        attackNpParams: atkNpParameters,
        starParams: starParameters,
        defenseNpParams: defNpParameters,
        result: result,
      ));
    }

    battleData.recorder.attack(
      activator,
      BattleAttackRecord(
        activator: activator,
        card: null,
        targets: targetResults,
        damage: Maths.sum(targetResults.map((e) => Maths.sum(e.result.damages))),
        attackNp: Maths.sum(targetResults.map((e) => Maths.sum(e.result.npGains))),
        defenseNp: Maths.sum(targetResults.map((e) => Maths.sum(e.result.defNpGains))),
        star: Maths.sum(targetResults.map((e) => Maths.sum(e.result.stars))),
      ),
    );

    return true;
  }

  static Future<bool> shouldSkipDamage(
    final BattleData battleData,
    final BattleServantData activator,
    final BattleServantData target,
    final CommandCardData currentCard,
  ) async {
    final hasSpecialInvincible = await target.hasBuffOnAction(battleData, BuffAction.specialInvincible);
    final hasPierceInvincible = await activator.hasBuffOnAction(battleData, BuffAction.pierceInvincible);
    if (hasSpecialInvincible) {
      return true;
    }
    final hasInvincible = await target.hasBuffOnAction(battleData, BuffAction.invincible);
    if (hasPierceInvincible) {
      return false;
    }
    final hasBreakAvoidance = await activator.hasBuffOnAction(battleData, BuffAction.breakAvoidance);
    if (hasInvincible) {
      return true;
    }
    final hasAvoidance = await target.hasBuffOnAction(battleData, BuffAction.avoidance) ||
        await target.hasBuffOnAction(battleData, BuffAction.avoidanceIndividuality);
    return !hasBreakAvoidance && hasAvoidance;
  }

  static Future<int> getClassRelation(
    final BattleData battleData,
    final BattleServantData activator,
    final BattleServantData target,
  ) async {
    int relation = ConstData.getClassRelation(activator.svtClass, target.svtClass);
    relation = await activator.getClassRelation(battleData, relation, target.svtClass, false);
    relation = await target.getClassRelation(battleData, relation, activator.svtClass, true);

    return relation;
  }

  static Future<int> adjustTotalDamage(final BattleData battleData, final DamageParameters damageParameters) async {
    if (battleData.tailoredExecution && battleData.context != null) {
      return showUserConfirm<int>(
        context: battleData.context!,
        barrierDismissible: false,
        builder: (context) {
          return DamageAdjustor(battleData: battleData, damageParameters: damageParameters);
        },
      );
    }

    return calculateDamage(damageParameters);
  }
}

class DamageAdjustor extends StatefulWidget {
  final BattleData battleData;
  final DamageParameters damageParameters;

  const DamageAdjustor({super.key, required this.battleData, required this.damageParameters});

  @override
  State<DamageAdjustor> createState() => _DamageAdjustorState();
}

class _DamageAdjustorState extends State<DamageAdjustor> {
  @override
  Widget build(BuildContext context) {
    final totalDamage = calculateDamage(widget.damageParameters);
    return SimpleCancelOkDialog(
      title: Text(S.current.battle_select_effect),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.battleData.activator!.lBattleName} - '
            '${widget.damageParameters.currentCardType.name.toTitle()} - '
            '${widget.damageParameters.isNp ? S.current.battle_np_card : S.current.battle_command_card}'
            '\nvs ${widget.battleData.target!.lBattleName} (HP: ${widget.battleData.target!.hp})',
            style: Theme.of(context).textTheme.bodyMedium,
            textScaleFactor: 0.9,
          ),
          const SizedBox(height: 8),
          Text('${S.current.battle_damage}: $totalDamage'),
          ServantOptionEditPage.buildSlider(
            leadingText: S.current.battle_random,
            min: ConstData.constants.attackRateRandomMin,
            max: ConstData.constants.attackRateRandomMax - 1,
            value: widget.damageParameters.fixedRandom,
            label: toModifier(widget.damageParameters.fixedRandom).toStringAsFixed(3),
            onChange: (v) {
              widget.damageParameters.fixedRandom = v.round();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      hideOk: true,
      hideCancel: true,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(totalDamage);
          },
          child: Text(S.current.confirm),
        )
      ],
    );
  }
}
