import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_settings.dart';
import 'model_validation.dart';

/// AI 推理模式（默认云端，首次使用会引导选择）。
final aiModeProvider = StateProvider<AiMode>((ref) => AiMode.cloud);

/// OpenAI 兼容接口地址（需包含 /v1 等路径前缀）。
final aiBaseUrlProvider =
    StateProvider<String>((ref) => 'https://api.deepseek.com/v1');

/// 云端模型名。
final aiModelNameProvider = StateProvider<String>((ref) => 'deepseek-chat');

/// OCR 使用的视觉模型名；留空则复用主模型名。
final aiOcrModelNameProvider = StateProvider<String>((ref) => '');

/// OCR 独立开关（仅云端可用）。
final aiOcrEnabledProvider = StateProvider<bool>((ref) => false);

/// 当前本地模型 id（对应 [localModelCatalog]）。
final aiLocalModelIdProvider = StateProvider<String?>((ref) => null);

/// 是否尝试使用 Vulkan GPU 加速。
///
/// 默认关闭：移动端 ggml-Vulkan 在部分驱动（实测 Mali）会在张量分配阶段
/// 原生崩溃，无法用 Dart try/catch 兜底。GPU 作为实验能力，需用户手动开启。
final aiGpuEnabledProvider = StateProvider<bool>((ref) => false);

/// 本地模型下载源。
final aiModelSourceProvider =
    StateProvider<ModelSource>((ref) => ModelSource.modelscope);

/// 自定义模型下载 URL（source == custom 时使用）。
final aiCustomModelUrlProvider = StateProvider<String>((ref) => '');

/// 是否已完成首次 AI 模式引导。
final aiFirstUseDoneProvider = StateProvider<bool>((ref) => false);

/// 从统计页跳转 AI 页时要自动执行的功能（summary / insight / null）。
final aiPendingFeatureProvider = StateProvider<String?>((ref) => null);

/// 内存中的 API Key（不落明文，持久化走 Keystore 加密存储）。
final aiApiKeyProvider = StateProvider<String?>((ref) => null);

const _secureStorage = FlutterSecureStorage();
const _apiKeyStorageKey = 'simpleledger_ai_api_key';

