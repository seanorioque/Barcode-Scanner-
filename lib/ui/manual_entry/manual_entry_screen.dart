import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_providers.dart';
import '../../domain/barcode_formats.dart';
import '../../domain/manual_entry.dart';
import '../format_time.dart';

class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  final _valueController = TextEditingController();
  final _labelController = TextEditingController();
  String _format = supportedBarcodeFormats.first;
  bool _saving = false;
  DateTime? _duplicateScannedAt;

  @override
  void dispose() {
    _valueController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final value = _valueController.text.trim();
    if (value.isEmpty) return;

    setState(() {
      _saving = true;
      _duplicateScannedAt = null;
    });

    final repository = ref.read(scanRepositoryProvider);
    final duplicate = await saveManualEntry(repository, value: value, format: _format, label: _labelController.text);

    if (!mounted) return;
    if (duplicate != null) {
      setState(() {
        _saving = false;
        _duplicateScannedAt = duplicate.scannedAt;
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$value"')));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _valueController.text.trim().isNotEmpty && !_saving;

    return Scaffold(
      appBar: AppBar(title: const Text('Add barcode manually')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _valueController,
                autofocus: true,
                onChanged: (_) => setState(() => _duplicateScannedAt = null),
                decoration: const InputDecoration(labelText: 'Barcode value', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _format,
                decoration: const InputDecoration(labelText: 'Format', border: OutlineInputBorder()),
                items: [
                  for (final format in supportedBarcodeFormats) DropdownMenuItem(value: format, child: Text(format)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _format = value);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(labelText: 'Label (optional)', border: OutlineInputBorder()),
              ),
              if (_duplicateScannedAt case final scannedAt?) ...[
                const SizedBox(height: 16),
                _DuplicateBanner(value: _valueController.text.trim(), scannedAt: scannedAt),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: canSave ? _save : null,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuplicateBanner extends StatelessWidget {
  const _DuplicateBanner({required this.value, required this.scannedAt});

  final String value;
  final DateTime scannedAt;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colorScheme.errorContainer, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 8),
              Text(
                'Already Scanned',
                style: TextStyle(color: colorScheme.onErrorContainer, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"$value" was already scanned on ${formatAbsoluteDate(scannedAt)}. It won\'t be saved again.',
            style: TextStyle(color: colorScheme.onErrorContainer),
          ),
        ],
      ),
    );
  }
}
