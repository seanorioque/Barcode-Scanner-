# Phase 2 Execution Log — Barcode Capture

Running log of what actually happened during Phase 2 (see `prompt/phase2-plan.md` for the plan). Newest entries at the bottom.

## 2026-08-15 — Kickoff

- Read `prompt/plan.md` (the original brief) and `prompt/requirements.md` (the FR table from the requirements pass).
- Confirmed with the user this is a continuation of the plan approved via `whats-our-next-steps-splendid-valiant.md`: manual test → resolve ambiguities → confirm automated tests → commit.

## 2026-08-15 — Step 2: FR-20 label editing + permission-resume fix

- Device disconnected between sessions (no longer listed in `flutter devices`) — Step 1 (manual test) is blocked until reconnected. Did Step 2's code work while waiting.
- `ScanEntry.copyWith` gained an explicit `clearLabel` flag (`lib/domain/scan_entry.dart`) — plain `label: null` was indistinguishable from "leave unchanged".
- `EntriesScreen` rows: label area is now always tappable (shows "Add label" placeholder when empty) and opens an edit dialog (`lib/ui/entries/entries_screen.dart`).
- `ScannerController.resumeFromBackground` now also retries from `ScanPhase.unavailable`, not just `scanning` (`lib/ui/capture/scanner_controller.dart`) — fixes the case where returning from system settings after granting camera permission left Capture stuck on the "unavailable" overlay.
- Added tests: `test/unit/scan_entry_test.dart` (copyWith), two new cases in `test/unit/scanner_controller_test.dart` (resume-from-unavailable, resume no-op), three new cases in `test/widget/entries_screen_test.dart` (edit/save, clear-to-null, cancel).
- **Bug caught by the test suite, not by review**: the first version of the edit dialog built the `TextEditingController` inline in `_editLabel` and called `.dispose()` immediately after `showDialog` returned. That's too early — the dialog's exit *animation* still needs the controller for a frame or two after `pop()` resolves, so it crashed with "A TextEditingController was used after being disposed" during `pumpAndSettle`. Fixed by moving the dialog into its own `_EditLabelDialog` `StatefulWidget` that owns the controller and disposes it in its own `dispose()`, which the framework calls only once the widget is actually removed from the tree. `flutter analyze` stayed clean throughout — this was a runtime-only bug the test suite caught, which is the whole point of Step 3.
