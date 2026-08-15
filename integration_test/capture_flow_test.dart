import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/data/sqlite_scan_repository.dart';
import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:barcode_scanner/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../test/fakes/fake_barcode_scanner_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets('scan -> preview -> save -> appears in the entries list', (tester) async {
    final service = FakeBarcodeScannerService();
    final repository = SqliteScanRepository(databaseFactory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(repository.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanRepositoryProvider.overrideWithValue(repository),
          barcodeScannerServiceProvider.overrideWithValue(service),
        ],
        child: const BarcodeCaptureApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No scans yet'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.barcode_reader));
    await tester.pumpAndSettle();

    // Stands in for a real camera frame containing a decoded barcode.
    service.emit(const [BarcodeDetection(value: '9781234567897', format: 'EAN_13', boundingBoxArea: 500)]);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(find.text('9781234567897'), findsOneWidget);
    expect(find.text('EAN_13'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('preview_label_field')), 'Cereal');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('No scans yet'), findsNothing);
    expect(find.text('9781234567897'), findsOneWidget);
    expect(find.text('Cereal'), findsOneWidget);
  });

  testWidgets('rescan discards the detection and returns to capture without saving', (tester) async {
    final service = FakeBarcodeScannerService();
    final repository = SqliteScanRepository(databaseFactory: databaseFactoryFfi, path: inMemoryDatabasePath);
    addTearDown(repository.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scanRepositoryProvider.overrideWithValue(repository),
          barcodeScannerServiceProvider.overrideWithValue(service),
        ],
        child: const BarcodeCaptureApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.barcode_reader));
    await tester.pumpAndSettle();

    service.emit(const [BarcodeDetection(value: 'discard-me', format: 'CODE_128', boundingBoxArea: 500)]);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, 'Rescan'));
    await tester.pumpAndSettle();

    // Back on Capture, not Preview or Entries.
    expect(find.text('discard-me'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('No scans yet'), findsOneWidget);
  });
}
