/// AI 推理模式。
enum AiMode { cloud, local }

/// 本地模型下载源。
enum ModelSource { modelscope, huggingface, custom }

/// 本地 GGUF 模型条目。
class LocalModelInfo {
  const LocalModelInfo({
    required this.id,
    required this.label,
    required this.fileName,
    required this.sizeLabel,
    required this.usage,
    required this.quantization,
    required this.modelScopeUrl,
    required this.huggingFaceUrl,
  });

  final String id;
  final String label;
  final String fileName;
  final String sizeLabel;
  final String usage;
  final String quantization;
  final String modelScopeUrl;
  final String huggingFaceUrl;
}

/// 经实际仓库核对后的 Qwen3 GGUF 清单。
///
/// ModelScope 上 0.6B/1.7B 提供 Q8_0，4B 提供 Q4_K_M；
/// HuggingFace 使用同名文件，若用户网络无法访问可切换下载源或填自定义 URL。
const List<LocalModelInfo> localModelCatalog = [
  LocalModelInfo(
    id: 'qwen3-0.6b',
    label: 'Qwen3 0.6B',
    fileName: 'Qwen3-0.6B-Q8_0.gguf',
    sizeLabel: '约 610 MB',
    usage: '快速记账解析，低性能设备',
    quantization: 'Q8_0',
    modelScopeUrl:
        'https://modelscope.cn/models/Qwen/Qwen3-0.6B-GGUF/resolve/master/Qwen3-0.6B-Q8_0.gguf',
    huggingFaceUrl:
        'https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf',
  ),
  LocalModelInfo(
    id: 'qwen3-1.7b',
    label: 'Qwen3 1.7B',
    fileName: 'Qwen3-1.7B-Q8_0.gguf',
    sizeLabel: '约 1.75 GB',
    usage: '均衡之选，总结与问答可用',
    quantization: 'Q8_0',
    modelScopeUrl:
        'https://modelscope.cn/models/Qwen/Qwen3-1.7B-GGUF/resolve/master/Qwen3-1.7B-Q8_0.gguf',
    huggingFaceUrl:
        'https://huggingface.co/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf',
  ),
  LocalModelInfo(
    id: 'qwen3-4b',
    label: 'Qwen3 4B',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    sizeLabel: '约 2.38 GB',
    usage: '高质量，洞察与复杂问答更佳',
    quantization: 'Q4_K_M',
    modelScopeUrl:
        'https://modelscope.cn/models/Qwen/Qwen3-4B-GGUF/resolve/master/Qwen3-4B-Q4_K_M.gguf',
    huggingFaceUrl:
        'https://huggingface.co/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf',
  ),
];

LocalModelInfo? localModelById(String? id) {
  for (final model in localModelCatalog) {
    if (model.id == id) return model;
  }
  return null;
}

String modelDownloadUrl(LocalModelInfo model, ModelSource source,
    {String customUrl = ''}) {
  switch (source) {
    case ModelSource.modelscope:
      return model.modelScopeUrl;
    case ModelSource.huggingface:
      return model.huggingFaceUrl;
    case ModelSource.custom:
      return customUrl.trim();
  }
}
