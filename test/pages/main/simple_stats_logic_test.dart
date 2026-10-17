import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/pages/main/simple_stats_logic.dart';

const _palette = <Color>[
  Color(0xFF000001),
  Color(0xFF000002),
  Color(0xFF000003),
  Color(0xFF000004),
  Color(0xFF000005),
  Color(0xFF000006),
];
const _other = Color(0xFFAAAAAA);

void main() {
  group('buildExpensePieSlices', () {
    test('Top5 按金额取，不受分类排序位置限制', () {
      final categories = <({int? id, String name, double total})>[
        (id: 8, name: '旅行', total: 1000),
        (id: 9, name: '教育', total: 900),
        (id: 10, name: '医疗', total: 800),
        (id: 11, name: '宠物', total: 700),
        (id: 12, name: '数码', total: 600),
        (id: 1, name: '餐饮', total: 100),
        (id: 2, name: '交通', total: 50),
      ];

      final slices = buildExpensePieSlices(
        categories: categories,
        palette: _palette,
        otherColor: _other,
      );

      expect(
        slices.map((slice) => slice.name).toList(),
        ['旅行', '教育', '医疗', '宠物', '数码', '其他'],
      );
      expect(slices[0].color, _palette[0]);
      expect(slices[4].color, _palette[4]);
      expect(slices.last.total, 150);
      expect(slices.last.color, _other);
    });

    test('恰好 5 个分类时不生成其他', () {
      final categories = <({int? id, String name, double total})>[
        for (var i = 0; i < 5; i++) (id: i, name: '分类$i', total: 10.0),
      ];

      final slices = buildExpensePieSlices(
        categories: categories,
        palette: _palette,
        otherColor: _other,
      );

      expect(slices, hasLength(5));
      expect(slices.any((slice) => slice.name == '其他'), isFalse);
    });

    test('没有支出时返回空列表', () {
      final slices = buildExpensePieSlices(
        categories: const [],
        palette: _palette,
        otherColor: _other,
      );

      expect(slices, isEmpty);
    });
  });
}
