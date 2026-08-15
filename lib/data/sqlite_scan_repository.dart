import 'dart:async';
import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../domain/scan_entry.dart';
import '../domain/scan_repository.dart';

const _tableName = 'scan_entries';
const _activeValueIndex = 'idx_scan_entries_active_value';

/// [ScanRepository] backed by SQLite via `sqflite`. `DatabaseFactory` is
/// injected so tests can substitute `sqflite_common_ffi`'s in-memory
/// factory and exercise real SQL instead of a mock.
///
/// The barcode `value` is the app's unique identifier among *active*
/// (non-deleted) rows, enforced by a partial unique index — see
/// [_activeValueIndex]. Deleting an entry moves it to Recently Deleted
/// (`deleted_at` set) rather than removing it; [permanentlyDelete] and the
/// [retentionPeriod] sweep are the only things that actually drop a row.
class SqliteScanRepository implements ScanRepository {
  SqliteScanRepository({
    required this._databaseFactory,
    required this._path,
    this.retentionPeriod = const Duration(days: 30),
  });

  final DatabaseFactory _databaseFactory;
  final String _path;
  final Duration retentionPeriod;

  Database? _db;
  final _controller = StreamController<List<ScanEntry>>.broadcast();
  final _deletedController = StreamController<List<ScanEntry>>.broadcast();

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await _databaseFactory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE $_tableName (
            id          TEXT PRIMARY KEY,
            value       TEXT    NOT NULL,
            format      TEXT    NOT NULL,
            label       TEXT,
            scanned_at  INTEGER NOT NULL,
            image_path  TEXT,
            deleted_at  INTEGER
          )
        '''),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE $_tableName ADD COLUMN image_path TEXT');
          }
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE $_tableName ADD COLUMN deleted_at INTEGER');
            // Older versions allowed literal duplicate rows per value. Keep
            // only the most-recently-scanned row per value active so the
            // partial unique index below can be created; the rest move to
            // Recently Deleted rather than being dropped outright. Relies on
            // SQLite's documented "bare column alongside MAX() resolves to
            // that row" GROUP BY behavior.
            await db.execute('''
              UPDATE $_tableName SET deleted_at = scanned_at
              WHERE id NOT IN (
                SELECT id FROM (SELECT id, MAX(scanned_at) FROM $_tableName GROUP BY value)
              )
            ''');
          }
        },
      ),
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scan_entries_scanned_at '
      'ON $_tableName (scanned_at DESC)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS $_activeValueIndex '
      'ON $_tableName (value) WHERE deleted_at IS NULL',
    );
    _db = db;
    await _purgeExpired(db);
    return db;
  }

  Future<void> _purgeExpired(Database db) async {
    final cutoff = DateTime.now().toUtc().subtract(retentionPeriod).millisecondsSinceEpoch;
    final expiring = await db.query(
      _tableName,
      columns: ['image_path'],
      where: 'deleted_at IS NOT NULL AND deleted_at < ?',
      whereArgs: [cutoff],
    );
    await db.delete(_tableName, where: 'deleted_at IS NOT NULL AND deleted_at < ?', whereArgs: [cutoff]);
    for (final row in expiring) {
      await _deleteImageFile(row['image_path'] as String?);
    }
  }

  /// Best-effort cleanup — a row's photo has no other owner (each capture
  /// gets its own generated filename, and duplicates never save a new row),
  /// so once the row is gone the file should go with it. A failure here
  /// (already missing, permissions, ...) just leaves a stray file; not
  /// worth surfacing to the caller.
  Future<void> _deleteImageFile(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Ignored -- see above.
    }
  }

  @override
  Stream<List<ScanEntry>> watchEntries() {
    unawaited(_refresh());
    return _controller.stream;
  }

  @override
  Stream<List<ScanEntry>> watchDeletedEntries() {
    unawaited(_refreshDeleted());
    return _deletedController.stream;
  }

  Future<void> _refresh() async {
    final db = await _open();
    final rows = await db.query(_tableName, where: 'deleted_at IS NULL', orderBy: 'scanned_at DESC');
    final entries = rows.map(_entryFromRow).toList(growable: false);
    if (!_controller.isClosed) _controller.add(entries);
  }

  Future<void> _refreshDeleted() async {
    final db = await _open();
    await _purgeExpired(db);
    final rows = await db.query(_tableName, where: 'deleted_at IS NOT NULL', orderBy: 'deleted_at DESC');
    final entries = rows.map(_entryFromRow).toList(growable: false);
    if (!_deletedController.isClosed) _deletedController.add(entries);
  }

  @override
  Future<void> save(ScanEntry entry) async {
    final db = await _open();
    // Update-by-id first (label edits, etc. — the row already exists and a
    // row never conflicts with itself), and only insert if it doesn't.
    // `ConflictAlgorithm.replace` on a plain insert is *not* safe here: it
    // resolves conflicts on *any* unique constraint, not just the primary
    // key, so inserting a genuinely new row that happens to collide with an
    // unrelated existing row on `value` would silently delete that row and
    // replace it — exactly the duplicate this app is trying to prevent.
    //
    // Both branches are guarded: callers are expected to check
    // findMostRecentByValue before saving, and today only the label is
    // editable (FR-19, ambiguity #11) so the update branch can't actually
    // hit the unique-value index. The guard stays anyway — if value editing
    // is ever added, an update colliding with another active row must keep
    // the existing rows rather than crash, same as a colliding insert does.
    try {
      final updated = await db.update(_tableName, _rowFromEntry(entry), where: 'id = ?', whereArgs: [entry.id]);
      if (updated == 0) {
        await db.insert(_tableName, _rowFromEntry(entry), conflictAlgorithm: ConflictAlgorithm.abort);
      }
    } on DatabaseException catch (e) {
      if (!e.isUniqueConstraintError()) rethrow;
    }
    await _refresh();
  }

  @override
  Future<void> softDelete(String id) async {
    final db = await _open();
    await db.update(
      _tableName,
      {'deleted_at': DateTime.now().toUtc().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
    await _refresh();
    await _refreshDeleted();
  }

  @override
  Future<bool> restore(String id) async {
    final db = await _open();
    final rows = await db.query(_tableName, where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return false;
    final value = rows.first['value'] as String;

    final activeDuplicate = await db.query(
      _tableName,
      where: 'value = ? AND deleted_at IS NULL',
      whereArgs: [value],
      limit: 1,
    );
    if (activeDuplicate.isNotEmpty) return false;

    await db.update(_tableName, {'deleted_at': null}, where: 'id = ?', whereArgs: [id]);
    await _refresh();
    await _refreshDeleted();
    return true;
  }

  @override
  Future<void> permanentlyDelete(String id) async {
    final db = await _open();
    final rows = await db.query(_tableName, columns: ['image_path'], where: 'id = ?', whereArgs: [id], limit: 1);
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    if (rows.isNotEmpty) await _deleteImageFile(rows.first['image_path'] as String?);
    await _refreshDeleted();
  }

  @override
  Future<void> purgeOrphanedImages(Directory imagesDir) async {
    if (!await imagesDir.exists()) return;
    final db = await _open();
    final rows = await db.query(_tableName, columns: ['image_path']);
    final referenced = rows.map((r) => r['image_path'] as String?).whereType<String>().toSet();
    await for (final entity in imagesDir.list()) {
      if (entity is! File) continue;
      if (!referenced.contains(entity.path)) {
        try {
          await entity.delete();
        } catch (_) {
          // Best-effort, same as _deleteImageFile.
        }
      }
    }
  }

  @override
  Future<ScanEntry?> findMostRecentByValue(String value) async {
    final db = await _open();
    final rows = await db.query(
      _tableName,
      where: 'value = ? AND deleted_at IS NULL',
      whereArgs: [value],
      orderBy: 'scanned_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _entryFromRow(rows.first);
  }

  /// Test-only. App code deliberately never calls this — the database and
  /// both stream controllers are meant to live for the whole process
  /// lifetime, and the OS reclaims them on exit. Tests call it between
  /// cases to avoid leaking connections/streams across a suite.
  Future<void> close() async {
    await _db?.close();
    await _controller.close();
    await _deletedController.close();
  }

  Map<String, Object?> _rowFromEntry(ScanEntry entry) => {
    'id': entry.id,
    'value': entry.value,
    'format': entry.format,
    'label': entry.label,
    'scanned_at': entry.scannedAt.toUtc().millisecondsSinceEpoch,
    'image_path': entry.imagePath,
    'deleted_at': entry.deletedAt?.toUtc().millisecondsSinceEpoch,
  };

  ScanEntry _entryFromRow(Map<String, Object?> row) => ScanEntry(
    id: row['id'] as String,
    value: row['value'] as String,
    format: row['format'] as String,
    label: row['label'] as String?,
    scannedAt: DateTime.fromMillisecondsSinceEpoch(row['scanned_at'] as int, isUtc: true),
    imagePath: row['image_path'] as String?,
    deletedAt: row['deleted_at'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row['deleted_at'] as int, isUtc: true),
  );
}
