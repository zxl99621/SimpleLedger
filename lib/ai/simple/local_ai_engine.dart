import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/system/logger_service.dart';
import 'ai_engine.dart';
import 'gpu_support.dart';

/// 本地模型运行状态，供 UI 展示“加载中/可对话/失败”。
enum LocalAiPhase { idle, loading, ready, error }

@immutable
class LocalAiStatus {
  const LocalAiStatus(this.phase, {this.progress = 0, this.message});

  final LocalAiPhase phase;
  final double progress; // 0..1，仅 loading 有效
  final String? message;

  bool get isLoading => phase == LocalAiPhase.loading;
  bool get isReady => phase == LocalAiPhase.ready;
}

/// 单例本地模型管理器。llama.cpp 的模型加载开销大，整个 App 只保留一个实例。
class LocalAiManager {
  LocalAiManager._();

  static final LocalAiManager instance = LocalAiManager._();

  /// 保守的 GPU 卸载层数。部分 Mali 驱动在 99 层（全量）卸载时会在
  /// ggml Vulkan 张量分配阶段崩溃；先限制为部分卸载。
  static const int _maxGpuLayers = 16;

  /// 原生 GPU 加载没有 Dart 异常可捕获；用同步落盘的标记文件判断上次是否
  /// 因崩溃中断，并在下一次启动时自动关闭 GPU，避免闪退循环。
  static const _gpuEnabledPrefKey = 'simple_ai_gpu_enabled_v2';
  static bool _gpuDisabledForSession = false;

  LlamaController? _controller;
  String? _loadedPath;
  bool _loadedWithGpu = false;
  bool _loadedUseGpu = false;

  /// 单飞加载：并发调用共享同一个 Future，而不是直接报“正在加载”。
  Future<void>? _loadingFuture;

  /// 当前生成是否已真正结束（原生 onDone/onError 或 stop 完成）。
  Completer<void>? _generationDone;

  /// 用户在模型加载期间点了停止；加载完成后不再启动推理。
  bool _cancelRequested = false;

  final ValueNotifier<LocalAiStatus> status =
      ValueNotifier(const LocalAiStatus(LocalAiPhase.idle));

  bool get isLoading => _loadingFuture != null;
  String? get loadedPath => _loadedPath;
  bool get loadedWithGpu => _loadedWithGpu;

  /// 用户在设置页重新打开 GPU 开关时，允许本会话再次尝试。
  void onUserEnabledGpu() {
    _gpuDisabledForSession = false;
  }

  Future<void> ensureLoaded(String modelPath, {bool useGpu = true}) async {
    final effectiveUseGpu = useGpu && !_gpuDisabledForSession;
    if (_loadedPath == modelPath &&
        _controller != null &&
        _loadedUseGpu == effectiveUseGpu) {
      _setStatus(const LocalAiStatus(LocalAiPhase.ready));
      return;
    }

    final pending = _loadingFuture;
    if (pending != null) {
      await pending;
      if (_loadedPath == modelPath &&
          _controller != null &&
          _loadedUseGpu == effectiveUseGpu) {
        return;
      }
    }

    final future = _load(modelPath, useGpu: effectiveUseGpu);
    _loadingFuture = future;
    try {
      await future;
    } finally {
      if (identical(_loadingFuture, future)) _loadingFuture = null;
    }
  }

