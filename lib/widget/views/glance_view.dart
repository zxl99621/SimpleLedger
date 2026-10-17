import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../widget_spec.dart' show HWSize;
import 'widget_view_style.dart';

/// 收支速览(glance)小组件视图:小/中两档,`WidgetSpec.glanceSmall` /
/// `WidgetSpec.glanceMedium` 对应渲染。
///
/// headless 组件(见 `widget_view_style.dart` 顶部注释)——金额已由调用方
/// (`WidgetManager`)格式化成显示字符串再传入,这里只负责排版/配色,不做
/// 数值计算。
///
/// **medium(2026-07 视觉统一,用户拍板)**:保留历史版的 2×2 stat 卡布局
/// (今日支出/今日收入/本月支出/本月收入 四宫格,含右上语义图标 chip 与右下
/// ⊕ 记账暗示),只做两处统一化改动——背景从"主题色渐变"改为与其余五款一致
/// 的白/暗内容卡(stat 小卡相应从纯白改浅灰系,保持在新底色上的层次),
/// header 从 App 名改为统一内容标签「收支速览」(A 方案;iOS HIG 也不建议
/// widget 内放 App 名),月份徽章改灰底适配白卡。iOS/Android 2:1 网格的
/// 宽高分叉逻辑(外层透明 padding 撑到 `width`×`height`、内容始终按
/// 364×169 画)照旧保留(D2 back-compat)。
class GlanceView extends StatelessWidget {
  final HWSize size;

  final String todayExpense;
  final String todayIncome;
  final String monthExpense;
  final String monthIncome;

  final Color themeColor;
  final bool redForIncome;

  /// 系统明暗态,由 `WidgetManager` 用 `PlatformDispatcher` 在渲染时取一次
  /// 传入(切换后靠 App 重渲染触发换色,App 存活时经
  /// `didChangePlatformBrightness` 即时触发)。
  final bool dark;

  /// medium 用:左上内容标签(「收支速览」,对应 arb `widgetGalleryGlanceTitle`;
  /// 按 iOS HIG,widget 内不放 App 名)+ 右上月份徽章文案后缀。
  final String titleLabel;
  final String monthSuffix;

  /// small 顶部"今日"徽章文案(medium 四宫格自带今日支出/收入 label,
  /// 不消费这个字段;构造上保留可选参数以便调用方两档统一传参)。
  final String todayLabel;

  final String todayExpenseLabel;
  final String todayIncomeLabel;
  final String monthExpenseLabel;
  final String monthIncomeLabel;

  final double width;
  final double height;

  const GlanceView.medium({
    super.key,
    required this.todayExpense,
    required this.todayIncome,
    required this.monthExpense,
    required this.monthIncome,
    required this.themeColor,
    required this.redForIncome,
    required this.dark,
    required this.monthSuffix,
    required this.todayExpenseLabel,
    required this.todayIncomeLabel,
    required this.monthExpenseLabel,
    required this.monthIncomeLabel,
    required this.width,
    required this.height,
    this.titleLabel = '收支速览',
    this.todayLabel = '今日',
  }) : size = HWSize.medium;

  const GlanceView.small({
    super.key,
    required this.todayExpense,
    required this.monthExpense,
    required this.monthIncome,
    required this.themeColor,
    required this.redForIncome,
    required this.dark,
    required this.todayLabel,
    required this.todayExpenseLabel,
    required this.monthExpenseLabel,
    required this.monthIncomeLabel,
    required this.width,
    required this.height,
    this.todayIncome = '',
    this.titleLabel = '',
    this.monthSuffix = '',
    this.todayIncomeLabel = '',
  }) : size = HWSize.small;

  Color get _expenseColor => widgetExpenseColor(redForIncome);
  Color get _incomeColor => widgetIncomeColor(redForIncome);

  @override
  Widget build(BuildContext context) {
    return size == HWSize.small ? _buildSmall() : _buildMedium();
  }

  // -------------------------------------------------------------------
  // small(155×155):紧凑卡,今日支出大数 + 本月收支底栏
  // -------------------------------------------------------------------
  Widget _buildSmall() {
    final expenseColor = _expenseColor;
    final incomeColor = _incomeColor;
    final bg = widgetCardBackground(dark);
    final textSecondary = widgetTextSecondary(dark);

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: themeColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                todayLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            todayExpenseLabel,
            style: TextStyle(fontSize: 11, color: textSecondary),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              todayExpense,
              maxLines: 1,
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
                color: expenseColor,
                height: 1.0,
                fontFeatures: const [kWidgetTabularFeature],
              ),
            ),
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _miniStat(monthExpenseLabel, monthExpense, expenseColor, textSecondary),
              ),
              Container(width: 1, height: 24, color: widgetDivider(dark)),
              const SizedBox(width: 8),
              Expanded(
                child: _miniStat(monthIncomeLabel, monthIncome, incomeColor, textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value, Color valueColor, Color labelColor) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 9, color: labelColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: valueColor,
              fontFeatures: const [kWidgetTabularFeature],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------
  // medium(364×169 / 2:1):历史版 2×2 stat 卡布局原样保留,背景改白/暗
  // 内容卡(2026-07 用户拍板"保持原样式、只把背景换白",见类文档)
  // -------------------------------------------------------------------
  Widget _buildMedium() {
    // iOS systemMedium 与 Android 2:1 网格宽高比不同,外层透明容器撑到
    // width×height,内容始终按 364×169 画并垂直居中(D2 back-compat)。
    //
    // SimpleLedger 4×2 规格:只显示本月支出，整块点击进入支出记账。
    final isAndroid = Platform.isAndroid;
    final verticalPadding = isAndroid ? (182 - 169) / 2 : 0.0;
    const foreground = Color(0xFFF2FBF9);

    return Container(
      width: width,
      height: height,
      color: Colors.transparent,
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Container(
        width: 364,
        height: 169,
        decoration: BoxDecoration(
          color: themeColor,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  monthExpenseLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: foreground.withValues(alpha: 0.72),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${DateTime.now().month}$monthSuffix',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: foreground.withValues(alpha: 0.85),
                      fontFeatures: const [kWidgetTabularFeature],
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                monthExpense,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: foreground,
                  height: 1.0,
                  fontFeatures: [kWidgetTabularFeature],
                ),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(Icons.add_circle_outline,
                    size: 13, color: foreground.withValues(alpha: 0.65)),
                const SizedBox(width: 5),
                Text(
                  '点按记一笔',
                  style: TextStyle(
                    fontSize: 10,
                    color: foreground.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
