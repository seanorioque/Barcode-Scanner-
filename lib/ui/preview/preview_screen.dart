import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/scan_entry.dart';
import '../capture/scanner_controller.dart';
import '../format_time.dart';

class PreviewScreen extends ConsumerStatefulWidget {
  const PreviewScreen({super.key});

  @override
  ConsumerState<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends ConsumerState<PreviewScreen> {
  final _labelController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _copyValue(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _rescan() {
    unawaited(ref.read(scannerControllerProvider.notifier).rescan());
    Navigator.of(context).pop();
  }

  Future<void> _save() async {
    await ref.read(scannerControllerProvider.notifier).save(label: _labelController.text);
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _done() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scannerControllerProvider);
    final detection = state.detection;

    if (detection == null) {
      // Reached without an active detection (e.g. deep navigation); bail out.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final saving = state.phase == ScanPhase.saving;
    final duplicate = state.duplicateOf;

    return Scaffold(
      appBar: AppBar(title: const Text('Preview & confirm')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (state.imagePath case final imagePath?)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 180,
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Image.file(File(imagePath), fit: BoxFit.contain),
                    ),
                  ),
                ),
              Chip(label: Text(detection.format)),
              const SizedBox(height: 12),
              SelectableText(detection.value, style: const TextStyle(fontFamily: 'monospace', fontSize: 18)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => _copyValue(detection.value),
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              if (duplicate != null)
                _AlreadyScannedBanner(duplicate: duplicate)
              else
                TextField(
                  key: const ValueKey('preview_label_field'),
                  controller: _labelController,
                  autofocus: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(labelText: 'Label (optional)', border: OutlineInputBorder()),
                ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: saving ? null : _rescan, child: const Text('Rescan')),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: duplicate != null
                        ? FilledButton(onPressed: _done, child: const Text('Done'))
                        : FilledButton(
                            onPressed: saving ? null : _save,
                            child: saving
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Save'),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Non-blocking, informational — this is a normal outcome of scanning, not
/// an error, so it deliberately avoids error styling/icons and never
/// requires a dismiss action.
class _AlreadyScannedBanner extends StatelessWidget {
  const _AlreadyScannedBanner({required this.duplicate});

  final ScanEntry duplicate;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onContainer = colorScheme.onSecondaryContainer;
    final label = duplicate.label;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: onContainer),
              const SizedBox(width: 8),
              Text(
                'Already scanned',
                style: TextStyle(color: onContainer, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label ?? 'Add label',
            style: TextStyle(
              color: onContainer,
              fontStyle: label == null ? FontStyle.italic : FontStyle.normal,
            ),
          ),
          const SizedBox(height: 4),
          Text('First scanned ${formatAbsoluteDate(duplicate.scannedAt)}', style: TextStyle(color: onContainer)),
        ],
      ),
    );
  }
}
