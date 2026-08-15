# Barcode Capture

An offline Flutter app for scanning 1D barcodes with Google ML Kit and keeping a local, searchable record of them. Android and iOS only — no network calls, no account, no sync.

## What it does

Point the camera at a barcode, confirm the value and an optional label, and it's saved locally with a cropped photo of the code. Scanning the same value again doesn't create a duplicate — it surfaces the existing entry instead. Entries can be edited, searched, deleted (with a 5-second Undo and a Recently Deleted trash), or entered manually without a camera.

## Screens

- **Captured entries** — the list of everything scanned, most recent first, with search, multi-select delete, and tap-to-edit labels.
- **Capture** — live camera preview with a 1D scan guide, torch toggle, and permission handling.
- **Preview & confirm** — shows the detected value, format, and cropped photo; Save, Rescan, or (for a duplicate) Done.
- **Recently Deleted** — soft-deleted entries, restorable until a 30-day retention period purges them.
- **Add manually** — type in a barcode value/format/label without scanning.

## Supported formats

1D only: EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39, Code 93, Codabar, ITF. QR/2D codes are intentionally out of scope (see `prompt/requirements.md` ambiguity #9).

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

**Barcode won't scan** — printed codes work far better than codes displayed on another screen, where glare and pixel moiré defeat the line scan. Also confirm the format is in the supported 1D list; QR codes are deliberately ignored.

**`flutter test` fails on database tests** — make sure `flutter pub get` has pulled `sqflite_common_ffi`; the tests need it to run SQLite on the host.

---

## More

`prompt/` holds the real documentation: `requirements.md` (numbered functional requirements with acceptance criteria and an ambiguity/bug log), `plan.md` (the original brief), and per-phase execution logs recording what broke, why, and how it was root-caused. Read it before making non-trivial changes — several current constraints are deliberate decisions rather than oversights.