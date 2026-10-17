import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 完整备份 / 恢复。
///
/// 备份内容：SQLite 数据库 + 图片附件 + 自定义图标，打包为 zip。
/// 恢复时只接受白名单条目，拒绝绝对路径与 `..` 路径穿越。
class SimpleBackupService {
  static const String dbFileName = 'beecount.sqlite';
  static const List<String> contentDirs = [
    'attachments',
    'attachment_thumbs',
    'custom_icons',
  ];

  /// 生成备份 zip（位于系统临时目录），返回文件。
  Future<File> createBackup() async {
    final docs = await getApplicationDocumentsDirectory();
    final stamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final zipPath = p.join(
      Directory.systemTemp.path,
      'simpleledger_backup_$stamp.zip',
    );

    final dbFile = File(p.join(docs.path, dbFileName));
    if (!await dbFile.exists()) {
      throw const FileSystemException('数据库文件不存在，无法备份');
    }

    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    try {
      await encoder.addFile(dbFile, dbFileName);
      for (final name in contentDirs) {
        final dir = Directory(p.join(docs.path, name));
        if (await dir.exists()) {
          await encoder.addDirectory(dir, includeDirName: true);
        }
      }
    } finally {
      await encoder.close();
    }
    return File(zipPath);
  }

  /// 校验备份并解压到临时目录。返回临时目录路径。
  Future<String> extractAndValidate(Uint8List bytes) async {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('不是有效的 zip 备份文件');
    }

    final temp = await Directory.systemTemp.createTemp('simpleledger_restore_');

    var foundDb = false;
    for (final entry in archive) {
      final rawName = entry.name.replaceAll('\\', '/');
      final normalized = p.posix.normalize(rawName);
      if (normalized.startsWith('../') ||
          normalized == '..' ||
          normalized.startsWith('/') ||
          normalized.contains(':') ||
          normalized.contains('/../')) {
        await temp.delete(recursive: true);
        throw const FormatException('备份文件包含非法路径');
      }

      final topLevel = normalized.split('/').first;
      final allowed = normalized == dbFileName ||
          contentDirs.contains(topLevel) ||
          normalized == '${contentDirs.first}/';
      if (!allowed) continue;

      if (entry.isFile) {
        final outFile = File(p.joinAll([temp.path, ...normalized.split('/')]));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content as List<int>, flush: false);
        if (normalized == dbFileName) foundDb = true;
      }
    }

    if (!foundDb) {
      await temp.delete(recursive: true);
      throw const FormatException('备份中缺少数据库文件');
    }

    // 校验 SQLite 文件头，避免把任意文件当成数据库覆盖进去。
    final db = File(p.join(temp.path, dbFileName));
    final header = await db.openRead(0, 16).expand((chunk) => chunk).toList();
    const sqliteHeader = 'SQLite format 3\u0000';
    final headerText = String.fromCharCodes(header);
    if (headerText != sqliteHeader) {
      await temp.delete(recursive: true);
      throw const FormatException('数据库文件已损坏');
    }

    return temp.path;
  }

  /// 用已解压的备份覆盖 App 数据目录。
  ///
  /// 调用前必须先关闭数据库连接。
  Future<void> applyRestore(String extractedDir) async {
    final docs = await getApplicationDocumentsDirectory();
    final source = Directory(extractedDir);

    for (final suffix in ['', '-wal', '-shm']) {
      final file = File(p.join(docs.path, '$dbFileName$suffix'));
      if (await file.exists()) await file.delete();
    }

    final restoredDb = File(p.join(source.path, dbFileName));
    await restoredDb.copy(p.join(docs.path, dbFileName));

    for (final name in contentDirs) {
      final target = Directory(p.join(docs.path, name));
      if (await target.exists()) {
        await target.delete(recursive: true);
      }
      final backupDir = Directory(p.join(source.path, name));
      if (await backupDir.exists()) {
        await _copyDirectory(backupDir, target);
      }
    }

    await source.delete(recursive: true);
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(p.join(target.path, name)));
      } else if (entity is File) {
        await entity.copy(p.join(target.path, name));
      }
    }
  }
}
