import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../domain/scan_entry.dart';
import '../capture/capture_screen.dart';
import '../format_time.dart';

class EntriesScreen extends ConsumerStatefulWidget {
  const EntriesScreen({super.key});

  @override
  ConsumerState<EntriesScreen> createState() => _EntriesScreenState();
}

class _EntriesScreenState extends ConsumerState<EntriesScreen> {
  final _revealedAbsolute = <String>{};

  void _openCapture() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CaptureScreen()));
  }

  Future<void> _deleteWithUndo(ScanEntry entry) async {
    final repository = ref.read(scanRepositoryProvider);
    await repository.delete(entry.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted ${entry.value}'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => repository.save(entry),
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

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(entriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Captured entries')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openCapture,
        tooltip: 'Scan a code',
        child: const Icon(Icons.qr_code_scanner),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Could not load entries: $error')),
        data: (entries) {
          if (entries.isEmpty) {
            return _EmptyState(onScanPressed: _openCapture);
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
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Icon(Icons.delete, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                onDismissed: (_) => _deleteWithUndo(entry),
                child: ListTile(
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
            Icon(Icons.qr_code_2, size: 96, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No scans yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Captured barcodes and QR codes will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onScanPressed,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan your first code'),
            ),
          ],
        ),
      ),
    );
  }
}
