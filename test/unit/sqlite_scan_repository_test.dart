import 'package:barcode_scanner/data/sqlite_scan_repository.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:flutter_test/flutter_test.dart';
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
    DateTime? scannedAt,
  }) {
    return ScanEntry(
      id: id,
      value: value,
      format: format,
      label: label,
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
    await repository.save(makeEntry(id: '1', scannedAt: DateTime.utc(2026, 1, 1)));
    await repository.save(makeEntry(id: '2', scannedAt: DateTime.utc(2026, 1, 3)));
    await repository.save(makeEntry(id: '3', scannedAt: DateTime.utc(2026, 1, 2)));

    final entries = await repository.watchEntries().first;
    expect(entries.map((e) => e.id).toList(), ['2', '3', '1']);
  });

  test('delete removes the entry and survives being watched', () async {
    await repository.save(makeEntry(id: '1'));
    await repository.delete('1');

    final entries = await repository.watchEntries().first;
    expect(entries, isEmpty);
  });

  test('findMostRecentByValue returns null when nothing matches', () async {
    final result = await repository.findMostRecentByValue('nope');
    expect(result, isNull);
  });

  test('findMostRecentByValue returns the most recent match', () async {
    await repository.save(makeEntry(id: '1', value: 'dup', scannedAt: DateTime.utc(2026, 1, 1)));
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
}
