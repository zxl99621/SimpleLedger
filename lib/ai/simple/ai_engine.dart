/// 统一 AI 消息。
class AiMessage {
  const AiMessage({required this.role, required this.content});

  final String role; // system / user / assistant
  final String content;
}

/// AI 调用异常（带用户可读文案）。
class AiException implements Exception {
  const AiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 文字类 AI 的统一推理接口：本地模型与云端 API 都实现它。
abstract class AiEngine {
  Stream<String> streamChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  });

  Future<String> complete(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) async {
    final buffer = StringBuffer();
    await for (final token in streamChat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
    )) {
      buffer.write(token);
    }
    return buffer.toString();
  }
}
