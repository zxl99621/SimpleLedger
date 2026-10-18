/// 桌面小组件 headless view([GlanceView])共用的视觉规范常量与小工具函数。
///
/// **headless 约束**:View 渲染在独立的 headless Flutter engine 里
/// (`HomeWidget.renderFlutterWidget`),不依赖调用方 App 的 `BuildContext`/
/// `Theme`/Riverpod `ref`——颜色、主题色、明暗态、文案全部由构造参数显式
/// 传入。这里集中各 View 会反复用到的色值/字重,避免散落。
///
/// **图片渲染方案的已知限制**:生成的图片不会随系统明暗切换自动重绘;深浅
/// 色靠 App 前台恢复 / 主题变化时重新触发 `WidgetManager.updateAllWidgets`
/// 重渲一张新图。
library;

import 'package:flutter/material.dart';

/// 支出/收入固定色值(未叠加 `redForIncome` 前)。
const Color kWidgetExpenseRed = Color(0xFFE5533C);
const Color kWidgetIncomeGreen = Color(0xFF2FA36B);

/// 数字等宽对齐,金额类文本统一叠加这个 FontFeature。
const kWidgetTabularFeature = FontFeature.tabularFigures();

/// 按 `redForIncome` 解析"支出"语义色(true=红色收入方案下支出用绿,
/// false=红色支出方案下支出用红)。
///
/// 与 `styles/tokens.dart` 的 `BeeTokens.expenseColor` 同一套语义。
Color widgetExpenseColor(bool redForIncome) =>
    redForIncome ? kWidgetIncomeGreen : kWidgetExpenseRed;

/// 按 `redForIncome` 解析"收入"语义色,见 [widgetExpenseColor]。
Color widgetIncomeColor(bool redForIncome) =>
    redForIncome ? kWidgetExpenseRed : kWidgetIncomeGreen;

/// 卡片背景(明/暗)。暗色不直接照搬 App 内「方案D」的纯黑
/// (`BeeColorTokens` 暗黑背景是 #000000)——小组件是桌面上的独立小卡片,不是
/// 全屏页面,纯黑在各种桌面壁纸上容易糊成一片,取比纯黑略浅的深暖灰。
Color widgetCardBackground(bool dark) =>
    dark ? const Color(0xFF1A1712) : Colors.white;

Color widgetTextSecondary(bool dark) =>
    dark ? Colors.white70 : const Color(0xFF6B6B6B);

Color widgetDivider(bool dark) =>
    dark ? Colors.white12 : const Color(0xFFEDEDED);
