import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/db.dart';
import '../../providers.dart';
import '../../providers/simple_settings_providers.dart';
import '../../theme.dart';
import '../../utils/currencies.dart';
import '../transaction/transaction_editor_page.dart';
import 'simple_home_logic.dart';

/// 首页最近交易流（SimpleLedger 独立于原版首页的数据入口）
final simpleRecentTransactionsProvider =
    StreamProvider.autoDispose<List<Transaction>>((ref) {
  final ledgerId = ref.watch(currentLedgerIdProvider);
  return ref
      .watch(repositoryProvider)
      .watchRecentTransactions(ledgerId: ledgerId, limit: 12);
});

/// 极简首页
///
/// 版式：顶部标题 → 总资产（可在设置隐藏）→ 本月收支两栏 → 最近交易列表。
/// 不使用整屏圆角卡片堆叠，只有总资产是可识别的视觉重点。
class SimpleHomePage extends ConsumerWidget {
  const SimpleHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final ink = isDark ? const Color(0xFFECEFEA) : BeeTheme.ink;
    final muted = isDark ? const Color(0xFF8A938C) : const Color(0xFF6B7169);
    final hairline =
        isDark ? Colors.white.withValues(alpha: 0.08) : BeeTheme.ink.withValues(alpha: 0.07);
    final teal = isDark ? BeeTheme.tealDark : BeeTheme.teal;
    final brick = isDark ? const Color(0xFFE0786B) : BeeTheme.brick;

    final ledgerId = ref.watch(currentLedgerIdProvider);
    final startDay = ref.watch(currentMonthStartDayProvider);
    final showTotalAsset = ref.watch(showTotalAssetProvider);
    final currencySymbol = getCurrencySymbol(ref.watch(baseCurrencyProvider));

    final now = DateTime.now();
    final monthParams = homeMonthlyTotalsParams(
      ledgerId: ledgerId,
      now: now,
      startDay: startDay,
    );
    final totalsAsync = ref.watch(monthlyTotalsProvider(monthParams));
    final balanceAsync = ref.watch(currentBalanceProvider(ledgerId));
    final recentAsync = ref.watch(simpleRecentTransactionsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    final totals = totalsAsync.valueOrNull;
    final balance = balanceAsync.valueOrNull;
    final transactions = recentAsync.valueOrNull ?? const <Transaction>[];
    final categoryMap = {
      for (final category in categoriesAsync.valueOrNull ?? const <Category>[])
        category.id: category,
    };

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: teal,
          onRefresh: () async {
            ref.read(statsRefreshProvider.notifier).state++;
            await Future<void>.delayed(const Duration(milliseconds: 350));
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 120),
            children: [
              _TopBar(ink: ink, muted: muted, now: now),
              const SizedBox(height: 26),
              if (showTotalAsset)
                _TotalAssetBlock(
                  symbol: currencySymbol,
                  value: balance,
                  isDark: isDark,
                ),
              if (showTotalAsset) const SizedBox(height: 26),
              _FlowRow(
                symbol: currencySymbol,
                income: totals?.$1,
                expense: totals?.$2,
                incomeColor: teal,
                expenseColor: brick,
                ink: ink,
                muted: muted,
                hairline: hairline,
              ),
              const SizedBox(height: 34),
              _SectionTitle(title: '最近交易', count: transactions.length, ink: ink, muted: muted),
              const SizedBox(height: 6),
              if (transactions.isEmpty)
                _EmptyTransactions(
                  muted: muted,
                  onAdd: () => _openEditor(context, 'expense'),
                )
              else
                for (var i = 0; i < transactions.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: hairline),
                  _TransactionRow(
                    transaction: transactions[i],
                    category: transactions[i].categoryId == null
                        ? null
                        : categoryMap[transactions[i].categoryId],
                    symbol: currencySymbol,
                    ink: ink,
                    muted: muted,
                    incomeColor: teal,
                    expenseColor: brick,
                    onTap: () => _openEditor(
                      context,
                      transactions[i].type,
                      editingTransactionId: transactions[i].id,
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }

  static void _openEditor(
    BuildContext context,
    String kind, {
    int? editingTransactionId,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditorPage(
          initialKind: kind,
          quickAdd: editingTransactionId == null,
          editingTransactionId: editingTransactionId,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.ink, required this.muted, required this.now});

  final Color ink;
  final Color muted;
  final DateTime now;

  static const _weekdays = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  Widget build(BuildContext context) {
    final weekday = _weekdays[now.weekday - 1];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '极简记账',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: ink,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Text(
            '${now.month}月${now.day}日 周$weekday',
            style: TextStyle(fontSize: 12, color: muted),
          ),
        ),
      ],
    );
  }
}

class _TotalAssetBlock extends StatelessWidget {
  const _TotalAssetBlock({
    required this.symbol,
    required this.value,
    required this.isDark,
  });

