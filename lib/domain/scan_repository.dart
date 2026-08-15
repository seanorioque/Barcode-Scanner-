import 'scan_entry.dart';

/// Persistence boundary for [ScanEntry]. Implemented against SQLite in
/// `data/`, so the layers above it can be tested without a database.
abstract class ScanRepository {
  /// Emits the current list of active (non-deleted) entries, most recent
  /// first, and again whenever the underlying store changes.
  Stream<List<ScanEntry>> watchEntries();

  /// Emits the current list of soft-deleted entries, most recently deleted
  /// first, and again whenever the underlying store changes.
  Stream<List<ScanEntry>> watchDeletedEntries();

  Future<void> save(ScanEntry entry);

  /// Moves an entry to Recently Deleted rather than removing it outright.
  Future<void> softDelete(String id);

  /// Moves an entry back from Recently Deleted to active. Returns `false`
  /// without changing anything if an active entry with the same value
  /// already exists (the value is the app's unique identifier).
  Future<bool> restore(String id);

  /// Irreversibly removes an entry from Recently Deleted.
  Future<void> permanentlyDelete(String id);

  /// The most recently saved *active* entry with this exact value, if any.
  /// Used to surface "already scanned on {date}" in preview.
  Future<ScanEntry?> findMostRecentByValue(String value);
}