  Future<File> _gpuFlagFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, '.gpu_load_in_progress'));
  }

  Future<void> _load(String modelPath, {required bool useGpu}) async {
    _setStatus(const LocalAiStatus(LocalAiPhase.loading));
    final prefs = await SharedPreferences.getInstance();
    final flagFile = await _gpuFlagFile();
    var effectiveUseGpu = useGpu;

    if (effectiveUseGpu) {
      if (await flagFile.exists()) {
        // 上次 GPU 加载没有正常收尾，说明原生进程崩过。
        _gpuDisabledForSession = true;
        effectiveUseGpu = false;
        await flagFile.delete();
        await prefs.setBool(_gpuEnabledPrefKey, false);
        logger.warning(
          'LocalAi',
          '上次 GPU 加载异常中断，本会话及下次启动自动使用 CPU',
        );
      } else {
        // 同步 flush 落盘，确保原生崩溃后标记仍在。
        await flagFile.writeAsString('1', flush: true);
      }
    } else if (await flagFile.exists()) {
      await flagFile.delete();
    }

    try {
      await _controller?.dispose();
      _controller = null;
      _loadedPath = null;

      final gpuSupported =
          effectiveUseGpu && await supportsGpuOffload();
      logger.info(
        'LocalAi',
        'GPU offload backend: $gpuSupported (useGpu=$effectiveUseGpu)',
      );
      var cpuFallback = false;
      ({LlamaController controller, int gpuLayers}) loaded;
      try {
        loaded = await _createController(
          modelPath,
          // 交给 detectGpu 的 recommendedGpuLayers 决定，但不超过保守上限。
          maxGpuLayers: gpuSupported ? _maxGpuLayers : 0,
        );
      } catch (error) {
        if (!gpuSupported) rethrow;
        // Vulkan 在个别驱动上可能加载失败；回退 CPU，保证仍可使用。
        debugPrint('Vulkan offload failed, falling back to CPU: $error');
        cpuFallback = true;
        loaded = await _createController(modelPath, maxGpuLayers: 0);
      }

      _controller = loaded.controller;
      _loadedPath = modelPath;
      _loadedUseGpu = effectiveUseGpu;
      _loadedWithGpu = loaded.gpuLayers > 0;
      if (await flagFile.exists()) await flagFile.delete();
      _setStatus(LocalAiStatus(
        LocalAiPhase.ready,
        message: cpuFallback ? 'GPU 加载失败，已回退 CPU' : null,
      ));
    } catch (error) {
      _controller = null;
      _loadedPath = null;
      if (await flagFile.exists()) await flagFile.delete();
      _setStatus(LocalAiStatus(
        LocalAiPhase.error,
        message: '$error',
      ));
      throw AiException('本地模型加载失败：$error');
    }
  }

  Future<({LlamaController controller, int gpuLayers})> _createController(
    String modelPath, {
    required int maxGpuLayers,
  }) async {
    final next = LlamaController();
    var gpuLayers = 0;
    if (maxGpuLayers > 0) {
      try {
        final gpu = await next.detectGpu();
        if (gpu.vulkanSupported) {
          // 实测该 Mali 驱动会在 ggml Vulkan 张量分配阶段 SIGSEGV；
          // 在找到可用的后端/驱动组合前，Mali 一律走 CPU。
          if (gpu.gpuName.toLowerCase().contains('mali')) {
            logger.warning(
              'LocalAi',
              'Mali Vulkan backend is unstable; forcing CPU',
            );
            gpuLayers = 0;
          } else {
            gpuLayers =
                gpu.recommendedGpuLayers.clamp(0, maxGpuLayers).toInt();
          }
        }
      } catch (_) {
        // GPU 检测失败不阻塞，走 CPU。
      }
    }

    final progressSub = next.loadProgress.listen((progress) {
      _setStatus(LocalAiStatus(
        LocalAiPhase.loading,
        progress: progress.clamp(0.0, 1.0),
      ));
    });
    try {
      final threads = (Platform.numberOfProcessors - 1).clamp(2, 8);
      logger.info(
        'LocalAi',
        'loading $modelPath (threads=$threads, gpuLayers=$gpuLayers)',
      );
      await next.loadModel(
        modelPath: modelPath,
        threads: threads,
        contextSize: 2048,
        gpuLayers: gpuLayers,
      );
      return (controller: next, gpuLayers: gpuLayers);
    } catch (error) {
      await next.dispose();
      rethrow;
    } finally {
      await progressSub.cancel();
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
    if (_generationDone != null) {
      throw const AiException('上一次生成尚未结束，请稍候');
    }

    _cancelRequested = false;
    final done = Completer<void>();
    _generationDone = done;

    final source = controller.generateChat(
      messages: [
        for (final message in messages)
          ChatMessage(role: message.role, content: message.content),
      ],
      template: 'chatml',
      temperature: temperature,
      maxTokens: maxTokens,
    );

    return source.transform(StreamTransformer<String, String>.fromHandlers(
      handleData: (data, sink) => sink.add(data),
      handleError: (error, stackTrace, sink) {
        _finishGeneration();
        sink.addError(error, stackTrace);
      },
      handleDone: (sink) {
        _finishGeneration();
        sink.close();
      },
    ));
  }

  void _finishGeneration() {
    final done = _generationDone;
    _generationDone = null;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// 停止当前生成。会等待原生生成循环退出（带超时兜底），避免新旧生成
  /// 并发操作同一个 llama context。
  Future<void> stop() async {
    if (_controller == null) {
      if (isLoading) _cancelRequested = true;
      _finishGeneration();
      return;
    }

    await _controller!.stop();
    final done = _generationDone;
    if (done != null) {
      try {
        await done.future.timeout(const Duration(seconds: 3));
      } catch (_) {
        // 原生异常/超时：仍然放行门控，避免永远卡在“正在停止”。
      }
    }
    _finishGeneration();
  }

  /// 加载完成后由 [LocalAiEngine] 检查用户是否在加载期间取消了本次请求。
  bool takeCancelRequest() {
    final value = _cancelRequested;
    _cancelRequested = false;
    return value;
  }

  Future<void> unload() async {
    await stop();
    await _controller?.dispose();
    _controller = null;
    _loadedPath = null;
    _loadedWithGpu = false;
    _loadedUseGpu = false;
    _setStatus(const LocalAiStatus(LocalAiPhase.idle));
  }

  void _setStatus(LocalAiStatus next) {
    if (status.value.phase == next.phase &&
        status.value.progress == next.progress &&
        status.value.message == next.message) {
      return;
    }
    status.value = next;
  }
}

class LocalAiEngine extends AiEngine {
  LocalAiEngine({required this.modelPath, this.useGpu = true});

  final String modelPath;
  final bool useGpu;

  @override
  Future<void> cancel() => LocalAiManager.instance.stop();

  @override
  Stream<String> streamChat(
    List<AiMessage> messages, {
    double temperature = 0.7,
    int maxTokens = 512,
  }) async* {
    if (modelPath.trim().isEmpty) {
      throw const AiException('请先在 AI 设置中下载并选择本地模型');
    }
    await LocalAiManager.instance.ensureLoaded(modelPath, useGpu: useGpu);
    if (LocalAiManager.instance.takeCancelRequest()) {
      throw const AiCancelled();
    }
    yield* LocalAiManager.instance.generateChat(
      messages,
      temperature: temperature,
      maxTokens: maxTokens,
    );
  }
}
