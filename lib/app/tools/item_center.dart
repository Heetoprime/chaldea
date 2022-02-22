import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:chaldea/models/models.dart';
import 'package:chaldea/utils/utils.dart';

class ItemCenter {
  final StreamController<ItemCenter> streamController = StreamController();

  void dispose() {
    streamController.close();
  }

  /// settings
  bool includingEvents = true;

  User get user => _user ?? db2.curUser;
  final User? _user;

  ItemCenter([this._user]);

  final List<int> _validItems = [];
  late final HashSet<int> _validItemSet;
  late _MatrixManager<int, int, SvtMatCostDetail<int>> _svtCur; //0->cur
  late _MatrixManager<int, int, SvtMatCostDetail<int>>
      _svtDemands; //cur->target
  late _MatrixManager<int, int, SvtMatCostDetail<int>> _svtFull; //0->max
  late _MatrixManager<int, int, int> _eventItem;

  // statistics
  Map<int, int> _statSvtConsumed = {};
  Map<int, int> _statSvtDemands = {};
  Map<int, int> _statSvtFull = {};

  Map<int, int> _statEvent = {};
  Map<int, int> _statMainStory = {};
  Map<int, int> _statTicket = {};
  Map<int, int> _statObtain = {};

  Map<int, int> _itemLeft = {};

  void init() {
    _validItems.clear();
    final List<int> _svtIds = [];
    for (final item in db2.gameData.items.values) {
      if (item.skillUpItemType != SkillUpItemType.none) {
        _validItems.add(item.id);
      }
    }
    _validItems.addAll(Items.specialItems);
    _validItems.addAll(Items.specialSvtMat);
    _validItemSet = HashSet.from(_validItems);

    // svt
    for (final svt in db2.gameData.servants.values) {
      if (svt.isUserSvt) _svtIds.add(svt.collectionNo);
    }
    _svtCur = _MatrixManager(
        dim1: _svtIds,
        dim2: _validItems,
        init: () => SvtMatCostDetail(() => 0));
    _svtDemands = _MatrixManager(
        dim1: _svtIds,
        dim2: _validItems,
        init: () => SvtMatCostDetail(() => 0));
    _svtFull = _MatrixManager(
        dim1: _svtIds,
        dim2: _validItems,
        init: () => SvtMatCostDetail(() => 0));
    // events
    _eventItem = _MatrixManager(
      dim1: db2.gameData.events.keys.toList(),
      dim2: _validItems,
      init: () => 0,
    );
  }

  void calculate() {
    updateSvts(all: true, notify: false);
    updateEvents(all: true, notify: false);
    updateMainStory(notify: false);
    updateExchangeTickets(notify: false);
    updateLeftItems();
  }

  void updateSvts(
      {List<Servant> svts = const [], bool all = false, bool notify = true}) {
    if (all) {
      for (int svtId in _svtCur.dim1) {
        updateOneSvt(svtId);
      }
    } else {
      for (final svt in svts) {
        updateOneSvt(svt.collectionNo);
      }
    }
    _updateSvtStat(_svtCur, _statSvtConsumed);
    _updateSvtStat(_svtDemands, _statSvtDemands);
    if (all) {
      _updateSvtStat(_svtFull, _statSvtFull);
    }
    if (notify) {
      updateLeftItems();
    }
  }

  void _updateSvtStat(_MatrixManager<int, int, SvtMatCostDetail<int>> detail,
      Map<int, int> stat) {
    stat.clear();
    List<int> itemSum = List.generate(detail.dim2.length, (index) => 0);
    for (int itemIndex = 0; itemIndex < itemSum.length; itemIndex++) {
      for (int svtIndex = 0; svtIndex < detail.dim1.length; svtIndex++) {
        itemSum[itemIndex] += detail._matrix[svtIndex][itemIndex].all;
      }
    }
  }

  void updateOneSvt(int svtId, {bool max = false}) {
    final svtIndex = _svtCur._dim1Map[svtId];
    final svt = db2.gameData.servants[svtId];
    if (svt == null || svtIndex == null) return;
    final consumed =
        calcOneSvt(svt, SvtPlan.empty, user.svtStatusOf(svtId).cur);
    final demands =
        calcOneSvt(svt, user.svtStatusOf(svtId).cur, user.svtPlanOf(svtId));

    for (int itemIndex = 0; itemIndex < _validItems.length; itemIndex++) {
      _svtCur._matrix[svtIndex][itemIndex].updateFrom<Map<int, int>>(
          consumed, (part) => part[_validItems[itemIndex]] ?? 0);
      _svtDemands._matrix[svtIndex][itemIndex].updateFrom<Map<int, int>>(
          demands, (part) => part[_validItems[itemIndex]] ?? 0);
    }
    if (max) {
      final allDemands = calcOneSvt(svt, SvtPlan.empty, SvtPlan.max(svt));
      for (int itemIndex = 0; itemIndex < _validItems.length; itemIndex++) {
        _svtFull._matrix[svtIndex][itemIndex].updateFrom<Map<int, int>>(
            allDemands, (part) => part[_validItems[itemIndex]] ?? 0);
      }
    }
  }

