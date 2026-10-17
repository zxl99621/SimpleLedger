import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../providers.dart';
import '../../services/backup_crypto.dart';
import '../../services/simple_backup_service.dart';
import '../../styles/tokens.dart';
import '../data/export_page.dart';
import '../data/import_page.dart';

/// 极简记账 - 备份与恢复页
class SimpleDataPage extends ConsumerStatefulWidget {
  const SimpleDataPage({super.key});

  @override
  ConsumerState<SimpleDataPage> createState() => _SimpleDataPageState();
}

class _SimpleDataPageState extends ConsumerState<SimpleDataPage> {
  final _backupService = SimpleBackupService();

  /// 当前实现会把整个 zip 读入内存；超过该阈值直接提示，避免 OOM。
  static const int _maxBackupBytes = 512 * 1024 * 1024;

  bool _busy = false;
  String _busyLabel = '';

  Future<void> _runBusy(String label, Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      await task();
    } catch (error) {
      if (mounted) _showMessage('操作失败：$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyLabel = '';
        });
      }
    }
  }

  Future<void> _createBackup() async {
    final dbOnlyBytes = await _backupService.estimateBackupSize(
      includeImages: false,
    );
    final fullBytes = await _backupService.estimateBackupSize(
      includeImages: true,
    );
    if (!mounted) return;

    final choice = await _askBackupOptions(
      dbOnlyBytes: dbOnlyBytes,
      fullBytes: fullBytes,
    );
    if (choice == null) return;

    await _runBusy('正在打包备份…', () async {
      final db = ref.read(databaseProvider);
      // 把 WAL 内容合并回主数据库文件，保证备份是完整快照。
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

      final zip = await _backupService.createBackup(
        includeImages: choice.includeImages,
      );
      if (await zip.length() > _maxBackupBytes) {
        if (await zip.exists()) await zip.delete();
        _showMessage('备份超过 512 MB，当前版本无法安全保存，请改用“仅数据库”或先清理附件');
        return;
      }

      var bytes = await zip.readAsBytes();
      var fileName = p.basename(zip.path);
      var extensions = const ['zip'];
      if (choice.password != null) {
        bytes = await BackupCrypto.encrypt(bytes, choice.password!);
        fileName = fileName.replaceFirst(RegExp(r'\.zip$'), '.slbk');
        extensions = const ['slbk'];
      }

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: extensions,
        bytes: bytes,
      );
      if (saved != null && mounted) {
        final content = choice.includeImages ? '完整备份' : '数据备份（不含图片）';
        _showMessage(choice.password == null ? '$content已保存' : '加密$content已保存');
      }
      if (await zip.exists()) await zip.delete();
    });
  }

  static String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }

  /// 返回 null 表示用户取消。
  Future<_BackupChoice?> _askBackupOptions({
    required int dbOnlyBytes,
    required int fullBytes,
  }) async {
    final password = TextEditingController();
    final confirm = TextEditingController();
    var includeImages = true;
    var usePassword = false;
    String? error;

    final result = await showDialog<_BackupChoice>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final estimated = includeImages ? fullBytes : dbOnlyBytes;
          final overLimit = estimated > _maxBackupBytes;
          return AlertDialog(
            title: const Text('备份选项'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: includeImages,
                  onChanged: (value) =>
                      setDialogState(() => includeImages = value),
                  title: const Text('包含图片附件'),
                  subtitle: const Text('关闭后仅备份账单/分类/标签，文件更小、速度更快'),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '预计大小：${_formatBytes(estimated)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: overLimit
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
                if (overLimit)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '超过 512 MB，当前版本无法安全保存；请关闭“包含图片附件”或先清理附件。',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: usePassword,
                  onChanged: (value) => setDialogState(() {
                    usePassword = value;
                    error = null;
                  }),
                  title: const Text('使用密码加密'),
                  subtitle: const Text('恢复时需要输入同一密码；忘记密码将无法恢复'),
                ),
                if (usePassword) ...[
                  TextField(
                    controller: password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '密码（至少 8 位）'),
                  ),
                  TextField(
                    controller: confirm,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: '确认密码'),
                  ),
                ],
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: overLimit
                    ? null
                    : () {
                        if (!usePassword) {
                          Navigator.pop(
                            dialogContext,
                            _BackupChoice(includeImages: includeImages),
                          );
                          return;
                        }
                        if (password.text.length < 8) {
                          setDialogState(() => error = '密码至少 8 位');
                          return;
                        }
                        if (password.text != confirm.text) {
                          setDialogState(() => error = '两次输入的密码不一致');
                          return;
                        }
                        Navigator.pop(
                          dialogContext,
                          _BackupChoice(
                            includeImages: includeImages,
                            password: password.text,
                          ),
                        );
                      },
                child: const Text('开始备份'),
              ),
            ],
          );
        },
      ),
    );

    password.dispose();
    confirm.dispose();
    return result;
  }

  Future<String?> _askRestorePassword({String? error}) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('输入备份密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('该备份已加密，请输入创建备份时设置的密码。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: '密码'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(dialogContext).colorScheme.error),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: const ['zip', 'slbk'],
    );
    final file = picked?.files.single;
    final path = file?.path;
    if (path == null) return;

    await _runBusy('正在校验备份…', () async {
      final backupFile = File(path);
      if (await backupFile.length() > _maxBackupBytes) {
        _showMessage('备份文件超过 512 MB，当前版本无法安全读取，请先在电脑上解压处理');
        return;
      }

      final raw = await backupFile.readAsBytes();
      Uint8List? decrypted;
      if (BackupCrypto.isEncrypted(raw)) {
        String? error;
        while (mounted) {
          final password = await _askRestorePassword(error: error);
          if (password == null) return;
          try {
            decrypted = await BackupCrypto.decrypt(raw, password);
            break;
          } on BackupCryptoException catch (e) {
            error = e.message;
          }
        }
        if (decrypted == null || !mounted) return;
      }

      final bytes = decrypted ?? raw;
      final extracted = await _backupService.extractAndValidate(bytes);

      if (!mounted) return;
      final hasImages = await SimpleBackupService.hasContentDirs(extracted);
      final confirmed = await _confirm(
        title: '恢复备份？',
        message: hasImages
            ? '当前账单与图片将被备份内容完全覆盖，且无法撤销。恢复完成后 App 会自动关闭，请重新打开。'
            : '当前账单将被备份数据库覆盖，现有图片会保留；此操作无法撤销。恢复完成后 App 会自动关闭，请重新打开。',
        confirmText: '恢复并覆盖',
      );
      if (!confirmed) {
        await Directory(extracted).delete(recursive: true);
        return;
      }

      _busyLabel = '正在恢复…';
      setState(() {});

      // 必须先关闭数据库连接，否则文件仍被占用。
      await ref.read(databaseProvider).close();
      await _backupService.applyRestore(extracted);

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('恢复完成'),
          content: const Text('App 即将关闭，请手动重新打开以加载恢复后的数据。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      await SystemNavigator.pop();
    });
  }

  Future<void> _clearAllBills() async {
    final confirmed = await _confirm(
      title: '清空全部账单？',
      message: '所有账单、标签和账单图片都会被删除（分类图标会保留），此操作无法撤销。',
      confirmText: '清空',
      destructive: true,
    );
    if (!confirmed) return;

    await _runBusy('正在清空…', () async {
      final db = ref.read(databaseProvider);
      final categoryRows = await (db.select(db.categories)
            ..where((c) => c.customIconPath.isNotNull()))
          .get();
      final referencedIcons = <String>{
        for (final row in categoryRows)
          if (row.customIconPath != null && row.customIconPath!.trim().isNotEmpty)
            p.basename(row.customIconPath!),
      };

      await db.transaction(() async {
        await db.delete(db.transactionTagOverrides).go();
        await db.delete(db.transactionTags).go();
        await db.delete(db.transactionAttachments).go();
        await db.delete(db.transactions).go();
        await db.delete(db.tags).go();
      });

      final docs = await getApplicationDocumentsDirectory();
      await _backupService.clearContentImages(
        docs,
        referencedCustomIconNames: referencedIcons,
      );

      ref.read(statsRefreshProvider.notifier).state++;
      if (mounted) _showMessage('已清空全部账单');
    });
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmText,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor:
                  destructive ? Theme.of(context).colorScheme.error : null,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BeeTokens.scaffoldBackground(context),
      appBar: AppBar(title: const Text('备份与恢复')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _group(context, [
                _tile(
                  context,
                  icon: Icons.backup_outlined,
                  title: '立即备份',
                  subtitle: '数据库与图片打包为 zip',
                  onTap: _busy ? null : _createBackup,
                ),
                _tile(
                  context,
                  icon: Icons.restore_outlined,
                  title: '从备份恢复',
                  subtitle: '选择此前导出的 zip 文件',
                  onTap: _busy ? null : _restore,
                ),
              ]),
              const SizedBox(height: 20),
              _group(context, [
                _tile(
                  context,
                  icon: Icons.file_download_outlined,
                  title: 'CSV 导入',
                  subtitle: '辅助迁移，不含图片',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ImportPage()),
                  ),
                ),
                _tile(
                  context,
                  icon: Icons.file_upload_outlined,
                  title: 'CSV 导出',
                  subtitle: '导出全部账单文本',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExportPage()),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              _group(context, [
                _tile(
                  context,
                  icon: Icons.delete_outline,
                  title: '清空全部账单',
                  subtitle: '标签与图片一并删除',
                  destructive: true,
                  onTap: _busy ? null : _clearAllBills,
                ),
              ]),
            ],
          ),
          if (_busy)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.25),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 18),
                    decoration: BoxDecoration(
                      color: BeeTokens.surfaceElevated(context),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _busyLabel,
                          style: TextStyle(
                            fontSize: 13,
                            color: BeeTokens.textSecondary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _group(BuildContext context, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: BeeTokens.surface(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BeeTokens.border(context), width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  indent: 52,
                  color: BeeTokens.divider(context),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final color = destructive
        ? Theme.of(context).colorScheme.error
        : BeeTokens.iconSecondary(context);

    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 22, color: color),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: destructive
              ? Theme.of(context).colorScheme.error
              : BeeTokens.textPrimary(context),
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 12, color: BeeTokens.textTertiary(context)),
      ),
      trailing: Icon(Icons.chevron_right,
          size: 20, color: BeeTokens.iconTertiary(context)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
    );
  }
}

/// 备份选项：是否包含图片，以及可选密码（null 表示明文）。
class _BackupChoice {
  const _BackupChoice({required this.includeImages, this.password});

  final bool includeImages;
  final String? password;
}
