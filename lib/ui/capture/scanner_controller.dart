import 'dart:async';

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
  });

  final ScanPhase phase;
  final BarcodeDetection? detection;
  final ScannerUnavailableReason? unavailableReason;

  /// A prior entry with the same value, if one exists.
  final ScanEntry? duplicateOf;
  final bool torchOn;

  /// Path to the photo captured at detection time, once capture finishes.
  final String? imagePath;

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
  }) {
    return ScannerState(
      phase: phase ?? this.phase,
      detection: clearDetection ? null : (detection ?? this.detection),
      unavailableReason: clearUnavailableReason ? null : (unavailableReason ?? this.unavailableReason),
      duplicateOf: clearDuplicateOf ? null : (duplicateOf ?? this.duplicateOf),
      torchOn: torchOn ?? this.torchOn,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
    );
  }
}

class ScannerController extends Notifier<ScannerState> {
  late final BarcodeScannerService _service;
  late final ScanRepository _repository;
  final Uuid _uuid = const Uuid();
  StreamSubscription<List<BarcodeDetection>>? _sub;

  @override
  ScannerState build() {
    _service = ref.watch(barcodeScannerServiceProvider);
    _repository = ref.watch(scanRepositoryProvider);
    ref.onDispose(() {
      unawaited(_sub?.cancel());
    });
    return const ScannerState();
  }

  Future<void> start() async {
    state = state.copyWith(
      phase: ScanPhase.scanning,
      clearDetection: true,
      clearUnavailableReason: true,
      clearImagePath: true,
    );
    final result = await _service.start();
    if (!result.isReady) {
      state = state.copyWith(phase: ScanPhase.unavailable, unavailableReason: result.reason);
      return;
    }
    await _sub?.cancel();
    _sub = _service.detections.listen(_onDetections);
    // _CameraPreviewOrPlaceholder reads the camera controller straight off
    // the service rather than listening for it, so it only ever notices a
    // freshly-initialized controller on the next rebuild. Nothing else
    // triggers one between here and the first detection, so force it.
    state = state.copyWith(phase: ScanPhase.scanning);
  }

  void _onDetections(List<BarcodeDetection> frame) {
    if (state.phase != ScanPhase.scanning) return;
    final selected = selectBarcode(frame);
    if (selected == null) return;

    // Flip out of `scanning` synchronously so a second frame arriving before
    // the duplicate lookup below resolves can't start a concurrent
    // resolution for the same detection.
    state = state.copyWith(phase: ScanPhase.resolving);
    unawaited(_captureImageThenStop(selected));
    unawaited(_resolveDetection(selected));
  }

  /// Looks up whether [selected] is a duplicate and only then publishes
  /// `detected` — with `detection` and `duplicateOf` set together in one
  /// state update, so Preview never observes a moment where Save looks
  /// available before the duplicate check has actually completed.
  Future<void> _resolveDetection(BarcodeDetection selected) async {
    final duplicate = await _repository.findMostRecentByValue(selected.value);
    state = state.copyWith(
      phase: ScanPhase.detected,
      detection: selected,
      duplicateOf: duplicate,
      clearDuplicateOf: duplicate == null,
    );
  }

  /// Takes the detection photo before releasing the camera — capture needs
  /// the controller alive, and `stop()` fully disposes it.
  Future<void> _captureImageThenStop(BarcodeDetection detection) async {
    final imagePath = await _service.captureImage();
    final stillCurrent = state.phase == ScanPhase.resolving || state.phase == ScanPhase.detected;
    if (stillCurrent && imagePath != null) {
      state = state.copyWith(imagePath: imagePath);
    }
    await _service.stop();
  }

  Future<void> rescan() async {
    state = state.copyWith(
      phase: ScanPhase.scanning,
      clearDetection: true,
      clearDuplicateOf: true,
      clearUnavailableReason: true,
      clearImagePath: true,
    );
    final result = await _service.start();
    if (!result.isReady) {
      state = state.copyWith(phase: ScanPhase.unavailable, unavailableReason: result.reason);
      return;
    }
    await _sub?.cancel();
    _sub = _service.detections.listen(_onDetections);
    state = state.copyWith(phase: ScanPhase.scanning);
  }

  Future<void> save({String? label}) async {
    final detection = state.detection;
    if (detection == null || state.phase != ScanPhase.detected) return;
    // Belt and suspenders alongside the disabled Save button in Preview and
    // the DB's partial unique index: never persist a known duplicate.
    if (state.duplicateOf != null) return;

    state = state.copyWith(phase: ScanPhase.saving);
    final trimmedLabel = label?.trim();
    final entry = ScanEntry(
      id: _uuid.v4(),
      value: detection.value,
      format: detection.format,
      label: (trimmedLabel == null || trimmedLabel.isEmpty) ? null : trimmedLabel,
      scannedAt: DateTime.now().toUtc(),
      imagePath: state.imagePath,
    );
    await _repository.save(entry);
    await _sub?.cancel();
    await _service.stop();
    state = state.copyWith(
      phase: ScanPhase.idle,
      clearDetection: true,
      clearDuplicateOf: true,
      clearImagePath: true,
    );
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
    state = state.copyWith(torchOn: next);
  }
}

final scannerControllerProvider = NotifierProvider.autoDispose<ScannerController, ScannerState>(
  ScannerController.new,
);
