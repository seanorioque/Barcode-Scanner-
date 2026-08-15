import 'barcode_scanner_service.dart' show BarcodeBoundingBox;

/// Pure geometry for turning an ML Kit analysis-frame detection into (a)
/// resolution-independent fractional coordinates and (b) a padded, clamped
/// pixel crop rectangle on a still photo. Extracted out of
/// `MlKitBarcodeScannerService` so the camera-frame rotation math -- the
/// highest-risk, least-tested part of the app -- can be table-tested
/// without a real `CameraImage`. No `camera`/`image`/ML Kit imports here;
/// the actual decode/crop/encode stays in `data/`.

/// True when [rotationDegrees] (0/90/180/270, from the camera sensor) swaps
/// a raw frame's width/height to get its upright orientation. Only
/// 90°/270° swap -- NOT 180°, which keeps the frame's original aspect.
/// ML Kit's `Barcode.boundingBox` is returned in this upright coordinate
/// space (matching the `rotation` given in `InputImageMetadata`), not the
/// raw sensor-native buffer dimensions.
///
/// This exact 90°/270° vs 180°/270° distinction was once broken by an
/// external edit and silently scrambled every crop -- see requirements.md
/// ambiguity log #17. [regression] tests lock the correct condition in.
bool isRotationSwapped(int rotationDegrees) => rotationDegrees == 90 || rotationDegrees == 270;

/// The frame's dimensions as a person would see it upright, i.e. with
/// [isRotationSwapped] applied to [rawWidth]/[rawHeight].
({int width, int height}) uprightFrameSize({
  required int rawWidth,
  required int rawHeight,
  required int rotationDegrees,
}) {
  return isRotationSwapped(rotationDegrees)
      ? (width: rawHeight, height: rawWidth)
      : (width: rawWidth, height: rawHeight);
}

/// Maps an ML Kit detection's bounding box -- already in the analysis
/// frame's upright coordinate space, in pixels -- onto resolution-
/// independent fractions (0.0-1.0) of that frame's upright width/height,
/// so it can later be re-applied to a differently-sized still photo.
BarcodeBoundingBox toFractionalBoundingBox({
  required double left,
  required double top,
  required double width,
  required double height,
  required int rawFrameWidth,
  required int rawFrameHeight,
  required int rotationDegrees,
}) {
  final upright = uprightFrameSize(
    rawWidth: rawFrameWidth,
    rawHeight: rawFrameHeight,
    rotationDegrees: rotationDegrees,
  );
  return BarcodeBoundingBox(
    left: (left / upright.width).clamp(0.0, 1.0),
    top: (top / upright.height).clamp(0.0, 1.0),
    width: (width / upright.width).clamp(0.0, 1.0),
    height: (height / upright.height).clamp(0.0, 1.0),
  );
}

/// A pixel-space crop rectangle; always non-degenerate (width/height > 0)
/// when returned by [computeCropRect].
class CropRect {
  const CropRect({required this.left, required this.top, required this.width, required this.height});

  final int left;
  final int top;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is CropRect && left == other.left && top == other.top && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(left, top, width, height);

  @override
  String toString() => 'CropRect(left: $left, top: $top, width: $width, height: $height)';
}

/// Expands [boundingBox] by [padding] (a fraction of its own width/height)
/// on each side, clamps to the `imageWidth` x `imageHeight` bounds, and
/// returns the resulting pixel rect -- or `null` if the result is
/// degenerate (zero or negative width/height), so the caller can fall back
/// to the uncropped photo instead of saving a broken/empty image.
CropRect? computeCropRect({
  required BarcodeBoundingBox boundingBox,
  required int imageWidth,
  required int imageHeight,
  double padding = 0.25,
}) {
  final padX = boundingBox.width * padding;
  final padY = boundingBox.height * padding;
  final left = ((boundingBox.left - padX) * imageWidth).clamp(0, imageWidth).round();
  final top = ((boundingBox.top - padY) * imageHeight).clamp(0, imageHeight).round();
  final right = ((boundingBox.left + boundingBox.width + padX) * imageWidth).clamp(0, imageWidth).round();
  final bottom = ((boundingBox.top + boundingBox.height + padY) * imageHeight).clamp(0, imageHeight).round();
  final width = right - left;
  final height = bottom - top;
  if (width <= 0 || height <= 0) return null;
  return CropRect(left: left, top: top, width: width, height: height);
}
