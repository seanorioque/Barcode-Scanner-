import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:barcode_scanner/domain/barcode_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectBarcode', () {
    test('returns null for an empty frame', () {
      expect(selectBarcode(const []), isNull);
    });

    test('returns the only detection when there is one', () {
      const detection = BarcodeDetection(
        value: '123',
        format: 'EAN_13',
        boundingBoxArea: 100,
        boundingBox: BarcodeBoundingBox.fullFrame(),
      );
      expect(selectBarcode(const [detection]), same(detection));
    });

    test('returns the detection with the largest bounding box', () {
      const small = BarcodeDetection(
        value: 'small',
        format: 'CODE_128',
        boundingBoxArea: 50,
        boundingBox: BarcodeBoundingBox.fullFrame(),
      );
      const large = BarcodeDetection(
        value: 'large',
        format: 'CODE_128',
        boundingBoxArea: 500,
        boundingBox: BarcodeBoundingBox.fullFrame(),
      );
      const medium = BarcodeDetection(
        value: 'medium',
        format: 'CODE_128',
        boundingBoxArea: 200,
        boundingBox: BarcodeBoundingBox.fullFrame(),
      );

      expect(selectBarcode(const [small, large, medium]), same(large));
    });

    test('is stable when two detections tie in area', () {
      const first = BarcodeDetection(
        value: 'first',
        format: 'CODE_128',
        boundingBoxArea: 100,
        boundingBox: BarcodeBoundingBox.fullFrame(),
      );
      const second = BarcodeDetection(
        value: 'second',
        format: 'CODE_128',
        boundingBoxArea: 100,
        boundingBox: BarcodeBoundingBox.fullFrame(),
      );
      expect(selectBarcode(const [first, second]), same(first));
    });
  });
}
