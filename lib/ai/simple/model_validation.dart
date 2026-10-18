/// 本地 GGUF 模型文件与设备 ABI 的轻量校验。
///
/// 这些检查不加载模型，只排除“文件不存在/被截断/下载到 HTML 错误页/
/// 32 位设备”等明显不可用的情况；真正的可加载性仍由 llama.cpp 决定。
library;

/// GGUF 文件头 4 字节：`GGUF`。
const List<int> _ggufMagic = [0x47, 0x47, 0x55, 0x46];

bool isGgufHeader(List<int> bytes) {
  if (bytes.length < _ggufMagic.length) return false;
  for (var i = 0; i < _ggufMagic.length; i++) {
    if (bytes[i] != _ggufMagic[i]) return false;
  }
  return true;
}

/// llama_flutter_android 只带 arm64-v8a 原生库，32 位设备无法本地推理。
bool isArm64AbiName(String abiName) =>
    abiName.toLowerCase().contains('arm64');

/// 小于 64MB 的文件对目录内任何 Qwen3 GGUF 都必然不完整。
bool isPlausibleModelSize(int bytes) => bytes >= 64 * 1024 * 1024;
