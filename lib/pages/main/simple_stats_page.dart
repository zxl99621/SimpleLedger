import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../ai/simple/ai_providers.dart';
import '../../data/db.dart';
import '../../data/repositories/base_repository.dart';
import '../../providers.dart';
import '../../theme.dart';
import '../../utils/currencies.dart';
import '../ai/simple_ai_page.dart';
import '../transaction/transaction_editor_page.dart';
import 'simple_stats_logic.dart';

// 图表色板：取自校验过的分类序列（蓝、橙、青、黄、品红、绿），
// 收入/支出是两序列，使用通过 CVD 校验的蓝/红组合。
const _categoryLight = <Color>[
  Color(0xFF2A78D6),
  Color(0xFFEB6834),
  Color(0xFF1BAF7A),
  Color(0xFFEDA100),
  Color(0xFFE87BA4),
  Color(0xFF008300),
];

const _categoryDark = <Color>[
  Color(0xFF3987E5),
  Color(0xFFD95926),
  Color(0xFF199E70),
  Color(0xFFC98500),
  Color(0xFFD55181),
  Color(0xFF008300),
];

const _incomeLight = Color(0xFF2A78D6);
const _incomeDark = Color(0xFF3987E5);
const _expenseLight = Color(0xFFE34948);
const _expenseDark = Color(0xFFE66767);
const _otherLight = Color(0xFFB9BDB7);
const _otherDark = Color(0xFF4A524C);

enum _Scope { week, month, custom }

class SimpleStatsData {
  const SimpleStatsData({
    required this.current,
    required this.previous,
    required this.lastYear,
    required this.categories,
    required this.trend,
    required this.transactions,
    required this.allCategories,
  });

  final (double income, double expense) current;
  final (double income, double expense) previous;
  final (double income, double expense) lastYear;
  final List<({int? id, String name, String? icon, double total})> categories;
  final List<({DateTime month, double income, double expense})> trend;
  final List<Transaction> transactions;
  final List<Category> allCategories;
}

/// 统计页数据：一次拉取当前周期、上期、去年同期、分类、趋势与明细。
final simpleStatsProvider = FutureProvider.autoDispose
    .family<SimpleStatsData, ({DateTime start, DateTime end})>((ref, range) {
  final repo = ref.watch(repositoryProvider);
  final ledgerId = ref.watch(currentLedgerIdProvider);
  ref.watch(statsRefreshProvider);

  return _load(repo, ledgerId, range, ref);
});

Future<SimpleStatsData> _load(
  BaseRepository repo,
  int ledgerId,
  ({DateTime start, DateTime end}) range,
  Ref ref,
) async {
  final allCategories = await ref.watch(categoriesProvider.future);
  final start = range.start;
  final end = range.end;
  final days = math.max(1, end.difference(start).inDays);
  final prevStart = start.subtract(Duration(days: days));
  final prevEnd = start;
  final lastYearStart = DateTime(start.year - 1, start.month, start.day);
  final lastYearEnd = DateTime(end.year - 1, end.month, end.day);

  final totals = await Future.wait([
    repo.totalsInRange(ledgerId: ledgerId, start: start, end: end),
    repo.totalsInRange(ledgerId: ledgerId, start: prevStart, end: prevEnd),
    repo.totalsInRange(
        ledgerId: ledgerId, start: lastYearStart, end: lastYearEnd),
  ]);

  final categories = await repo.totalsByCategory(
    ledgerId: ledgerId,
    type: 'expense',
    start: start,
    end: end,
  );

  final now = DateTime.now();
  final months = [
    for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i, 1),
  ];
  final monthly = await Future.wait([
    for (final month in months)
      repo.monthlyTotals(ledgerId: ledgerId, month: month),
  ]);

  // 页面只展示 20 条、AI 快照最多 20 条；长区间不再把全部交易读进内存。
  final loadedTransactions = await repo.getTransactionsByLedgerInRange(
    ledgerId: ledgerId,
    start: start,
    end: end,
    limit: 50,
  );
  final transactions = [...loadedTransactions]
    ..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));

  final sortedCategories = [...categories]
    ..sort((a, b) => b.total.compareTo(a.total));

  return SimpleStatsData(
    current: totals[0],
    previous: totals[1],
    lastYear: totals[2],
    categories: sortedCategories,
    trend: [
      for (var i = 0; i < months.length; i++)
        (
          month: months[i],
          income: monthly[i].$1,
          expense: monthly[i].$2,
        ),
    ],
    transactions: transactions,
    allCategories: allCategories,
  );
}

