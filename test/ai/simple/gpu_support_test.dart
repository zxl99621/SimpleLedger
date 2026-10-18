/// 原生 GPU 卸载能力探测。
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/ai/simple/gpu_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('simpleledger/llama');

  testWidgets('原生返回 true 时可用', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      expect(call.method, 'supportsGpuOffload');
      return true;
    });

    expect(await supportsGpuOffload(), isTrue);
  });

  testWidgets('原生通道不存在时安全回退为 false', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      throw MissingPluginException();
    });

    expect(await supportsGpuOffload(), isFalse);
  });
}
