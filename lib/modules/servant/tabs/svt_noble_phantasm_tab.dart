import 'package:auto_size_text/auto_size_text.dart';
import 'package:chaldea/components/components.dart';
import 'package:chaldea/modules/shared/filter_page.dart';

import '../servant_detail_page.dart';
import 'svt_tab_base.dart';

class SvtNoblePhantasmTab extends SvtTabBaseWidget {
  SvtNoblePhantasmTab({
    Key? key,
    ServantDetailPageState? parent,
    Servant? svt,
    ServantStatus? status,
  }) : super(key: key, parent: parent, svt: svt, status: status);

  @override
  _SvtNoblePhantasmTabState createState() =>
      _SvtNoblePhantasmTabState(parent: parent, svt: svt, plan: status);
}

class _SvtNoblePhantasmTabState extends SvtTabBaseState<SvtNoblePhantasmTab> {
  _SvtNoblePhantasmTabState(
      {ServantDetailPageState? parent, Servant? svt, ServantStatus? plan})
      : super(parent: parent, svt: svt, status: plan);

  List<NoblePhantasm> get noblePhantasms => svt.lNoblePhantasm;

  @override
  Widget build(BuildContext context) {
    if (noblePhantasms.length == 0) {
      return Container(child: Center(child: Text('No NoblePhantasm Data')));
    }
    status.npIndex =
        fixValidRange(status.npIndex, 0, noblePhantasms.length - 1);

    final td = noblePhantasms[status.npIndex];
    return ListView(
      children: <Widget>[
        TileGroup(
          children: <Widget>[
            buildToggle(status.npIndex, td),
            buildHeader(td),
            for (Effect e in td.effects) ...buildEffect(e)
          ],
        )
      ],
    );
  }

  FilterGroupData _toggleData = FilterGroupData(options: {'0': true});

  Widget buildToggle(int selected, NoblePhantasm td) {
    if (noblePhantasms.length <= 1) {
      return Container();
    }
    final filter = FilterGroup(
      options:
          List.generate(noblePhantasms.length, (index) => index.toString()),
      values: _toggleData,
      optionBuilder: (s) {
        String state = noblePhantasms[int.parse(s)].state ?? 'NP';
        Widget button;
        if (state.contains('强化前') || state.contains('强化后')) {
          final iconKey = state.contains('强化前') ? '宝具未强化' : '宝具强化';
          button = Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              db.getIconImage(iconKey, height: 22),
              Text(state)
            ],
          );
        } else {
          button = Text(state);
        }
        return button;
      },
      combined: true,
      useRadio: true,
      onFilterChanged: (v) {
        setState(() {
          status.npIndex = int.parse(v.options.keys.first);
        });
      },
    );
    return Padding(
      padding: EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (td.openCondition?.isNotEmpty == true) SizedBox(width: 48),
          Expanded(child: Center(child: filter)),
          if (td.openCondition?.isNotEmpty == true)
            SizedBox(
              width: 48,
              child: IconButton(
                padding: EdgeInsets.all(2),
                constraints: const BoxConstraints(
                  minWidth: 48,
                  minHeight: 24,
                ),
                onPressed: () {
                  SimpleCancelOkDialog(
                    title: Text(td.lName),
                    content: Text(
                      td.openCondition!,
                      style: Theme.of(context).textTheme.caption,
                    ),
                  ).showDialog(context);
                },
                icon: Icon(Icons.info_outline),
                color: Theme.of(context).hintColor,
                tooltip: S.current.open_condition,
              ),
            )
        ],
      ),
    );
  }

  Widget buildHeader(NoblePhantasm td) {
    return CustomTile(
      leading: Column(
        children: <Widget>[
          db.getIconImage(td.color?.toLowerCase().toTitle(), width: 99),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 110 * 0.9),
            child: Text(
              '${td.typeText} ${td.rank}',
              style: TextStyle(fontSize: 14),
              textAlign: TextAlign.center,
            ),
          )
        ],
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AutoSizeText(
            td.upperName,
            style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).textTheme.caption?.color),
            maxLines: 1,
          ),
          AutoSizeText(
            td.name,
            style: TextStyle(fontWeight: FontWeight.w600),
            maxLines: Language.isEN ? 2 : 1,
          ),
          if (td.upperNameJp?.isNotEmpty == true)
            AutoSizeText(
              td.upperNameJp!,
              style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).textTheme.caption?.color),
              maxLines: 1,
            ),
          if (td.nameJp?.isNotEmpty == true)
            AutoSizeText(
              td.nameJp!,
              style: TextStyle(fontWeight: FontWeight.w600),
              maxLines: 1,
            ),
        ],
      ),
    );
  }

  List<Widget> buildEffect(Effect effect) {
    assert([0, 1, 5].contains(effect.lvData.length));
    int crossCount = effect.lvData.length > 1
        ? 5
        : effect.lvData.length == 1 && effect.lvData.first.length >= 10
            ? 1
            : 0;
    String description = effect.description;
    if (Language.isEN) {
      description =
          description.split('\n').map((e) => '· ${e.trim()}').join('\n');
    }
    return <Widget>[
      CustomTile(
        contentPadding: EdgeInsets.fromLTRB(16, 6, crossCount == 0 ? 0 : 16, 6),
        subtitle: crossCount == 0
            ? Row(children: [
                Expanded(child: Text(description), flex: 4),
                if (effect.lvData.isNotEmpty)
                  Expanded(
                      child: Center(child: Text(effect.lvData[0])), flex: 1),
              ])
            : Text(description),
      ),
      if (crossCount > 0)
        Table(
          children: [
            for (int row = 0; row < effect.lvData.length / crossCount; row++)
              TableRow(
                children: List.generate(crossCount, (col) {
                  int index = row * crossCount + col;
                  if (index >= effect.lvData.length) return Container();
                  return Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.all(5),
                      child: Text(
                        effect.lvData[index],
                        style: TextStyle(
                          fontSize: 14,
                          color: index == 5 || index == 9
                              ? Colors.redAccent
                              : null,
                        ),
                      ),
                    ),
                  );
                }),
              )
          ],
        ),
    ];
  }
}