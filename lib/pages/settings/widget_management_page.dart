import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../../styles/tokens.dart';
import '../../widget/views/glance_view.dart';

/// 桌面小组件说明页 —— SimpleLedger 只保留 4×2 横版「本月支出」。
class WidgetManagementPage extends ConsumerWidget {
  const WidgetManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final primaryColor = ref.watch(primaryColorProvider);
    final redForIncome = ref.watch(incomeExpenseColorSchemeProvider);
    final dark = BeeTokens.isDark(context);

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      appBar: AppBar(title: const Text('桌面小组件')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: BeeTokens.surface(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: BeeTokens.border(context), width: 0.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FittedBox(
                fit: BoxFit.contain,
                child: GlanceView.medium(
                  todayExpense: '¥0',
                  todayIncome: '¥0',
                  monthExpense: '¥3,200.50',
                  monthIncome: '¥8,000.00',
                  themeColor: primaryColor,
                  redForIncome: redForIncome,
                  dark: dark,
                  monthSuffix: '月',
                  todayExpenseLabel: '今日支出',
                  todayIncomeLabel: '今日收入',
                  monthExpenseLabel: '本月支出',
                  monthIncomeLabel: '本月收入',
                  width: 364,
                  height: 169,
                  titleLabel: '极简记账',
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            '小组件显示本月总支出，点击任意位置直接打开支出记账。',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          const SizedBox(height: 24),
          _Step(index: 1, text: '长按手机桌面空白处'),
          _Step(index: 2, text: '选择「小组件」或「添加工具」'),
          _Step(index: 3, text: '找到「极简记账」，添加 4×2 横版组件'),
          const SizedBox(height: 24),
          Text(
            '说明：组件内容随记账数据自动刷新；切换系统深浅色后，桌面组件会在下次 App 回到前台时同步更新。',
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: BeeTokens.textTertiary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
