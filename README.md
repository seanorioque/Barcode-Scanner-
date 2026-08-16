# Barcode Capture

An offline Flutter app for scanning 1D barcodes and QR codes with Google ML Kit and keeping a local, searchable record of them. Android and iOS only — no network calls, no account, no sync.

## Demo

[1D](https://drive.google.com/file/d/1pPjIBn1EW5Uw5OekcpW-5MfJJe4Zhxjj/view?usp=sharing) 
[2D](https://drive.google.com/file/d/1wkrNl482iIpE-iI77w0H0fViYb4SHlXZ/view?usp=sharing)
— Captured entries → Capture → detect → Preview & confirm → Save.

## Exercise requirements

A direct mapping to the brief, for quick verification.

**Captured entries**
- ✅ List of previously scanned barcodes/QR codes — `EntriesScreen`, most recent first
- ✅ Stored locally on the device — SQLite via `sqflite` (`SqliteScanRepository`), fully offline
- ✅ Each entry shows the scanned value and date/time — monospace value + relative timestamp (tap to reveal the absolute date/time)
- ✅ Start a new scan from this screen — FAB, present including on the empty state

**Capture**
- ✅ Opens the phone camera — `camera` package, live preview
- ✅ Google ML Kit recognizes common 1D barcodes and QR codes — EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, Codabar, ITF, and QR (see [Supported formats](#supported-formats))
- ✅ Clear indication when a code is detected — haptic pulse, the scan guide's border turns green, and a ~300ms pause before advancing to Preview so the confirmation is actually seen

**Preview & confirm**
- ✅ Shows the detected value and format/type — selectable monospace value block + a labelled format chip
- ✅ Rescan if needed — one tap, no confirmation dialog, nothing was persisted yet so there's nothing to discard
- ✅ Save the entry — one tap
- ✅ Optional name/label — a text field that doesn't autofocus (keeps Save one tap away), blank is fine

**Deliverables**
- ✅ GitHub repository with source + a README with run/build instructions — this repo
- ✅ Android APK, installable and testable — attached to the [v1.0.0 release](https://github.com/seanorioque/Barcode-Scanner-/releases/tag/v1.0.0)
- ✅ Short screen recording of the main flow — see [Demo](#demo) above
- ✅ Technical decisions, libraries used, what I learned, what I'd improve — see the matching sections near the bottom of this README

Reasonable decisions made where the brief/mockup didn't specify are called out inline throughout, and the full list (with dates and root causes for anything that was a bug rather than a choice) lives in [`prompt/requirements.md`](prompt/requirements.md)'s ambiguity/bug log.

## What it does

Point the camera at a barcode, confirm the value and an optional label, and it's saved locally with a cropped photo of the code. Scanning the same value again doesn't create a duplicate — it surfaces the existing entry instead. Entries can be edited, searched, deleted (with a 5-second Undo and a Recently Deleted trash), or entered manually without a camera.

## Screens

- **Captured entries** — the list of everything scanned, most recent first, with search, multi-select delete, and tap-to-edit labels.
- **Capture** — live camera preview with a scan guide, torch toggle, and permission handling.
- **Preview & confirm** — shows the detected value, format, and cropped photo; Save, Rescan, or (for a duplicate) Done.
- **Recently Deleted** — soft-deleted entries, restorable until a 30-day retention period purges them.
- **Add manually** — type in a barcode value/format/label without scanning.

## Supported formats

1D: EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, Codabar, ITF. Plus QR codes. Other 2D formats (Data Matrix, Aztec, PDF417, ...) are out of scope — the brief asked for 1D + QR specifically.

---

## Requirements

| | |
|---|---|
| Flutter | 3.44.9 stable (SDK constraint `^3.12.2`) — this is the version CI pins |
| Android | 8.0+ (API 26) at runtime, compiled against API 36, JDK 17 |
| iOS | 15.5+, Xcode with CocoaPods installed, macOS host |
| Device | **A physical device is required for scanning** |

That last row is the one that catches people out. The Android emulator's synthetic camera can't present a scannable barcode and iOS simulators have no camera at all — the entries list and manual entry work fine, but the whole capture path needs real hardware.

Check your toolchain before anything else:

```bash
flutter doctor
```

---

## Running

```bash
git clone https://github.com/seanorioque/Barcode-Scanner-.git
cd Barcode-Scanner-
flutter pub get
flutter devices          # confirm your phone is listed
flutter run
```

Grant the camera permission when prompted — the Capture screen is unusable without it, and Android's "permanently denied" state (two refusals) sends you to system settings to recover.

To measure real scan latency, use a profile build. Debug-mode Dart makes ML Kit detection look considerably slower than it is:

```bash
flutter run --profile
```

### Android specifics

Nothing beyond the standard setup — enable USB debugging on the phone and accept the RSA prompt.

One pin worth knowing about before you touch dependencies: `compileSdk` is held at **36** and `permission_handler` at **^12.0.3**. Versions of `permission_handler` at 13.0.0 or above pull in `permission_handler_android` ≥14.0.0, which hardcodes `compileSdk = 37` — a preview-only level that isn't installable as a stable target and breaks the Java compile step on any machine without it. Both files carry comments explaining this. Don't bump either in isolation.

### iOS specifics

```bash
cd ios && pod install && cd ..
flutter run
```

The `Podfile` pins `platform :ios, '15.5'` to match the ML Kit podspecs. If CocoaPods complains about a platform mismatch, that's the line to check first — and check the installed podspec's actual minimum rather than assuming 15.5 is still current.

To install on your own device you need either a free Apple ID (the build expires after 7 days) or a paid developer account. Open `ios/Runner.xcworkspace` — not the `.xcodeproj` — to set your signing team.

---

## Building

```bash
flutter build apk --debug              # sideloadable debug APK
flutter build apk --release            # release APK
flutter build appbundle --release      # AAB for Play Store
flutter build ios --release            # requires signing
flutter build ios --no-codesign        # compile check without signing
```

Output lands in `build/app/outputs/flutter-apk/` and `build/ios/`.

**Before any store submission:** the bundle ID is still `com.example.barcode_scanner`, in `android/app/build.gradle.kts` (both `namespace` and `applicationId`) and in the Xcode project. Apple and Google both reject `com.example.*`. Release builds also need a signing config — the Android release build currently uses debug signing keys.

---

## Testing

```bash
flutter analyze --fatal-infos          # what CI runs
flutter test                           # unit + widget suite
flutter test integration_test          # needs a connected device
```

The repository tests run real SQL through `sqflite_common_ffi` rather than mocks, so they exercise the actual schema, migrations, and the partial unique index. The integration test drives the full navigation flow with a fake scanner service — worth knowing that it does *not* exercise the camera or ML Kit, so those stay manual.

CI (`.github/workflows/ci.yml`) runs analyze and the test suite on every push, plus a debug APK build to catch Android build regressions early.

### Debug-only tools

Debug builds show a bug icon in the Captured entries AppBar with **Clear all data** and **Purge trash now**. These exist because duplicate blocking means each physical barcode can only be saved once — without a reset you run out of test barcodes fast. They're compiled out of release builds via `kDebugMode` and are test fixtures, not features.

### Inspecting the database

```bash
adb exec-out run-as com.example.barcode_scanner cat databases/scan_entries.db > local.db
```

Debug builds only. Entries live in `scan_entries.db`; cropped photos live alongside in `app_flutter/scan_images/`, referenced by path from the `image_path` column.

---

## Project layout

```
lib/
  domain/     pure Dart — models, repository/scanner interfaces, crop math.
              No camera, sqflite, or ML Kit imports here by design.
  data/       real implementations: MlKitBarcodeScannerService (camera +
              ML Kit + photo cropping), SqliteScanRepository (schema v3,
              migrations, retention sweep, image cleanup)
  ui/         one folder per screen, Riverpod controllers alongside
  main.dart   opens the database, injects the repository via ProviderScope
test/         unit + widget tests, with fakes in test/fakes/
integration_test/  end-to-end flow against a fake scanner
prompt/       the real documentation — see below
android/ ios/ platform scaffolding (other platforms removed deliberately;
              ML Kit barcode scanning is mobile-only)
```

The interfaces in `lib/domain/` are the seam that makes the UI testable without a camera or a database. Keep them dependency-free.

---

## Troubleshooting

**Camera permission stuck after granting it in system settings** — this was a real bug, fixed in Phase 2 via lifecycle observation. If you see it again, check `CaptureScreen`'s `didChangeAppLifecycleState`.

**Build fails on `:app:compileDebugJavaWithJavac`** — almost certainly the `compileSdk`/`permission_handler` interaction described above. Check whether something bumped either one.

**Barcode won't scan** — printed codes work far better than codes displayed on another screen, where glare and pixel moiré defeat the line scan. Also confirm the format is in the supported list — 1D + QR, not other 2D formats like Data Matrix or PDF417.

**`flutter test` fails on database tests** — make sure `flutter pub get` has pulled `sqflite_common_ffi`; the tests need it to run SQLite on the host.

---

## More

`prompt/` holds the real documentation: `requirements.md` (numbered functional requirements with acceptance criteria and an ambiguity/bug log), `plan.md` (the original brief), and per-phase execution logs recording what broke, why, and how it was root-caused. Read it before making non-trivial changes — several current constraints are deliberate decisions rather than oversights.

---

## Technical decisions

- **`camera` + `google_mlkit_barcode_scanning` over `mobile_scanner`.** `mobile_scanner` is far less code, but recent versions use ML Kit on Android and Apple's own Vision framework on iOS. The brief calls for Google ML Kit specifically, so this route keeps that true on both platforms and gives direct control over frame throttling, resolution, and rotation — at the cost of owning the `CameraImage → InputImage` conversion by hand (YUV420 on Android, BGRA8888 on iOS), which is the highest-risk code in the app (`lib/data/mlkit_barcode_scanner_service.dart`).
- **`sqflite` over Hive.** Hive is a simpler API with no schema, but `sqflite_common_ffi` gives the test suite a real in-memory SQLite engine, so repository tests run actual SQL — including a partial unique index (`... WHERE deleted_at IS NULL`) — instead of asserting against a mock.
- **The scanned `value` is the app's unique identifier.** Once duplicate-blocking became a requirement, `value` needed to be immutable and uniquely constrained among active rows, enforced at the DB level (not just in the UI), so a second scan of the same code can't slip through a race or a bypassed check.
- **Riverpod with an explicit state machine** (`idle → scanning → resolving → detected → saving`) rather than ad hoc booleans. The `resolving` phase exists specifically to stop a second camera frame from starting a concurrent duplicate-lookup while the first one is still in flight — a real bug class with repeated detection callbacks during a screen transition.
- **1D + QR, not general 2D.** An earlier pass narrowed the detector to 1D-only, which was a real deviation from the brief's stated "1D + QR" requirement rather than something the mockup left open — see `prompt/requirements.md`'s bug log for the full account. `BarcodeFormat.qrCode` is now back in the detector, and the scan guide changed from a wide 1D-shaped rectangle to a square, since a square correctly frames a QR code while still comfortably fitting a horizontal 1D barcode. Other 2D formats (Data Matrix, Aztec, PDF417) stay out of scope — the brief only asked for QR.
- **Photo cropping uses resolution-independent fractional coordinates.** ML Kit's analysis frame and the full-resolution still photo are different sizes, so the detected bounding box is stored as a fraction (0.0–1.0) of the upright frame, then re-applied to whatever resolution the still photo turns out to be (`lib/domain/barcode_crop.dart`).

## Libraries used

| Package | Why |
|---|---|
| `camera` | Live preview + frame stream + still capture |
| `google_mlkit_barcode_scanning` | The actual barcode detection, per the brief |
| `flutter_riverpod` | State management — `StreamProvider` for the live entry list, a `Notifier` for the scan state machine |
| `sqflite` / `sqflite_common_ffi` | Local persistence; the FFI variant runs real SQLite in tests |
| `image` | Decoding, EXIF-orientation baking, and cropping the captured JPEG |
| `path_provider` / `path` | Locating and building paths into app-private storage for the DB and photos |
| `permission_handler` | Camera permission request/status, including the "permanently denied → system settings" path |
| `uuid` | Entry IDs |

## What I learned

This was my first time working with Flutter and Google ML Kit, so most of the learning was hands-on:

- **Camera frame formats aren't uniform across platforms.** Android delivers YUV420 planes that need concatenating into an NV21-compatible buffer; iOS delivers BGRA8888 directly. Both need a rotation value derived from the sensor orientation, not just the frame dimensions.
- **A frame's "upright" dimensions depend on rotation in a specific way** — only 90°/270° sensor rotations swap width/height; 180° doesn't. This app actually shipped a bug where that condition got flipped to 180°/270° at some point, silently scrambling every cropped photo. It's now a table-tested pure function (`lib/domain/barcode_crop.dart`) specifically so that class of bug can't come back unnoticed.
- **Riverpod has real rules about where you can read provider state.** Reading a notifier's own `state` from inside its `ref.onDispose` callback throws — "Cannot use Ref inside life-cycles" — because Ref access is guarded during lifecycle callbacks. The fix was mirroring the two fields cleanup needed into plain instance fields kept in sync on every state write, rather than reading through `state` at dispose time.
- **`flutter_test`'s `pumpAndSettle()` needs a genuinely settling widget tree.** A conditionally-enabled button whose `onPressed` was captured from a build *before* a text field's `setState` fires will silently no-op on tap unless you `pump()` in between — the tap still "succeeds" against the stale widget, it just doesn't do anything.
- **SQLite's partial unique indexes** (`CREATE UNIQUE INDEX ... WHERE deleted_at IS NULL`) are a clean way to express "unique among active rows only," which is exactly what duplicate-blocking-with-soft-delete needed.

## What I'd improve with more time

- **iOS has never actually been built.** The deployment target and `Podfile` are set correctly against the real ML Kit pod requirements, but this was developed on a Windows machine with no Xcode/macOS access, so `pod install` and a real device build have never been run.
- **CSV/data export** — raised as a candidate but deliberately not built this pass; the repository interface would need one more method.
- **Pagination for the entries list** — currently loads every active row and filters client-side, which is fine at hundreds of entries but wouldn't scale cleanly to very large datasets. Not worth the complexity without evidence that volume is real.
- **Android release signing** — the release build currently reuses the debug signing config, and the bundle ID is still the `com.example.*` placeholder; both need to change before any real store submission.
