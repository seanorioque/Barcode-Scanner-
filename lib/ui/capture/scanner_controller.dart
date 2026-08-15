import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../../domain/barcode_scanner_service.dart';
import '../../domain/barcode_selector.dart';
import '../../domain/scan_entry.dart';
import '../../domain/scan_repository.dart';

/// idle -> scanning -> resolving -> detected -> saving -> idle, with
/// `rescan` looping detected back to scanning. `resolving` is the brief gap
/// between a frame matching a code and the duplicate lookup finishing;
/// nothing renders differently for it (the camera preview just keeps
/// showing), it exists purely to guard against re-entrant frame handling.
enum ScanPhase { idle, scanning, unavailable, resolving, detected, saving }

class ScannerState {
  const ScannerState({
    this.phase = ScanPhase.idle,
    this.detection,
    this.unavailableReason,
    this.duplicateOf,
    this.torchOn = false,
    this.imagePath,
    this.saveError,
  });

  final ScanPhase phase;
  final BarcodeDetection? detection;
  final ScannerUnavailableReason? unavailableReason;

  /// A prior entry with the same value, if one exists.
  final ScanEntry? duplicateOf;
  final bool torchOn;

  /// Path to the photo captured at detection time, once capture finishes.
  final String? imagePath;

  /// Set when [ScannerController.save] fails (e.g. a disk-full or
  /// permission error from the repository). Preview renders this as a
  /// SnackBar, then dismisses it; `phase` is already back to `detected` so
  /// the user can just retry.
  final String? saveError;

  ScannerState copyWith({
    ScanPhase? phase,
    BarcodeDetection? detection,
    bool clearDetection = false,
    ScannerUnavailableReason? unavailableReason,
    bool clearUnavailableReason = false,
    ScanEntry? duplicateOf,
    bool clearDuplicateOf = false,
    bool? torchOn,
    String? imagePath,
    bool clearImagePath = false,
    String? saveError,
    bool clearSaveError = false,
  }) {
    return ScannerState(
      phase: phase ?? this.phase,
      detection: clearDetection ? null : (detection ?? this.detection),
      unavailableReason: clearUnavailableReason ? null : (unavailableReason ?? this.unavailableReason),
      duplicateOf: clearDuplicateOf ? null : (duplicateOf ?? this.duplicateOf),
      torchOn: torchOn ?? this.torchOn,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      saveError: clearSaveError ? null : (saveError ?? this.saveError),
    );
  }
}

/// Plain, exception-free message shown to the user when a repository write
/// fails. Deliberately vague — disk-full, corruption, and permission errors
/// all land here, and none of that detail is actionable for the user.
const _saveFailedMessage = "Couldn't save. Please try again.";

class ScannerController extends Notifier<ScannerState> {
  late final BarcodeScannerService _service;
  late final ScanRepository _repository;
  final Uuid _uuid = const Uuid();
  StreamSubscription<List<BarcodeDetection>>? _sub;

  // Plain-field mirror of state.imagePath/state.duplicateOf?.imagePath, kept
  // in sync by _setState. ref.onDispose can't read `state` itself (the
  // notifier's `state` getter asserts "Cannot use Ref ... inside
  // life-cycles" when called from inside a dispose callback), so cleanup on
  // dispose reads these plain fields instead.
  String? _imagePathForCleanup;
  String? _duplicateImagePathForCleanup;

  @override
  ScannerState build() {
    _service = ref.watch(barcodeScannerServiceProvider);
    _repository = ref.watch(scanRepositoryProvider);
    ref.onDispose(() {
      unawaited(_sub?.cancel());
      unawaited(_deleteAbandonedImage(_imagePathForCleanup, _duplicateImagePathForCleanup));
    });
    return const ScannerState();
  }

  void _setState(ScannerState next) {
    state = next;
    _imagePathForCleanup = next.imagePath;
    _duplicateImagePathForCleanup = next.duplicateOf?.imagePath;
  }

