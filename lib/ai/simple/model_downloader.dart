import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_engine.dart';

/// 用户主动取消下载（不是失败）。
class DownloadCancelled implements Exception {
  const DownloadCancelled();
}

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
    final partial = File('${destination.path}.part');
    try {
      final request = http.Request('GET', url);
      final response = await client.send(request);
      if (_cancelled) {
        throw const DownloadCancelled();
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AiException('模型下载失败 (${response.statusCode})，请检查下载源或网络');
      }

      final total = response.contentLength ?? -1;
      await destination.parent.create(recursive: true);
      if (await partial.exists()) await partial.delete();
      sink = partial.openWrite();

      var received = 0;
      await for (final chunk in response.stream) {
        if (_cancelled) {
          throw const DownloadCancelled();
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
      if (error is DownloadCancelled || _cancelled) {
        if (await partial.exists()) await partial.delete();
        throw const DownloadCancelled();
      }
      if (error is AiException) rethrow;
      // 不把带签名的下载 URL 暴露到界面；详细原因只写调试日志。
      debugPrint('Model download failed: $error');
      throw const AiException('模型下载失败，请检查网络后重试');
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
