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

/// 用户主动停止当前生成（不是失败）。
class AiCancelled implements Exception {
  const AiCancelled();
}

/// 文字类 AI 的统一推理接口：本地模型与云端 API 都实现它。
abstract class AiEngine {
  Stream<String> streamChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  });

  /// 停止当前生成，并在停止动作真正完成后返回。
  ///
  /// 本地引擎需要等待原生生成循环退出，避免旧生成尚未结束就启动新生成；
  /// 云端引擎会关闭 HTTP 连接。
  Future<void> cancel() async {}

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
