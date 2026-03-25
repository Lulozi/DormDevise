import 'package:dormdevise/utils/app_toast.dart';
import 'package:file_picker/file_picker.dart';
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
  bool _isHandling = false;
  bool _torchEnabled = false;

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    if (_handled || _isHandling) {
      return;
    }

    final String rawValue = _extractRawValue(capture.barcodes);
    if (rawValue.isEmpty) {
      return;
    }

    setState(() {
      _isHandling = true;
    });
    await _controller.stop();
    await _finishWithRaw(rawValue);
  }

  String _extractRawValue(Iterable<Barcode> barcodes) {
    return barcodes
        .map((Barcode barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
  }

  Future<void> _finishWithRaw(String rawValue) async {
    if (_handled || rawValue.isEmpty) {
      return;
    }

    _handled = true;
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(rawValue);
  }

  Future<void> _resumeScanning() async {
    if (!mounted || _handled) {
      return;
    }
    setState(() {
      _isHandling = false;
    });
    await _controller.start();
  }

  Future<void> _scanFromImage() async {
    if (_handled || _isHandling) {
      return;
    }

    setState(() {
      _isHandling = true;
    });
    await _controller.stop();

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      final String path =
          result != null && result.files.isNotEmpty
          ? result.files.first.path?.trim() ?? ''
          : '';
      if (path.isEmpty) {
        await _resumeScanning();
        return;
      }

      final BarcodeCapture? capture = await _controller.analyzeImage(path);
      final String rawValue = _extractRawValue(capture?.barcodes ?? <Barcode>[]);
      if (rawValue.isEmpty) {
        if (!mounted) {
          return;
        }
        AppToast.show(
          context,
          '未识别到二维码，请换一张更清晰的图片',
          variant: AppToastVariant.warning,
        );
        await _resumeScanning();
        return;
      }

      await _finishWithRaw(rawValue);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        '图片识别失败：$error',
        variant: AppToastVariant.error,
      );
      await _resumeScanning();
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) {
      return;
    }
    setState(() {
      _torchEnabled = !_torchEnabled;
    });
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
        actions: <Widget>[
          IconButton(
            tooltip: '选择图片扫码',
            onPressed: _isHandling ? null : _scanFromImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: _torchEnabled ? '关闭闪光灯' : '打开闪光灯',
            onPressed: _isHandling ? null : _toggleTorch,
            icon: Icon(
              _torchEnabled
                  ? Icons.flashlight_on_rounded
                  : Icons.flashlight_off_rounded,
            ),
          ),
        ],
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Text(
                  _isHandling
                      ? '正在解析二维码，请稍候...'
                      : '将门锁配置二维码放入取景框中，或点击右上角从图片识别',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
