/// AI 记账确认条的展示与回调。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/pages/ai/bill_confirm_bar.dart';

void main() {
  testWidgets('展示金额/分类，并分别触发保存与取消', (tester) async {
    var saved = 0;
    var canceled = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BillConfirmBar(
            bill: PendingBill(
              amount: 35,
              type: 'expense',
              category: Category(
                id: 1,
                name: '餐饮',
                kind: 'expense',
                sortOrder: 1,
                level: 1,
                iconType: 'material',
              ),
              date: DateTime(2026, 10, 18),
              note: '咖啡',
            ),
            onSave: () => saved++,
            onCancel: () => canceled++,
          ),
        ),
      ),
    );

    expect(find.textContaining('35.00'), findsOneWidget);
    expect(find.textContaining('餐饮'), findsOneWidget);
    expect(find.textContaining('咖啡'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('bill-confirm-save')));
    await tester.tap(find.byKey(const ValueKey('bill-confirm-cancel')));

    expect(saved, 1);
    expect(canceled, 1);
  });
}
