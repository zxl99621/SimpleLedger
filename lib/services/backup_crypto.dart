import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// 备份密码错误或文件被篡改。
class BackupCryptoException implements Exception {
  const BackupCryptoException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 可选密码加密：PBKDF2-HMAC-SHA256 派生密钥 + AES-256-GCM。
///
/// 文件格式：`SLBK1`(5) + salt(16) + nonce(12) + 密文(含 16 字节认证标签)。
/// 头部同时作为 AAD 参与认证，改动 salt/nonce 也会导致解密失败。
class BackupCrypto {
  BackupCrypto._();

  static const List<int> _magic = [0x53, 0x4C, 0x42, 0x4B, 0x31]; // SLBK1
  static const int _saltLength = 16;
  static const int _nonceLength = 12;
  static const int _keyLength = 32;
  static const int _tagBits = 128;
  static const int _iterations = 100000;

  static bool isEncrypted(Uint8List data) {
    if (data.length <= _magic.length) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (data[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<Uint8List> encrypt(Uint8List plain, String password) {
    return Isolate.run(() => _encryptSync(plain, password));
  }

  static Future<Uint8List> decrypt(Uint8List encrypted, String password) {
    return Isolate.run(() => _decryptSync(encrypted, password));
  }

  static Uint8List _encryptSync(Uint8List plain, String password) {
    final random = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(_saltLength, (_) => random.nextInt(256)));
    final nonce = Uint8List.fromList(
        List<int>.generate(_nonceLength, (_) => random.nextInt(256)));
    final header = Uint8List.fromList([..._magic, ...salt, ...nonce]);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(_deriveKey(password, salt)),
          _tagBits,
          nonce,
          header,
        ),
      );

    final cipherText = cipher.process(plain);
    return Uint8List.fromList([...header, ...cipherText]);
  }

  static Uint8List _decryptSync(Uint8List encrypted, String password) {
    final headerLength = _magic.length + _saltLength + _nonceLength;
    if (!isEncrypted(encrypted) || encrypted.length <= headerLength) {
      throw const BackupCryptoException('不是有效的加密备份文件');
    }

    final salt = Uint8List.sublistView(
        encrypted, _magic.length, _magic.length + _saltLength);
    final nonce = Uint8List.sublistView(encrypted,
        _magic.length + _saltLength, headerLength);
    final header = Uint8List.sublistView(encrypted, 0, headerLength);
    final cipherText = Uint8List.sublistView(encrypted, headerLength);

    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(_deriveKey(password, salt)),
            _tagBits,
            nonce,
            header,
          ),
        );
      return cipher.process(cipherText);
    } catch (_) {
      throw const BackupCryptoException('密码错误或备份文件已损坏');
    }
  }

  static Uint8List _deriveKey(String password, Uint8List salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, _iterations, _keyLength));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }
}
