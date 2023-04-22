import 'dart:math';

import 'package:chaldea/app/app.dart';
import 'package:chaldea/app/battle/models/battle.dart';
import 'package:chaldea/app/descriptors/skill_descriptor.dart';
import 'package:chaldea/app/modules/common/filter_group.dart';
import 'package:chaldea/generated/l10n.dart';
import 'package:chaldea/models/gamedata/gamedata.dart';
import 'package:chaldea/models/userdata/filter_data.dart';
import 'package:chaldea/utils/utils.dart';
import 'package:chaldea/widgets/widgets.dart';
import '../formation/select_skill_page.dart';

class CustomSkillActivator extends StatefulWidget {
  final BattleData battleData;

  const CustomSkillActivator({super.key, required this.battleData});

  @override
  State<CustomSkillActivator> createState() => _CustomSkillActivatorState();
}

class _CustomSkillActivatorState extends State<CustomSkillActivator> {
  BaseSkill? skill;
  int skillLv = 1;
  BattleServantData? activator;
  bool isAlly = true;
  SkillType skillType = SkillType.active;
  String? skillErrorMsg;
  String? errorMsg;
  Region? region;

  @override
  Widget build(final BuildContext context) {
    errorMsg = skill == null ? S.current.battle_no_skill_selected : null;
    if (skill != null) skillLv = min(skillLv, skill!.functions.first.svals.length);
    final List<BattleServantData> actors = isAlly ? widget.battleData.nonnullAllies : widget.battleData.nonnullEnemies;

    return Scaffold(
      appBar: AppBar(title: Text(S.current.battle_activate_custom_skill)),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  title: Text(S.current.select_skill),
                  trailing: Icon(DirectionalIcons.keyboard_arrow_forward(context)),
                  onTap: () {
                    router.pushPage(SkillSelectPage(
                      skillType: null,
                      onSelected: (selected) {
                        skill = BaseSkill.fromJson(selected.toJson());
                        skillLv = selected.maxLv;
                        skillType = selected.type;
                        if (mounted) setState(() {});
                      },
                    ));
                  },
                ),
                if (skillErrorMsg != null)
                  SFooter.rich(
                      TextSpan(text: skillErrorMsg, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 8),
                if (skill != null)
                  SkillDescriptor(
                    skill: skill!,
                    showEnemy: true,
                    showNone: true,
                    jumpToDetail: false,
                    level: skillLv,
                  ),
                if (skill != null && skill!.maxLv > 1)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 16),
                    child: SliderWithTitle(
                      padding: EdgeInsets.zero,
                      leadingText: S.current.level,
                      min: 1,
                      max: skill!.maxLv,
                      value: skillLv.clamp(1, skill!.maxLv),
                      label: skillLv.toString(),
                      onChange: (v) {
                        skillLv = v.toInt();
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                const Divider(),
                ListTile(
                  dense: true,
                  title: Text(S.current.general_type),
                  trailing: FilterGroup<SkillType>(
                    combined: true,
                    options: SkillType.values,
                    values: FilterRadioData.nonnull(skillType),
                    optionBuilder: (value) =>
                        Text(value == SkillType.active ? S.current.active_skill_short : S.current.passive_skill_short),
                    onFilterChanged: (v, _) {
                      skillType = v.radioValue!;
                      skill?.type = skillType;
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  dense: true,
                  title: Text(S.current.battle_select_activator),
                  trailing: FilterGroup<bool>(
                    combined: true,
                    options: const [true, false],
                    values: FilterRadioData.nonnull(isAlly),
                    optionBuilder: (value) => Text(value ? S.current.battle_ally : S.current.enemy),
                    onFilterChanged: (v, _) {
                      isAlly = v.radioValue!;
                      if (activator != null) {
                        if ((activator!.isPlayer && isAlly) || (activator!.isEnemy && !isAlly)) {
                          activator = null;
                        }
                      }
                      if (mounted) setState(() {});
                    },
                  ),
                ),
                ButtonBar(
                  alignment: MainAxisAlignment.start,
                  children: [
                    FilterGroup<BattleServantData?>(
                      combined: true,
                      options: [null, ...actors],
                      values: FilterRadioData(activator),
                      optionBuilder: (value) => Text(value == null ? S.current.battle_no_source : value.lBattleName),
                      onFilterChanged: (v, _) {
                        activator = v.radioValue;
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          kDefaultDivider,
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      errorMsg ?? "",
                      style:
                          Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: errorMsg != null
                        ? null
                        : () async {
                            await widget.battleData.recordError(
                              save: true,
                              action: 'custom_skill-${skill?.id}',
                              task: () async {
                                if (activator != null) widget.battleData.setActivator(activator!);
                                widget.battleData.battleLogger
                                    .action('${activator == null ? S.current.battle_no_source : activator!.lBattleName}'
                                        ' - ${S.current.skill}: ${skill!.lName.l}');
                                await BattleSkillInfoData.activateSkill(
                                  widget.battleData,
                                  skill!,
                                  skillLv,
                                  defaultToPlayer: isAlly,
                                );
                                widget.battleData.recorder.skill(
                                  battleData: widget.battleData,
                                  activator: activator,
                                  skill: BattleSkillInfoData([], skill!),
                                  type: SkillInfoType.custom,
                                  fromPlayer: isAlly,
                                );
                              },
                            );
                            if (mounted) Navigator.of(context).pop(skill);
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: Text(S.current.battle_activate_custom_skill),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}