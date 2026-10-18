/// 本地引擎的 modelPath 必须直接来自已经校验完成的模型状态，避免
/// `aiLocalModelFileProvider` 尚未就绪时拿到空路径。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/ai/simple/ai_providers.dart';
import 'package:beecount/ai/simple/ai_service.dart';
import 'package:beecount/ai/simple/ai_settings.dart';
import 'package:beecount/ai/simple/local_ai_engine.dart';

void main() {
  test('本地模式使用模型状态里的 path', () async {
    final container = ProviderContainer(
      overrides: [
        aiModeProvider.overrideWith((ref) => AiMode.local),
        aiGpuEnabledProvider.overrideWith((ref) => false),
        localModelStatusProvider.overrideWith(
          (ref) async => const LocalModelStatusInfo(
            LocalModelStatus.ready,
            path: '/tmp/model.gguf',
          ),
        ),
        // 模拟另一个 FutureProvider 尚未就绪。
        aiLocalModelFileProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(container.dispose);

    await container.read(localModelStatusProvider.future);

    final engine = container.read(aiEngineProvider) as LocalAiEngine;
    expect(engine.modelPath, '/tmp/model.gguf');
    expect(engine.useGpu, isFalse);
  });
}
