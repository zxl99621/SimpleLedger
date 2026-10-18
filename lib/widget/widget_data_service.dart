import '../data/repositories/base_repository.dart';
import '../utils/month_range.dart';

/// 收支速览(glance)小组件所需的原始金额数据:今日 + 本月(账本自定义
/// 记账周期)的收入/支出合计。
class GlanceWidgetData {
  final double todayExpenseTotal;
  final double todayIncomeTotal;
  final double monthExpenseTotal;
  final double monthIncomeTotal;

  const GlanceWidgetData({
    required this.todayExpenseTotal,
    required this.todayIncomeTotal,
    required this.monthExpenseTotal,
    required this.monthIncomeTotal,
  });
}

/// 桌面小组件数据服务:从 repo 取数、聚合成渲染所需的数值,供
/// `WidgetManager` 渲染收支速览视图。
///
/// 方法均为纯粹的"repo → 数值"聚合,不依赖 Riverpod `ref`/`BuildContext`,
/// 便于用内存 Drift 库直接单测(见 `test/widget/widget_data_service_test.dart`)。
class WidgetDataService {
  const WidgetDataService._();

  /// 取「今日」+「本月」(账本自定义起始日周期)收支合计。
  static Future<GlanceWidgetData> gatherGlance({
    required BaseRepository repository,
    required int ledgerId,
  }) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // 「本月」= 账本自定义记账周期(包含今天的 [起始日, 次月起始日))
    final ledger = await repository.getLedgerById(ledgerId);
    final startDay = (ledger?.monthStartDay ?? 1).clamp(1, 28);
    final range = periodContaining(now, startDay);

    final todayExpense = await repository.totalsByCategory(
      ledgerId: ledgerId,
      type: 'expense',
      start: today,
      end: tomorrow,
    );
    final todayIncome = await repository.totalsByCategory(
      ledgerId: ledgerId,
      type: 'income',
      start: today,
      end: tomorrow,
    );
    final monthExpense = await repository.totalsByCategory(
      ledgerId: ledgerId,
      type: 'expense',
      start: range.start,
      end: range.end,
    );
    final monthIncome = await repository.totalsByCategory(
      ledgerId: ledgerId,
      type: 'income',
      start: range.start,
      end: range.end,
    );

    return GlanceWidgetData(
      todayExpenseTotal: _sumTotals(todayExpense),
      todayIncomeTotal: _sumTotals(todayIncome),
      monthExpenseTotal: _sumTotals(monthExpense),
      monthIncomeTotal: _sumTotals(monthIncome),
    );
  }

  /// 账本自身币种(`Ledger.currency`),供收支速览做金额格式化。
  ///
  /// 取不到账本(理论不应发生)兜底 'CNY',与 [gatherGlance] 的
  /// `monthStartDay` 兜底同一套保守策略。
  static Future<String> gatherLedgerCurrency({
    required BaseRepository repository,
    required int ledgerId,
  }) async {
    final ledger = await repository.getLedgerById(ledgerId);
    return ledger?.currency ?? 'CNY';
  }

  static double _sumTotals(
    List<({int? id, String name, String? icon, double total})> items,
  ) {
    return items.fold<double>(0.0, (sum, item) => sum + item.total);
  }
}

/// 一次渲染批次(`WidgetManager.updateAllWidgets` 单次调用)内的取数缓存。
///
/// 批次内同一份数据只查一次,生命周期 = 一个批次:每次 `updateAllWidgets`
/// 新建一个,批次结束即丢弃,不做跨批次缓存(数据新鲜度优先)。
class WidgetGatherBatch {
  final BaseRepository repository;
  final int ledgerId;

  WidgetGatherBatch({
    required this.repository,
    required this.ledgerId,
  });

  Future<GlanceWidgetData>? _glance;
  Future<GlanceWidgetData> glance() =>
      _glance ??= WidgetDataService.gatherGlance(
          repository: repository, ledgerId: ledgerId);

  Future<String>? _ledgerCurrency;
  Future<String> ledgerCurrency() =>
      _ledgerCurrency ??= WidgetDataService.gatherLedgerCurrency(
          repository: repository, ledgerId: ledgerId);
}
