/// AI 解析出的分类名 → 本地分类的匹配规则。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/ai/simple/ai_service.dart';
import 'package:beecount/data/db.dart';

Category cat(int id, String name, String kind) => Category(
      id: id,
      name: name,
      kind: kind,
      sortOrder: id,
      level: 1,
      iconType: 'material',
    );

void main() {
  final categories = [
    cat(1, '餐饮', 'expense'),
    cat(2, '交通', 'expense'),
    cat(3, '工资', 'income'),
  ];

  test('优先精确匹配同名且类型一致的分类', () {
    expect(matchBillCategory(categories, 'expense', '交通')?.id, 2);
  });

  test('类型不一致时不匹配，回退到同类型第一个分类', () {
    expect(matchBillCategory(categories, 'expense', '工资')?.id, 1);
  });

  test('未知分类名回退到同类型第一个分类', () {
    expect(matchBillCategory(categories, 'income', '不存在')?.id, 3);
  });

  test('没有同类型分类时返回 null', () {
    expect(matchBillCategory(categories, 'transfer', '餐饮'), isNull);
  });
}
