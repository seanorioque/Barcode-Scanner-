import 'package:barcode_scanner/domain/barcode_crop.dart';
import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isRotationSwapped', () {
    // Regression for ambiguity log #17: an external edit once changed this
    // condition to 180°/270°, silently scrambling every crop. Only
    // 90°/270° (the near-universal back-camera sensor orientation) swap.
    test('90° and 270° swap; 0° and 180° do not', () {
      expect(isRotationSwapped(0), isFalse);
      expect(isRotationSwapped(90), isTrue);
      expect(isRotationSwapped(180), isFalse);
      expect(isRotationSwapped(270), isTrue);
    });
  });

  group('uprightFrameSize', () {
    test('0° and 180° keep the raw (landscape sensor buffer) dimensions', () {
      for (final rotation in [0, 180]) {
        final size = uprightFrameSize(rawWidth: 1920, rawHeight: 1080, rotationDegrees: rotation);
        expect(size, (width: 1920, height: 1080), reason: 'rotation $rotation');
      }
    });

    test('90° and 270° swap a landscape sensor buffer into portrait', () {
      for (final rotation in [90, 270]) {
        final size = uprightFrameSize(rawWidth: 1920, rawHeight: 1080, rotationDegrees: rotation);
        expect(size, (width: 1080, height: 1920), reason: 'rotation $rotation');
      }
    });

    test('a square frame is unaffected by any rotation', () {
      for (final rotation in [0, 90, 180, 270]) {
        expect(
          uprightFrameSize(rawWidth: 1000, rawHeight: 1000, rotationDegrees: rotation),
          (width: 1000, height: 1000),
        );
      }
    });
  });

  group('toFractionalBoundingBox', () {
    test('90° portrait: a raw-space box maps onto the swapped upright frame', () {
      // 1920x1080 raw landscape buffer, rotated 90° into a 1080x1920
      // upright portrait frame. A box at raw (100, 200) sized 300x400
      // becomes a fraction of the swapped (1080-wide, 1920-tall) frame.
      final box = toFractionalBoundingBox(
        left: 100,
        top: 200,
        width: 300,
        height: 400,
        rawFrameWidth: 1920,
        rawFrameHeight: 1080,
        rotationDegrees: 90,
      );

      expect(box.left, closeTo(100 / 1080, 1e-9));
      expect(box.top, closeTo(200 / 1920, 1e-9));
      expect(box.width, closeTo(300 / 1080, 1e-9));
      expect(box.height, closeTo(400 / 1920, 1e-9));
    });

    test('0° landscape: a raw-space box maps directly, no swap', () {
      final box = toFractionalBoundingBox(
        left: 100,
        top: 200,
        width: 300,
        height: 400,
        rawFrameWidth: 1920,
        rawFrameHeight: 1080,
        rotationDegrees: 0,
      );

      expect(box.left, closeTo(100 / 1920, 1e-9));
      expect(box.top, closeTo(200 / 1080, 1e-9));
      expect(box.width, closeTo(300 / 1920, 1e-9));
      expect(box.height, closeTo(400 / 1080, 1e-9));
    });

    test('a box flush with the frame edges clamps to exactly 0.0-1.0', () {
      final box = toFractionalBoundingBox(
        left: 0,
        top: 0,
        width: 1920,
        height: 1080,
        rawFrameWidth: 1920,
        rawFrameHeight: 1080,
        rotationDegrees: 0,
      );

      expect(box.left, 0.0);
      expect(box.top, 0.0);
      expect(box.width, 1.0);
      expect(box.height, 1.0);
    });

    test('a box reported slightly outside the frame clamps into range', () {
      // ML Kit can report a box a few pixels past the frame boundary; the
      // fraction must never go negative or exceed 1.0.
      final box = toFractionalBoundingBox(
        left: -10,
        top: -10,
        width: 1940,
        height: 1100,
        rawFrameWidth: 1920,
        rawFrameHeight: 1080,
        rotationDegrees: 0,
      );

      expect(box.left, 0.0);
      expect(box.top, 0.0);
      expect(box.width, 1.0);
      expect(box.height, 1.0);
    });
  });

  group('computeCropRect', () {
    test('pads a centered box by the given fraction on each side', () {
      const box = BarcodeBoundingBox(left: 0.4, top: 0.4, width: 0.2, height: 0.2);

      final rect = computeCropRect(boundingBox: box, imageWidth: 1000, imageHeight: 1000, padding: 0.25);

      // padX = padY = 0.2 * 0.25 = 0.05 (fraction) -> 50px at this size.
      expect(rect, const CropRect(left: 350, top: 350, width: 300, height: 300));
    });

    test('clamps the padded rect to the image bounds at each edge', () {
      const topLeft = BarcodeBoundingBox(left: 0.0, top: 0.0, width: 0.1, height: 0.1);
      final topLeftRect = computeCropRect(boundingBox: topLeft, imageWidth: 1000, imageHeight: 1000, padding: 0.25);
      expect(topLeftRect!.left, 0);
      expect(topLeftRect.top, 0);

      const bottomRight = BarcodeBoundingBox(left: 0.9, top: 0.9, width: 0.1, height: 0.1);
      final bottomRightRect = computeCropRect(
        boundingBox: bottomRight,
        imageWidth: 1000,
        imageHeight: 1000,
        padding: 0.25,
      );
      expect(bottomRightRect!.left + bottomRightRect.width, 1000);
      expect(bottomRightRect.top + bottomRightRect.height, 1000);
    });

    test('a zero-area box returns null (degenerate) instead of an empty rect', () {
      const zeroWidth = BarcodeBoundingBox(left: 0.5, top: 0.5, width: 0.0, height: 0.2);
      expect(computeCropRect(boundingBox: zeroWidth, imageWidth: 1000, imageHeight: 1000), isNull);

      const zeroHeight = BarcodeBoundingBox(left: 0.5, top: 0.5, width: 0.2, height: 0.0);
      expect(computeCropRect(boundingBox: zeroHeight, imageWidth: 1000, imageHeight: 1000), isNull);

      const zeroBoth = BarcodeBoundingBox(left: 0.5, top: 0.5, width: 0.0, height: 0.0);
      expect(computeCropRect(boundingBox: zeroBoth, imageWidth: 1000, imageHeight: 1000), isNull);
    });

    test('a full-frame box crops to (approximately) the whole image', () {
      const box = BarcodeBoundingBox.fullFrame();
      final rect = computeCropRect(boundingBox: box, imageWidth: 800, imageHeight: 600, padding: 0.25);

      expect(rect, const CropRect(left: 0, top: 0, width: 800, height: 600));
    });

    test('landscape and portrait still-photo dimensions both produce a valid rect', () {
      const box = BarcodeBoundingBox(left: 0.25, top: 0.25, width: 0.5, height: 0.1);

      final landscape = computeCropRect(boundingBox: box, imageWidth: 1920, imageHeight: 1080);
      expect(landscape, isNotNull);
      expect(landscape!.width, greaterThan(0));
      expect(landscape.height, greaterThan(0));

      final portrait = computeCropRect(boundingBox: box, imageWidth: 1080, imageHeight: 1920);
      expect(portrait, isNotNull);
      expect(portrait!.width, greaterThan(0));
      expect(portrait.height, greaterThan(0));
    });
  });
}
