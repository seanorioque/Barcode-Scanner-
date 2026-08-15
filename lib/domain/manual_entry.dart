import 'package:uuid/uuid.dart';

import 'scan_entry.dart';
import 'scan_repository.dart';

const _uuid = Uuid();

/// Saves a manually-typed barcode, applying the same duplicate rule as a
/// camera scan. Returns the existing active entry if [value] is a duplicate
/// (nothing is saved), or `null` after successfully saving a new entry.
///
/// Pure aside from the repository call, so it's unit-testable with
/// [ScanRepository] fakes the same way `selectBarcode` is tested with plain
/// lists.
Future<ScanEntry?> saveManualEntry(
  ScanRepository repository, {
  required String value,
  required String format,
  String? label,
}) async {
  final trimmedValue = value.trim();
  final duplicate = await repository.findMostRecentByValue(trimmedValue);
  if (duplicate != null) return duplicate;

  final trimmedLabel = label?.trim();
  await repository.save(
    ScanEntry(
      id: _uuid.v4(),
      value: trimmedValue,
      format: format,
      label: (trimmedLabel == null || trimmedLabel.isEmpty) ? null : trimmedLabel,
      scannedAt: DateTime.now().toUtc(),
    ),
  );
  return null;
}
