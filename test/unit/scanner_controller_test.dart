import 'dart:io';

import 'package:barcode_scanner/app_providers.dart';
import 'package:barcode_scanner/domain/barcode_scanner_service.dart';
import 'package:barcode_scanner/domain/scan_entry.dart';
import 'package:barcode_scanner/ui/capture/scanner_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../fakes/fake_barcode_scanner_service.dart';
import '../fakes/fake_scan_repository.dart';

void main() {
  late FakeBarcodeScannerService service;
  late FakeScanRepository repository;
  late ProviderContainer container;

  setUp(() {
    service = FakeBarcodeScannerService();
    repository = FakeScanRepository();
    container = ProviderContainer(
      overrides: [
        barcodeScannerServiceProvider.overrideWithValue(service),
        scanRepositoryProvider.overrideWithValue(repository),
      ],
    );
    // scannerControllerProvider is autoDispose; a bare container.read()
    // doesn't hold it alive across the awaits below, so keep a listener.
    container.listen(scannerControllerProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  test('starts in idle', () {
    expect(container.read(scannerControllerProvider).phase, ScanPhase.idle);
  });

  test('start() moves to scanning when the service is ready', () async {
    await container.read(scannerControllerProvider.notifier).start();
    expect(container.read(scannerControllerProvider).phase, ScanPhase.scanning);
  });

  test('start() moves to unavailable when permission is denied', () async {
    service.startResult = const ScannerStartResult.unavailable(ScannerUnavailableReason.permissionDenied);

    await container.read(scannerControllerProvider.notifier).start();

    final state = container.read(scannerControllerProvider);
    expect(state.phase, ScanPhase.unavailable);
    expect(state.unavailableReason, ScannerUnavailableReason.permissionDenied);
  });

  test('resumeFromBackground retries from unavailable (e.g. returning from system settings)', () async {
    service.startResult = const ScannerStartResult.unavailable(ScannerUnavailableReason.permissionPermanentlyDenied);
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    expect(container.read(scannerControllerProvider).phase, ScanPhase.unavailable);

    service.startResult = const ScannerStartResult.ready();
    await notifier.resumeFromBackground();

    expect(container.read(scannerControllerProvider).phase, ScanPhase.scanning);
  });

  test('resumeFromBackground is a no-op from detected/saving/idle', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    expect(container.read(scannerControllerProvider).phase, ScanPhase.idle);

    await notifier.resumeFromBackground();

    expect(container.read(scannerControllerProvider).phase, ScanPhase.idle);
    expect(service.startCallCount, 0);
  });

  test('a fresh detection moves scanning -> detected, captures a photo, and stops the service', () async {
    await container.read(scannerControllerProvider.notifier).start();

    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(scannerControllerProvider);
    expect(state.phase, ScanPhase.detected);
    expect(state.detection?.value, 'abc');
    expect(service.captureImageCallCount, 1);
    expect(service.stopCallCount, 1);
  });

  test('a duplicate detection skips capturing a photo and reuses the stored image', () async {
    await repository.save(
      ScanEntry(
        id: 'old',
        value: 'dup',
        format: 'CODE_128',
        imagePath: '/stored/dup.jpg',
        scannedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await container.read(scannerControllerProvider.notifier).start();
    service.emit(const [
      BarcodeDetection(value: 'dup', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(scannerControllerProvider);
    expect(state.phase, ScanPhase.detected);
    expect(state.duplicateOf?.id, 'old');
    expect(state.imagePath, '/stored/dup.jpg');
    expect(service.captureImageCallCount, 0);
    expect(service.stopCallCount, 1);
  });

  test('multiple codes in one frame select the largest', () async {
    await container.read(scannerControllerProvider.notifier).start();

    service.emit(const [
      BarcodeDetection(value: 'small', format: 'CODE_128', boundingBoxArea: 10, boundingBox: BarcodeBoundingBox.fullFrame()),
      BarcodeDetection(value: 'big', format: 'CODE_128', boundingBoxArea: 900, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(scannerControllerProvider).detection?.value, 'big');
  });

  test('frames are ignored once a code has been detected', () async {
    await container.read(scannerControllerProvider.notifier).start();

    service.emit(const [
      BarcodeDetection(value: 'first', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);
    service.emit(const [
      BarcodeDetection(value: 'second', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(scannerControllerProvider).detection?.value, 'first');
  });

  test('duplicate values are surfaced from the repository', () async {
    await repository.save(ScanEntry(id: 'old', value: 'dup', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1)));

    await container.read(scannerControllerProvider.notifier).start();
    service.emit(const [
      BarcodeDetection(value: 'dup', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(scannerControllerProvider).duplicateOf?.id, 'old');
  });

  test('a fresh value has no duplicate note', () async {
    await container.read(scannerControllerProvider.notifier).start();
    service.emit(const [
      BarcodeDetection(value: 'fresh', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(scannerControllerProvider).duplicateOf, isNull);
  });

  test('rescan clears the detection, duplicate note, and returns to scanning', () async {
    await repository.save(ScanEntry(id: 'old', value: 'dup', format: 'CODE_128', scannedAt: DateTime.utc(2026, 1, 1)));
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'dup', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    await notifier.rescan();

    final state = container.read(scannerControllerProvider);
    expect(state.phase, ScanPhase.scanning);
    expect(state.detection, isNull);
    expect(state.duplicateOf, isNull);
  });

  test('rescan does not persist anything', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    await notifier.rescan();

    expect(repository.entries, isEmpty);
  });

  test('save persists the entry and returns to idle', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'EAN_13', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    await notifier.save(label: 'Groceries');

    final state = container.read(scannerControllerProvider);
    expect(state.phase, ScanPhase.idle);
    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.value, 'abc');
    expect(repository.entries.single.format, 'EAN_13');
    expect(repository.entries.single.label, 'Groceries');
  });

  test('save with a blank label stores null', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'EAN_13', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    await notifier.save(label: '   ');

    expect(repository.entries.single.label, isNull);
  });

  test('save is a no-op without an active detection', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.save(label: 'ignored');

    expect(repository.entries, isEmpty);
    expect(container.read(scannerControllerProvider).phase, ScanPhase.idle);
  });

  test('rescan after a fresh capture deletes the abandoned photo file', () async {
    final dir = await Directory.systemTemp.createTemp('scanner_controller_test_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final freshPath = p.join(dir.path, 'fresh.jpg');
    await File(freshPath).writeAsBytes([0]);
    service.imageToCapture = freshPath;

    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(scannerControllerProvider).imagePath, freshPath);
    expect(await File(freshPath).exists(), isTrue);

    await notifier.rescan();
    await Future<void>.delayed(Duration.zero);

    expect(await File(freshPath).exists(), isFalse);
  });

  test('rescan after a duplicate detection does not delete the entry\'s stored image', () async {
    final dir = await Directory.systemTemp.createTemp('scanner_controller_test_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final storedPath = p.join(dir.path, 'stored.jpg');
    await File(storedPath).writeAsBytes([0]);
    await repository.save(
      ScanEntry(id: 'old', value: 'dup', format: 'CODE_128', imagePath: storedPath, scannedAt: DateTime.utc(2026, 1, 1)),
    );

    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'dup', format: 'CODE_128', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(scannerControllerProvider).imagePath, storedPath);

    await notifier.rescan();
    await Future<void>.delayed(Duration.zero);

    expect(await File(storedPath).exists(), isTrue);
  });

  test('save surfaces a repository write failure, returns to detected, and can be retried', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'EAN_13', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);

    repository.throwOnSave = true;
    await notifier.save(label: 'Groceries');

    final failedState = container.read(scannerControllerProvider);
    expect(failedState.phase, ScanPhase.detected);
    expect(failedState.saveError, isNotNull);
    expect(failedState.detection?.value, 'abc');
    expect(repository.entries, isEmpty);

    repository.throwOnSave = false;
    await notifier.save(label: 'Groceries');

    final retriedState = container.read(scannerControllerProvider);
    expect(retriedState.phase, ScanPhase.idle);
    expect(repository.entries, hasLength(1));
  });

  test('dismissSaveError clears saveError without touching anything else', () async {
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'abc', format: 'EAN_13', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);
    repository.throwOnSave = true;
    await notifier.save(label: 'Groceries');
    expect(container.read(scannerControllerProvider).saveError, isNotNull);

    notifier.dismissSaveError();

    final state = container.read(scannerControllerProvider);
    expect(state.saveError, isNull);
    expect(state.phase, ScanPhase.detected);
  });

  test('save is a no-op for a duplicate detection', () async {
    await repository.save(ScanEntry(id: 'old', value: 'dup', format: 'EAN_13', scannedAt: DateTime.utc(2026, 1, 1)));
    final notifier = container.read(scannerControllerProvider.notifier);
    await notifier.start();
    service.emit(const [
      BarcodeDetection(value: 'dup', format: 'EAN_13', boundingBoxArea: 100, boundingBox: BarcodeBoundingBox.fullFrame()),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(scannerControllerProvider).duplicateOf?.id, 'old');

    await notifier.save(label: 'ignored');

    expect(repository.entries, hasLength(1));
    expect(repository.entries.single.id, 'old');
  });
}
