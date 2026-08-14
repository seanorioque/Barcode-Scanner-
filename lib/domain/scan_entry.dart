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

  ScanEntry copyWith({String? label}) {
    return ScanEntry(
      id: id,
      value: value,
      format: format,
      scannedAt: scannedAt,
      label: label ?? this.label,
    );
  }
}