  final String symbol;
  final double? value;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    const foreground = Color(0xFFF3F7F4);
    final background = isDark ? const Color(0xFF0F3B36) : BeeTheme.teal;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '总资产',
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 0.4,
              color: foreground.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                symbol,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: foreground.withValues(alpha: 0.85),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                value == null ? '—' : _formatAmount(value!),
                style: const TextStyle(
                  fontSize: 34,
                  height: 1.05,
                  fontWeight: FontWeight.w600,
                  color: foreground,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  const _FlowRow({
    required this.symbol,
    required this.income,
    required this.expense,
    required this.incomeColor,
    required this.expenseColor,
    required this.ink,
    required this.muted,
    required this.hairline,
  });

  final String symbol;
  final double? income;
  final double? expense;
  final Color incomeColor;
  final Color expenseColor;
  final Color ink;
  final Color muted;
  final Color hairline;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _Metric(
            label: '本月收入',
            symbol: symbol,
            value: income,
            color: incomeColor,
            ink: ink,
            muted: muted,
            alignEnd: false,
          ),
        ),
        Container(
          width: 1,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 18),
          color: hairline,
        ),
        Expanded(
          child: _Metric(
            label: '本月支出',
            symbol: symbol,
            value: expense,
            color: expenseColor,
            ink: ink,
            muted: muted,
            alignEnd: true,
          ),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.symbol,
    required this.value,
    required this.color,
    required this.ink,
    required this.muted,
    required this.alignEnd,
  });

  final String label;
  final String symbol;
  final double? value;
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              symbol,
              style: TextStyle(fontSize: 13, color: color.withValues(alpha: 0.8)),
            ),
            const SizedBox(width: 3),
            Text(
              value == null ? '—' : _formatAmount(value!),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: value == null ? muted : color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.count,
    required this.ink,
    required this.muted,
  });

  final String title;
  final int count;
  final Color ink;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
        const Spacer(),
        if (count > 0)
          Text('$count 笔', style: TextStyle(fontSize: 12, color: muted)),
      ],
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.transaction,
    required this.category,
    required this.symbol,
    required this.ink,
    required this.muted,
    required this.incomeColor,
    required this.expenseColor,
    required this.onTap,
  });

  final Transaction transaction;
  final Category? category;
  final String symbol;
  final Color ink;
  final Color muted;
  final Color incomeColor;
  final Color expenseColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isTransfer = transaction.type == 'transfer';
    final isIncome = transaction.type == 'income';
    final amountColor = isTransfer
        ? muted
        : isIncome
            ? incomeColor
            : expenseColor;
    final sign = isTransfer ? '' : isIncome ? '+' : '-';
    final title = category?.name ?? (isTransfer ? '转账' : '未分类');
    final note = transaction.note?.trim();

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    ),
                  ),
                  if (note != null && note.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$sign$symbol${_formatAmount(transaction.amount)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: amountColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _dateLabel(transaction.happenedAt),
                  style: TextStyle(fontSize: 11, color: muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return '今天';
    if (diff == 1) return '昨天';
    return '${date.month}月${date.day}日';
  }
}

class _EmptyTransactions extends StatelessWidget {
  const _EmptyTransactions({required this.muted, required this.onAdd});

  final Color muted;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 34, color: muted.withValues(alpha: 0.45)),
          const SizedBox(height: 12),
          Text('还没有记账', style: TextStyle(fontSize: 14, color: muted)),
          const SizedBox(height: 4),
          TextButton(
            onPressed: onAdd,
            child: const Text('记一笔'),
          ),
        ],
      ),
    );
  }
}

String _formatAmount(double value) => NumberFormat('#,##0.00').format(value);
