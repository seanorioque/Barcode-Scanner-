import 'dart:async';

import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:barcode_scanner/domain/scan_repository.dart';

/// In-memory [ScanRepository] for widget/unit tests that need repository
/// behaviour without a real database.
class FakeScanRepository implements ScanRepository {
  final List<ScanEntry> _entries = [];
  final _controller = StreamController<List<ScanEntry>>.broadcast();

  List<ScanEntry> get entries => List.unmodifiable(_entries);

  void _emit() {
    final sorted = [..._entries]..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    if (!_controller.isClosed) _controller.add(sorted);
  }

  @override
  Stream<List<ScanEntry>> watchEntries() {
    scheduleMicrotask(_emit);
    return _controller.stream;
  }

  @override
  Future<void> save(ScanEntry entry) async {
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.add(entry);
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    _entries.removeWhere((e) => e.id == id);
    _emit();
  }

  @override
  Future<ScanEntry?> findMostRecentByValue(String value) async {
    final matches = _entries.where((e) => e.value == value).toList()..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return matches.isEmpty ? null : matches.first;
  }

  Future<void> dispose() => _controller.close();
}
