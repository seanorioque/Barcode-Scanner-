import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/barcode_scanner_service.dart';

/// Formats the detector accepts. Narrowing the list (rather than "all
/// formats") measurably improves latency and reduces misreads.
const _supportedFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upca,
  BarcodeFormat.upce,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.itf,
  BarcodeFormat.qrCode,
];

/// [BarcodeScannerService] backed by `camera` + Google ML Kit. Owns the
/// camera lifecycle and the `CameraImage` -> `InputImage` conversion,
/// which differs between Android (YUV420) and iOS (BGRA8888) and needs
/// rotation derived from the sensor orientation. This conversion is the
/// highest-risk part of the app, so it's isolated here rather than mixed
/// into UI code.
class MlKitBarcodeScannerService implements BarcodeScannerService {
  MlKitBarcodeScannerService({this._frameInterval = const Duration(milliseconds: 250)})
    : _barcodeScanner = BarcodeScanner(formats: _supportedFormats);

  final Duration _frameInterval;
  final BarcodeScanner _barcodeScanner;

  CameraController? _controller;
  CameraController? get cameraController => _controller;

  final _detectionsController = StreamController<List<BarcodeDetection>>.broadcast();
  bool _analyzing = false;
  bool _busy = false;
  DateTime? _lastAnalysis;

  @override
  Stream<List<BarcodeDetection>> get detections => _detectionsController.stream;

  @override
  Future<ScannerStartResult> start() async {
    final permission = await Permission.camera.status;
    if (permission.isPermanentlyDenied) {
      return const ScannerStartResult.unavailable(ScannerUnavailableReason.permissionPermanentlyDenied);
    }
    if (!permission.isGranted) {
      final result = await Permission.camera.request();
      if (result.isPermanentlyDenied) {
        return const ScannerStartResult.unavailable(ScannerUnavailableReason.permissionPermanentlyDenied);
      }
      if (!result.isGranted) {
        return const ScannerStartResult.unavailable(ScannerUnavailableReason.permissionDenied);
      }
    }

    List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException {
      cameras = const [];
    }
    if (cameras.isEmpty) {
      return const ScannerStartResult.unavailable(ScannerUnavailableReason.noCameraAvailable);
    }

    final back = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      back,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
    );
    await controller.initialize();
    _controller = controller;

    _analyzing = true;
    await controller.startImageStream(_onFrame);
    return const ScannerStartResult.ready();
  }

  void _onFrame(CameraImage image) {
    if (!_analyzing || _busy) return;
    final now = DateTime.now();
    final last = _lastAnalysis;
    if (last != null && now.difference(last) < _frameInterval) return;
    _lastAnalysis = now;
    _busy = true;
    unawaited(_analyze(image));
  }

  Future<void> _analyze(CameraImage image) async {
    try {
      final controller = _controller;
      if (controller == null) return;
      final inputImage = _toInputImage(image, controller.description);
      if (inputImage == null) return;
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!_analyzing || _detectionsController.isClosed) return;
      final detections = barcodes
          .where((b) => b.rawValue != null)
          .map(
            (b) => BarcodeDetection(
              value: b.rawValue!,
              format: b.format.name,
              boundingBoxArea: b.boundingBox.width * b.boundingBox.height,
            ),
          )
          .toList(growable: false);
      _detectionsController.add(detections);
    } finally {
      _busy = false;
    }
  }

  InputImage? _toInputImage(CameraImage image, CameraDescription description) {
    final rotation = InputImageRotationValue.fromRawValue(description.sensorOrientation) ?? InputImageRotation.rotation0deg;

    if (Platform.isIOS) {
      final plane = image.planes.first;
      return InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: plane.bytesPerRow,
        ),
      );
    }

    // Android: concatenate YUV420 planes into a single NV21-compatible buffer.
    final bytes = _concatenatePlanes(image.planes);
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final buffer = BytesBuilder();
    for (final plane in planes) {
      buffer.add(plane.bytes);
    }
    return buffer.takeBytes();
  }

  /// Stops analysis and fully releases the camera hardware (not just the
  /// image stream), so it's safe to call both when a code is detected and
  /// when the app is backgrounded. `start()` recreates the controller.
  @override
  Future<void> stop() async {
    _analyzing = false;
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      await controller.dispose();
    }
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _barcodeScanner.close();
    await _detectionsController.close();
  }

  @override
  Future<void> setTorchEnabled(bool enabled) async {
    final controller = _controller;
    if (controller == null) return;
    await controller.setFlashMode(enabled ? FlashMode.torch : FlashMode.off);
  }
}
