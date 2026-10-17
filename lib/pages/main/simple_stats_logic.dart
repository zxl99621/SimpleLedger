import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 饼图最多展示的分类数；其余合并为「其他」。
const int expensePieTopCount = 5;

const Color _pieLabelDark = Color(0xFF1B1F1C);

/// 根据扇区底色选择白/深色文字，保证百分比标签可读。
Color readablePieLabelColor(Color background) {
  final white = contrastRatio(background, Colors.white);
  final dark = contrastRatio(background, _pieLabelDark);
  return white >= dark ? Colors.white : _pieLabelDark;
}

/// WCAG 相对亮度对比度。
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 按支出金额取 Top5，固定色槽顺序分配颜色，剩余金额合并为「其他」。
///
/// [categories] 需按金额从大到小排序。颜色跟随展示顺序，不做循环取色；
/// 分类数超过 5 个时统一折叠，而不是丢弃没有色槽的分类。
List<({String name, double total, Color color})> buildExpensePieSlices({
  required List<({int? id, String name, double total})> categories,
  required List<Color> palette,
  required Color otherColor,
}) {
  if (categories.isEmpty) return const [];

  final top = categories.take(expensePieTopCount).toList();
  final topTotal = top.fold<double>(0, (sum, item) => sum + item.total);
  final allTotal = categories.fold<double>(0, (sum, item) => sum + item.total);
  final otherTotal = allTotal - topTotal;

  return [
    for (var i = 0; i < top.length; i++)
      (
        name: top[i].name,
        total: top[i].total,
        color: i < palette.length ? palette[i] : otherColor,
      ),
    if (otherTotal > 0.005)
      (name: '其他', total: otherTotal, color: otherColor),
  ];
}
