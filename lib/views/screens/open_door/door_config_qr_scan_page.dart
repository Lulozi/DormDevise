import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 通用二维码扫描页，返回识别到的原始文本。
class DoorConfigQrScanPage extends StatefulWidget {
  const DoorConfigQrScanPage({super.key, this.title = '扫码导入配置'});

  final String title;

  @override
  State<DoorConfigQrScanPage> createState() => _DoorConfigQrScanPageState();
}

class _DoorConfigQrScanPageState extends State<DoorConfigQrScanPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    if (_handled) {
      return;
    }
    final String rawValue = capture.barcodes
        .map((Barcode barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) {
      return;
    }
    _handled = true;
    await _controller.stop();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(rawValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcodeCapture,
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.primary, width: 3),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.58),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  '将门锁配置二维码放入取景框中即可自动导入',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
