import 'dart:io';

import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'ai_engine.dart';

/// 单例本地模型管理器。llama.cpp 的模型加载开销大，整个 App 只保留一个实例。
class LocalAiManager {
  LocalAiManager._();

  static final LocalAiManager instance = LocalAiManager._();

  LlamaController? _controller;
  String? _loadedPath;
  bool _loading = false;

  bool get isLoading => _loading;
  String? get loadedPath => _loadedPath;

  Future<void> ensureLoaded(String modelPath) async {
    if (_loading) {
      throw const AiException('本地模型正在加载，请稍候再试');
    }
    final controller = _controller;
    if (_loadedPath == modelPath &&
        controller != null &&
        await controller.isModelLoaded()) {
      return;
    }

    _loading = true;
    try {
      await controller?.dispose();
      _controller = null;
      _loadedPath = null;

      final next = LlamaController();
      var gpuLayers = 0;
      try {
        final gpu = await next.detectGpu();
        if (gpu.vulkanSupported) {
          gpuLayers = gpu.recommendedGpuLayers;
        }
      } catch (_) {
        // GPU 检测失败不阻塞，走 CPU。
      }
      final threads = (Platform.numberOfProcessors - 1).clamp(2, 8);
      await next.loadModel(
        modelPath: modelPath,
        threads: threads,
        contextSize: 2048,
        gpuLayers: gpuLayers,
      );
      _controller = next;
      _loadedPath = modelPath;
    } catch (error) {
      _controller = null;
      _loadedPath = null;
      throw AiException('本地模型加载失败：$error');
    } finally {
      _loading = false;
    }
  }

  Stream<String> generateChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) {
    final controller = _controller;
    if (controller == null) {
      throw const AiException('本地模型尚未加载');
    }
    return controller.generateChat(
      messages: [
        for (final message in messages)
          ChatMessage(role: message.role, content: message.content),
      ],
      template: 'chatml',
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }

  Future<void> stop() async {
    await _controller?.stop();
  }

  Future<void> unload() async {
    await _controller?.dispose();
    _controller = null;
    _loadedPath = null;
  }
}

class LocalAiEngine extends AiEngine {
  LocalAiEngine({required this.modelPath});

  final String modelPath;

  @override
  void cancel() {
    LocalAiManager.instance.stop();
  }

  @override
  Stream<String> streamChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    if (modelPath.trim().isEmpty) {
      throw const AiException('请先在 AI 设置中下载并选择本地模型');
    }
    await LocalAiManager.instance.ensureLoaded(modelPath);
    yield* LocalAiManager.instance.generateChat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}
