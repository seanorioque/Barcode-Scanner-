# Barcode Capture

A small Flutter app for scanning 1D barcodes and QR codes with Google ML Kit, storing them locally, and reviewing them later.

**Flow:** Captured entries → Capture → Preview & confirm → back to Captured entries.

---

## Getting started

```bash
flutter pub get
flutter run
```

**Requirements:** Flutter 3.x (stable), Android 8.0+ (API 26) or iOS 15.5+ (the floor `google_mlkit_barcode_scanning`/`google_mlkit_commons` actually pin via their podspecs — not the 13.0 the project started at). A physical device is needed for scanning — the camera path is not usable on a simulator.

Permissions are declared in `android/app/src/main/AndroidManifest.xml` (`CAMERA`) and `ios/Runner/Info.plist` (`NSCameraUsageDescription`).

```bash
flutter analyze
flutter test
flutter test integration_test
```

---

## 1. Requirements

### Functional

| ID | Requirement |
|----|-------------|
| FR-01 | List previously captured entries, most recent first |
| FR-02 | Persist entries locally, surviving app restart |
| FR-03 | Start a new scan from the list screen |
| FR-04 | Detect common 1D barcodes and QR codes via Google ML Kit |
| FR-05 | Give clear feedback the moment a code is detected |
| FR-06 | Show the detected value and its format on the preview screen |
| FR-07 | Allow rescanning from preview without saving |
| FR-08 | Save the entry from preview |
| FR-09 | Allow an optional user-supplied label on the entry |

### Non-functional

- Detection within roughly one second in normal indoor lighting
- Fully offline — no network calls, no account
- Portrait orientation only
- Camera preview stays responsive while frames are being analysed

### Supported formats

EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, ITF, QR.

The detector is configured with this explicit list rather than "all formats". Narrowing the set measurably improves detection latency and reduces misreads on noisy frames.

---

## 2. Assumptions and decisions

The brief left several behaviours open. Each decision below is deliberate, and each is cheap to reverse.

| Question | Decision | Reasoning |
|---|---|---|
| Multiple codes in frame? | Capture one — the largest, most central detection | Multi-select adds UI weight for a case that is rare in practice; rescanning is a one-tap recovery |
| Duplicate values? | Save them, but show "already scanned on {date}" in the preview | Two scans of the same item can be legitimate. Informing the user beats deciding for them |
| Label required? | Optional, and editable after saving | The primary path should be scan → save in one tap |
| Rescan discards silently? | Yes | Nothing has been persisted yet, so a confirmation dialog is friction without value |
| Delete entries? | Swipe-to-delete with undo | Not in the brief, but a list you can only add to is a frustrating one |
| Export? | Out of scope for v1 | The repository interface anticipates it — see Roadmap |

**Explicitly out of scope:** sync or backup, search and filtering, batch/continuous scanning, deep-link handling for URL payloads, landscape layout, tablet-specific layout.

---

## 3. Architecture

```
lib/
├── domain/     ScanEntry, ScanRepository, BarcodeScannerService  (interfaces + model)
├── data/       SqliteScanRepository, MlKitBarcodeScannerService
└── ui/         entries/, capture/, preview/
```

Dependencies point inward. `domain/` knows nothing about SQLite, ML Kit, or Flutter widgets.

The two boundaries that matter are `ScanRepository` and `BarcodeScannerService`. Both exist so the layers above them can be tested without a database or a camera — the camera boundary in particular is drawn for testability rather than convenience, and it is what makes an end-to-end test of the capture flow possible at all.

### ADR-01: Google ML Kit via `camera` + `google_mlkit_barcode_scanning`

**Alternative considered:** `mobile_scanner`, which is a drop-in widget and considerably less work.

**Chosen:** `camera` + `google_mlkit_barcode_scanning`.

Recent `mobile_scanner` versions use ML Kit on Android but Apple Vision on iOS. Since the brief specifies Google ML Kit, this route keeps that true on both platforms and gives direct control over frame throttling and resolution.

