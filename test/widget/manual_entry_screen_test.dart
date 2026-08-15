import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/ui/manual_entry/manual_entry_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scan_repository.dart';

void main() {
  Future<FakeScanRepository> pumpScreen(WidgetTester tester) async {
    final repository = FakeScanRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scanRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: ManualEntryScreen()),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('saving a value persists it and returns to the previous screen', (tester) async {
    final repository = await pumpScreen(tester);

    await tester.enterText(find.byType(TextField).first, '0123456789012');
    await tester.pump(); // rebuilds so Save's onPressed reflects the now-non-empty value
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.value, '0123456789012');
  });

  testWidgets('a repository save failure shows a SnackBar and keeps the form open for retry', (tester) async {
    final repository = await pumpScreen(tester);
    repository.throwOnSave = true;

    await tester.enterText(find.byType(TextField).first, '0123456789012');
    await tester.pump(); // rebuilds so Save's onPressed reflects the now-non-empty value
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save. Please try again."), findsOneWidget);
    expect(find.byType(ManualEntryScreen), findsOneWidget);
    expect(repository.entries, isEmpty);

    repository.throwOnSave = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.entries, hasLength(1));
  });
}
