import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import '../../ai/simple/ai_engine.dart';
import '../../ai/simple/ai_providers.dart';
import '../../ai/simple/ai_settings.dart';
import '../../ai/simple/cloud_ai_engine.dart';
import '../../ai/simple/local_ai_engine.dart';
import '../../ai/simple/model_downloader.dart';
import '../../styles/tokens.dart';

class SimpleAiSettingsPage extends ConsumerStatefulWidget {
  const SimpleAiSettingsPage({super.key});

  @override
  ConsumerState<SimpleAiSettingsPage> createState() =>
      _SimpleAiSettingsPageState();
}

class _SimpleAiSettingsPageState extends ConsumerState<SimpleAiSettingsPage> {
  late final TextEditingController _baseUrlCtrl;
  late final TextEditingController _modelCtrl;
  late final TextEditingController _apiKeyCtrl;
  late final TextEditingController _ocrModelCtrl;
  late final TextEditingController _customUrlCtrl;

  final _downloader = ModelDownloader();
  String? _downloadingId;
  bool _cancelling = false;
  int _received = 0;
  int _total = -1;
  bool _testing = false;
  String? _gpuInfo;
  bool _detectingGpu = false;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController(text: ref.read(aiBaseUrlProvider));
    _modelCtrl = TextEditingController(text: ref.read(aiModelNameProvider));
    _apiKeyCtrl = TextEditingController(text: ref.read(aiApiKeyProvider) ?? '');
    _ocrModelCtrl =
        TextEditingController(text: ref.read(aiOcrModelNameProvider));
    _customUrlCtrl =
        TextEditingController(text: ref.read(aiCustomModelUrlProvider));
  }

  @override
  void dispose() {
    _downloader.cancel();
    _baseUrlCtrl.dispose();
    _modelCtrl.dispose();
    _apiKeyCtrl.dispose();
    _ocrModelCtrl.dispose();
    _customUrlCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _testCloud() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      final engine = CloudAiEngine(
        baseUrl: ref.read(aiBaseUrlProvider),
        apiKey: ref.read(aiApiKeyProvider) ?? '',
        model: ref.read(aiModelNameProvider),
      );
      final result = await engine.complete(
        const [AiMessage(role: 'user', content: '请只回复四个字：连接成功')],
        maxTokens: 16,
        temperature: 0,
      );
      _showMessage('连接成功：${result.trim()}');
    } catch (error) {
      _showMessage(error is AiException ? error.message : '连接失败：$error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _download(LocalModelInfo model) async {
    if (_downloadingId != null) return;
    final source = ref.read(aiModelSourceProvider);
    final url = modelDownloadUrl(model, source,
        customUrl: ref.read(aiCustomModelUrlProvider));
    if (url.isEmpty) {
      _showMessage('请先填写自定义下载 URL');
      return;
    }
    final path = await localModelPath(model.fileName);
    final file = File(path);
    setState(() {
      _downloadingId = model.id;
      _cancelling = false;
      _received = 0;
      _total = -1;
    });
    try {
      await _downloader.download(
        url: Uri.parse(url),
        destination: file,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );
      ref.read(aiLocalModelIdProvider.notifier).state = model.id;
      if (mounted) setState(() {});
      _showMessage('${model.label} 下载完成');
    } on DownloadCancelled {
      if (mounted) _showMessage('下载已取消');
    } catch (error) {
      _showMessage(
        error is AiException ? error.message : '下载失败，请检查网络后重试',
      );
    } finally {
      if (mounted) {
        setState(() {
          _downloadingId = null;
          _cancelling = false;
        });
      }
    }
  }

  Future<void> _delete(LocalModelInfo model) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型？'),
        content: Text('将删除 ${model.label}，需要时可重新下载。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (ref.read(aiLocalModelIdProvider) == model.id) {
      await LocalAiManager.instance.unload();
      ref.read(aiLocalModelIdProvider.notifier).state = null;
    }
    final file = File(await localModelPath(model.fileName));
    if (await file.exists()) await file.delete();
    if (mounted) setState(() {});
    _showMessage('已删除 ${model.label}');
  }

  Future<void> _detectGpu() async {
    if (_detectingGpu) return;
    setState(() {
      _detectingGpu = true;
      _gpuInfo = '正在检测…';
    });
    final controller = LlamaController();
    try {
      final gpu = await controller.detectGpu();
      if (!mounted) return;
      setState(() {
        _gpuInfo = gpu.vulkanSupported
            ? '${gpu.gpuName} · Vulkan 可用 · 推荐 ${gpu.recommendedGpuLayers} 层 GPU 卸载'
            : '未检测到可用 Vulkan，使用 CPU 推理';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _gpuInfo = 'GPU 检测失败：$error');
    } finally {
      await controller.dispose();
      if (mounted) setState(() => _detectingGpu = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(aiModeProvider);
    final source = ref.watch(aiModelSourceProvider);
    final selectedId = ref.watch(aiLocalModelIdProvider);
    final ocrEnabled = ref.watch(aiOcrEnabledProvider);
    final modelDir = ref.watch(_modelDirProvider).valueOrNull;

    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle('推理模式'),
          _group([
            RadioListTile<AiMode>(
              value: AiMode.cloud,
              groupValue: mode,
              onChanged: (value) =>
                  ref.read(aiModeProvider.notifier).state = value!,
              title: const Text('云端 API'),
              subtitle: const Text('需要联网，填写 OpenAI 兼容接口'),
              secondary: const Icon(Icons.cloud_outlined),
            ),
            RadioListTile<AiMode>(
              value: AiMode.local,
              groupValue: mode,
              onChanged: (value) =>
                  ref.read(aiModeProvider.notifier).state = value!,
              title: const Text('本地模型'),
              subtitle: const Text('完全离线，账单数据不出设备'),
              secondary: const Icon(Icons.phone_android_rounded),
            ),
          ]),
          if (mode == AiMode.cloud) ...[
            _sectionTitle('云端配置'),
            _group([
              _textTile(
                controller: _baseUrlCtrl,
                label: '接口地址',
                hint: 'https://api.deepseek.com/v1',
                onChanged: (value) =>
                    ref.read(aiBaseUrlProvider.notifier).state = value,
              ),
              _textTile(
                controller: _modelCtrl,
                label: '模型名',
                hint: 'deepseek-chat',
                onChanged: (value) =>
                    ref.read(aiModelNameProvider.notifier).state = value,
              ),
              _textTile(
                controller: _apiKeyCtrl,
                label: 'API Key',
                hint: 'sk-...',
                obscure: true,
                onChanged: (value) =>
                    ref.read(aiApiKeyProvider.notifier).state = value,
              ),
            ]),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _testing ? null : _testCloud,
                child: Text(_testing ? '正在测试…' : '测试连接'),
              ),
            ),
            _sectionTitle('图片 OCR'),
            _group([
              SwitchListTile(
                value: ocrEnabled,
                onChanged: (value) =>
                    ref.read(aiOcrEnabledProvider.notifier).state = value,
                title: const Text('启用图片 OCR'),
                subtitle: const Text('仅云端可用，使用视觉模型识别账单图片'),
                secondary: const Icon(Icons.document_scanner_outlined),
              ),
              _textTile(
                controller: _ocrModelCtrl,
                label: 'OCR 模型名',
                hint: '留空则使用上方模型',
                onChanged: (value) =>
                    ref.read(aiOcrModelNameProvider.notifier).state = value,
              ),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                '隐私提示：云端模式只发送当前功能必需的账单文本；API Key 通过 Android Keystore 加密存储。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: BeeTokens.textTertiary(context),
                ),
              ),
            ),
          ],
          if (mode == AiMode.local) ...[
            _sectionTitle('下载源'),
            _group([
              RadioListTile<ModelSource>(
                value: ModelSource.modelscope,
                groupValue: source,
                onChanged: (value) =>
                    ref.read(aiModelSourceProvider.notifier).state = value!,
                title: const Text('ModelScope 魔搭'),
                subtitle: const Text('国内直连，推荐'),
              ),
              RadioListTile<ModelSource>(
                value: ModelSource.huggingface,
                groupValue: source,
                onChanged: (value) =>
                    ref.read(aiModelSourceProvider.notifier).state = value!,
                title: const Text('Hugging Face'),
                subtitle: const Text('模型更全，国内可能需要代理'),
              ),
              RadioListTile<ModelSource>(
                value: ModelSource.custom,
                groupValue: source,
                onChanged: (value) =>
                    ref.read(aiModelSourceProvider.notifier).state = value!,
                title: const Text('自定义 URL'),
                subtitle: const Text('填写任意可直接下载的 GGUF 地址'),
              ),
              if (source == ModelSource.custom)
                _textTile(
                  controller: _customUrlCtrl,
                  label: 'GGUF 下载地址',
                  hint: 'https://.../model.gguf',
                  onChanged: (value) => ref
                      .read(aiCustomModelUrlProvider.notifier)
                      .state = value,
                ),
            ]),
            _sectionTitle('本地模型'),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                '模型文件较大，建议在 Wi-Fi 环境下下载，并确认手机有足够存储空间。'
                '下载可随时取消；取消后需要重新下载（暂不支持断点续传）。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: BeeTokens.textTertiary(context),
                ),
              ),
            ),
            for (final model in localModelCatalog) ...[
              _modelCard(model, selectedId, modelDir),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _detectingGpu ? null : _detectGpu,
                    child: const Text('检测设备 GPU'),
                  ),
                ),
              ],
            ),
            if (_gpuInfo != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                child: Text(
                  _gpuInfo!,
                  style: TextStyle(
                    fontSize: 12,
                    color: BeeTokens.textSecondary(context),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
              child: Text(
                '模型保存在 App 私有目录，其他应用无法访问，卸载 App 时会一并删除。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: BeeTokens.textTertiary(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modelCard(
      LocalModelInfo model, String? selectedId, String? modelDir) {
    final path = modelDir == null
        ? null
        : '$modelDir${Platform.pathSeparator}${model.fileName}';
    final file = path == null ? null : File(path);
    final exists = file?.existsSync() ?? false;
    final size = exists ? file!.lengthSync() : 0;
    final downloading = _downloadingId == model.id;
    final selected = selectedId == model.id;
    final progress = downloading
        ? (_total > 0 ? (_received / _total).clamp(0.0, 1.0) : 0.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.5)
              : BeeTokens.border(context),
          width: selected ? 1.2 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                model.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: BeeTokens.textPrimary(context),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${model.quantization} · ${model.sizeLabel}',
                style: TextStyle(
                  fontSize: 11,
                  color: BeeTokens.textTertiary(context),
                ),
              ),
              const Spacer(),
              if (selected)
                Icon(Icons.check_circle,
                    size: 18, color: Theme.of(context).colorScheme.primary),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            model.usage,
            style: TextStyle(
              fontSize: 12,
              color: BeeTokens.textSecondary(context),
            ),
          ),
          if (exists) ...[
            const SizedBox(height: 6),
            Text(
              '已下载 · ${_formatBytes(size)}',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
          if (downloading) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: progress == 0 ? null : progress),
            const SizedBox(height: 6),
            Text(
              _total > 0
                  ? '${(_received / 1024 / 1024).toStringAsFixed(1)} / '
                      '${(_total / 1024 / 1024).toStringAsFixed(1)} MB'
                  : '${(_received / 1024 / 1024).toStringAsFixed(1)} MB',
              style: TextStyle(
                fontSize: 11,
                color: BeeTokens.textTertiary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (downloading)
                OutlinedButton(
                  onPressed: _cancelling
                      ? null
                      : () {
                          setState(() => _cancelling = true);
                          _downloader.cancel();
                        },
                  child: Text(_cancelling ? '正在取消…' : '取消'),
                )
              else if (!exists)
                FilledButton(
                  onPressed: _downloadingId == null ? () => _download(model) : null,
                  child: const Text('下载'),
                )
              else ...[
                if (!selected)
                  FilledButton(
                    onPressed: () {
                      ref.read(aiLocalModelIdProvider.notifier).state = model.id;
                      setState(() {});
                    },
                    child: const Text('使用此模型'),
                  ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => _delete(model),
                  child: const Text('删除'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: BeeTokens.textTertiary(context),
        ),
      ),
    );
  }

  Widget _group(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BeeTokens.border(context), width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: children),
      ),
    );
  }

  Widget _textTile({
    required TextEditingController controller,
    required String label,
    required String hint,
    required ValueChanged<String> onChanged,
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: onChanged,
        style: TextStyle(color: BeeTokens.textPrimary(context)),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: TextStyle(color: BeeTokens.textSecondary(context)),
          hintStyle: TextStyle(color: BeeTokens.textTertiary(context)),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
  }
}

/// 本地模型目录的同步缓存（仅用于 UI 展示文件是否存在）。
final _modelDirProvider = FutureProvider<String>((ref) async {
  final dir = await localModelDirectory();
  return dir.path;
});