  SvtMatCostDetail<Map<int, int>> calcOneSvt(
      Servant svt, SvtPlan cur, SvtPlan target) {
    final detail = SvtMatCostDetail<Map<int, int>>(() => {});
    detail.ascension = _sumMat(svt.ascensionMaterials,
        [for (int lv = cur.ascension; lv < target.ascension; lv++) lv]);

    for (int skill = 0; skill < 3; skill++) {
      Maths.sumDict([
        detail.activeSkill,
        _sumMat(svt.skillMaterials, [
          for (int lv = cur.skills[skill]; lv < target.skills[skill]; lv++) lv
        ])
      ], inPlace: true);
    }

    for (int skill = 0; skill < 3; skill++) {
      Maths.sumDict([
        detail.appendSkill,
        _sumMat(svt.appendSkillMaterials, [
          for (int lv = cur.appendSkills[skill];
              lv < target.appendSkills[skill];
              lv++)
            lv
        ])
      ], inPlace: true);
    }

    detail.costume = _sumMat(svt.costumeMaterials, [
      for (final costumeId in target.costumes.keys)
        if (target.costumes[costumeId]! > 0 &&
            (cur.costumes[costumeId] ?? 0) == 0)
          costumeId
    ]);

    detail.special = {
      Items.hpFou4: max(0, target.fouHp - cur.fouHp),
      Items.atkFou4: max(0, target.fouAtk - cur.fouAtk),
      Items.grailId: max(0, target.grail - cur.grail),
      Items.lanternId: max(0, target.bondLimit - cur.bondLimit),
      Items.qpId: QpCost.grail(svt.rarity, cur.grail, target.grail) +
          QpCost.bondLimit(cur.bondLimit, target.bondLimit),
    };

    detail.all = Maths.sumDict(detail.parts);
    return detail;
  }

  void updateOneEvent(int eventId) {
    final eventIndex = _eventItem._dim1Map[eventId];
    final event = db2.gameData.events[eventId];
    if (eventIndex == null || event == null) return;
    final eventItems = calcOneEvent(event);
    for (int itemIndex = 0; itemIndex < _validItems.length; itemIndex++) {
      _eventItem._matrix[eventIndex][itemIndex] =
          eventItems[_validItems[itemIndex]] ?? 0;
    }
  }

  void updateEvents(
      {List<Event> events = const [], bool all = false, bool notify = true}) {
    if (all) {
      for (int eventId in _eventItem.dim1) {
        updateOneEvent(eventId);
      }
    } else {
      for (final event in events) {
        updateOneEvent(event.id);
      }
    }
    if (notify) {
      updateLeftItems();
    }
  }

  /// shop/point rewards/mission rewards/Tower rewards/lottery/treasureBox/fixedDrop/wars rewards
  Map<int, int> calcOneEvent(Event event) {
    Map<int, int> result = {};
    // shop
    final plan = db2.curUser.eventPlanOf(event.id);
    if (!plan.planned) return result;
    if (plan.shop) {
      result.addDict({
        for (final k in event.itemShop.keys)
          if (!plan.shopExcludeItem.contains(k)) k: event.itemShop[k]!,
      });
    }
    if (plan.point) {
      result.addDict(event.itemPointReward);
    }
    if (plan.mission) {
      result.addDict(event.itemMission);
    }
    if (plan.tower) {
      result.addDict(event.itemTower);
    }
    for (final lottery in event.lotteries) {
      int planBoxNum = plan.lotteries[lottery.id] ?? 0;
      for (int boxIndex in event.itemLottery.keys) {
        if (boxIndex < planBoxNum) {
          result.addDict(event.itemLottery[lottery.id]?[boxIndex] ?? {});
        }
        int maxBoxIndex = Maths.max(event.itemLottery.keys); //0-9,10
        if (!lottery.limited && planBoxNum > maxBoxIndex) {
          result.addDict(event.itemLottery[lottery.id]?[maxBoxIndex]
                  ?.multiple(planBoxNum - maxBoxIndex) ??
              {});
        }
      }
    }
    if (plan.treasureBox) {
      result.addDict(plan.treasureBoxItems);
    }
    if (plan.fixedDrop) {
      result.addDict(event.itemWarDrop);
    }
    if (plan.questReward) {
      result.addDict(event.itemWarReward);
    }
    if (plan.extra) {
      // check event.extra.extraItems;
      for (final idx in plan.extraItems.keys) {
        result.addDict(plan.extraItems[idx]!);
      }
    }

    return result;
  }

