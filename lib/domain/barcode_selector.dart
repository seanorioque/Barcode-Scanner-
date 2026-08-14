import 'barcode_scanner_service.dart';

/// Given every code detected in a single frame, choose the one to act on:
/// the largest bounding box, a proxy for "most central and most in-focus".
///
/// Pure and camera-free so it can be unit tested with plain lists.
BarcodeDetection? selectBarcode(List<BarcodeDetection> detections) {
  if (detections.isEmpty) return null;
  return detections.reduce(
    (largest, next) =>
        next.boundingBoxArea > largest.boundingBoxArea ? next : largest,
  );
}
