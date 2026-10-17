import 'dart:convert';

import 'package:http/http.dart' as http;

import 'ai_engine.dart';

/// OpenAI 兼容接口（DeepSeek / 通义 / GLM / Moonshot / OpenAI 等）。
class CloudAiEngine extends AiEngine {
  CloudAiEngine({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    http.Client Function()? clientFactory,
  }) : _clientFactory = clientFactory ?? (() => http.Client());

  final String baseUrl;
  final String apiKey;
  final String model;
  final http.Client Function() _clientFactory;

  http.Client? _activeClient;
  bool _cancelled = false;

  @override
  void cancel() {
    _cancelled = true;
    _activeClient?.close();
    _activeClient = null;
  }

  String get _normalizedBase {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  void _assertConfigured() {
    if (_normalizedBase.isEmpty || apiKey.trim().isEmpty || model.trim().isEmpty) {
      throw const AiException('请先在 AI 设置中填写接口地址、API Key 和模型名');
    }
  }

  @override
  Stream<String> streamChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    _assertConfigured();
    _cancelled = false;
    final client = _clientFactory();
    _activeClient = client;
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_normalizedBase/chat/completions'),
      )
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..body = jsonEncode({
          'model': model.trim(),
          'messages': [
            for (final message in messages)
              {'role': message.role, 'content': message.content},
          ],
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': true,
        });

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        client.close();
        throw const AiException('云端请求超时，请检查网络或接口地址');
      });
      if (_cancelled) throw const AiCancelled();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = await response.stream.bytesToString();
        throw AiException(
          '云端请求失败 (${response.statusCode})：${_errorMessage(body)}',
        );
      }

      final contentType = response.headers['content-type'] ?? '';
      final lineStream =
          response.stream.transform(utf8.decoder).transform(const LineSplitter());

      if (!contentType.contains('text/event-stream')) {
        // 部分兼容服务忽略 stream=true，直接返回完整 JSON。
        final buffer = StringBuffer();
        await for (final line in lineStream) {
          if (_cancelled) throw const AiCancelled();
          buffer.write(line);
        }
        final decoded = jsonDecode(buffer.toString());
        final content = _messageContent(decoded);
        if (content.isNotEmpty) yield content;
        return;
      }

      await for (final line in lineStream) {
        if (_cancelled) throw const AiCancelled();
        final trimmed = line.trim();
        if (!trimmed.startsWith('data:')) continue;
        final data = trimmed.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') break;
        try {
          final decoded = jsonDecode(data);
          dynamic delta;
          if (decoded is Map) {
            final choices = decoded['choices'];
            if (choices is List && choices.isNotEmpty && choices.first is Map) {
              final first = choices.first as Map;
              final deltaMap = first['delta'];
              if (deltaMap is Map) {
                delta = deltaMap['content'];
              }
            }
          }
          if (delta is String && delta.isNotEmpty) {
            yield delta;
          }
        } catch (_) {
          // 忽略单条无法解析的 SSE 行，继续读取后续 token。
        }
      }
    } catch (error) {
      if (_cancelled) throw const AiCancelled();
      rethrow;
    } finally {
      if (identical(_activeClient, client)) _activeClient = null;
      client.close();
    }
  }

  /// 图片 OCR：OpenAI 兼容的视觉模型接口。
  Future<String> ocrImage({
    required String base64Image,
    required String mimeType,
    String? ocrModel,
    String prompt = '识别这张账单图片，提取：金额、收支类型（收入或支出）、分类、日期、商户或备注。'
        '请用简短的中文纯文本输出，不要编造图片中不存在的信息。',
  }) async {
    _assertConfigured();
    final client = _clientFactory();
    try {
      final request = http.Request(
        'POST',
        Uri.parse('$_normalizedBase/chat/completions'),
      )
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..body = jsonEncode({
          'model': (ocrModel == null || ocrModel.trim().isEmpty)
              ? model.trim()
              : ocrModel.trim(),
          'messages': [
            {
              'role': 'user',
              'content': [
                {'type': 'text', 'text': prompt},
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'temperature': 0.1,
          'max_tokens': 512,
        });

      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 60), onTimeout: () {
        client.close();
        throw const AiException('云端请求超时，请检查网络或接口地址');
      });
      final body = await response.stream.bytesToString();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiException(
          'OCR 请求失败 (${response.statusCode})：${_errorMessage(body)}',
        );
      }
      final decoded = jsonDecode(body);
      return _messageContent(decoded);
    } finally {
      client.close();
    }
  }

  static String _messageContent(dynamic decoded) {
    if (decoded is! Map) return '';
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final message = choices[0] is Map ? choices[0]['message'] : null;
    if (message is! Map) return '';
    final content = message['content'];
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
    }
    return '';
  }

  static String _errorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] is String) {
          return error['message'] as String;
        }
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    return body.length > 300 ? '${body.substring(0, 300)}…' : body;
  }
}
