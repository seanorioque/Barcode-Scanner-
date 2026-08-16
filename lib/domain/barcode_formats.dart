/// Barcode formats the app supports, for the manual-entry format picker.
/// Kept as plain strings (rather than importing ML Kit's enum here) so the
/// domain/UI layers stay free of the ML Kit dependency. Mirrors
/// `MlKitBarcodeScannerService._supportedFormats` — update both together.
const supportedBarcodeFormats = [
  'EAN_13',
  'EAN_8',
  'UPC_A',
  'UPC_E',
  'CODE_128',
  'CODE_39',
  'CODE_93',
  'CODABAR',
  'ITF',
  'QR_CODE',
];
