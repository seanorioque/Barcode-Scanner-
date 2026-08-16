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

  /// A bounded alternative to `pumpAndSettle()` for the Save flow.
  /// `pumpAndSettle()` can never return while `ScanPhase.saving`'s
  /// indeterminate `CircularProgressIndicator` is on screen -- it keeps
  /// scheduling new frames for its own rotation forever, regardless of
  /// whether the underlying save has actually finished, so pumpAndSettle
  /// has no way to distinguish "still saving" from "decorative animation
  /// still spinning." A fixed number of pumps sidesteps that: it advances
  /// the real work (repository save, stream-subscription teardown, the
  /// state transition back to idle, and the pop) without depending on
  /// hasScheduledFrame ever going false while a spinner is in the tree.
  Future<void> pumpThroughSave(WidgetTester tester) async {
    // runAsync, not more fake-clock pump() calls -- something in the save
    // path (suspected: cancelling the StreamSubscription to the fake
    // service's broadcast stream) needs real async/event-loop time to
    // resolve that fake-clock pumping alone never provides, no matter how
    // many iterations. runAsync briefly steps outside the fake-clock zone
    // to let real Futures/Timers actually complete. pumpAndSettle afterward
    // is safe here (unlike right after tapping Save) because the only
    // thing left to settle is the route's own bounded pop transition, not
    // an indeterminate spinner.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

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
    // tester.pump(), not a bare Future.delayed -- testWidgets() runs inside
    // TestWidgetsFlutterBinding's controlled-clock zone, where a bare
    // Future.delayed (even Duration.zero) never gets its timer processed
    // without an explicit pump to drive it, and just hangs until the test's
    // outer timeout aborts it. This was previously hanging every single
    // test in this file for the full 10-minute pumpAndSettle ceiling.
    await tester.pump();
    await tester.pump(); // let the duplicate lookup resolve

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
    await pumpThroughSave(tester);

    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.value, '0123456789012');
    expect(repository.entries.single.label, 'Pantry');
    expect(find.text('open capture'), findsOneWidget);
    expect(find.byType(PreviewScreen), findsNothing);
  });

  testWidgets('Save with an empty label stores null', (tester) async {
    await pumpDetected(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpThroughSave(tester);

    expect(repository.entries.single.label, isNull);
  });

  testWidgets('a repository save failure shows a SnackBar and leaves Save tappable to retry', (tester) async {
    await pumpDetected(tester);
    repository.throwOnSave = true;

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpThroughSave(tester);

    expect(find.text("Couldn't save. Please try again."), findsOneWidget);
    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(repository.entries, isEmpty);

    repository.throwOnSave = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await pumpThroughSave(tester);

    expect(repository.entries, hasLength(1));
    expect(find.byType(PreviewScreen), findsNothing);
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