  /// Deletes [imagePath] unless it's `null` or it's actually
  /// [duplicateImagePath] — the photo already on file for a duplicate entry,
  /// which must never be touched. Called wherever a detection's photo can be
  /// abandoned without ever being saved: rescanning past it, or leaving
  /// Capture (provider dispose) before deciding.
  Future<void> _deleteAbandonedImage(String? imagePath, String? duplicateImagePath) async {
    if (imagePath == null || imagePath == duplicateImagePath) return;
    try {
      final file = File(imagePath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; a stray file is the failure mode, not a crash.
    }
  }

  Future<void> start() async {
    _setState(
      state.copyWith(
        phase: ScanPhase.scanning,
        clearDetection: true,
        clearUnavailableReason: true,
        clearImagePath: true,
      ),
    );
    final result = await _service.start();
    if (!result.isReady) {
      _setState(state.copyWith(phase: ScanPhase.unavailable, unavailableReason: result.reason));
      return;
    }
    await _sub?.cancel();
    _sub = _service.detections.listen(_onDetections);
    // _CameraPreviewOrPlaceholder reads the camera controller straight off
    // the service rather than listening for it, so it only ever notices a
    // freshly-initialized controller on the next rebuild. Nothing else
    // triggers one between here and the first detection, so force it.
    _setState(state.copyWith(phase: ScanPhase.scanning));
  }

  void _onDetections(List<BarcodeDetection> frame) {
    if (state.phase != ScanPhase.scanning) return;
    final selected = selectBarcode(frame);
    if (selected == null) return;

    // Flip out of `scanning` synchronously so a second frame arriving before
    // the duplicate lookup below resolves can't start a concurrent
    // resolution for the same detection.
    _setState(state.copyWith(phase: ScanPhase.resolving));
    unawaited(_resolveDetection(selected));
  }

  /// Looks up whether [selected] is a duplicate *before* deciding whether to
  /// capture a photo at all: a duplicate reuses the image already stored
  /// from its first scan (faster, and matches "show what's on file"), so
  /// there's no reason to take and crop a fresh one.
  Future<void> _resolveDetection(BarcodeDetection selected) async {
    final duplicate = await _repository.findMostRecentByValue(selected.value);
    if (duplicate != null) {
      await _service.stop();
      _setState(
        state.copyWith(
          phase: ScanPhase.detected,
          detection: selected,
          duplicateOf: duplicate,
          imagePath: duplicate.imagePath,
          clearImagePath: duplicate.imagePath == null,
        ),
      );
      return;
    }

    _setState(state.copyWith(phase: ScanPhase.detected, detection: selected, clearDuplicateOf: true));
    unawaited(_captureImageThenStop(selected));
  }

  /// Takes the detection photo before releasing the camera — capture needs
  /// the controller alive, and `stop()` fully disposes it.
  Future<void> _captureImageThenStop(BarcodeDetection detection) async {
    final imagePath = await _service.captureImage(detection.boundingBox);
    if (state.detection?.value == detection.value && imagePath != null) {
      _setState(state.copyWith(imagePath: imagePath));
    }
    await _service.stop();
  }

  Future<void> rescan() async {
    unawaited(_deleteAbandonedImage(state.imagePath, state.duplicateOf?.imagePath));
    _setState(
      state.copyWith(
        phase: ScanPhase.scanning,
        clearDetection: true,
        clearDuplicateOf: true,
        clearUnavailableReason: true,
        clearImagePath: true,
        clearSaveError: true,
      ),
    );
    final result = await _service.start();
    if (!result.isReady) {
      _setState(state.copyWith(phase: ScanPhase.unavailable, unavailableReason: result.reason));
      return;
    }
    await _sub?.cancel();
    _sub = _service.detections.listen(_onDetections);
    _setState(state.copyWith(phase: ScanPhase.scanning));
  }

  Future<void> save({String? label}) async {
    final detection = state.detection;
    if (detection == null || state.phase != ScanPhase.detected) return;
    // Belt and suspenders alongside the disabled Save button in Preview and
    // the DB's partial unique index: never persist a known duplicate.
    if (state.duplicateOf != null) return;

    _setState(state.copyWith(phase: ScanPhase.saving, clearSaveError: true));
    final trimmedLabel = label?.trim();
    final entry = ScanEntry(
      id: _uuid.v4(),
      value: detection.value,
      format: detection.format,
      label: (trimmedLabel == null || trimmedLabel.isEmpty) ? null : trimmedLabel,
      scannedAt: DateTime.now().toUtc(),
      imagePath: state.imagePath,
    );
    try {
      await _repository.save(entry);
    } catch (_) {
      // Leaves phase back at `detected` (Preview's Save button un-spins)
      // and the detection/image intact so the user can just retry.
      _setState(state.copyWith(phase: ScanPhase.detected, saveError: _saveFailedMessage));
      return;
    }
    await _sub?.cancel();
    await _service.stop();
    _setState(
      state.copyWith(
        phase: ScanPhase.idle,
        clearDetection: true,
        clearDuplicateOf: true,
        clearImagePath: true,
      ),
    );
  }

  /// Clears [ScannerState.saveError] once Preview has shown it as a
  /// SnackBar, so it doesn't reappear on an unrelated rebuild.
  void dismissSaveError() {
    if (state.saveError == null) return;
    _setState(state.copyWith(clearSaveError: true));
  }

  /// Releases the camera while the app is backgrounded, without disturbing
  /// `phase` (a detected/preview state should stay put; only active
  /// scanning needs to give up the camera).
  Future<void> pauseForBackground() async {
    if (state.phase != ScanPhase.scanning) return;
    await _sub?.cancel();
    await _service.stop();
  }

  /// Retries from `scanning` (camera was paused for the background trip)
  /// and from `unavailable` (e.g. the user backgrounded the app to grant
  /// camera permission from system settings and is now returning).
  /// `detected`/`saving` are left alone — there's an active preview to not
  /// disturb.
  Future<void> resumeFromBackground() async {
    if (state.phase != ScanPhase.scanning && state.phase != ScanPhase.unavailable) return;
    await start();
  }

  Future<void> toggleTorch() async {
    final next = !state.torchOn;
    await _service.setTorchEnabled(next);
    _setState(state.copyWith(torchOn: next));
  }
}

final scannerControllerProvider = NotifierProvider.autoDispose<ScannerController, ScannerState>(
  ScannerController.new,
);
