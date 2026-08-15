import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/barcode_scanner_service.dart';

/// Fraction of the detected barcode's own width/height added as padding on
/// each side when cropping, so the quiet zone / edges aren't clipped.
const _cropPadding = 0.25;

/// Formats the detector accepts. 1D only — narrowing the list (rather than
/// "all formats") also measurably improves latency and reduces misreads.
const _supportedFormats = [
  BarcodeFormat.ean13,
  BarcodeFormat.ean8,
  BarcodeFormat.upca,
  BarcodeFormat.upce,
  BarcodeFormat.code128,
  BarcodeFormat.code39,
  BarcodeFormat.code93,
  BarcodeFormat.codabar,
  BarcodeFormat.itf,
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
      final rotation = _rotationFor(controller.description);
      final inputImage = _toInputImage(image, rotation);
      if (inputImage == null) return;
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (!_analyzing || _detectionsController.isClosed) return;
      final uprightSize = _uprightFrameSize(image.width, image.height, rotation);
      final detections = barcodes
          .where((b) => b.rawValue != null)
          .map(
            (b) => BarcodeDetection(
              value: b.rawValue!,
              format: b.format.name,
              boundingBoxArea: b.boundingBox.width * b.boundingBox.height,
              boundingBox: BarcodeBoundingBox(
                left: (b.boundingBox.left / uprightSize.width).clamp(0.0, 1.0),
                top: (b.boundingBox.top / uprightSize.height).clamp(0.0, 1.0),
                width: (b.boundingBox.width / uprightSize.width).clamp(0.0, 1.0),
                height: (b.boundingBox.height / uprightSize.height).clamp(0.0, 1.0),
              ),
            ),
          )
          .toList(growable: false);
      _detectionsController.add(detections);
    } finally {
      _busy = false;
    }
  }

  InputImageRotation _rotationFor(CameraDescription description) =>
      InputImageRotationValue.fromRawValue(description.sensorOrientation) ?? InputImageRotation.rotation0deg;

  /// The frame's dimensions as a person would see it upright, i.e. with a
  /// 90°/270° rotation applied. ML Kit returns `Barcode.boundingBox` in this
  /// rotated coordinate space (matching the `rotation` given in
  /// [InputImageMetadata]), not the raw sensor-native buffer dimensions.
  Size _uprightFrameSize(int rawWidth, int rawHeight, InputImageRotation rotation) {
    final swapped = rotation == InputImageRotation.rotation90deg || rotation == InputImageRotation.rotation270deg;
    return swapped ? Size(rawHeight.toDouble(), rawWidth.toDouble()) : Size(rawWidth.toDouble(), rawHeight.toDouble());
  }

  InputImage? _toInputImage(CameraImage image, InputImageRotation rotation) {
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

  /// Stops frame analysis (a capture request can't share the camera with an
  /// active image stream), takes a full-resolution photo, crops it to
  /// [boundingBox] (falling back to the uncropped photo if cropping fails
  /// for any reason), and saves the result to a durable app-storage
  /// location.
  @override
  Future<String?> captureImage(BarcodeBoundingBox boundingBox) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
      final picture = await controller.takePicture();
      final originalBytes = await File(picture.path).readAsBytes();
      final bytesToSave = _cropToBarcode(originalBytes, boundingBox) ?? originalBytes;

      final documentsDir = await getApplicationDocumentsDirectory();
      final imagesDir = Directory(p.join(documentsDir.path, 'scan_images'));
      await imagesDir.create(recursive: true);
      final destination = p.join(imagesDir.path, '${DateTime.now().microsecondsSinceEpoch}.jpg');
      await File(destination).writeAsBytes(bytesToSave);
      return destination;
    } on CameraException {
      return null;
    }
  }

  /// Crops [jpegBytes] to [boundingBox] (expanded by [_cropPadding] on each
  /// side, clamped to the image), re-encoding as JPEG. Returns `null` on any
  /// failure — decode error, or a degenerate/zero-size crop rect — so the
  /// caller can fall back to the uncropped photo rather than save a broken
  /// or empty image.
  Uint8List? _cropToBarcode(Uint8List jpegBytes, BarcodeBoundingBox boundingBox) {
    try {
      final decoded = img.decodeImage(jpegBytes);
      if (decoded == null) return null;
      final upright = img.bakeOrientation(decoded);

      final w = upright.width;
      final h = upright.height;
      final padX = boundingBox.width * _cropPadding;
      final padY = boundingBox.height * _cropPadding;
      final left = ((boundingBox.left - padX) * w).clamp(0, w).round();
      final top = ((boundingBox.top - padY) * h).clamp(0, h).round();
      final right = ((boundingBox.left + boundingBox.width + padX) * w).clamp(0, w).round();
      final bottom = ((boundingBox.top + boundingBox.height + padY) * h).clamp(0, h).round();
      final cropWidth = right - left;
      final cropHeight = bottom - top;
      if (cropWidth <= 0 || cropHeight <= 0) return null;

      final cropped = img.copyCrop(upright, x: left, y: top, width: cropWidth, height: cropHeight);
      return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
    } catch (_) {
      return null;
    }
  }
}
