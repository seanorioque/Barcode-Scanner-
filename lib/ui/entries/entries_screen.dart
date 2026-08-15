import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../domain/scan_entry.dart';
import '../capture/capture_screen.dart';
import '../format_time.dart';
import '../manual_entry/manual_entry_screen.dart';
import '../recently_deleted/recently_deleted_screen.dart';

class EntriesScreen extends ConsumerStatefulWidget {
  const EntriesScreen({super.key});

  @override
  ConsumerState<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends ConsumerState<EntriesScreen> {
  final _revealedAbsolute = <String>{};
  final _searchController = TextEditingController();
  String _query = '';

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

  Future<bool> _confirmDelete(ScanEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this scan?'),
        content: Text('"${entry.value}" will be moved to Recently Deleted.'),
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
    await repository.softDelete(entry.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Moved "${entry.value}" to Recently Deleted'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            final restored = await repository.restore(entry.id);
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

  Future<void> _editLabel(ScanEntry entry) async {
    final newLabel = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _EditLabelDialog(initialLabel: entry.label ?? ''),
    );
    if (newLabel == null) return;

    final trimmed = newLabel.trim();
    final repository = ref.read(scanRepositoryProvider);
    await repository.save(trimmed.isEmpty ? entry.copyWith(clearLabel: true) : entry.copyWith(label: trimmed));
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
      appBar: AppBar(
        title: const Text('Captured entries'),
        actions: [
          IconButton(
            onPressed: _openManualEntry,
            tooltip: 'Add manually',
            icon: const Icon(Icons.add),
          ),
          IconButton(
            onPressed: _openRecentlyDeleted,
            tooltip: 'Recently Deleted',
            icon: const Icon(Icons.restore_from_trash),
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
      floatingActionButton: FloatingActionButton(
        onPressed: _openCapture,
        tooltip: 'Scan a barcode',
        child: const Icon(Icons.barcode_reader),
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
              return Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(entry),
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                onDismissed: (_) => _deleteWithUndo(entry),
                child: ListTile(
                  leading: switch (entry.imagePath) {
                    final path? => ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(File(path), width: 48, height: 48, fit: BoxFit.cover),
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
                          onTap: () => _editLabel(entry),
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
                  trailing: GestureDetector(
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
                ),
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
            Icon(Icons.barcode_reader, size: 96, color: Theme.of(context).colorScheme.outline),
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
              icon: const Icon(Icons.barcode_reader),
              label: const Text('Scan your first barcode'),
            ),
          ],
        ),
      ),
    );
  }
}
