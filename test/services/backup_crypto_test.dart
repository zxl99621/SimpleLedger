import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:beecount/services/backup_crypto.dart';

void main() {
  final plain = Uint8List.fromList(utf8.encode('SimpleLedger backup payload'));

  test('加解密往返得到原文', () async {
    final encrypted = await BackupCrypto.encrypt(plain, 'correct horse battery');
    expect(BackupCrypto.isEncrypted(encrypted), isTrue);
    expect(encrypted.length, greaterThan(plain.length));

    final decrypted =
        await BackupCrypto.decrypt(encrypted, 'correct horse battery');
    expect(decrypted, plain);
  });

  test('错误密码无法解密', () async {
    final encrypted = await BackupCrypto.encrypt(plain, 'right-password');
    await expectLater(
      BackupCrypto.decrypt(encrypted, 'wrong-password'),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('篡改密文会被识别', () async {
    final encrypted = await BackupCrypto.encrypt(plain, 'right-password');
    encrypted[encrypted.length - 1] ^= 0xFF;

    await expectLater(
      BackupCrypto.decrypt(encrypted, 'right-password'),
      throwsA(isA<BackupCryptoException>()),
    );
  });

  test('普通 zip 不会被误判为加密文件', () {
    expect(BackupCrypto.isEncrypted(plain), isFalse);
  });
}
