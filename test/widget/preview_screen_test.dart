import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:barcode_scanner/ui/capture/scanner_controller.dart';
import 'package:barcode_scanner/ui/preview/preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_barcode_scanner_service.dart';
import '../fakes/fake_scan_repository.dart';

void main() {
  late FakeBarcodeScannerService service;
  late FakeScanRepository repository;

  /// Drives a real [ScannerController] to the `detected` phase (via a
  /// scripted frame, same as the app would) and pumps [PreviewScreen] on
  /// top of a base route, so Save/Rescan navigation behaves like it does
  /// in the real app.
  Future<void> pumpDetected(
    WidgetTester tester, {
    ScanEntry? duplicate,
    String value = '0123456789012',
    String format = 'EAN_13',
  }) async {
    service = FakeBarcodeScannerService();
    repository = FakeScanRepository();
    if (duplicate != null) await repository.save(duplicate);

    final container = ProviderContainer(
      overrides: [
        barcodeScannerServiceProvider.overrideWithValue(service),
        scanRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    // scannerControllerProvider is autoDispose; a bare container.read()
    // doesn't hold it alive across the awaits below, so keep a listener.
    container.listen(scannerControllerProvider, (_, _) {});

    await container.read(scannerControllerProvider.notifier).start();
    service.emit([
      BarcodeDetection(value: value, format: format, boundingBoxArea: 100, boundingBox: const BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero); // let the duplicate lookup resolve

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PreviewScreen())),
                  child: const Text('open capture'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open capture'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the detected value and format', (tester) async {
    await pumpDetected(tester);

    expect(find.text('0123456789012'), findsOneWidget);
    expect(find.text('EAN_13'), findsOneWidget);
  });

  testWidgets('shows an Already scanned banner with the existing label when the value was scanned before', (
    tester,
  ) async {
    final duplicate = ScanEntry(
      id: 'old',
      value: '0123456789012',
      format: 'EAN_13',
      label: 'Pantry',
      scannedAt: DateTime.utc(2026, 1, 1, 9, 30),
    );
    await pumpDetected(tester, duplicate: duplicate);

    expect(find.text('Already scanned'), findsOneWidget);
    expect(find.text('Pantry'), findsOneWidget);
    expect(find.textContaining('First scanned'), findsOneWidget);
  });

  testWidgets('shows Add label when the existing entry has no label', (tester) async {
    final duplicate = ScanEntry(
      id: 'old',
      value: '0123456789012',
      format: 'EAN_13',
      scannedAt: DateTime.utc(2026, 1, 1, 9, 30),
    );
    await pumpDetected(tester, duplicate: duplicate);

    expect(find.text('Already scanned'), findsOneWidget);
    expect(find.text('Add label'), findsOneWidget);
  });

  testWidgets('no Already scanned banner for a fresh value', (tester) async {
    await pumpDetected(tester);

    expect(find.text('Already scanned'), findsNothing);
  });

  testWidgets('Save is replaced by Done and cannot persist a duplicate', (tester) async {
    final duplicate = ScanEntry(
      id: 'old',
      value: '0123456789012',
      format: 'EAN_13',
      scannedAt: DateTime.utc(2026, 1, 1, 9, 30),
    );
    await pumpDetected(tester, duplicate: duplicate);

    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Done'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.id, 'old');
    expect(find.text('open capture'), findsOneWidget);
  });

  testWidgets('the label field does not autofocus', (tester) async {
    await pumpDetected(tester);

    final textField = tester.widget<TextField>(find.byKey(const ValueKey('preview_label_field')));
    expect(textField.autofocus, isFalse);
  });

  testWidgets('Save persists the entry with its label and returns to the base route', (tester) async {
    await pumpDetected(tester);

    await tester.enterText(find.byKey(const ValueKey('preview_label_field')), 'Pantry');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.value, '0123456789012');
    expect(repository.entries.single.label, 'Pantry');
    expect(find.text('open capture'), findsOneWidget);
    expect(find.byType(PreviewScreen), findsNothing);
  });

  testWidgets('Save with an empty label stores null', (tester) async {
    await pumpDetected(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.entries.single.label, isNull);
  });

  testWidgets('Rescan discards without saving and pops back to capture', (tester) async {
    await pumpDetected(tester);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Rescan'));
    await tester.pumpAndSettle();

    expect(repository.entries, isEmpty);
    expect(find.text('open capture'), findsOneWidget);
    expect(find.byType(PreviewScreen), findsNothing);
  });
}