  void updateMainStory({bool notify = true}) {
    _statMainStory.clear();
    for (final war in db2.gameData.wars.values) {
      if (war.isMainStory) {
        db2.curUser.mainStoryOf(war.id);
        _statMainStory.addDict(war.itemDrop);
      }
    }
    if (notify) {
      updateLeftItems();
    }
  }

  void updateExchangeTickets({bool notify = true}) {
    _statTicket.clear();
    for (final ticket in db2.gameData.exchangeTickets.values) {
      final plan = db2.curUser.ticketOf(ticket.key);
      for (int i = 0; i < 3; i++) {
        _statTicket.addNum(ticket.items[i], plan.counts[i]);
      }
    }
    if (notify) {
      updateLeftItems();
    }
  }

  void updateLeftItems() {
    _itemLeft.clear();
    _statObtain = Maths.sumDict([_statEvent, _statMainStory, _statTicket]);
    _itemLeft
      ..addDict(user.items)
      ..addDict(_statObtain)
      ..addDict(_statSvtDemands.multiple(-1));
    streamController.sink.add(this);
  }
}

class _MatrixManager<K1, K2, V> {
  final List<K1> dim1;
  final List<K2> dim2;
  final Map<K1, int> _dim1Map;
  final Map<K2, int> _dim2Map;
  final List<List<V>> _matrix;
  final V Function() init;

  _MatrixManager({required this.dim1, required this.dim2, required this.init})
      : assert(dim1.toSet().length == dim1.length),
        assert(dim2.toSet().length == dim2.length),
        _dim1Map = {
          for (int index = 0; index < dim1.length; index++) dim1[index]: index,
        },
        _dim2Map = {
          for (int index = 0; index < dim2.length; index++) dim2[index]: index,
        },
        _matrix = List.generate(
            dim1.length, (_) => List.generate(dim2.length, (__) => init()));

  void addDim1(K1 k1) {
    if (dim1.contains(k1)) return;
    dim1.add(k1);
    _dim1Map[k1] = dim1.length - 1;
    _matrix.add(List.generate(dim2.length, (index) => init()));
  }

  void removeDim1(K1 k1) {
    final index = _dim1Map.remove(k1);
    if (index != null) {
      _matrix.removeAt(index);
    }
  }
}

class SvtMatCostDetail<T> {
  T ascension;
  T activeSkill;
  T appendSkill;
  T costume;
  T special;
  T all;

  SvtMatCostDetail(T Function() k)
      : ascension = k(),
        activeSkill = k(),
        appendSkill = k(),
        costume = k(),
        special = k(),
        all = k();

  List<T> get parts => [ascension, activeSkill, appendSkill, costume, special];

  void updateFrom<S>(SvtMatCostDetail<S> other, T Function(S part) converter) {
    ascension = converter(other.ascension);
    activeSkill = converter(other.activeSkill);
    appendSkill = converter(other.appendSkill);
    costume = converter(other.costume);
    special = converter(other.special);
    all = converter(other.all);
  }
}

/// shop/point rewards/mission rewards/Tower rewards/lottery/treasureBox/fixedDrop/wars rewards
class EventMatCostDetail<T> {
  T shop;
  T point;
  T mission;
  T tower;
  T lottery;
  T treasureBox;
  T fixedDrop;
  T questReward;

  EventMatCostDetail(T Function() init)
      : shop = init(),
        point = init(),
        mission = init(),
        tower = init(),
        lottery = init(),
        treasureBox = init(),
        fixedDrop = init(),
        questReward = init();
}

Map<int, int> _sumMat(Map<int, LvlUpMaterial> matDetail, List<int> lvs) {
  Map<int, int> mats = {};
  for (int lv in lvs) {
    final lvMat = matDetail[lv];
    if (lvMat != null) {
      mats[Items.qp.id] = lvMat.qp;
      for (final itemAmount in lvMat.items) {
        mats[itemAmount.item.id] =
            (mats[itemAmount.item.id] ?? 0) + itemAmount.amount;
      }
    }
  }
  return mats;
}

class QpCost {
  const QpCost._();

  static int grail(int rarity, int cur, int target) {
    int qp = 0;
    for (int grail = cur + 1; grail <= target; grail++) {
      qp += db2.gameData.constData.svtGrailCost[rarity]![grail]?.qp ?? 0;
    }
    return qp;
  }

  static int bondLimit(int cur, int target) {
    int qp = 0;
    for (int lv = cur + 1; lv <= target; lv++) {
      qp += db2.gameData.constData.bondLimitQp[lv] ?? 0;
    }
    return qp;
  }
}