# Functional Requirements — Barcode Capture

Extracted from `prompt/plan.md`'s `Section 1 (Functional)`, `Section 2 (Assumptions/decisions)`, `Section 5 (Screens)`, and `Section 6 (Edge cases)`. FR-01–FR-09 map to the IDs specified in the original brief; FR-10+ are additional requirements the brief describes but didn't number.

| ID | Requirement | Screen | Priority | Acceptance Criteria |
|---|---|---|---|---|
| FR-01 | List previously captured entries, most recent first | Captured entries | Must | Entries load ordered by `scanned_at DESC`. Each row shows value (monospace, ellipsis-truncated), a format chip, and a relative timestamp. List updates live (no manual refresh) via `StreamProvider` when an entry is saved or deleted. |
| FR-02 | Persist entries locally, surviving app restart | Data layer (all screens) | Must | Entries write to SQLite (`scan_entries` table: id, value, format, label, scanned_at). Force-quitting and relaunching shows all prior entries unchanged. No network call occurs at any point (offline-only). |
| FR-03 | Start a new scan from the list screen | Captured entries → Capture | Must | A FAB is present on Captured entries (including empty state). Tapping it navigates to Capture and triggers the permission check (FR-13). |
| FR-04 | Detect common 1D barcodes and QR codes via Google ML Kit | Capture | Must | Detector is scoped to exactly: EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, ITF, QR — no other symbology triggers a result. A steady, in-focus code of a supported format is detected in ~1s under normal indoor lighting. When multiple codes are in frame, exactly one is selected (largest/most central) via the documented pure-function selector. |
| FR-05 | Give clear feedback the moment a code is detected | Capture | Must | On detection: haptic pulse fires, cutout border animates to the success color, frame analysis stops immediately, and navigation to Preview occurs ~300ms later (not instantly). State machine (`idle→scanning→detected→saving`) never pushes more than one Preview screen from repeated callbacks during the transition. |
| FR-06 | Show the detected value and its format on the preview screen | Preview & confirm | Must | Value renders in a selectable monospace block; format renders as a labelled chip. Long payloads are fully visible via scrolling, not truncated. If the value already exists in storage, a duplicate note is shown (FR-19). |
| FR-07 | Allow rescanning from preview without saving | Preview & confirm | Must | "Rescan" pops back to Capture and resets scanner state to `scanning`, with no confirmation dialog and no DB write. Detection resumes automatically. |
| FR-08 | Save the entry from preview | Preview & confirm | Must | "Save" is reachable in one tap (label field doesn't autofocus). Tapping it inserts a row (`id`=uuid v4, value, format, label-or-null, `scanned_at`=now UTC) and returns to Captured entries with the new row visible at the top. Save succeeds with an empty label. |
| FR-09 | Allow an optional user-supplied label on the entry | Preview & confirm | Should | Label field is present, does not autofocus, and is optional — save succeeds whether it's populated or blank. |
| FR-10 | Reveal absolute timestamp on tapping a row's relative timestamp | Captured entries | Could | Tapping a row's relative timestamp (e.g. "3d ago") displays the absolute date/time; tapping again reverts. |
| FR-11 | Show empty state with call-to-action when no entries exist | Captured entries | Should | When `scan_entries` is empty, list is replaced by an illustration + "Scan your first code" CTA. Tapping the CTA navigates to Capture. Empty state disappears once ≥1 entry exists. |
| FR-12 | Delete an entry via swipe, with undo | Captured entries | Should | Swiping a row removes it from the visible list and shows an "Undo" snackbar. Tapping Undo restores the entry. If the snackbar times out unactioned, the row is permanently deleted from SQLite. |
| FR-13 | Request and handle camera permission states | Capture | Must | Permission is requested on entering Capture if not already granted. Denied → in-context explainer with retry (not a blank screen). Permanently denied → detected via `permission_handler` and routed to system settings. |
| FR-14 | Toggle torch during capture | Capture | Could | A torch control on the overlay toggles the device flashlight on/off. |
| FR-15 | Close capture without scanning | Capture | Must | A close control stops camera/analysis and returns to Captured entries with no entry created. |
| FR-16 | Show friendly error state when no camera is available | Capture | Should | If the device reports no camera, Capture shows a friendly error state instead of crashing; no preview/detection is attempted. |
| FR-17 | Suspend/resume camera on app backgrounding mid-capture | Capture | Should | On backgrounding, the camera controller disposes via `didChangeAppLifecycleState`; on resume it reinitializes and detection resumes, with no crash or frozen preview. |
| FR-18 | Copy detected value to clipboard | Preview & confirm | Could | Tapping the value block copies the raw decoded value to the system clipboard. |
| FR-19 | Flag duplicate scans against existing entries | Preview & confirm | Should | Value is checked against stored `scan_entries.value`. On match, Preview shows "already scanned on {date}." Save is **not** blocked — duplicates can still be saved. |
| FR-20 | Edit label on a previously saved entry | Captured entries | Should | Tapping an entry's label (or an edit affordance next to it) opens a small dialog pre-filled with the current label. Confirming persists the change via `ScanRepository.save`; leaving it blank clears the label back to `null`. **Resolved 2026-08-15: tap-to-edit on the row, implemented in Phase 2** (see `prompt/phase2-plan.md`). |

## Totals

- **20 functional requirements** (9 explicitly numbered in the brief, 10 additional derived from the Screens/Decisions/Edge-cases sections, plus FR-20 which was a gap at first pass and has since been assigned an implementation).
- **Screens covered:** Captured entries (FR-01, 02, 03, 10, 11, 12, 20), Capture (FR-03, 04, 05, 13, 14, 15, 16, 17), Preview & confirm (FR-06, 07, 08, 09, 18, 19).

## Ambiguities — resolution log

| # | Ambiguity | Resolution | Date |
|---|---|---|---|
| 1 | FR-20 had no assigned screen/UI | Tap-to-edit dialog on the Captured entries row | 2026-08-15 |
| 2 | Timestamp tap: one-way reveal or toggle? | Implemented as a toggle (tap again reverts) | Implemented during initial build |
| 3 | Undo snackbar duration | Uses Material's default `SnackBar` duration (~4s) | Implemented during initial build |
| 4 | Permission granted via system settings — does Capture auto-resume? | Was a real gap (found during Phase 2 review) — fixed so `resumeFromBackground` also retries from the `unavailable` phase | 2026-08-15 |
| 5 | Torch state persistence across sessions | Does not persist — resets each time Capture is entered (new `MlKitBarcodeScannerService` instance per session) | Implemented during initial build |
| 6 | Copy-to-clipboard confirmation | A `SnackBar` ("Copied to clipboard") is shown | Implemented during initial build |
| 7 | Duplicate match logic (exact value only? which date on multiple matches?) | Exact `value` match; `findMostRecentByValue` returns the most recently scanned match | Implemented during initial build |
| 8 | Swipe-to-delete direction / permanence after undo window | `DismissDirection.endToStart` (swipe left); deletion is immediate with `save()` as the undo path (re-inserts the same entry) | Implemented during initial build |
