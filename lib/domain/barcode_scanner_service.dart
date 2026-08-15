/// A single 1D barcode found in one analyzed camera frame.
class BarcodeDetection {
  const BarcodeDetection({
    required this.value,
    required this.format,
    required this.boundingBoxArea,
    required this.boundingBox,
  });

  final String value;
  final String format;

  /// Area (in px^2) of the detection's bounding box within the frame.
  /// Used to pick the largest/most central code when several are visible.
  final double boundingBoxArea;

  /// Where the barcode sits within the analyzed frame, as fractions of the
  /// frame so it can be re-applied to a differently-sized still photo.
  final BarcodeBoundingBox boundingBox;
}

/// A detection's position within its frame, expressed as fractions
/// (0.0-1.0) of the frame's upright width/height — resolution-independent
/// so it can be mapped onto a still photo captured at a different size.
class BarcodeBoundingBox {
  const BarcodeBoundingBox({required this.left, required this.top, required this.width, required this.height});

  /// Stands in for "the whole frame" — useful for tests that don't care
  /// about precise cropping.
  const BarcodeBoundingBox.fullFrame() : left = 0, top = 0, width = 1, height = 1;

  final double left;
  final double top;
  final double width;
  final double height;
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

  /// Captures a photo of the current camera frame, crops it to
  /// [boundingBox] (with padding), and saves it to persistent storage,
  /// returning its file path. Returns `null` if a photo can't be captured;
  /// falls back to the uncropped photo if the crop itself fails.
  Future<String?> captureImage(BarcodeBoundingBox boundingBox);
}
