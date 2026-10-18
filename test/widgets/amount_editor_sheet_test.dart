/// 金额键盘「默认极简、按需展开计算器」的布局契约。
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:beecount/data/db.dart';
import 'package:beecount/data/repositories/local/local_repository.dart';
import 'package:beecount/l10n/app_localizations.dart';
import 'package:beecount/providers.dart';
import 'package:beecount/widgets/biz/amount_editor_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late BeeDatabase db;
  late LocalRepository repo;

  setUp(() async {
    db = BeeDatabase.forTesting(NativeDatabase.memory());
    repo = LocalRepository(db);
    await db.customStatement(
        "INSERT INTO ledgers (id, name, currency) VALUES (1, 'L', 'CNY')");
  });

  tearDown(() async => db.close());

  Future<void> pumpSheet(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(repo),
          currentLedgerCurrencyProvider.overrideWithValue('CNY'),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: AmountEditorSheet(
              categoryName: '餐饮',
              initialDate: DateTime(2026, 10, 18),
              ledgerId: 1,
              onSubmit: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('默认收起计算器，且不显示冗余提示', (tester) async {
    await pumpSheet(tester);

    expect(find.byKey(const ValueKey('amount-calc-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('amount-op-+')), findsNothing);
    expect(find.text('备注 · 图片 · 标签'), findsNothing);
    expect(find.text('双击再记'), findsNothing);
  });

  testWidgets('点击等号入口后展开运算符，再次点击收起', (tester) async {
    await pumpSheet(tester);

    await tester.tap(find.byKey(const ValueKey('amount-calc-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('amount-op-+')), findsOneWidget);
    expect(find.byKey(const ValueKey('amount-op-−')), findsOneWidget);
    expect(find.byKey(const ValueKey('amount-op-×')), findsOneWidget);
    expect(find.byKey(const ValueKey('amount-op-÷')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('amount-calc-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('amount-op-+')), findsNothing);
  });
}
