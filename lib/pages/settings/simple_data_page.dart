import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../providers.dart';
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
    await _runBusy('正在打包备份…', () async {
      final db = ref.read(databaseProvider);
      // 把 WAL 内容合并回主数据库文件，保证备份是完整快照。
      await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

      final zip = await _backupService.createBackup();
      final bytes = await zip.readAsBytes();
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '保存备份',
        fileName: p.basename(zip.path),
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: bytes,
      );
      if (saved != null) {
        if (mounted) _showMessage('备份已保存');
      }
      if (await zip.exists()) await zip.delete();
    });
  }

  Future<void> _restore() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择备份文件',
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final file = picked?.files.single;
    final path = file?.path;
    if (path == null) return;

    await _runBusy('正在校验备份…', () async {
      final bytes = await File(path).readAsBytes();
      final extracted = await _backupService.extractAndValidate(bytes);

      if (!mounted) return;
      final confirmed = await _confirm(
        title: '恢复备份？',
        message: '当前账单与图片将被备份内容完全覆盖，且无法撤销。恢复完成后 App 会自动关闭，请重新打开。',
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
      message: '所有账单、标签和图片都会被删除，此操作无法撤销。',
      confirmText: '清空',
      destructive: true,
    );
    if (!confirmed) return;

    await _runBusy('正在清空…', () async {
      final db = ref.read(databaseProvider);
      await db.transaction(() async {
        await db.delete(db.transactionTags).go();
        await db.delete(db.transactionAttachments).go();
        await db.delete(db.transactions).go();
        await db.delete(db.tags).go();
      });

      final docs = await getApplicationDocumentsDirectory();
      for (final name in SimpleBackupService.contentDirs) {
        final dir = Directory(p.join(docs.path, name));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }

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
