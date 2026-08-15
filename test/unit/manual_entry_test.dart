import 'package:barcode_scanner/domain/manual_entry.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scan_repository.dart';

void main() {
  late FakeScanRepository repository;

  setUp(() => repository = FakeScanRepository());
  tearDown(() => repository.dispose());

  test('saves a new entry and returns null', () async {
    final result = await saveManualEntry(repository, value: '0123456789012', format: 'EAN_13', label: 'Pantry');

    expect(result, isNull);
    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.value, '0123456789012');
    expect(repository.entries.single.format, 'EAN_13');
    expect(repository.entries.single.label, 'Pantry');
    expect(repository.entries.single.imagePath, isNull);
  });

  test('trims the value and label', () async {
    await saveManualEntry(repository, value: '  0123456789012  ', format: 'EAN_13', label: '  Pantry  ');

    expect(repository.entries.single.value, '0123456789012');
    expect(repository.entries.single.label, 'Pantry');
  });

  test('a blank label is stored as null', () async {
    await saveManualEntry(repository, value: '0123456789012', format: 'EAN_13', label: '   ');

    expect(repository.entries.single.label, isNull);
  });

  test('returns the existing active entry for a duplicate value without saving a second row', () async {
    final existing = ScanEntry(id: 'old', value: 'dup', format: 'EAN_13', scannedAt: DateTime.utc(2026, 1, 1));
    await repository.save(existing);

    final result = await saveManualEntry(repository, value: 'dup', format: 'CODE_128');

    expect(result?.id, 'old');
    expect(repository.entries, hasLength(1));
  });

  test('a value matching only a soft-deleted entry is not treated as a duplicate', () async {
    await repository.save(ScanEntry(id: 'old', value: 'dup', format: 'EAN_13', scannedAt: DateTime.utc(2026, 1, 1)));
    await repository.softDelete('old');

    final result = await saveManualEntry(repository, value: 'dup', format: 'CODE_128');

    expect(result, isNull);
    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.id, isNot('old'));
  });
}
