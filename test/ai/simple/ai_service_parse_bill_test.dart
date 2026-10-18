/// parseBill 必须先清洗 `<think>` 块，避免思考内容里的 JSON 干扰解析。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/ai/simple/ai_engine.dart';
import 'package:beecount/ai/simple/ai_service.dart';

class _FakeEngine extends AiEngine {
  _FakeEngine(this.response);

  final String response;

  @override
  Stream<String> streamChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    yield response;
  }
}

void main() {
  test('忽略 think 块中的 JSON，只解析正式回答', () async {
    final service = AiService(_FakeEngine(
      '<think>{"amount": 99, "type": "income"}</think>'
      '{"amount": 35, "type": "expense", "category": "餐饮", '
      '"date": "2026-10-18", "note": "咖啡"}',
    ));

    final draft = await service.parseBill(
      '买了杯咖啡 35 块',
      categoryNames: const ['餐饮', '交通'],
      now: DateTime(2026, 10, 18),
    );

    expect(draft.amount, 35);
    expect(draft.type, 'expense');
    expect(draft.categoryName, '餐饮');
    expect(draft.note, '咖啡');
  });
}