/// 本地模型目录（App 私有沙箱，卸载时一并清除）。
Future<Directory> localModelDirectory() async {
  final support = await getApplicationSupportDirectory();
  final dir = Directory(p.join(support.path, 'models'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

Future<String> localModelPath(String fileName) async {
  final dir = await localModelDirectory();
  return p.join(dir.path, fileName);
}

/// 启动时恢复 AI 配置，并把后续修改持久化。
final aiConfigInitProvider = FutureProvider<void>((ref) async {
  final prefs = await SharedPreferences.getInstance();

  final mode = prefs.getString('simple_ai_mode');
  if (mode != null) {
    ref.read(aiModeProvider.notifier).state =
        AiMode.values.firstWhere((e) => e.name == mode,
            orElse: () => AiMode.cloud);
  }
  final baseUrl = prefs.getString('simple_ai_base_url');
  if (baseUrl != null && baseUrl.isNotEmpty) {
    ref.read(aiBaseUrlProvider.notifier).state = baseUrl;
  }
  final modelName = prefs.getString('simple_ai_model_name');
  if (modelName != null) {
    ref.read(aiModelNameProvider.notifier).state = modelName;
  }
  final ocrModel = prefs.getString('simple_ai_ocr_model');
  if (ocrModel != null) {
    ref.read(aiOcrModelNameProvider.notifier).state = ocrModel;
  }
  ref.read(aiOcrEnabledProvider.notifier).state =
      prefs.getBool('simple_ai_ocr_enabled') ?? false;
  final localModelId = prefs.getString('simple_ai_local_model_id');
  if (localModelId != null && localModelId.isNotEmpty) {
    ref.read(aiLocalModelIdProvider.notifier).state = localModelId;
  }
  final source = prefs.getString('simple_ai_model_source');
  if (source != null) {
    ref.read(aiModelSourceProvider.notifier).state =
        ModelSource.values.firstWhere((e) => e.name == source,
            orElse: () => ModelSource.modelscope);
  }
  final customUrl = prefs.getString('simple_ai_custom_url');
  if (customUrl != null) {
    ref.read(aiCustomModelUrlProvider.notifier).state = customUrl;
  }
  ref.read(aiFirstUseDoneProvider.notifier).state =
      prefs.getBool('simple_ai_first_use_done') ?? false;
  // 新 key：旧版本可能把 GPU 开关持久化为 true，升级后必须回到默认 CPU。
  ref.read(aiGpuEnabledProvider.notifier).state =
      prefs.getBool('simple_ai_gpu_enabled_v2') ?? false;

  final key = await _secureStorage.read(key: _apiKeyStorageKey);
  if (key != null) {
    ref.read(aiApiKeyProvider.notifier).state = key;
  }

  // 持久化监听
  ref.listen<AiMode>(aiModeProvider, (_, next) {
    prefs.setString('simple_ai_mode', next.name);
  });
  ref.listen<String>(aiBaseUrlProvider, (_, next) {
    prefs.setString('simple_ai_base_url', next);
  });
  ref.listen<String>(aiModelNameProvider, (_, next) {
    prefs.setString('simple_ai_model_name', next);
  });
  ref.listen<String>(aiOcrModelNameProvider, (_, next) {
    prefs.setString('simple_ai_ocr_model', next);
  });
  ref.listen<bool>(aiOcrEnabledProvider, (_, next) {
    prefs.setBool('simple_ai_ocr_enabled', next);
  });
  ref.listen<String?>(aiLocalModelIdProvider, (_, next) {
    prefs.setString('simple_ai_local_model_id', next ?? '');
  });
  ref.listen<ModelSource>(aiModelSourceProvider, (_, next) {
    prefs.setString('simple_ai_model_source', next.name);
  });
  ref.listen<String>(aiCustomModelUrlProvider, (_, next) {
    prefs.setString('simple_ai_custom_url', next);
  });
  ref.listen<bool>(aiFirstUseDoneProvider, (_, next) {
    prefs.setBool('simple_ai_first_use_done', next);
  });
  ref.listen<bool>(aiGpuEnabledProvider, (_, next) {
    prefs.setBool('simple_ai_gpu_enabled_v2', next);
  });
  ref.listen<String?>(aiApiKeyProvider, (_, next) async {
    final value = next?.trim() ?? '';
    if (value.isEmpty) {
      await _secureStorage.delete(key: _apiKeyStorageKey);
    } else {
      await _secureStorage.write(key: _apiKeyStorageKey, value: value);
    }
  });
});

/// 本地模型的可用状态（比“文件存在”更细，供 UI 给出可操作的提示）。
enum LocalModelStatus { notSelected, checking, missing, unsupportedAbi, invalid, ready }

class LocalModelStatusInfo {
  const LocalModelStatusInfo(
    this.status, {
    this.path,
    this.sizeBytes,
    this.reason,
  });

  final LocalModelStatus status;
  final String? path;
  final int? sizeBytes;
  final String? reason;
}

/// 校验本地模型：ABI → 文件存在 → 大小合理 → GGUF magic。
final localModelStatusProvider =
    FutureProvider<LocalModelStatusInfo>((ref) async {
  final id = ref.watch(aiLocalModelIdProvider);
  final model = localModelById(id);
  if (model == null) {
    return const LocalModelStatusInfo(LocalModelStatus.notSelected);
  }

  // llama_flutter_android 只提供 arm64-v8a 原生库。
  if (!isArm64AbiName(Abi.current().toString())) {
    return const LocalModelStatusInfo(
      LocalModelStatus.unsupportedAbi,
      reason: '本地模型仅支持 arm64 设备',
    );
  }

  final path = await localModelPath(model.fileName);
  final file = File(path);
  if (!await file.exists()) {
    return LocalModelStatusInfo(LocalModelStatus.missing, path: path);
  }

  final size = await file.length();
  if (!isPlausibleModelSize(size)) {
    return LocalModelStatusInfo(
      LocalModelStatus.invalid,
      path: path,
      sizeBytes: size,
      reason: '模型文件不完整，请重新下载',
    );
  }

  try {
    final raf = await file.open();
    List<int> header;
    try {
      header = await raf.read(4);
    } finally {
      await raf.close();
    }
    if (!isGgufHeader(header)) {
      return LocalModelStatusInfo(
        LocalModelStatus.invalid,
        path: path,
        sizeBytes: size,
        reason: '不是有效的 GGUF 模型文件，请重新下载',
      );
    }
  } catch (error) {
    return LocalModelStatusInfo(
      LocalModelStatus.invalid,
      path: path,
      sizeBytes: size,
      reason: '模型文件无法读取：$error',
    );
  }

  return LocalModelStatusInfo(
    LocalModelStatus.ready,
    path: path,
    sizeBytes: size,
  );
});

/// 当前本地模型文件路径；未选择或校验未通过时返回 null。
final aiLocalModelFileProvider = FutureProvider<String?>((ref) async {
  final info = await ref.watch(localModelStatusProvider.future);
  return info.status == LocalModelStatus.ready ? info.path : null;
});

/// AI 是否已具备可用配置（云端需要地址+模型+Key；本地需要通过文件校验）。
final aiReadyProvider = Provider<bool>((ref) {
  final mode = ref.watch(aiModeProvider);
  if (mode == AiMode.local) {
    return ref.watch(localModelStatusProvider).valueOrNull?.status ==
        LocalModelStatus.ready;
  }
  final baseUrl = ref.watch(aiBaseUrlProvider).trim();
  final model = ref.watch(aiModelNameProvider).trim();
  final key = (ref.watch(aiApiKeyProvider) ?? '').trim();
  return baseUrl.isNotEmpty && model.isNotEmpty && key.isNotEmpty;
});
