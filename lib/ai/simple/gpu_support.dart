import 'package:flutter/services.dart';

const _channel = MethodChannel('simpleledger/llama');

/// 查询原生 llama.cpp 是否真的编译了 GPU 卸载后端。
///
/// 仅看 `detectGpu()` 不够：Vulkan 设备存在不代表 ggml 编译了 Vulkan
/// backend。原生侧用 `llama_supports_gpu_offload()` 给出权威答案；通道缺失
/// 或调用失败时按 CPU 处理。
Future<bool> supportsGpuOffload() async {
  try {
    return await _channel.invokeMethod<bool>('supportsGpuOffload') ?? false;
  } catch (_) {
    return false;
  }
}
