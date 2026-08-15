/// A single captured barcode scan.
class ScanEntry {
  const ScanEntry({
    required this.id,
    required this.value,
    required this.format,
    required this.scannedAt,
    this.label,
    this.imagePath,
    this.deletedAt,
  });

  final String id;
  final String value;
  final String format;
  final String? label;
  final DateTime scannedAt;

  /// Path to a saved photo of the scanned barcode, if one was captured.
  final String? imagePath;

  /// When this entry was moved to Recently Deleted. `null` means active.
  final DateTime? deletedAt;

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
      imagePath: imagePath,
      deletedAt: deletedAt,
    );
  }
}
