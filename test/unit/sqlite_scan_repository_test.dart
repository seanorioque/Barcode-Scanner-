import 'dart:io';

import 'package:barcode_scanner/data/sqlite_scan_repository.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late SqliteScanRepository repository;

  setUp(() {
    repository = SqliteScanRepository(databaseFactory: databaseFactoryFfi, path: inMemoryDatabasePath);
  });

  tearDown(() => repository.close());

  ScanEntry makeEntry({
    String id = '1',
    String value = '0123456789012',
    String format = 'EAN_13',
    String? label,
    String? imagePath,
    DateTime? scannedAt,
  }) {
    return ScanEntry(
      id: id,
      value: value,
      format: format,
      label: label,
      imagePath: imagePath,
      scannedAt: scannedAt ?? DateTime.utc(2026, 1, 1),
    );
  }

  test('save then watchEntries emits the saved entry', () async {
    final entry = makeEntry();
    await repository.save(entry);

    final entries = await repository.watchEntries().first;
    expect(entries, hasLength(1));
    expect(entries.first.id, entry.id);
    expect(entries.first.value, entry.value);
    expect(entries.first.format, entry.format);
  });

  test('entries are ordered most-recent-first', () async {
    await repository.save(makeEntry(id: '1', value: 'a', scannedAt: DateTime.utc(2026, 1, 1)));
    await repository.save(makeEntry(id: '2', value: 'b', scannedAt: DateTime.utc(2026, 1, 3)));
    await repository.save(makeEntry(id: '3', value: 'c', scannedAt: DateTime.utc(2026, 1, 2)));

    final entries = await repository.watchEntries().first;
    expect(entries.map((e) => e.id).toList(), ['2', '3', '1']);
  });

  test('saving a duplicate active value does not create a second row', () async {
    await repository.save(makeEntry(id: '1', value: 'dup'));
    await repository.save(makeEntry(id: '2', value: 'dup'));

    final entries = await repository.watchEntries().first;
    expect(entries, hasLength(1));
    expect(entries.single.id, '1');
  });

  test('softDelete moves the entry out of watchEntries and into watchDeletedEntries', () async {
    await repository.save(makeEntry(id: '1'));
    await repository.softDelete('1');

    expect(await repository.watchEntries().first, isEmpty);
    final deleted = await repository.watchDeletedEntries().first;
    expect(deleted.single.id, '1');
    expect(deleted.single.deletedAt, isNotNull);
  });

  test('restore moves the entry back to active', () async {
    await repository.save(makeEntry(id: '1'));
    await repository.softDelete('1');

    final restored = await repository.restore('1');

    expect(restored, isTrue);
    expect((await repository.watchEntries().first).single.id, '1');
    expect(await repository.watchDeletedEntries().first, isEmpty);
  });

  test('restore is blocked when an active entry with the same value already exists', () async {
    await repository.save(makeEntry(id: '1', value: 'dup'));
    await repository.softDelete('1');
    await repository.save(makeEntry(id: '2', value: 'dup'));

    final restored = await repository.restore('1');

    expect(restored, isFalse);
    expect(await repository.watchDeletedEntries().first, hasLength(1));
    expect((await repository.watchEntries().first).single.id, '2');
  });

  test('permanentlyDelete removes the entry entirely', () async {
    await repository.save(makeEntry(id: '1'));
    await repository.softDelete('1');
    await repository.permanentlyDelete('1');

    expect(await repository.watchDeletedEntries().first, isEmpty);
  });

  test('permanentlyDelete also removes the entry\'s image file from disk', () async {
    final imagePath = p.join(Directory.systemTemp.path, 'image_test_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await File(imagePath).writeAsBytes([0]);
    addTearDown(() async {
      if (await File(imagePath).exists()) await File(imagePath).delete();
    });

    await repository.save(makeEntry(id: '1', imagePath: imagePath));
    await repository.softDelete('1');
    expect(await File(imagePath).exists(), isTrue);

    await repository.permanentlyDelete('1');

    expect(await File(imagePath).exists(), isFalse);
  });

  test('permanentlyDelete does not error when the entry has no image', () async {
    await repository.save(makeEntry(id: '1'));
    await repository.softDelete('1');

    await expectLater(repository.permanentlyDelete('1'), completes);
  });

  test('watchDeletedEntries orders most-recently-deleted first', () async {
    await repository.save(makeEntry(id: '1', value: 'a'));
    await repository.save(makeEntry(id: '2', value: 'b'));
    await repository.softDelete('1');
    await repository.softDelete('2');

    final deleted = await repository.watchDeletedEntries().first;
    expect(deleted.map((e) => e.id).toList(), ['2', '1']);
  });

  test('findMostRecentByValue returns null when nothing matches', () async {
    final result = await repository.findMostRecentByValue('nope');
    expect(result, isNull);
  });

  test('findMostRecentByValue only considers active entries', () async {
    await repository.save(makeEntry(id: '1', value: 'dup', scannedAt: DateTime.utc(2026, 1, 1)));
    await repository.softDelete('1');
    await repository.save(makeEntry(id: '2', value: 'dup', scannedAt: DateTime.utc(2026, 1, 5)));

    final result = await repository.findMostRecentByValue('dup');
    expect(result?.id, '2');
  });

  test('label persists as null when not provided', () async {
    await repository.save(makeEntry(id: '1'));
    final entries = await repository.watchEntries().first;
    expect(entries.single.label, isNull);
  });

  test('label persists when provided', () async {
    await repository.save(makeEntry(id: '1', label: 'Groceries'));
    final entries = await repository.watchEntries().first;
    expect(entries.single.label, 'Groceries');
  });

  test('timestamps round-trip as UTC', () async {
    final scannedAt = DateTime.utc(2026, 3, 14, 15, 9, 26);
    await repository.save(makeEntry(id: '1', scannedAt: scannedAt));

    final entries = await repository.watchEntries().first;
    expect(entries.single.scannedAt.isUtc, isTrue);
    expect(entries.single.scannedAt, scannedAt);
  });

  test('deleted entries older than the retention period are purged, image file included', () async {
    final path = p.join(Directory.systemTemp.path, 'retention_test_${DateTime.now().microsecondsSinceEpoch}.db');
    addTearDown(() async {
      if (await File(path).exists()) await File(path).delete();
    });
    final imagePath = p.join(
      Directory.systemTemp.path,
      'retention_image_test_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await File(imagePath).writeAsBytes([0]);
    addTearDown(() async {
      if (await File(imagePath).exists()) await File(imagePath).delete();
    });

    final repo = SqliteScanRepository(
      databaseFactory: databaseFactoryFfi,
      path: path,
      retentionPeriod: const Duration(days: 30),
    );
    addTearDown(repo.close);

    await repo.save(makeEntry(id: '1', imagePath: imagePath));
    await repo.softDelete('1');

    // Back-date deleted_at via a second connection to the same file,
    // simulating time passing without a production clock-injection seam.
    // `singleInstance: false` is required here -- sqflite otherwise caches
    // and returns `repo`'s own connection for a path that's already open,
    // so closing "raw" below would silently close `repo`'s connection too.
    final raw = await databaseFactoryFfi.openDatabase(path, options: OpenDatabaseOptions(singleInstance: false));
    final beyondRetention = DateTime.now().toUtc().subtract(const Duration(days: 31)).millisecondsSinceEpoch;
    await raw.update('scan_entries', {'deleted_at': beyondRetention}, where: "id = '1'");
    await raw.close();

    expect(await repo.watchDeletedEntries().first, isEmpty);
    expect(await File(imagePath).exists(), isFalse);
  });

  test(
    'updating an existing row to a value colliding with another active row does not crash or lose data',
    () async {
      await repository.save(makeEntry(id: '1', value: 'a'));
      await repository.save(makeEntry(id: '2', value: 'b'));

      // Simulates what would happen if value editing were ever added: an
      // update-by-id (the row already exists) whose new value collides with
      // another active row's unique index. The update branch in save() must
      // be guarded the same way the insert branch already is.
      await expectLater(repository.save(makeEntry(id: '1', value: 'b')), completes);

      final entries = await repository.watchEntries().first;
      expect(entries, hasLength(2));
      expect(entries.firstWhere((e) => e.id == '1').value, 'a');
      expect(entries.firstWhere((e) => e.id == '2').value, 'b');
    },
  );

  test('purgeOrphanedImages deletes unreferenced files, keeps referenced and soft-deleted-referenced ones', () async {
    final dir = await Directory.systemTemp.createTemp('orphan_test_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    final referencedPath = p.join(dir.path, 'referenced.jpg');
    final deletedRowPath = p.join(dir.path, 'deleted_row.jpg');
    final orphanPath = p.join(dir.path, 'orphan.jpg');
    await File(referencedPath).writeAsBytes([0]);
    await File(deletedRowPath).writeAsBytes([0]);
    await File(orphanPath).writeAsBytes([0]);

    await repository.save(makeEntry(id: '1', value: 'active', imagePath: referencedPath));
    await repository.save(makeEntry(id: '2', value: 'trashed', imagePath: deletedRowPath));
    await repository.softDelete('2');

    await repository.purgeOrphanedImages(dir);

    expect(await File(referencedPath).exists(), isTrue);
    expect(await File(deletedRowPath).exists(), isTrue);
    expect(await File(orphanPath).exists(), isFalse);
  });

  test('purgeOrphanedImages is a no-op when the directory does not exist', () async {
    final dir = Directory(p.join(Directory.systemTemp.path, 'does_not_exist_${DateTime.now().microsecondsSinceEpoch}'));

    await expectLater(repository.purgeOrphanedImages(dir), completes);
  });

  test('migrating from v2 deduplicates active rows sharing a value', () async {
    final path = p.join(Directory.systemTemp.path, 'migration_test_${DateTime.now().microsecondsSinceEpoch}.db');
    addTearDown(() async {
      if (await File(path).exists()) await File(path).delete();
    });

    // Seed a v2-schema database directly (no deleted_at column) with two
    // active rows sharing a value -- allowed before this migration.
    final oldDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE scan_entries (
            id TEXT PRIMARY KEY, value TEXT NOT NULL, format TEXT NOT NULL,
            label TEXT, scanned_at INTEGER NOT NULL, image_path TEXT
          )
        '''),
      ),
    );
    await oldDb.insert('scan_entries', {
      'id': 'old',
      'value': 'dup',
      'format': 'EAN_13',
      'scanned_at': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
    });
    await oldDb.insert('scan_entries', {
      'id': 'new',
      'value': 'dup',
      'format': 'EAN_13',
      'scanned_at': DateTime.utc(2026, 1, 5).millisecondsSinceEpoch,
    });
    await oldDb.close();

    // A long retention period -- this test is about migration/dedup, not
    // retention, and the fixed 2026-01-01 seed date would otherwise be
    // purged as "expired" by the default 30-day window.
    final migrated = SqliteScanRepository(
      databaseFactory: databaseFactoryFfi,
      path: path,
      retentionPeriod: const Duration(days: 3650),
    );
    addTearDown(migrated.close);

    final active = await migrated.watchEntries().first;
    expect(active.map((e) => e.id).toList(), ['new']);

    final deleted = await migrated.watchDeletedEntries().first;
    expect(deleted.map((e) => e.id).toList(), ['old']);

    // The unique index should now be enforced: a fresh active row with the
    // same value can't be added on top of 'new'.
    await migrated.save(makeEntry(id: 'another', value: 'dup'));
    expect((await migrated.watchEntries().first).map((e) => e.id).toList(), ['new']);
  });
}
