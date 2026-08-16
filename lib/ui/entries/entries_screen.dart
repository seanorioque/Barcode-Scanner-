import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../domain/scan_entry.dart';
import '../capture/capture_screen.dart';
import '../format_time.dart';
import '../manual_entry/manual_entry_screen.dart';
import '../recently_deleted/recently_deleted_screen.dart';

/// How long the delete "Undo" snackbar stays up before the deletion is
/// treated as final.
const _undoDuration = Duration(seconds: 5);

/// Plain, exception-free messages for repository write failures (disk-full,
/// corruption, permissions, ...) — no exception detail is actionable for
/// the user, so all of them collapse to one of these.
const _saveFailedMessage = "Couldn't save. Please try again.";
const _deleteFailedMessage = "Couldn't delete. Please try again.";
const _restoreFailedMessage = "Couldn't restore. Please try again.";

class EntriesScreen extends ConsumerStatefulWidget {
  const EntriesScreen({super.key});

  @override
  ConsumerState<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends ConsumerState<EntriesScreen> {
  final _revealedAbsolute = <String>{};
  final _searchController = TextEditingController();
  String _query = '';
  final _selectedIds = <String>{};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openCapture() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaptureScreen()));
  }

  void _openManualEntry() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ManualEntryScreen()));
  }

  void _openRecentlyDeleted() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RecentlyDeletedScreen()));
  }

  Future<bool> _confirmDebugAction(String title, String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Confirm')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  /// Debug-only test fixture (see requirements.md P2-2): duplicate blocking
  /// (FR-22) means each barcode value can only ever be saved once, which
  /// makes manually retesting scan -> preview -> save tedious without a way
  /// to wipe the slate. Reuses the existing public repository API rather
  /// than adding one purely for this.
  Future<void> _debugClearAllData() async {
    final confirmed = await _confirmDebugAction(
      'Clear all data?',
      'Debug only: permanently deletes every entry and photo, active and trashed.',
    );
    if (!confirmed) return;

    final repository = ref.read(scanRepositoryProvider);
    final active = await repository.watchEntries().first;
    final deleted = await repository.watchDeletedEntries().first;
    for (final entry in [...active, ...deleted]) {
      await repository.permanentlyDelete(entry.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All data cleared')));
  }

  /// Debug-only test fixture (see requirements.md P2-3): the 30-day
  /// retention sweep is otherwise unobservable on a device without editing
  /// code and rebuilding. Permanently deletes everything currently in
  /// Recently Deleted right now, bypassing the retention period, so the
  /// row+photo purge behavior can be verified on demand.
  Future<void> _debugPurgeTrashNow() async {
    final repository = ref.read(scanRepositoryProvider);
    final deleted = await repository.watchDeletedEntries().first;
    if (deleted.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Recently Deleted is already empty')));
      return;
    }

    final confirmed = await _confirmDebugAction(
      'Purge trash now?',
      'Debug only: permanently deletes all ${deleted.length} '
          '${deleted.length == 1 ? 'entry' : 'entries'} currently in Recently Deleted, bypassing the retention period.',
    );
    if (!confirmed) return;

    for (final entry in deleted) {
      await repository.permanentlyDelete(entry.id);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trash purged')));
  }

  void _toggleSelection(String id) {
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

  Future<bool> _confirmDelete(String message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _deleteWithUndo(ScanEntry entry) async {
    final repository = ref.read(scanRepositoryProvider);
    try {
      await repository.softDelete(entry.id);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_deleteFailedMessage)));
      }
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved "${entry.value}" to Recently Deleted'),
        duration: _undoDuration,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            bool restored;
            try {
              restored = await repository.restore(entry.id);
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_restoreFailedMessage)));
              }
              return;
            }
            if (!restored && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Can't undo — that value is active again")),
              );
            }
          },
        ),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    final ids = _selectedIds.toList(growable: false);
    final confirmed = await _confirmDelete(
      ids.length == 1
          ? 'This scan will be moved to Recently Deleted.'
          : '${ids.length} scans will be moved to Recently Deleted.',
    );
    if (!confirmed) return;

    final repository = ref.read(scanRepositoryProvider);
    try {
      for (final id in ids) {
        await repository.softDelete(id);
      }
    } catch (_) {
      _clearSelection();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_deleteFailedMessage)));
      }
      return;
    }
    _clearSelection();
    if (!mounted) return;

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ids.length == 1 ? '1 item moved to Recently Deleted' : '${ids.length} items moved to Recently Deleted'),
        duration: _undoDuration,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            try {
              var failures = 0;
              for (final id in ids) {
                if (!await repository.restore(id)) failures++;
              }
              if (failures > 0 && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$failures item(s) couldn\'t be restored — already active again')),
                );
              }
            } catch (_) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_restoreFailedMessage)));
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _editLabel(ScanEntry entry) async {
    final newLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _EditLabelDialog(initialLabel: entry.label ?? ''),
    );
    if (newLabel == null) return;

    final trimmed = newLabel.trim();
    final repository = ref.read(scanRepositoryProvider);
    try {
      await repository.save(trimmed.isEmpty ? entry.copyWith(clearLabel: true) : entry.copyWith(label: trimmed));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(_saveFailedMessage)));
      }
    }
  }

  List<ScanEntry> _filter(List<ScanEntry> entries) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return entries;
    return entries
        .where((e) => e.value.toLowerCase().contains(query) || (e.label ?? '').toLowerCase().contains(query))
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(entriesProvider);

    return Scaffold(
      appBar: _selectionMode
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: _clearSelection,
              ),
              title: Text('${_selectedIds.length} selected'),
              actions: [
                IconButton(icon: const Icon(Icons.delete), tooltip: 'Delete selected', onPressed: _deleteSelected),
              ],
            )
          : AppBar(
              title: const Text('Captured entries'),
              actions: [
                IconButton(onPressed: _openManualEntry, tooltip: 'Add manually', icon: const Icon(Icons.add)),
                IconButton(
                  onPressed: _openRecentlyDeleted,
                  tooltip: 'Recently Deleted',
                  icon: const Icon(Icons.restore_from_trash),
                ),
                if (kDebugMode)
                  PopupMenuButton<void>(
                    tooltip: 'Debug tools',
                    icon: const Icon(Icons.bug_report_outlined),
                    itemBuilder: (context) => [
                      PopupMenuItem(onTap: _debugClearAllData, child: const Text('Clear all data')),
                      PopupMenuItem(onTap: _debugPurgeTrashNow, child: const Text('Purge trash now')),
                    ],
                  ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: TextField(
                    key: const ValueKey('entries_search'),
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Search by value or label',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() {
                                _searchController.clear();
                                _query = '';
                              }),
                            ),
                    ),
                  ),
                ),
              ),
            ),
      floatingActionButton: _selectionMode
          ? null
          : FloatingActionButton(
              onPressed: _openCapture,
              tooltip: 'Scan a barcode',
              child: const Icon(Icons.qr_code_scanner),
            ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Could not load entries: $error')),
        data: (allEntries) {
          if (allEntries.isEmpty) {
            return _EmptyState(onScanPressed: _openCapture);
          }
          final entries = _filter(allEntries);
          if (entries.isEmpty) {
            return Center(child: Text('No matches for "$_query"', style: Theme.of(context).textTheme.bodyMedium));
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final showAbsolute = _revealedAbsolute.contains(entry.id);
              final selected = _selectedIds.contains(entry.id);

              final tile = ListTile(
                selected: selected,
                onTap: _selectionMode ? () => _toggleSelection(entry.id) : null,
                onLongPress: () => _toggleSelection(entry.id),
                leading: _selectionMode
                    ? Checkbox(value: selected, onChanged: (_) => _toggleSelection(entry.id))
                    : switch (entry.imagePath) {
                        final path? => ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: 48,
                            height: 48,
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: Image.file(File(path), fit: BoxFit.contain),
                          ),
                        ),
                        null => null,
                      },
                title: Text(
                  entry.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                subtitle: Row(
                  children: [
                    Chip(
                      label: Text(entry.format, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('label_${entry.id}'),
                        onTap: _selectionMode ? () => _toggleSelection(entry.id) : () => _editLabel(entry),
                        child: Text(
                          entry.label ?? 'Add label',
                          overflow: TextOverflow.ellipsis,
                          style: entry.label == null
                              ? TextStyle(color: Theme.of(context).colorScheme.outline, fontStyle: FontStyle.italic)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
                trailing: _selectionMode
                    ? null
                    : GestureDetector(
                        key: ValueKey('timestamp_${entry.id}'),
                        onTap: () => setState(() {
                          if (!_revealedAbsolute.add(entry.id)) {
                            _revealedAbsolute.remove(entry.id);
                          }
                        }),
                        child: Text(
                          showAbsolute ? formatAbsoluteDate(entry.scannedAt) : formatRelativeTime(entry.scannedAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
              );

              if (_selectionMode) return tile;

              // Swipe-to-delete only outside selection mode, so the gesture
              // doesn't fight with tap-to-select.
              return Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete('"${entry.value}" will be moved to Recently Deleted.'),
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                onDismissed: (_) => _deleteWithUndo(entry),
                child: tile,
              );
            },
          );
        },
      ),
    );
  }
}

class _EditLabelDialog extends StatefulWidget {
  const _EditLabelDialog({required this.initialLabel});

  final String initialLabel;

  @override
  State<_EditLabelDialog> createState() => _EditLabelDialogState();
}

class _EditLabelDialogState extends State<_EditLabelDialog> {
  late final _controller = TextEditingController(text: widget.initialLabel);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit label'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Label', border: OutlineInputBorder()),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.of(context).pop(_controller.text), child: const Text('Save')),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onScanPressed});

  final VoidCallback onScanPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.qr_code_scanner, size: 96, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No scans yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Captured barcodes will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onScanPressed,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan your first barcode'),
            ),
          ],
        ),
      ),
    );
  }
}
