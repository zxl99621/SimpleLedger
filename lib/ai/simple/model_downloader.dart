import 'dart:io';

import 'package:http/http.dart' as http;

import 'ai_engine.dart';

/// 带进度的 GGUF 模型下载器。
class ModelDownloader {
  http.Client? _client;
  bool _cancelled = false;

  bool get isDownloading => _client != null;

  Future<void> download({
    required Uri url,
    required File destination,
    required void Function(int received, int total) onProgress,
  }) async {
    if (_client != null) {
      throw const AiException('已有下载任务在进行');
    }
    _cancelled = false;
    final client = http.Client();
    _client = client;
    IOSink? sink;
    try {
      final request = http.Request('GET', url);
      final response = await client.send(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiException('模型下载失败 (${response.statusCode})，请检查下载源或网络');
      }

      final total = response.contentLength ?? -1;
      await destination.parent.create(recursive: true);
      final partial = File('${destination.path}.part');
      if (await partial.exists()) await partial.delete();
      sink = partial.openWrite();

      var received = 0;
      await for (final chunk in response.stream) {
        if (_cancelled) {
          throw const AiException('下载已取消');
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      // 校验 GGUF 魔数，避免把错误页/损坏文件当成模型。
      final handle = await partial.open();
      final header = await handle.read(4);
      await handle.close();
      if (String.fromCharCodes(header) != 'GGUF') {
        await partial.delete();
        throw const AiException('下载的文件不是有效的 GGUF 模型');
      }

      if (await destination.exists()) await destination.delete();
      await partial.rename(destination.path);
    } catch (error) {
      if (error is AiException) rethrow;
      throw AiException('模型下载失败：$error');
    } finally {
      await sink?.close();
      client.close();
      _client = null;
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
    _client = null;
  }
}
