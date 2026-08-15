# Phase 2 Plan — Barcode Capture

*Written 2026-08-15 during a planning pass after the initial implementation. Execution log lives in `prompt/phase2-log.md`.*

## Context

The three-screen app (Captured entries / Capture / Preview & confirm) described in the brief (`prompt/plan.md`) was fully implemented in Phase 1, committed (`f603208`), and successfully built and launched once on a connected Galaxy device (SM S921B, Android 16). Getting it running uncovered a real Android build issue that was fixed in the working tree but not yet committed. Three things were still open before this could be called done:

1. The app had only been verified to *launch* to the empty entries screen — the actual scan → preview → save flow had never been exercised on a real device.
2. The automated test suite (unit + widget, written in Phase 1) had never returned a confirmed pass/fail result — two `flutter test` runs got orphaned by a session restart before finishing.
3. One genuine gap from the requirements review (FR-20: label editing after save) had no implementation and needed one.

This plan sequences the four things the user prioritized: manual test → resolve ambiguities → confirm automated tests → commit.

## Step 1 — Manual test on the phone

Relaunch and walk the golden path for real:

- `flutter run -d RFCX808WJGV` (device may need reconnecting — the previous session ended with "Lost connection to device", exit code 0, no crash/exception in the log — likely just a USB/ADB blip).
- On device: empty state → tap FAB → grant camera permission → point at a real barcode/QR → confirm haptic + green border feedback → preview shows correct value/format → Save → appears in Captured entries.
- Also exercise: Rescan (discards, returns to live camera), swipe-to-delete + Undo snackbar, tap timestamp to reveal/hide absolute date, torch toggle, scanning the same code twice (duplicate note), and denying camera permission (explainer + retry).
- Fix anything that doesn't behave as expected before moving on — camera frame conversion (`lib/data/mlkit_barcode_scanner_service.dart`) is the highest-risk code path and had never run against a real camera frame.

## Step 2 — Resolve ambiguities

### FR-20: label editing after save (decided: tap-to-edit on the row)

- In `lib/ui/entries/entries_screen.dart`, make each row's label tappable (or add a small edit `IconButton` next to it). Tapping opens a small dialog (`showDialog` with a `TextField` pre-filled with the current label) to rename it.
- On confirm, call `ref.read(scanRepositoryProvider).save(entry.copyWith(label: newLabel))` — `ScanEntry.copyWith` (`lib/domain/scan_entry.dart`) and `ScanRepository.save`'s upsert (`ConflictAlgorithm.replace` in `lib/data/sqlite_scan_repository.dart`) already support this with no new plumbing.
- Blank input clears the label back to `null` (mirrors the save-time behavior in `ScannerController.save`, `lib/ui/capture/scanner_controller.dart`).
- Add a widget test in `test/widget/entries_screen_test.dart` covering: opening the edit dialog, saving a new label, and clearing a label back to none.

### Secondary bug found while reviewing the ambiguities: permission grant doesn't auto-resume

`CaptureScreen.didChangeAppLifecycleState` (`lib/ui/capture/capture_screen.dart`) only calls `resumeFromBackground()` when `state.phase == ScanPhase.scanning`. If the user backgrounds the app to grant camera permission from system settings (the `ScannerUnavailableReason.permissionPermanentlyDenied` path), returning to the app left the screen stuck on the "unavailable" overlay instead of retrying. Fix: also retry when `state.phase == ScanPhase.unavailable` on resume, in `ScannerController.resumeFromBackground` (`lib/ui/capture/scanner_controller.dart`).

## Step 3 — Confirm the automated test suite

- `flutter test` for the full unit + widget suite (`test/unit/`, `test/widget/`).
- With the device connected, also run the integration test for real: `flutter test integration_test/capture_flow_test.dart -d RFCX808WJGV`.

## Step 4 — Commit

Two logical commits:

1. **Android build fix**: `permission_handler` downgraded to `11.4.0` in `pubspec.yaml` (was `13.0.1`, which pulled `permission_handler_android 14.0.0` — that version hard-codes `compileSdk = 37`, a preview-only SDK level that isn't cleanly installable as a stable target and broke `:app:compileDebugJavaWithJavac`), plus whatever `android/app/build.gradle.kts`'s `compileSdk` setting is confirmed to need.
2. **Label editing + permission-resume fix**: the FR-20 implementation and the lifecycle bug fix from Step 2, together with their new/updated tests.

## Verification

- `flutter analyze` clean.
- `flutter test` — all unit + widget tests green, including the new label-edit test.
- `flutter test integration_test/capture_flow_test.dart -d RFCX808WJGV` green.
- Manual walkthrough from Step 1 completed with no unexpected behavior.
- `git status` clean after the two commits in Step 4.
