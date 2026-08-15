import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:barcode_scanner/ui/capture/capture_screen.dart';
import 'package:barcode_scanner/ui/preview/preview_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_barcode_scanner_service.dart';
import '../fakes/fake_scan_repository.dart';

void main() {
  testWidgets('a system/gesture back from Preview (not Rescan/Save) restarts the camera', (tester) async {
    final service = FakeBarcodeScannerService();
    final repository = FakeScanRepository();
    final container = ProviderContainer(
      overrides: [
        barcodeScannerServiceProvider.overrideWithValue(service),
        scanRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: CaptureScreen())),
    );
    await tester.pump(); // flush the microtask-deferred start()

    expect(service.startCallCount, 1);

    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await tester.pump(const Duration(milliseconds: 350)); // haptic delay before navigating
    await tester.pumpAndSettle();

    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(service.stopCallCount, 1); // camera released for the (non-duplicate) capture

    // Simulate a system/gesture back press rather than tapping Rescan/Save/Done.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.byType(PreviewScreen), findsNothing);
    expect(find.byType(CaptureScreen), findsOneWidget);
    expect(service.startCallCount, 2);
  });

  testWidgets('tapping Rescan does not trigger a second, redundant start()', (tester) async {
    final service = FakeBarcodeScannerService();
    final repository = FakeScanRepository();
    final container = ProviderContainer(
      overrides: [
        barcodeScannerServiceProvider.overrideWithValue(service),
        scanRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const MaterialApp(home: CaptureScreen())),
    );
    await tester.pump();

    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Rescan'));
    await tester.pumpAndSettle();

    // rescan() itself calls start() once; _onDetected's post-pop check should
    // see phase == scanning already and skip calling it again.
    expect(service.startCallCount, 2);
  });
}
