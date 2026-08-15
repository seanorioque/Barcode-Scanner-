import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/mlkit_barcode_scanner_service.dart';
import 'domain/barcode_scanner_service.dart';
import 'domain/scan_entry.dart';
import 'domain/scan_repository.dart';

/// Overridden in `main()` once the SQLite path has been resolved.
final scanRepositoryProvider = Provider<ScanRepository>((ref) {
  throw UnimplementedError('scanRepositoryProvider must be overridden in main()');
});

/// The live, most-recent-first list of active captured entries.
final entriesProvider = StreamProvider<List<ScanEntry>>((ref) {
  final repository = ref.watch(scanRepositoryProvider);
  return repository.watchEntries();
});

/// The live, most-recently-deleted-first list of entries in Recently Deleted.
final deletedEntriesProvider = StreamProvider<List<ScanEntry>>((ref) {
  final repository = ref.watch(scanRepositoryProvider);
  return repository.watchDeletedEntries();
});

/// A fresh scanner service per capture session. Disposed automatically
/// (releasing the camera) once nothing is watching it anymore, i.e. once
/// the capture screen leaves the widget tree.
final barcodeScannerServiceProvider = Provider.autoDispose<BarcodeScannerService>((ref) {
  final service = MlKitBarcodeScannerService();
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});
