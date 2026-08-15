import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:barcode_scanner/ui/recently_deleted/recently_deleted_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scan_repository.dart';

void main() {
  Future<FakeScanRepository> pumpScreen(WidgetTester tester, {List<ScanEntry> seed = const []}) async {
    final repository = FakeScanRepository();
    for (final entry in seed) {
      await repository.save(entry);
      await repository.softDelete(entry.id);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scanRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: RecentlyDeletedScreen()),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('shows an empty message when nothing is deleted', (tester) async {
    await pumpScreen(tester);

    expect(find.text('Nothing in Recently Deleted.'), findsOneWidget);
  });

  testWidgets('lists deleted entries', (tester) async {
    await pumpScreen(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    expect(find.text('AAA111'), findsOneWidget);
    // Trailing space so this doesn't also match the "Recently Deleted"
    // AppBar title -- the relative-time suffix ("just now", "3h ago", ...)
    // isn't predictable enough to match exactly.
    expect(find.textContaining('Deleted '), findsOneWidget);
  });

  testWidgets('Restore moves the entry back to active', (tester) async {
    final repository = await pumpScreen(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();

    expect(find.text('AAA111'), findsNothing);
    expect(find.text('Nothing in Recently Deleted.'), findsOneWidget);
    expect(repository.entries, hasLength(1));
    expect(repository.deletedEntries, isEmpty);
  });

  testWidgets('Restore is blocked and reported when an active duplicate exists', (tester) async {
    final repository = await pumpScreen(
      tester,
      seed: [ScanEntry(id: '1', value: 'dup', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );
    await repository.save(ScanEntry(id: '2', value: 'dup', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 5)));

    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();

    expect(find.textContaining("Can't restore"), findsOneWidget);
    expect(repository.deletedEntries, hasLength(1));
  });

  testWidgets('a repository failure while restoring shows a SnackBar and keeps the entry in the trash', (tester) async {
    final repository = await pumpScreen(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );
    repository.throwOnRestore = true;

    await tester.tap(find.byTooltip('Restore'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't restore. Please try again."), findsOneWidget);
    expect(repository.deletedEntries, hasLength(1));
    expect(repository.entries, isEmpty);
  });

  testWidgets('a repository failure while permanently deleting shows a SnackBar and keeps the entry', (tester) async {
    final repository = await pumpScreen(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );
    repository.throwOnPermanentlyDelete = true;

    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't delete. Please try again."), findsOneWidget);
    expect(repository.deletedEntries, hasLength(1));
  });

  testWidgets('Delete permanently asks for confirmation before removing the entry', (tester) async {
    final repository = await pumpScreen(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();

    expect(find.text('Delete permanently?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deletedEntries, hasLength(1));

    await tester.tap(find.byTooltip('Delete permanently'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.deletedEntries, isEmpty);
    expect(find.text('Nothing in Recently Deleted.'), findsOneWidget);
  });
}
