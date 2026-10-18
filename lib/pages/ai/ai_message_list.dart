import 'package:flutter/material.dart';

import '../../ai/simple/ai_text_utils.dart';

/// AI 对话中的一条消息。文本可变，便于流式/占位更新。
class AiChatItem {
  AiChatItem({required this.fromUser, required this.text});

  final bool fromUser;
  String text;
}

/// AI 消息列表：内容从底部堆叠。
///
/// 采用 `reverse: true`，按时间正序的数据在列表里反向索引：
/// 最新消息位于 index 0（视觉底部），少消息时不会在输入框上方留下大块空白。
class AiMessageList extends StatelessWidget {
  const AiMessageList({
    super.key,
    required this.items,
    required this.busy,
    required this.ink,
    required this.muted,
    this.controller,
  });

  final List<AiChatItem> items;
  final bool busy;
  final Color ink;
  final Color muted;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      reverse: true,
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[items.length - 1 - index];
        return AiMessageBubble(
          item: item,
          ink: ink,
          muted: muted,
          busy: busy && index == 0,
        );
      },
    );
  }
}

/// 单条消息气泡。助手文本统一清洗 `<think>` 标签后再展示。
class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({
    super.key,
    required this.item,
    required this.ink,
    required this.muted,
    required this.busy,
  });

  final AiChatItem item;
  final Color ink;
  final Color muted;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    if (item.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(top: 12, left: 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: primary,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            item.text,
            style: const TextStyle(
                fontSize: 14, height: 1.5, color: Colors.white),
          ),
        ),
      );
    }

    final text = sanitizeAiText(item.text);
    return Padding(
      padding: const EdgeInsets.only(top: 16, right: 32),
      child: item.text == '正在思考…' && busy
          ? Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 8),
                Text('正在思考…', style: TextStyle(fontSize: 13, color: muted)),
              ],
            )
          : SelectableText(
              text,
              style: TextStyle(fontSize: 14, height: 1.7, color: ink),
            ),
    );
  }
}
