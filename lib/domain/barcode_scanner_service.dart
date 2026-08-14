/// A single barcode/QR code found in one analyzed camera frame.
class BarcodeDetection {
  const BarcodeDetection({
    required this.value,
    required this.format,
    required this.boundingBoxArea,
  });

  final String value;
  final String format;

  /// Area (in px^2) of the detection's bounding box within the frame.
  /// Used to pick the largest/most central code when several are visible.
  final double boundingBoxArea;
}

/// Why live scanning isn't available right now.
enum ScannerUnavailableReason {
  permissionDenied,
  permissionPermanentlyDenied,
  noCameraAvailable,
}

/// Result of attempting to start the scanner.
class ScannerStartResult {
  const ScannerStartResult.ready() : reason = null;
  const ScannerStartResult.unavailable(ScannerUnavailableReason this.reason);

  final ScannerUnavailableReason? reason;
  bool get isReady => reason == null;
}

/// Live barcode detection boundary. Implemented against `camera` +
/// Google ML Kit in `data/`, so everything above it (state machine, UI)
/// can be tested without a real camera by substituting a fake that emits
/// scripted detections.
abstract class BarcodeScannerService {
  /// Emits every time a frame is analyzed; a frame with no codes emits
  /// an empty list. Selecting a single detection is a separate, pure step.
  Stream<List<BarcodeDetection>> get detections;

  Future<ScannerStartResult> start();

  /// Stops frame analysis without releasing camera resources.
  Future<void> stop();

  /// Releases camera resources. Call when leaving the capture screen.
  Future<void> dispose();

  Future<void> setTorchEnabled(bool enabled);
}
