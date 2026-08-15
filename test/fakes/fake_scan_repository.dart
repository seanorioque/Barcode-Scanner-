import 'dart:async';
import 'dart:io';

import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:barcode_scanner/domain/scan_repository.dart';
import 'package:sqflite/sqflite.dart';

/// A [DatabaseException] that doesn't need a real database connection to
/// construct, for tests simulating a repository write failure (disk-full,
/// corruption, permissions, ...) that isn't a unique-constraint error.
class FakeDatabaseException extends DatabaseException {
  FakeDatabaseException() : super('simulated database failure');

  @override
  int? getResultCode() => null;

  @override
  Object? get result => null;
}

/// In-memory [ScanRepository] for widget/unit tests that need repository
/// behaviour without a real database.
class FakeScanRepository implements ScanRepository {
  final List<ScanEntry> _entries = [];
  final _controller = StreamController<List<ScanEntry>>.broadcast();
  final _deletedController = StreamController<List<ScanEntry>>.broadcast();

  /// When true, the matching method throws a non-unique-constraint
  /// [FakeDatabaseException] instead of writing, simulating disk-full,
  /// corruption, or permission errors from the real database.
  bool throwOnSave = false;
  bool throwOnSoftDelete = false;
  bool throwOnRestore = false;
  bool throwOnPermanentlyDelete = false;

  /// Active (non-deleted) entries.
  List<ScanEntry> get entries => List.unmodifiable(_entries.where((e) => e.deletedAt == null));

  /// Soft-deleted entries.
  List<ScanEntry> get deletedEntries => List.unmodifiable(_entries.where((e) => e.deletedAt != null));

  void _emit() {
    final active = entries.toList()..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    if (!_controller.isClosed) _controller.add(active);
  }

  void _emitDeleted() {
    final deleted = deletedEntries.toList()..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    if (!_deletedController.isClosed) _deletedController.add(deleted);
  }

  @override
  Stream<List<ScanEntry>> watchEntries() {
    scheduleMicrotask(_emit);
    return _controller.stream;
  }

  @override
  Stream<List<ScanEntry>> watchDeletedEntries() {
    scheduleMicrotask(_emitDeleted);
    return _deletedController.stream;
  }

  @override
  Future<void> save(ScanEntry entry) async {
    if (throwOnSave) throw FakeDatabaseException();
    _entries.removeWhere((e) => e.id == entry.id);
    _entries.add(entry);
    _emit();
  }

  @override
  Future<void> softDelete(String id) async {
    if (throwOnSoftDelete) throw FakeDatabaseException();
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return;
    _entries[index] = ScanEntry(
      id: _entries[index].id,
      value: _entries[index].value,
      format: _entries[index].format,
      label: _entries[index].label,
      imagePath: _entries[index].imagePath,
      scannedAt: _entries[index].scannedAt,
      deletedAt: DateTime.now().toUtc(),
    );
    _emit();
    _emitDeleted();
  }

  @override
  Future<bool> restore(String id) async {
    if (throwOnRestore) throw FakeDatabaseException();
    final index = _entries.indexWhere((e) => e.id == id);
    if (index == -1) return false;
    final entry = _entries[index];
    final activeDuplicate = _entries.any((e) => e.value == entry.value && e.deletedAt == null && e.id != id);
    if (activeDuplicate) return false;

    _entries[index] = ScanEntry(
      id: entry.id,
      value: entry.value,
      format: entry.format,
      label: entry.label,
      imagePath: entry.imagePath,
      scannedAt: entry.scannedAt,
    );
    _emit();
    _emitDeleted();
    return true;
  }

  @override
  Future<void> permanentlyDelete(String id) async {
    if (throwOnPermanentlyDelete) throw FakeDatabaseException();
    _entries.removeWhere((e) => e.id == id);
    _emitDeleted();
  }

  @override
  Future<ScanEntry?> findMostRecentByValue(String value) async {
    final matches = entries.where((e) => e.value == value).toList()..sort((a, b) => b.scannedAt.compareTo(a.scannedAt));
    return matches.isEmpty ? null : matches.first;
  }

  /// No files to purge in-memory; present only to satisfy the interface.
  @override
  Future<void> purgeOrphanedImages(Directory imagesDir) async {}

  Future<void> dispose() async {
    await _controller.close();
    await _deletedController.close();
  }
}
