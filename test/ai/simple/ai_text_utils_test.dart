/// AI 输出清洗与记账意图判定的纯函数测试。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/ai/simple/ai_text_utils.dart';

void main() {
  group('sanitizeAiText', () {
    test('移除成对的 think 标签及其内容', () {
      expect(
        sanitizeAiText('<think>\n用户想记账\n</think>\n\n我无法帮助记账。'),
        '我无法帮助记账。',
      );
    });

    test('移除空的 think 标签', () {
      expect(
        sanitizeAiText('<think>\n\n</think>\n\n我可以帮你统计收支。'),
        '我可以帮你统计收支。',
      );
    });

    test('移除没有闭合的 think 标签', () {
      expect(
        sanitizeAiText('<think>正在思考\n这是一段回答'),
        '正在思考\n这是一段回答',
      );
    });

    test('保留正常文本与 JSON', () {
      const json = '{"amount": 35, "type": "expense"}';
      expect(sanitizeAiText('<think></think>$json'), json);
    });
  });

  group('sanitizeAiStreamText', () {
    test('隐藏未闭合 think 块及其后的思考内容', () {
      expect(sanitizeAiStreamText('回答<think>正在思考'), '回答');
    });

    test('隐藏流式过程中尚未闭合的标签前缀', () {
      expect(sanitizeAiStreamText('回答<thi'), '回答');
      expect(sanitizeAiStreamText('回答<think'), '回答');
    });

    test('移除完整 think 块与游离闭合标签', () {
      expect(
        sanitizeAiStreamText('<think>思考</think>正式回答</think>继续'),
        '正式回答继续',
      );
    });
  });

  group('looksLikeBillIntent', () {
    test('金额 + 消费动词识别为记账', () {
      expect(looksLikeBillIntent('买了杯咖啡 35 块'), isTrue);
      expect(looksLikeBillIntent('今天打车花了 20 元'), isTrue);
      expect(looksLikeBillIntent('收到工资 8000'), isTrue);
      expect(looksLikeBillIntent('为我记一笔购物的账，花费1块5'), isTrue);
    });

    test('明确的记账指令即使没有金额也识别为记账', () {
      expect(looksLikeBillIntent('记一笔购物的账'), isTrue);
      expect(looksLikeBillIntent('帮我记一笔'), isTrue);
    });

    test('能力询问与统计问答不识别为记账', () {
      expect(looksLikeBillIntent('你能帮我记账吗'), isFalse);
      expect(looksLikeBillIntent('你可以帮我记账吗？'), isFalse);
      expect(looksLikeBillIntent('我本月支出多少'), isFalse);
      expect(looksLikeBillIntent('这个月花了多少钱'), isFalse);
      expect(looksLikeBillIntent('我该怎么控制消费'), isFalse);
    });
  });
}
