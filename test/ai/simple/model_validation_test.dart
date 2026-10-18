/// 本地模型文件/设备可用性的轻量校验。
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/ai/simple/model_validation.dart';

void main() {
  group('isGgufHeader', () {
    test('GGUF magic 通过', () {
      expect(isGgufHeader([0x47, 0x47, 0x55, 0x46]), isTrue);
    });

    test('HTML 错误页/空文件/短文件拒绝', () {
      expect(isGgufHeader('<html>'.codeUnits), isFalse);
      expect(isGgufHeader(const []), isFalse);
      expect(isGgufHeader([0x47, 0x47]), isFalse);
    });
  });

  group('isArm64AbiName', () {
    test('arm64 变体通过', () {
      expect(isArm64AbiName('androidArm64'), isTrue);
      expect(isArm64AbiName('Abi.arm64'), isTrue);
    });

    test('32 位与 x64 拒绝', () {
      expect(isArm64AbiName('androidArm'), isFalse);
      expect(isArm64AbiName('androidX64'), isFalse);
      expect(isArm64AbiName('windowsX64'), isFalse);
    });
  });

  group('isPlausibleModelSize', () {
    test('过小的文件视为不完整', () {
      expect(isPlausibleModelSize(1024 * 1024), isFalse);
      expect(isPlausibleModelSize(0), isFalse);
    });

    test('超过 64MB 视为可能的完整 GGUF', () {
      expect(isPlausibleModelSize(64 * 1024 * 1024), isTrue);
      expect(isPlausibleModelSize(2 * 1024 * 1024 * 1024), isTrue);
    });
  });
}
