import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../domain/scan_entry.dart';
import '../format_time.dart';

class RecentlyDeletedScreen extends ConsumerWidget {
  const RecentlyDeletedScreen({super.key});

  Future<void> _restore(BuildContext context, WidgetRef ref, ScanEntry entry) async {
    final repository = ref.read(scanRepositoryProvider);
    final restored = await repository.restore(entry.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored ? 'Restored "${entry.value}"' : 'Can\'t restore — "${entry.value}" is already active',
        ),
      ),
    );
  }

  Future<void> _permanentlyDelete(BuildContext context, WidgetRef ref, ScanEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: Text('"${entry.value}" will be permanently removed. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(scanRepositoryProvider).permanentlyDelete(entry.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deletedAsync = ref.watch(deletedEntriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Recently Deleted')),
      body: deletedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Could not load Recently Deleted: $error')),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Text('Nothing in Recently Deleted.', style: Theme.of(context).textTheme.bodyMedium),
            );
          }
          return ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              return ListTile(
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
                subtitle: Text('Deleted ${formatRelativeTime(entry.deletedAt!)}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Restore',
                      icon: const Icon(Icons.restore),
                      onPressed: () => _restore(context, ref, entry),
                    ),
                    IconButton(
                      tooltip: 'Delete permanently',
                      icon: const Icon(Icons.delete_forever),
                      onPressed: () => _permanentlyDelete(context, ref, entry),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
