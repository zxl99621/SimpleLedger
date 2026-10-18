/// AI 消息列表应始终从底部堆叠，避免少消息时输入框上方出现大块空白。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/pages/ai/ai_message_list.dart';

void main() {
  testWidgets('消息不足一屏时从底部堆叠', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: AiMessageList(
              items: [
                AiChatItem(fromUser: true, text: '第一条'),
                AiChatItem(fromUser: false, text: '第二条'),
              ],
              busy: false,
              ink: Colors.black,
              muted: Colors.grey,
            ),
          ),
        ),
      ),
    );

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.reverse, isTrue);

    final firstTop = tester.getTopLeft(find.text('第一条')).dy;
    final secondBottom = tester.getBottomLeft(find.text('第二条')).dy;
    // 两条消息都被推到底部：第一条不在顶部，第二条接近列表底部。
    expect(firstTop, greaterThan(300));
    expect(secondBottom, greaterThan(500));
  });
}
