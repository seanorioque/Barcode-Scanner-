import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app_providers.dart';
import '../../domain/barcode_scanner_service.dart';
import '../../domain/barcode_selector.dart';
import '../../domain/scan_entry.dart';
import '../../domain/scan_repository.dart';

/// idle -> scanning -> detected -> saving -> idle, with `rescan` looping
/// detected back to scanning. Mirrors the diagram in the app brief.
enum ScanPhase { idle, scanning, unavailable, detected, saving }

class ScannerState {
  const ScannerState({
    this.phase = ScanPhase.idle,
    this.detection,
    this.unavailableReason,
    this.duplicateOf,
    this.torchOn = false,
  });

  final ScanPhase phase;
  final BarcodeDetection? detection;
  final ScannerUnavailableReason? unavailableReason;

  /// A prior entry with the same value, if one exists.
  final ScanEntry? duplicateOf;
  final bool torchOn;

  ScannerState copyWith({
    ScanPhase? phase,
    BarcodeDetection? detection,
    bool clearDetection = false,
    ScannerUnavailableReason? unavailableReason,
    bool clearUnavailableReason = false,
    ScanEntry? duplicateOf,
    bool clearDuplicateOf = false,
    bool? torchOn,
  }) {
    return ScannerState(
      phase: phase ?? this.phase,
      detection: clearDetection ? null : (detection ?? this.detection),
      unavailableReason: clearUnavailableReason ? null : (unavailableReason ?? this.unavailableReason),
      duplicateOf: clearDuplicateOf ? null : (duplicateOf ?? this.duplicateOf),
      torchOn: torchOn ?? this.torchOn,
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
    state = state.copyWith(phase: ScanPhase.scanning, clearDetection: true, clearUnavailableReason: true);
    final result = await _service.start();
    if (!result.isReady) {
      state = state.copyWith(phase: ScanPhase.unavailable, unavailableReason: result.reason);
      return;
    }
    await _sub?.cancel();
    _sub = _service.detections.listen(_onDetections);
  }

  void _onDetections(List<BarcodeDetection> frame) {
    if (state.phase != ScanPhase.scanning) return;
    final selected = selectBarcode(frame);
    if (selected == null) return;

    state = state.copyWith(phase: ScanPhase.detected, detection: selected);
    unawaited(_service.stop());
    unawaited(
      _repository.findMostRecentByValue(selected.value).then((duplicate) {
        if (state.detection?.value != selected.value) return;
        if (duplicate != null) {
          state = state.copyWith(duplicateOf: duplicate);
        }
      }),
    );
  }

  Future<void> rescan() async {
    state = state.copyWith(
      phase: ScanPhase.scanning,
      clearDetection: true,
      clearDuplicateOf: true,
      clearUnavailableReason: true,
    );
    final result = await _service.start();
    if (!result.isReady) {
      state = state.copyWith(phase: ScanPhase.unavailable, unavailableReason: result.reason);
      return;
    }
    await _sub?.cancel();
    _sub = _service.detections.listen(_onDetections);
  }

  Future<void> save({String? label}) async {
    final detection = state.detection;
    if (detection == null || state.phase != ScanPhase.detected) return;

    state = state.copyWith(phase: ScanPhase.saving);
    final trimmedLabel = label?.trim();
    final entry = ScanEntry(
      id: _uuid.v4(),
      value: detection.value,
      format: detection.format,
      label: (trimmedLabel == null || trimmedLabel.isEmpty) ? null : trimmedLabel,
      scannedAt: DateTime.now().toUtc(),
    );
    await _repository.save(entry);
    await _sub?.cancel();
    await _service.stop();
    state = state.copyWith(phase: ScanPhase.idle, clearDetection: true, clearDuplicateOf: true);
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
