import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../data/schema_version.dart';

/// 完整备份 / 恢复。
///
/// 备份内容：SQLite 数据库 + 图片附件 + 自定义图标，打包为 zip。
/// 恢复时只接受白名单条目，拒绝绝对路径与 `..` 路径穿越。
class SimpleBackupService {
  static const String dbFileName = 'beecount.sqlite';

  /// 恢复时拒绝来自更新版本的备份，避免旧 App 打开新 schema 后直接崩溃。
  static const int supportedSchemaVersion = kSimpleLedgerSchemaVersion;
  static const List<String> contentDirs = [
    'attachments',
    'attachment_thumbs',
    'custom_icons',
  ];

  /// 生成备份 zip（位于系统临时目录），返回文件。
  ///
  /// [includeImages] 为 false 时只打包数据库，适合日常快速备份；
  /// 图片附件、缩略图和自定义图标会被跳过。
  Future<File> createBackup({
    bool includeImages = true,
    Directory? documentsDir,
  }) async {
    final docs = documentsDir ?? await getApplicationDocumentsDirectory();
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
      if (includeImages) {
        for (final name in contentDirs) {
          final dir = Directory(p.join(docs.path, name));
          if (await dir.exists()) {
            await encoder.addDirectory(dir, includeDirName: true);
          }
        }
      }
    } finally {
      await encoder.close();
    }
    return File(zipPath);
  }

  /// 估算备份体积（未压缩前的文件总量），用于备份前提示用户。
  Future<int> estimateBackupSize({
    required bool includeImages,
    Directory? documentsDir,
  }) async {
    final docs = documentsDir ?? await getApplicationDocumentsDirectory();
    var total = 0;

    final dbFile = File(p.join(docs.path, dbFileName));
    if (await dbFile.exists()) total += await dbFile.length();

    if (includeImages) {
      for (final name in contentDirs) {
        final dir = Directory(p.join(docs.path, name));
        if (!await dir.exists()) continue;
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) total += await entity.length();
        }
      }
    }
    return total;
  }

  /// 备份中是否包含图片目录。仅数据库的备份恢复时不应覆盖现有图片。
  static Future<bool> hasContentDirs(String extractedDir) async {
    for (final name in contentDirs) {
      if (await Directory(p.join(extractedDir, name)).exists()) return true;
    }
    return false;
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

    try {
      _validateDatabase(db);
    } catch (error) {
      await temp.delete(recursive: true);
      if (error is FormatException) rethrow;
      throw FormatException('数据库校验失败：$error');
    }

    return temp.path;
  }

  static void _validateDatabase(File dbFile) {
    final Database db;
    try {
      db = sqlite3.open(dbFile.path, mode: OpenMode.readOnly);
    } catch (error) {
      throw FormatException('数据库无法打开：$error');
    }
    try {
      final integrity = db.select('PRAGMA integrity_check');
      final result = integrity.isEmpty
          ? ''
          : '${integrity.first.values.first}'.toLowerCase();
      if (result != 'ok') {
        throw const FormatException('数据库完整性校验失败');
      }

      final versionRows = db.select('PRAGMA user_version');
      final version = versionRows.isEmpty
          ? 0
          : (versionRows.first.values.first as num?)?.toInt() ?? 0;
      if (version > supportedSchemaVersion) {
        throw FormatException(
          '备份来自更新版本的 App（数据库版本 $version），请先升级 App 再恢复',
        );
      }
    } finally {
      db.close();
    }
  }

  /// 清空账单相关的图片目录。
  ///
  /// 账单附件与缩略图整体删除；`custom_icons` 只删除没有被分类引用的文件，
  /// 避免「清空账单」把用户仍在使用的自定义分类图标一起删掉。
  Future<void> clearContentImages(
    Directory docs, {
    required Set<String> referencedCustomIconNames,
  }) async {
    for (final name in ['attachments', 'attachment_thumbs']) {
      final dir = Directory(p.join(docs.path, name));
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }

    final icons = Directory(p.join(docs.path, 'custom_icons'));
    if (!await icons.exists()) return;

    await for (final entity in icons.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      if (referencedCustomIconNames.contains(p.basename(entity.path))) continue;
      try {
        await entity.delete();
      } catch (_) {
        // 单个文件删除失败不阻断整体清理。
      }
    }

    // 清掉空的子目录；目录本身还有被引用的图标就保留。
    await for (final entity in icons.list(recursive: false)) {
      if (entity is Directory && await entity.list().isEmpty) {
        await entity.delete();
      }
    }
    if (await icons.list(recursive: false).isEmpty) {
      await icons.delete(recursive: true);
    }
  }

  /// 用已解压的备份覆盖 App 数据目录。
  ///
  /// 调用前必须先关闭数据库连接。现有数据先整体移入回滚目录，复制失败时
  /// 原样移回，避免“删完旧库、复制新库失败”导致数据全部丢失。
  Future<void> applyRestore(
    String extractedDir, {
    Directory? documentsDir,
  }) async {
    final docs = documentsDir ?? await getApplicationDocumentsDirectory();
    final source = Directory(extractedDir);
    final restoredDb = File(p.join(source.path, dbFileName));
    if (!await restoredDb.exists()) {
      throw const FileSystemException('解压目录中缺少数据库文件');
    }

    final rollback = Directory(
      p.join(docs.path, '.restore_rollback_${DateTime.now().microsecondsSinceEpoch}'),
    );
    await rollback.create(recursive: true);
    final moved = <String>[];
    // 仅数据库的备份不携带图片目录：恢复时保留现有图片。
    final hasContent = await hasContentDirs(source.path);

    try {
      for (final suffix in ['', '-wal', '-shm']) {
        final name = '$dbFileName$suffix';
        final file = File(p.join(docs.path, name));
        if (await file.exists()) {
          await file.rename(p.join(rollback.path, name));
          moved.add(name);
        }
      }

      if (hasContent) {
        for (final name in contentDirs) {
          final dir = Directory(p.join(docs.path, name));
          if (await dir.exists()) {
            await dir.rename(p.join(rollback.path, name));
            moved.add(name);
          }
        }
      }

      await restoredDb.copy(p.join(docs.path, dbFileName));

      if (hasContent) {
        for (final name in contentDirs) {
          final backupDir = Directory(p.join(source.path, name));
          if (await backupDir.exists()) {
            await _copyDirectory(backupDir, Directory(p.join(docs.path, name)));
          }
        }
      }

      await rollback.delete(recursive: true);
    } catch (_) {
      // 清理可能已部分写入的新数据，再把原数据移回原位。
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File(p.join(docs.path, '$dbFileName$suffix'));
        if (await file.exists()) await file.delete();
      }
      if (hasContent) {
        for (final name in contentDirs) {
          final dir = Directory(p.join(docs.path, name));
          if (await dir.exists()) await dir.delete(recursive: true);
        }
      }

      for (final name in moved) {
        final from = p.join(rollback.path, name);
        final to = p.join(docs.path, name);
        final type = FileSystemEntity.typeSync(from);
        if (type == FileSystemEntityType.directory) {
          await Directory(from).rename(to);
        } else if (type == FileSystemEntityType.file) {
          await File(from).rename(to);
        }
      }

      if (await rollback.exists()) await rollback.delete(recursive: true);
      rethrow;
    }

    try {
      await source.delete(recursive: true);
    } catch (_) {
      // 临时解压目录清理失败不影响恢复结果。
    }
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
