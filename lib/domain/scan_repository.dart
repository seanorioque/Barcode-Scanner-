import 'scan_entry.dart';

/// Persistence boundary for [ScanEntry]. Implemented against SQLite in
/// `data/`, so the layers above it can be tested without a database.
abstract class ScanRepository {
  /// Emits the current list of entries, most recent first, and again
  /// whenever the underlying store changes.
  Stream<List<ScanEntry>> watchEntries();

  Future<void> save(ScanEntry entry);

  Future<void> delete(String id);

  /// The most recently saved entry with this exact value, if any.
  /// Used to surface "already scanned on {date}" in preview.
  Future<ScanEntry?> findMostRecentByValue(String value);
}
