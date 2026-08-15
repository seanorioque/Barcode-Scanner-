/// A single captured barcode/QR scan.
class ScanEntry {
  const ScanEntry({
    required this.id,
    required this.value,
    required this.format,
    required this.scannedAt,
    this.label,
  });

  final String id;
  final String value;
  final String format;
  final String? label;
  final DateTime scannedAt;

  /// Pass [label] to set it, or [clearLabel] to explicitly reset it to
  /// `null` (plain `label: null` would otherwise be indistinguishable from
  /// "leave unchanged").
  ScanEntry copyWith({String? label, bool clearLabel = false}) {
    return ScanEntry(
      id: id,
      value: value,
      format: format,
      scannedAt: scannedAt,
      label: clearLabel ? null : (label ?? this.label),
    );
  }
}
