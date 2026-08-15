import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanEntry makeEntry({String? label}) {
    return ScanEntry(id: '1', value: 'abc', format: 'QR_CODE', label: label, scannedAt: DateTime.utc(2026, 1, 1));
  }

  group('ScanEntry.copyWith', () {
    test('leaves the label unchanged when neither label nor clearLabel is passed', () {
      final entry = makeEntry(label: 'Pantry');
      expect(entry.copyWith().label, 'Pantry');
    });

    test('sets a new label', () {
      final entry = makeEntry(label: 'Pantry');
      expect(entry.copyWith(label: 'Garage').label, 'Garage');
    });

    test('clearLabel explicitly resets the label to null', () {
      final entry = makeEntry(label: 'Pantry');
      expect(entry.copyWith(clearLabel: true).label, isNull);
    });

    test('other fields are preserved', () {
      final entry = makeEntry(label: 'Pantry');
      final copy = entry.copyWith(label: 'Garage');
      expect(copy.id, entry.id);
      expect(copy.value, entry.value);
      expect(copy.format, entry.format);
      expect(copy.scannedAt, entry.scannedAt);
    });
  });
}
