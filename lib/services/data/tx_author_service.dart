import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 共享账本移除后，交易不再记录跨设备作者信息。
///
/// 保留这组空实现，避免编辑/创建交易的主流程需要大范围改动。
class TxAuthorService {
  TxAuthorService._();

  static Future<void> markCreated(WidgetRef ref, int txId) async {}

  static Future<void> markEdited(WidgetRef ref, int txId) async {}

  static Future<void> markCreatedC(ProviderContainer c, int txId) async {}

  static Future<void> markEditedC(ProviderContainer c, int txId) async {}
}
