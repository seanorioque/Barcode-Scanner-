import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_providers.dart';
import '../../data/mlkit_barcode_scanner_service.dart';
import '../../domain/barcode_scanner_service.dart';
import '../preview/preview_screen.dart';
import 'scanner_controller.dart';

class CaptureScreen extends ConsumerStatefulWidget {
  const CaptureScreen({super.key});

  @override
  ConsumerState<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends ConsumerState<CaptureScreen> with WidgetsBindingObserver {
  bool _navigatingToPreview = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(Future.microtask(() => ref.read(scannerControllerProvider.notifier).start()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final notifier = ref.read(scannerControllerProvider.notifier);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        unawaited(notifier.pauseForBackground());
      case AppLifecycleState.resumed:
        unawaited(notifier.resumeFromBackground());
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _onDetected() async {
    if (_navigatingToPreview) return;
    _navigatingToPreview = true;
    unawaited(HapticFeedback.mediumImpact());
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PreviewScreen()));
    _navigatingToPreview = false;
    if (!mounted) return;

    // Rescan/Save/Done on Preview already leave the scanner in the right
    // state (or navigate past this screen entirely, unmounting it before
    // this line ever runs). A system/gesture back from Preview does
    // neither — it just pops back here with the camera still stopped from
    // capture/detection — so pick scanning back up in that case.
    final phase = ref.read(scannerControllerProvider).phase;
    if (phase != ScanPhase.scanning) {
      unawaited(ref.read(scannerControllerProvider.notifier).start());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ScannerState>(scannerControllerProvider, (previous, next) {
      if (next.phase == ScanPhase.detected && previous?.phase != ScanPhase.detected) {
        unawaited(_onDetected());
      }
    });

    final state = ref.watch(scannerControllerProvider);
    final service = ref.watch(barcodeScannerServiceProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _CameraPreviewOrPlaceholder(service: service),
          _ScanOverlay(success: state.phase == ScanPhase.detected),
          if (state.phase == ScanPhase.unavailable && state.unavailableReason != null)
            _UnavailableOverlay(reason: state.unavailableReason!),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundIconButton(icon: Icons.close, onPressed: () => Navigator.of(context).pop()),
                    _RoundIconButton(
                      icon: state.torchOn ? Icons.flash_on : Icons.flash_off,
                      onPressed: () => ref.read(scannerControllerProvider.notifier).toggleTorch(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraPreviewOrPlaceholder extends StatelessWidget {
  const _CameraPreviewOrPlaceholder({required this.service});

  final BarcodeScannerService service;

  @override
  Widget build(BuildContext context) {
    final service = this.service;
    if (service is MlKitBarcodeScannerService) {
      final controller = service.cameraController;
      final previewSize = controller?.value.previewSize;
      if (controller != null && controller.value.isInitialized && previewSize != null) {
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.height,
                height: previewSize.width,
                child: CameraPreview(controller),
              ),
            ),
          ),
        );
      }
    }
    return const ColoredBox(color: Colors.black);
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.success});

  final bool success;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _ScanOverlayPainter(borderColor: success ? Colors.greenAccent : Colors.white),
        size: Size.infinite,
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  _ScanOverlayPainter({required this.borderColor});

  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    // A square guide -- this app scans both 1D barcodes and QR codes, and a
    // square frames a QR code correctly while still comfortably fitting a
    // horizontal 1D barcode inside it. Purely a visual guide: actual
    // detection runs on the full camera frame regardless of this shape.
    final cutoutSize = (size.width * 0.7).clamp(60.0, size.height * 0.5);
    final cutoutRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: cutoutSize,
      height: cutoutSize,
    );
    final cutoutRRect = RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16));

    final overlayPath = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(cutoutRRect),
    );
    canvas.drawPath(overlayPath, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawRRect(
      cutoutRRect,
      Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) => oldDelegate.borderColor != borderColor;
}

class _UnavailableOverlay extends ConsumerWidget {
  const _UnavailableOverlay({required this.reason});

  final ScannerUnavailableReason reason;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String message;
    final Widget? action;
    switch (reason) {
      case ScannerUnavailableReason.permissionDenied:
        message = 'Camera access was denied.';
        action = FilledButton(
          onPressed: () => ref.read(scannerControllerProvider.notifier).start(),
          child: const Text('Retry'),
        );
      case ScannerUnavailableReason.permissionPermanentlyDenied:
        message = 'Camera access is permanently denied. Enable it in system settings to scan.';
        action = FilledButton(onPressed: openAppSettings, child: const Text('Open settings'));
      case ScannerUnavailableReason.noCameraAvailable:
        message = 'No camera is available on this device.';
        action = null;
    }

    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.no_photography, color: Colors.white70, size: 48),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor: Colors.black45,
      child: IconButton(icon: Icon(icon, color: Colors.white), onPressed: onPressed),
    );
  }
}
