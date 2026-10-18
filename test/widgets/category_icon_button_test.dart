/// 分类图标点击反馈必须与图标/选中圆同尺寸。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/widgets/category/category_icon_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('点击区域是 56dp 圆形，与图标尺寸一致', (tester) async {
    await tester.pumpWidget(wrap(
      CategoryIconButton(
        size: 56,
        selected: false,
        primaryColor: const Color(0xFF0E7369),
        backgroundColor: const Color(0xFFF0F0F0),
        onTap: () {},
        child: const Icon(Icons.medical_services),
      ),
    ));

    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.customBorder, isA<CircleBorder>());
    expect(tester.getSize(find.byType(InkWell)), const Size(56, 56));
  });

  testWidgets('子分类使用 48dp 圆形点击区域', (tester) async {
    await tester.pumpWidget(wrap(
      CategoryIconButton(
        size: 48,
        selected: true,
        primaryColor: const Color(0xFF0E7369),
        backgroundColor: const Color(0xFFF0F0F0),
        onTap: () {},
        child: const Icon(Icons.medical_services),
      ),
    ));

    expect(tester.getSize(find.byType(InkWell)), const Size(48, 48));
  });
}
