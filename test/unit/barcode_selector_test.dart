import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:barcode_scanner/domain/barcode_selector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectBarcode', () {
    test('returns null for an empty frame', () {
      expect(selectBarcode(const []), isNull);
    });

    test('returns the only detection when there is one', () {
      const detection = BarcodeDetection(value: '123', format: 'EAN_13', boundingBoxArea: 100);
      expect(selectBarcode(const [detection]), same(detection));
    });

    test('returns the detection with the largest bounding box', () {
      const small = BarcodeDetection(value: 'small', format: 'QR_CODE', boundingBoxArea: 50);
      const large = BarcodeDetection(value: 'large', format: 'QR_CODE', boundingBoxArea: 500);
      const medium = BarcodeDetection(value: 'medium', format: 'QR_CODE', boundingBoxArea: 200);

      expect(selectBarcode(const [small, large, medium]), same(large));
    });

    test('is stable when two detections tie in area', () {
      const first = BarcodeDetection(value: 'first', format: 'QR_CODE', boundingBoxArea: 100);
      const second = BarcodeDetection(value: 'second', format: 'QR_CODE', boundingBoxArea: 100);
      expect(selectBarcode(const [first, second]), same(first));
    });
  });
}
