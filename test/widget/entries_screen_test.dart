import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:barcode_scanner/ui/entries/entries_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_scan_repository.dart';

void main() {
  // Once the search field is present, `find.byType(TextField)` matches it
  // too, so dialog-scoped lookups need to be narrowed to the dialog itself.
  final dialogTextField = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));

  Future<FakeScanRepository> pumpEntries(WidgetTester tester, {List<ScanEntry> seed = const []}) async {
    final repository = FakeScanRepository();
    for (final entry in seed) {
      await repository.save(entry);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [scanRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: EntriesScreen()),
      ),
    );
    await tester.pump();
    return repository;
  }

  testWidgets('shows the empty state with a call to action when there are no entries', (tester) async {
    await pumpEntries(tester);

    expect(find.text('No scans yet'), findsOneWidget);
    expect(find.text('Scan your first barcode'), findsOneWidget);
  });

  testWidgets('lists entries most-recent-first with value and format', (tester) async {
    await pumpEntries(
      tester,
      seed: [
        ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1)),
        ScanEntry(id: '2', value: 'BBB222', format: 'EAN_13', scannedAt: DateTime.utc(2026, 1, 5)),
      ],
    );

    expect(find.byType(ListTile), findsNWidgets(2));
    expect(find.text('AAA111'), findsOneWidget);
    expect(find.text('BBB222'), findsOneWidget);
    expect(find.text('EAN_13'), findsOneWidget);

    final mostRecentTop = tester.getTopLeft(find.text('BBB222')).dy;
    final olderTop = tester.getTopLeft(find.text('AAA111')).dy;
    expect(mostRecentTop, lessThan(olderTop));
  });

  testWidgets('swiping an entry asks for confirmation before deleting it, and Undo restores it', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.drag(find.text('AAA111'), const Offset(-500, 0));
    await tester.pump();

    expect(find.text('Delete this scan?'), findsOneWidget);
    expect(find.text('AAA111'), findsWidgets); // still present, not yet deleted

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('AAA111'), findsNothing);
    expect(repository.entries, isEmpty);
    expect(repository.deletedEntries, hasLength(1));
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(find.text('AAA111'), findsOneWidget);
    expect(repository.entries, hasLength(1));
    expect(repository.deletedEntries, isEmpty);
  });

  testWidgets('Cancel in the delete confirmation keeps the entry', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.drag(find.text('AAA111'), const Offset(-500, 0));
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('AAA111'), findsOneWidget);
    expect(repository.entries, hasLength(1));
  });

  testWidgets('search filters by value and label', (tester) async {
    await pumpEntries(
      tester,
      seed: [
        ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', label: 'Pantry', scannedAt: DateTime.utc(2026, 1, 1)),
        ScanEntry(id: '2', value: 'BBB222', format: 'EAN_13', scannedAt: DateTime.utc(2026, 1, 5)),
      ],
    );

    await tester.enterText(find.byKey(const ValueKey('entries_search')), 'BBB');
    await tester.pump();

    expect(find.text('AAA111'), findsNothing);
    expect(find.text('BBB222'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('entries_search')), 'Pantry');
    await tester.pump();

    expect(find.text('AAA111'), findsOneWidget);
    expect(find.text('BBB222'), findsNothing);
  });

  testWidgets('search with no matches shows a message instead of the list', (tester) async {
    await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.enterText(find.byKey(const ValueKey('entries_search')), 'nope');
    await tester.pump();

    expect(find.text('AAA111'), findsNothing);
    expect(find.textContaining('No matches for'), findsOneWidget);
  });

  testWidgets('tapping a timestamp reveals the absolute date, tapping again reverts', (tester) async {
    final scannedAt = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: scannedAt)],
    );

    expect(find.text('3h ago'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timestamp_1')));
    await tester.pump();

    expect(find.text('3h ago'), findsNothing);
    expect(find.textContaining(':'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('timestamp_1')));
    await tester.pump();

    expect(find.text('3h ago'), findsOneWidget);
  });

  testWidgets('tapping the label opens an editable dialog and saves the new label', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    expect(find.text('Add label'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('label_1')));
    await tester.pumpAndSettle();

    expect(find.text('Edit label'), findsOneWidget);
    await tester.enterText(dialogTextField, 'Pantry');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Pantry'), findsOneWidget);
    expect(repository.entries.single.label, 'Pantry');
  });

  testWidgets('clearing the label field removes the label', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [
        ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', label: 'Pantry', scannedAt: DateTime.utc(2026, 1, 1)),
      ],
    );

    expect(find.text('Pantry'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('label_1')));
    await tester.pumpAndSettle();
    await tester.enterText(dialogTextField, '');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Add label'), findsOneWidget);
    expect(repository.entries.single.label, isNull);
  });

  testWidgets('Cancel in the label dialog leaves the label unchanged', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [
        ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', label: 'Pantry', scannedAt: DateTime.utc(2026, 1, 1)),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('label_1')));
    await tester.pumpAndSettle();
    await tester.enterText(dialogTextField, 'Ignored');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Pantry'), findsOneWidget);
    expect(repository.entries.single.label, 'Pantry');
  });

  testWidgets('long-pressing an entry enters selection mode and shows a checkbox', (tester) async {
    await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.longPress(find.text('AAA111'));
    await tester.pump();

    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
  });

  testWidgets('tapping other entries while selecting adds them, and Delete removes all selected with Undo', (
    tester,
  ) async {
    final repository = await pumpEntries(
      tester,
      seed: [
        ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1)),
        ScanEntry(id: '2', value: 'BBB222', format: 'EAN_13', scannedAt: DateTime.utc(2026, 1, 5)),
      ],
    );

    await tester.longPress(find.text('AAA111'));
    await tester.pump();
    await tester.tap(find.text('BBB222'));
    await tester.pump();

    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(find.text('Delete this scan?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(find.text('AAA111'), findsNothing);
    expect(find.text('BBB222'), findsNothing);
    expect(repository.entries, isEmpty);
    expect(repository.deletedEntries, hasLength(2));
    // Selection mode exits automatically once the delete completes.
    expect(find.text('Captured entries'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(repository.entries, hasLength(2));
    expect(repository.deletedEntries, isEmpty);
  });

  testWidgets('Cancel in the bulk-delete confirmation keeps the entries and selection', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.longPress(find.text('AAA111'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('1 selected'), findsOneWidget);
    expect(repository.entries, hasLength(1));
  });

  testWidgets('the close icon exits selection mode without deleting anything', (tester) async {
    final repository = await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.longPress(find.text('AAA111'));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    expect(find.text('Captured entries'), findsOneWidget);
    expect(repository.entries, hasLength(1));
  });

  testWidgets('the delete Undo snackbar lasts exactly 5 seconds', (tester) async {
    await pumpEntries(
      tester,
      seed: [ScanEntry(id: '1', value: 'AAA111', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1))],
    );

    await tester.drag(find.text('AAA111'), const Offset(-500, 0));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(seconds: 5));
  });
}
