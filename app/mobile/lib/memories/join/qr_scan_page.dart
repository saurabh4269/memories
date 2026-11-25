import 'dart:async';

import 'package:flutter/material.dart';
import 'package:immich_mobile/memories/join/join_link.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera QR scanner. Pops with a [JoinLink] when a valid invite
/// QR is seen, or with null if the user goes back.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  static Future<JoinLink?> open(BuildContext context) =>
      Navigator.of(context).push<JoinLink>(MaterialPageRoute(builder: (_) => const QrScanPage()));

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  final MobileScannerController _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;
  bool _sawWrongCode = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final link = JoinLink.tryParse(barcode.rawValue);
      if (link != null) {
        _done = true;
        Navigator.of(context).pop(link);
        return;
      }
    }
    if (!_sawWrongCode && mounted) {
      setState(() => _sawWrongCode = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan the QR'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            iconSize: 30,
            icon: const Icon(Icons.flashlight_on_rounded),
            onPressed: () => unawaited(_controller.toggleTorch()),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => _CameraError(onBack: () => Navigator.of(context).pop()),
          ),
          const IgnorePointer(child: _ScanFrame()),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _sawWrongCode
                      ? 'That QR is not a Memories invite. Try the one on the host\'s phone.'
                      : 'Point the camera at the QR code on the host\'s phone',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanFrame extends StatelessWidget {
  const _ScanFrame();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 4),
          borderRadius: BorderRadius.circular(28),
        ),
      ),
    );
  }
}

class _CameraError extends StatelessWidget {
  final VoidCallback onBack;

  const _CameraError({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.no_photography_rounded, color: Colors.white, size: 64),
              const SizedBox(height: 16),
              const Text(
                'The camera is not available.\nPlease allow camera access, or type the code instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 20),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(220, 60)),
                onPressed: onBack,
                child: const Text('Type the code', style: TextStyle(fontSize: 20)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