**Cost accepted:** manual `CameraImage → InputImage` conversion, including YUV420 on Android vs BGRA8888 on iOS and rotation derived from `sensorOrientation`. This is the highest-risk part of the codebase and is isolated inside `MlKitBarcodeScannerService`.

### ADR-02: SQLite via `sqflite`

**Alternative considered:** Hive — simpler API, no schema.

**Chosen:** `sqflite`, because `sqflite_common_ffi` provides a real in-memory database in unit tests. Repository behaviour is verified against actual SQL rather than a mock, and schema migrations have a defined path if the model grows.

### ADR-03: Riverpod for state

A `StreamProvider` exposes the entry list so the UI reacts to writes without manual refresh. Scanner state is a `StateNotifier` over an explicit machine:

```
idle → scanning → detected → saving → idle
         ↑                 │
         └──── rescan ─────┘
```

Modelling this explicitly prevents the common failure where detection callbacks keep firing during the navigation transition and push several preview screens.

---

## 4. Data model

```dart
class ScanEntry {
  final String id;           // uuid v4
  final String value;        // raw barcode value
  final String format;       // "QR_CODE", "EAN_13", ...
  final String? label;       // optional, user-supplied
  final DateTime scannedAt;  // stored UTC, displayed local
}
```

```sql
CREATE TABLE scan_entries (
  id          TEXT PRIMARY KEY,
  value       TEXT    NOT NULL,
  format      TEXT    NOT NULL,
  label       TEXT,
  scanned_at  INTEGER NOT NULL   -- UTC epoch millis
);
CREATE INDEX idx_scan_entries_scanned_at ON scan_entries (scanned_at DESC);
```

Timestamps are stored as UTC epoch milliseconds and formatted at display time. Storing local time is the reliable way to acquire a timezone bug later.

---

## 5. Screens

### Captured entries

Reverse-chronological list. Each row shows the value in a monospace face (truncated with ellipsis), a format chip, and a relative timestamp — tapping reveals the absolute one. Empty state carries an illustration and a "Scan your first code" call to action. A FAB starts a capture. Swipe-to-delete offers an undo snackbar.

### Capture

Full-bleed preview under a dimmed overlay with a clear cutout, plus torch and close controls.

On detection: haptic pulse, the cutout border animates to the success colour, frame analysis stops immediately, and navigation to preview follows after roughly 300 ms so the confirmation is actually seen.

Frames are throttled to one analysis per ~250 ms, and frames arriving while an analysis is in flight are dropped. Without this the detector queues work faster than it completes it and the preview stutters.

### Preview & confirm

The value sits in a selectable monospace block with tap-to-copy; the format appears as a labelled chip. The optional label field does not autofocus, keeping **Save** one tap away. **Rescan** pops back and resets the scanner state.

---

## 6. Edge cases handled

| Case | Behaviour |
|---|---|
| Camera permission denied | In-context explainer with a retry action, not a black screen |
| Permission permanently denied | Detected via `permission_handler`, routed to system settings |
| App backgrounded mid-scan | Controller disposed in `didChangeAppLifecycleState`, re-initialised on resume |
| No camera available | Friendly error state instead of an exception |
| Very long QR payloads | Truncated in the list, fully scrollable and copyable in preview |
| Duplicate value | Saved, with a note showing when it was previously scanned |

---

## 7. Testing

- **Unit** — repository CRUD against in-memory SQLite; scanner state machine transitions; barcode selection written as a pure function (given N detections, choose one) so it needs no camera
- **Widget** — list rendering, empty state, preview screen against a fake repository, save flow
- **Integration** — a fake `BarcodeScannerService` emits scripted detections, letting the full scan → preview → save → appears-in-list path run in `integration_test`
- **Manual** — device checklist covering each supported format, low light, glare, curved and damaged labels, permission states, and background/resume mid-scan

---

## 8. Roadmap

- CSV / JSON export — one additional method on `ScanRepository`
- Search and filter by format or label
- Multi-code capture and continuous batch mode
- Deep-link handling for QR payloads containing URLs

---

## Known limitations

- Portrait only; landscape is locked out rather than laid out
- Damaged, heavily curved, or low-contrast 1D barcodes may need several attempts
- No backup — uninstalling the app removes all entries