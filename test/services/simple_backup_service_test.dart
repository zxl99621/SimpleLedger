import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:beecount/services/simple_backup_service.dart';

void main() {
  group('clearContentImages', () {
    late Directory docs;

    setUp(() async {
      docs = await Directory.systemTemp.createTemp('simpleledger_clear_test_');
    });

    tearDown(() async {
      if (await docs.exists()) await docs.delete(recursive: true);
    });

    test('删除账单图片与缩略图，保留分类仍在引用的自定义图标', () async {
      final attachments = Directory(p.join(docs.path, 'attachments'));
      final thumbs = Directory(p.join(docs.path, 'attachment_thumbs'));
      final icons = Directory(p.join(docs.path, 'custom_icons'));
      await attachments.create(recursive: true);
      await thumbs.create(recursive: true);
      await icons.create(recursive: true);

      final attachment = File(p.join(attachments.path, 'bill.jpg'));
      final thumb = File(p.join(thumbs.path, 'bill_thumb.jpg'));
      final keptIcon = File(p.join(icons.path, 'food.png'));
      final orphanIcon = File(p.join(icons.path, 'old.png'));
      for (final file in [attachment, thumb, keptIcon, orphanIcon]) {
        await file.writeAsBytes([1, 2, 3]);
      }

      await SimpleBackupService().clearContentImages(
        docs,
        referencedCustomIconNames: {'food.png'},
      );

      expect(await attachment.exists(), isFalse);
      expect(await thumb.exists(), isFalse);
      expect(await keptIcon.exists(), isTrue);
      expect(await orphanIcon.exists(), isFalse);
      expect(await attachments.exists(), isFalse);
      expect(await thumbs.exists(), isFalse);
      expect(await icons.exists(), isTrue);
    });

    test('没有自定义图标引用时清空整个目录', () async {
      final icons = Directory(p.join(docs.path, 'custom_icons'));
      await icons.create(recursive: true);
      final icon = File(p.join(icons.path, 'old.png'));
      await icon.writeAsBytes([1]);

      await SimpleBackupService().clearContentImages(
        docs,
        referencedCustomIconNames: const {},
      );

      expect(await icons.exists(), isFalse);
    });
  });

  group('extractAndValidate', () {
    Future<Uint8List> buildZip(String dbPath) async {
      final archive = Archive()
        ..addFile(ArchiveFile(
          SimpleBackupService.dbFileName,
          await File(dbPath).length(),
          await File(dbPath).readAsBytes(),
        ));
      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    }

    Future<Directory> createDb(int userVersion) async {
      final dir = await Directory.systemTemp.createTemp('backup_db_');
      final path = p.join(dir.path, SimpleBackupService.dbFileName);
      final db = sqlite3.open(path);
      db.execute('CREATE TABLE sample (id INTEGER PRIMARY KEY, note TEXT)');
      db.execute('INSERT INTO sample (note) VALUES (\'ok\')');
      db.execute('PRAGMA user_version = $userVersion');
      db.close();
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      return dir;
    }

    test('完整性和 schema 版本都通过时接受备份', () async {
      final dir = await createDb(SimpleBackupService.supportedSchemaVersion);
      final zip = await buildZip(p.join(dir.path, SimpleBackupService.dbFileName));

      final extracted =
          await SimpleBackupService().extractAndValidate(zip);

      final restored = File(p.join(extracted, SimpleBackupService.dbFileName));
      expect(await restored.exists(), isTrue);
      addTearDown(() async {
        final d = Directory(extracted);
        if (await d.exists()) await d.delete(recursive: true);
      });
    });

    test('拒绝来自更新 schema 版本的备份', () async {
      final dir = await createDb(SimpleBackupService.supportedSchemaVersion + 1);
      final zip = await buildZip(p.join(dir.path, SimpleBackupService.dbFileName));

      await expectLater(
        SimpleBackupService().extractAndValidate(zip),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('applyRestore', () {
    late Directory docs;
    late Directory extracted;

    setUp(() async {
      docs = await Directory.systemTemp.createTemp('restore_docs_');
      extracted = await Directory.systemTemp.createTemp('restore_src_');
    });

    tearDown(() async {
      if (await docs.exists()) await docs.delete(recursive: true);
      if (await extracted.exists()) await extracted.delete(recursive: true);
    });

    test('成功恢复后替换数据库与图片目录', () async {
      final oldDb = File(p.join(docs.path, SimpleBackupService.dbFileName));
      await oldDb.writeAsString('OLD');
      final oldAttachments =
          Directory(p.join(docs.path, 'attachments'));
      await oldAttachments.create(recursive: true);
      await File(p.join(oldAttachments.path, 'old.jpg')).writeAsBytes([1]);

      final newDb = File(p.join(extracted.path, SimpleBackupService.dbFileName));
      await newDb.writeAsString('NEW');
      final newAttachments =
          Directory(p.join(extracted.path, 'attachments'));
      await newAttachments.create(recursive: true);
      await File(p.join(newAttachments.path, 'new.jpg')).writeAsBytes([2]);

      await SimpleBackupService().applyRestore(
        extracted.path,
        documentsDir: docs,
      );

      expect(
        await File(p.join(docs.path, SimpleBackupService.dbFileName))
            .readAsString(),
        'NEW',
      );
      expect(
        await File(p.join(docs.path, 'attachments', 'new.jpg')).exists(),
        isTrue,
      );
      expect(
        await File(p.join(docs.path, 'attachments', 'old.jpg')).exists(),
        isFalse,
      );
      expect(
        await Directory(p.join(docs.path, 'attachments')).exists(),
        isTrue,
      );
      expect(await extracted.exists(), isFalse);
      final leftovers = await docs
          .list()
          .where((e) => p.basename(e.path).startsWith('.restore_rollback_'))
          .toList();
      expect(leftovers, isEmpty);
    });

    test('解压目录缺少数据库时不动现有数据', () async {
      final oldDb = File(p.join(docs.path, SimpleBackupService.dbFileName));
      await oldDb.writeAsString('OLD');

      await expectLater(
        SimpleBackupService().applyRestore(
          extracted.path,
          documentsDir: docs,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(await oldDb.readAsString(), 'OLD');
    });
  });
}