class SimpleStatsPage extends ConsumerStatefulWidget {
  const SimpleStatsPage({super.key});

  @override
  ConsumerState<SimpleStatsPage> createState() => _SimpleStatsPageState();
}

class _SimpleStatsPageState extends ConsumerState<SimpleStatsPage> {
  _Scope _scope = _Scope.week;
  DateTimeRange? _customRange;

  ({DateTime start, DateTime end}) _resolveRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_scope) {
      case _Scope.week:
        final monday = today.subtract(Duration(days: today.weekday - 1));
        return (start: monday, end: today.add(const Duration(days: 1)));
      case _Scope.month:
        return (
          start: DateTime(now.year, now.month, 1),
          end: today.add(const Duration(days: 1)),
        );
      case _Scope.custom:
        final custom = _customRange;
        if (custom == null) {
          return (start: today, end: today.add(const Duration(days: 1)));
        }
        return (
          start: DateTime(custom.start.year, custom.start.month, custom.start.day),
          end: DateTime(custom.end.year, custom.end.month, custom.end.day)
              .add(const Duration(days: 1)),
        );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: now,
          ),
      locale: const Locale('zh'),
      helpText: '选择统计时间段',
      saveText: '确定',
    );
    if (picked != null) {
      setState(() {
        _customRange = picked;
        _scope = _Scope.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ink = isDark ? const Color(0xFFECEFEA) : BeeTheme.ink;
    final muted = isDark ? const Color(0xFF8A938C) : const Color(0xFF6B7169);
    final hairline =
        isDark ? Colors.white.withValues(alpha: 0.08) : BeeTheme.ink.withValues(alpha: 0.07);
    final incomeColor = isDark ? _incomeDark : _incomeLight;
    final expenseColor = isDark ? _expenseDark : _expenseLight;

    final range = _resolveRange();
    final statsAsync = ref.watch(simpleStatsProvider(range));
    final symbol = getCurrencySymbol(ref.watch(baseCurrencyProvider));

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
          children: [
            Row(
              children: [
                Text(
                  '统计',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const Spacer(),
                Text(
                  _rangeLabel(range),
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ScopeSelector(
              scope: _scope,
              ink: ink,
              muted: muted,
              hairline: hairline,
              onSelect: (scope) {
                if (scope == _Scope.custom) {
                  _pickCustomRange();
                } else {
                  setState(() => _scope = scope);
                }
              },
            ),
            const SizedBox(height: 24),
            ...statsAsync.when(
              loading: () => [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 80),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Text('统计加载失败',
                          style: TextStyle(fontSize: 14, color: muted)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => ref.invalidate(simpleStatsProvider),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              ],
              data: (data) => _buildContent(
                data: data,
                isDark: isDark,
                ink: ink,
                muted: muted,
                hairline: hairline,
                incomeColor: incomeColor,
                expenseColor: expenseColor,
                symbol: symbol,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildContent({
    required SimpleStatsData data,
    required bool isDark,
    required Color ink,
    required Color muted,
    required Color hairline,
    required Color incomeColor,
    required Color expenseColor,
    required String symbol,
  }) {
    final categoryColors = isDark ? _categoryDark : _categoryLight;
    final otherColor = isDark ? _otherDark : _otherLight;
    final allTotal =
        data.categories.fold<double>(0, (sum, item) => sum + item.total);

    // Top5 按金额取，固定色槽顺序分配；分类排行沿用同一组颜色，
    // 保证饼图和排行榜里的分类色一致。
    final slices = buildExpensePieSlices(
      categories: [
        for (final item in data.categories)
          (id: item.id, name: item.name, total: item.total),
      ],
      palette: categoryColors,
      otherColor: otherColor,
    );
    final topColorById = <int, Color>{
      for (var i = 0;
          i < data.categories.length && i < expensePieTopCount;
          i++)
        if (data.categories[i].id != null) data.categories[i].id!: slices[i].color,
    };

    return [
      _SummaryBlock(
        income: data.current.$1,
        expense: data.current.$2,
        previous: data.previous,
        lastYear: data.lastYear,
        symbol: symbol,
        ink: ink,
        muted: muted,
        hairline: hairline,
        incomeColor: incomeColor,
        expenseColor: expenseColor,
      ),
      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            ref.read(aiPendingFeatureProvider.notifier).state = 'summary';
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SimpleAiPage()),
            );
          },
          icon: Icon(Icons.auto_awesome,
              size: 16, color: Theme.of(context).colorScheme.primary),
          label: Text(
            'AI 解读',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            minimumSize: const Size(0, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
        ),
      ),
      const SizedBox(height: 22),
      _SectionHeader(title: '支出构成', ink: ink),
      const SizedBox(height: 12),
      if (slices.isEmpty)
        _EmptyHint(text: '本期还没有支出', muted: muted)
      else
        _PieSection(
          slices: slices,
          symbol: symbol,
          ink: ink,
          muted: muted,
          hairline: hairline,
        ),
      const SizedBox(height: 32),
      _SectionHeader(title: '近 6 个月收支', ink: ink),
      const SizedBox(height: 12),
      _TrendChart(
        data: data.trend,
        incomeColor: incomeColor,
        expenseColor: expenseColor,
        ink: ink,
        muted: muted,
        hairline: hairline,
        isDark: isDark,
        symbol: symbol,
      ),
      const SizedBox(height: 32),
      _SectionHeader(title: '分类排行', ink: ink),
      const SizedBox(height: 6),
      if (data.categories.isEmpty)
        _EmptyHint(text: '本期还没有支出', muted: muted)
      else
        for (final item in data.categories.take(8))
          _RankingRow(
            name: item.name,
            total: item.total,
            percent: allTotal <= 0 ? 0 : item.total / allTotal,
            color: item.id == null
                ? otherColor
                : topColorById[item.id] ?? otherColor,
            symbol: symbol,
            ink: ink,
            muted: muted,
            hairline: hairline,
          ),
      const SizedBox(height: 32),
      _SectionHeader(title: '本期明细', ink: ink),
      const SizedBox(height: 6),
      if (data.transactions.isEmpty)
        _EmptyHint(text: '本期还没有账单', muted: muted)
      else
        for (var i = 0;
            i < math.min(20, data.transactions.length);
            i++) ...[
          if (i > 0) Divider(height: 1, thickness: 1, color: hairline),
          _DetailRow(
            transaction: data.transactions[i],
            categoryName: _categoryName(
                data.transactions[i], data.allCategories),
            symbol: symbol,
            ink: ink,
            muted: muted,
            incomeColor: incomeColor,
            expenseColor: expenseColor,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TransactionEditorPage(
                  initialKind: data.transactions[i].type,
                  editingTransactionId: data.transactions[i].id,
                ),
              ),
            ),
          ),
        ],
    ];
  }

  static String _categoryName(Transaction tx, List<Category> categories) {
    if (tx.type == 'transfer') return '转账';
    for (final category in categories) {
      if (category.id == tx.categoryId) return category.name;
    }
    return '未分类';
  }

  String _rangeLabel(({DateTime start, DateTime end}) range) {
    final endInclusive = range.end.subtract(const Duration(days: 1));
    final sameYear = range.start.year == endInclusive.year;
    if (range.start == endInclusive) {
      return '${range.start.year}年${range.start.month}月${range.start.day}日';
    }
    if (sameYear) {
      return '${range.start.month}月${range.start.day}日 - '
          '${endInclusive.month}月${endInclusive.day}日';
    }
    return '${range.start.year}.${range.start.month}.${range.start.day} - '
        '${endInclusive.year}.${endInclusive.month}.${endInclusive.day}';
  }
}

class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.scope,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.onSelect,
  });

  final _Scope scope;
  final Color ink;
  final Color muted;
  final Color hairline;
  final ValueChanged<_Scope> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final entry in const [
          (_Scope.week, '本周'),
          (_Scope.month, '本月'),
          (_Scope.custom, '自定义'),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelect(entry.$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: scope == entry.$1
                        ? Theme.of(context).colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: scope == entry.$1
                          ? Colors.transparent
                          : hairline,
                    ),
                  ),
                  child: Text(
                    entry.$2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: scope == entry.$1
                          ? Theme.of(context).colorScheme.onPrimary
                          : muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.income,
    required this.expense,
    required this.previous,
    required this.lastYear,
    required this.symbol,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.incomeColor,
    required this.expenseColor,
  });

  final double income;
  final double expense;
  final (double income, double expense) previous;
  final (double income, double expense) lastYear;
  final String symbol;
  final Color ink;
  final Color muted;
  final Color hairline;
  final Color incomeColor;
  final Color expenseColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _MetricBlock(
                label: '本期收入',
                value: income,
                symbol: symbol,
                color: incomeColor,
                ink: ink,
                muted: muted,
              ),
            ),
            Container(
              width: 1,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 18),
              color: hairline,
            ),
            Expanded(
              child: _MetricBlock(
                label: '本期支出',
                value: expense,
                symbol: symbol,
                color: expenseColor,
                ink: ink,
                muted: muted,
                alignEnd: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: _DeltaBlock(
                title: '环比上期',
                incomeDelta: _percent(income, previous.$1),
                expenseDelta: _percent(expense, previous.$2),
                muted: muted,
                hairline: hairline,
                goodColor: incomeColor,
                badColor: expenseColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DeltaBlock(
                title: '同比去年',
                incomeDelta: _percent(income, lastYear.$1),
                expenseDelta: _percent(expense, lastYear.$2),
                muted: muted,
                hairline: hairline,
                goodColor: incomeColor,
                badColor: expenseColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static double? _percent(double current, double base) {
    if (base.abs() < 0.0001) return null;
    return (current - base) / base * 100;
  }
}

class _MetricBlock extends StatelessWidget {
  const _MetricBlock({
    required this.label,
    required this.value,
    required this.symbol,
    required this.color,
    required this.ink,
    required this.muted,
    this.alignEnd = false,
  });

  final String label;
  final double value;
  final String symbol;
  final Color color;
  final Color ink;
  final Color muted;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        const SizedBox(height: 7),
        Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(symbol,
                style:
                    TextStyle(fontSize: 13, color: color.withValues(alpha: 0.8))),
            const SizedBox(width: 3),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment:
                    alignEnd ? Alignment.centerRight : Alignment.centerLeft,
                child: Text(
                  NumberFormat('#,##0.00').format(value),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DeltaBlock extends StatelessWidget {
  const _DeltaBlock({
    required this.title,
    required this.incomeDelta,
    required this.expenseDelta,
    required this.muted,
    required this.hairline,
    required this.goodColor,
    required this.badColor,
  });

  final String title;
  final double? incomeDelta;
  final double? expenseDelta;
  final Color muted;
  final Color hairline;
  final Color goodColor;
  final Color badColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, color: muted)),
          const SizedBox(height: 8),
          _deltaLine('收入', incomeDelta, muted, positiveIsGood: true),
          const SizedBox(height: 4),
          _deltaLine('支出', expenseDelta, muted, positiveIsGood: false),
        ],
      ),
    );
  }

  Widget _deltaLine(String label, double? delta, Color muted,
      {required bool positiveIsGood}) {
    final text = delta == null
        ? '—'
        : '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}%';
    final color = delta == null || delta.abs() < 0.05
        ? muted
        : ((delta > 0) == positiveIsGood ? goodColor : badColor);
    return Row(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
        const Spacer(),
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PieSection extends StatelessWidget {
  const _PieSection({
    required this.slices,
    required this.symbol,
    required this.ink,
    required this.muted,
    required this.hairline,
  });

  final List<({String name, double total, Color color})> slices;
  final String symbol;
  final Color ink;
  final Color muted;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (sum, item) => sum + item.total);

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 140,
              height: 140,
              child: PieChart(
                PieChartData(
                  centerSpaceRadius: 40,
                  sectionsSpace: 2,
                  startDegreeOffset: -90,
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.total,
                        color: slice.color,
                        radius: 28,
                        showTitle: total > 0 && slice.total / total >= 0.08,
                        title:
                            '${(slice.total / total * 100).toStringAsFixed(0)}%',
                        titleStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: readablePieLabelColor(slice.color),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final slice in slices.take(6))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: slice.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              slice.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: ink),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            total <= 0
                                ? '—'
                                : '${(slice.total / total * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontSize: 11,
                              color: muted,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '本期支出 $symbol${NumberFormat('#,##0.00').format(total)}',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({
    required this.data,
    required this.incomeColor,
    required this.expenseColor,
    required this.ink,
    required this.muted,
    required this.hairline,
    required this.isDark,
    required this.symbol,
  });

  final List<({DateTime month, double income, double expense})> data;
  final Color incomeColor;
  final Color expenseColor;
  final Color ink;
  final Color muted;
  final Color hairline;
  final bool isDark;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final maxValue = data.fold<double>(
      0,
      (max, item) => math.max(max, math.max(item.income, item.expense)),
    );
    final interval = _niceCeil(maxValue <= 0 ? 2.5 : maxValue / 4);
    final maxY = maxValue <= 0
        ? interval
        : interval * ((maxValue * 1.1) / interval).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendDot(color: incomeColor, label: '收入', muted: muted),
            const SizedBox(width: 16),
            _LegendDot(color: expenseColor, label: '支出', muted: muted),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 190,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < data.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: data[i].income,
                        color: incomeColor,
                        width: 7,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: data[i].expense,
                        color: expenseColor,
                        width: 7,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(4),
                        ),
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (value) =>
                    FlLine(color: hairline, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    interval: interval,
                    getTitlesWidget: (value, meta) => Text(
                      _compact(value),
                      style: TextStyle(fontSize: 10, color: muted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index < 0 || index >= data.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          '${data[index].month.month}月',
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) =>
                      isDark ? const Color(0xFF2A2F2C) : BeeTheme.ink,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final item = data[groupIndex];
                    final label = rodIndex == 0 ? '收入' : '支出';
                    final value = rodIndex == 0 ? item.income : item.expense;
                    return BarTooltipItem(
                      '${item.month.month}月 $label\n$symbol${NumberFormat('#,##0.00').format(value)}',
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _compact(double value) {
    if (value >= 10000) {
      final v = value / 10000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}万';
    }
    if (value >= 1000) {
      final v = value / 1000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}k';
    }
    return value.toStringAsFixed(0);
  }

  /// 取 1 / 2 / 5 × 10^n 中不小于 [value] 的最小步长。
  static double _niceCeil(double value) {
    if (value <= 0) return 1;
    final exponent = (math.log(value) / math.ln10).floor();
    final base = math.pow(10, exponent).toDouble();
    final normalized = value / base;
    final nice = normalized <= 1
        ? 1.0
        : normalized <= 2
            ? 2.0
            : normalized <= 5
                ? 5.0
                : 10.0;
    return nice * base;
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.muted,
  });

  final Color color;
  final String label;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({
    required this.name,
    required this.total,
    required this.percent,
    required this.color,
    required this.symbol,
    required this.ink,
    required this.muted,
    required this.hairline,
  });

  final String name;
  final double total;
  final double percent;
  final Color color;
  final String symbol;
  final Color ink;
  final Color muted;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: ink),
            ),
          ),
          Text(
            '$symbol${NumberFormat('#,##0.00').format(total)}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              '${(percent * 100).toStringAsFixed(1)}%',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 11,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.transaction,
    required this.categoryName,
    required this.symbol,
    required this.ink,
    required this.muted,
    required this.incomeColor,
    required this.expenseColor,
    required this.onTap,
  });

  final Transaction transaction;
  final String categoryName;
  final String symbol;
  final Color ink;
  final Color muted;
  final Color incomeColor;
  final Color expenseColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.type == 'income';
    final isTransfer = transaction.type == 'transfer';
    final color = isTransfer ? muted : (isIncome ? incomeColor : expenseColor);
    final sign = isTransfer ? '' : (isIncome ? '+' : '-');
    final date = transaction.happenedAt;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.month}月${date.day}日'
                    '${transaction.note == null || transaction.note!.isEmpty ? '' : ' · ${transaction.note}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$sign$symbol${NumberFormat('#,##0.00').format(transaction.amount)}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.ink});

  final String title;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.muted});

  final String text;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Text(text, style: TextStyle(fontSize: 13, color: muted)),
      ),
    );
  }
}
