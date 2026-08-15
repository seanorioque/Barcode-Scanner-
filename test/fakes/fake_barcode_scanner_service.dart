import 'dart:async';

import 'package:barcode_scanner/domain/barcode_scanner_service.dart';

/// [BarcodeScannerService] test double that emits scripted detections
/// instead of touching a real camera, so the scanner state machine and the
/// capture -> preview flow can be exercised without a device.
class FakeBarcodeScannerService implements BarcodeScannerService {
  final _controller = StreamController<List<BarcodeDetection>>.broadcast();

  ScannerStartResult startResult = const ScannerStartResult.ready();
  int startCallCount = 0;
  int stopCallCount = 0;
  int disposeCallCount = 0;
  bool torchOn = false;
  String? imageToCapture;
  int captureImageCallCount = 0;

  @override
  Stream<List<BarcodeDetection>> get detections => _controller.stream;

  /// Simulates a single analyzed camera frame containing [frame] codes.
  void emit(List<BarcodeDetection> frame) => _controller.add(frame);

  @override
  Future<ScannerStartResult> start() async {
    startCallCount++;
    return startResult;
  }

  @override
  Future<void> stop() async {
    stopCallCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
    await _controller.close();
  }

  @override
  Future<void> setTorchEnabled(bool enabled) async {
    torchOn = enabled;
  }

  @override
  Future<String?> captureImage() async {
    captureImageCallCount++;
    return imageToCapture;
  }
}
