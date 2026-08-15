import 'dart:async';

import 'package:sqflite/sqflite.dart';

import '../domain/scan_entry.dart';
import '../domain/scan_repository.dart';

const _tableName = 'scan_entries';

/// [ScanRepository] backed by SQLite via `sqflite`. `DatabaseFactory` is
/// injected so tests can substitute `sqflite_common_ffi`'s in-memory
/// factory and exercise real SQL instead of a mock.
class SqliteScanRepository implements ScanRepository {
  SqliteScanRepository({required this._databaseFactory, required this._path});

  final DatabaseFactory _databaseFactory;
  final String _path;

  Database? _db;
  final _controller = StreamController<List<ScanEntry>>.broadcast();

  Future<Database> _open() async {
    final existing = _db;
    if (existing != null) return existing;
    final db = await _databaseFactory.openDatabase(
      _path,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => db.execute('''
          CREATE TABLE $_tableName (
            id          TEXT PRIMARY KEY,
            value       TEXT    NOT NULL,
            format      TEXT    NOT NULL,
            label       TEXT,
            scanned_at  INTEGER NOT NULL,
            image_path  TEXT
          )
        '''),
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE $_tableName ADD COLUMN image_path TEXT');
          }
        },
      ),
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_scan_entries_scanned_at '
      'ON $_tableName (scanned_at DESC)',
    );
    _db = db;
    return db;
  }

  @override
  Stream<List<ScanEntry>> watchEntries() {
    unawaited(_refresh());
    return _controller.stream;
  }

  Future<void> _refresh() async {
    final db = await _open();
    final rows = await db.query(_tableName, orderBy: 'scanned_at DESC');
    final entries = rows.map(_entryFromRow).toList(growable: false);
    if (!_controller.isClosed) _controller.add(entries);
  }

  @override
  Future<void> save(ScanEntry entry) async {
    final db = await _open();
    await db.insert(_tableName, _rowFromEntry(entry), conflictAlgorithm: ConflictAlgorithm.replace);
    await _refresh();
  }

  @override
  Future<void> delete(String id) async {
    final db = await _open();
    await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
    await _refresh();
  }

  @override
  Future<ScanEntry?> findMostRecentByValue(String value) async {
    final db = await _open();
    final rows = await db.query(
      _tableName,
      where: 'value = ?',
      whereArgs: [value],
      orderBy: 'scanned_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _entryFromRow(rows.first);
  }

  Future<void> close() async {
    await _db?.close();
    await _controller.close();
  }

  Map<String, Object?> _rowFromEntry(ScanEntry entry) => {
    'id': entry.id,
    'value': entry.value,
    'format': entry.format,
    'label': entry.label,
    'scanned_at': entry.scannedAt.toUtc().millisecondsSinceEpoch,
    'image_path': entry.imagePath,
  };

  ScanEntry _entryFromRow(Map<String, Object?> row) => ScanEntry(
    id: row['id'] as String,
    value: row['value'] as String,
    format: row['format'] as String,
    label: row['label'] as String?,
    scannedAt: DateTime.fromMillisecondsSinceEpoch(row['scanned_at'] as int, isUtc: true),
    imagePath: row['image_path'] as String?,
  );
}
