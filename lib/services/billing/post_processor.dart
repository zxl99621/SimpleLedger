import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers.dart';
import '../attachment_service.dart';
import '../system/logger_service.dart';

/// 数据变更后的统一后处理服务
///
/// 两类方法：
/// - `run` 系列：交易创建后使用，刷新统计 + 可选刷新标签/附件 + 同步
/// - `sync` 系列：其他数据变更后使用（分类、账户等），仅同步
class PostProcessor {
  // ============ 交易后完整处理 ============

  /// UI 层使用（WidgetRef）
  static Future<void> run(
    WidgetRef ref, {
    required int ledgerId,
    bool tags = false,
    bool attachments = false,
  }) async {
    ref.read(statsRefreshProvider.notifier).state++;
    if (tags) ref.read(tagListRefreshProvider.notifier).state++;
    if (attachments) ref.read(attachmentListRefreshProvider.notifier).state++;
    await _doSync(ref, ledgerId);
  }

  /// 后台服务使用（ProviderContainer）
  static Future<void> runC(
    ProviderContainer c, {
    required int ledgerId,
    bool tags = false,
    bool attachments = false,
  }) async {
    c.read(statsRefreshProvider.notifier).state++;
    if (tags) c.read(tagListRefreshProvider.notifier).state++;
    if (attachments) c.read(attachmentListRefreshProvider.notifier).state++;
    await _doSyncC(c, ledgerId);
  }

  /// Provider 内部使用（Ref）
  static Future<void> runR(
    Ref ref, {
    required int ledgerId,
    bool tags = false,
    bool attachments = false,
  }) async {
    ref.read(statsRefreshProvider.notifier).state++;
    if (tags) ref.read(tagListRefreshProvider.notifier).state++;
    if (attachments) ref.read(attachmentListRefreshProvider.notifier).state++;
    await _doSyncR(ref, ledgerId);
  }

  // ============ 仅同步 ============

  /// UI 层使用（WidgetRef）
  static Future<void> sync(WidgetRef ref, {required int ledgerId}) =>
      _doSync(ref, ledgerId);

  /// 后台服务使用（ProviderContainer）
  static Future<void> syncC(ProviderContainer c, {required int ledgerId}) =>
      _doSyncC(c, ledgerId);

  /// Provider 内部使用（Ref）
  static Future<void> syncR(Ref ref, {required int ledgerId}) =>
      _doSyncR(ref, ledgerId);

  // ============ 云端下载后处理（仅刷新，不触发同步） ============

  /// 云端下载后的处理：刷新统计和UI状态，但不触发同步上传
  /// UI 层使用（WidgetRef）
  static void runAfterDownload(WidgetRef ref) {
    ref.read(statsRefreshProvider.notifier).state++;
    ref.read(syncStatusRefreshProvider.notifier).state++;
    ref.read(ledgerListRefreshProvider.notifier).state++;
    ref.read(tagListRefreshProvider.notifier).state++;
    ref.read(attachmentListRefreshProvider.notifier).state++;
    logger.info('PostProcessor', '云端下载后刷新完成');
  }

  /// 云端下载后的处理：刷新统计和UI状态，但不触发同步上传
  /// 后台服务使用（ProviderContainer）
  static void runAfterDownloadC(ProviderContainer c) {
    c.read(statsRefreshProvider.notifier).state++;
    c.read(syncStatusRefreshProvider.notifier).state++;
    c.read(ledgerListRefreshProvider.notifier).state++;
    c.read(tagListRefreshProvider.notifier).state++;
    c.read(attachmentListRefreshProvider.notifier).state++;
    logger.info('PostProcessor', '云端下载后刷新完成');
  }

  // ============ 内部刷新实现 ============

  // 极简版没有云同步，只负责触发依赖这些 tick 的本地页面重算。
  static Future<void> _doSync(WidgetRef ref, int ledgerId) async {
    ref.read(syncStatusRefreshProvider.notifier).state++;
    ref.read(ledgerListRefreshProvider.notifier).state++;
  }

  static Future<void> _doSyncC(ProviderContainer c, int ledgerId) async {
    c.read(syncStatusRefreshProvider.notifier).state++;
    c.read(ledgerListRefreshProvider.notifier).state++;
  }

  static Future<void> _doSyncR(Ref ref, int ledgerId) async {
    ref.read(syncStatusRefreshProvider.notifier).state++;
    ref.read(ledgerListRefreshProvider.notifier).state++;
  }
}
