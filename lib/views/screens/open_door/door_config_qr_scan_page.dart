import 'package:dormdevise/utils/app_toast.dart';
import '../../../utils/qr_transfer_codec.dart';
import '../table/table_page.dart';
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

  /// 最近一次处理的原始二维码内容与时间，用于防止短时间内重复识别导致重复弹窗。
  String? _lastHandledRaw;
  DateTime? _lastHandledAt;
  static const Duration _duplicateCooldown = Duration(seconds: 2);

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    if (_handled || _isHandling) {
      return;
    }

    final String rawValue = _extractRawValue(capture.barcodes);
    if (rawValue.isEmpty) {
      return;
    }

    // 如果与上次处理的内容相同且在冷却期内，则忽略此次识别
    if (_lastHandledRaw != null && _lastHandledRaw == rawValue) {
      final DateTime now = DateTime.now();
      if (_lastHandledAt != null &&
          now.difference(_lastHandledAt!) < _duplicateCooldown) {
        return;
      }
    }

    // 先尝试解码，若识别到的是课表导入码，则在本页弹出提示并保持页面为处理状态（黑屏），
    // 用户选择取消后继续扫码，选择跳转则直接跳转到课表导入页面。
    try {
      final decoded = QrTransferCodec.tryDecode(rawValue);
      if (decoded != null && decoded.type == 'schedule') {
        // 进入处理状态并停止相机，防止继续扫码
        setState(() {
          _isHandling = true;
        });
        _lastHandledRaw = rawValue;
        _lastHandledAt = DateTime.now();

        final BuildContext dialogCallerContext = context;
        if (!dialogCallerContext.mounted) {
          await _resumeScanning();
          return;
        }
        _controller.stop();

        final bool? go = await showDialog<bool>(
          context: dialogCallerContext,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('识别到课表导入码'),
              content: const Text('扫描结果为课表导入码，是否跳转到课表导入页面以导入该课表？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('跳转'),
                ),
              ],
            );
          },
        );

        if (go == true) {
          if (!mounted) return;
          // 跳转到课表导入页面，并移除之前的路由，避免返回到门锁页面
          await Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (_) => TablePage(initialImportRaw: rawValue),
            ),
            (Route<dynamic> route) => false,
          );
          return;
        }

        // 取消则恢复扫描
        await _resumeScanning();
        return;
      }
    } catch (_) {
      // ignore decode errors and continue with normal flow
    }

    // 正常的门锁配置扫描流：进入处理状态并返回结果
    setState(() {
      _isHandling = true;
    });
    _lastHandledRaw = rawValue;
    _lastHandledAt = DateTime.now();
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
    // 清除去抖记录，允许用户在取消/恢复后重新识别同一二维码
    _lastHandledRaw = null;
    _lastHandledAt = null;
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
      final String path = result != null && result.files.isNotEmpty
          ? result.files.first.path?.trim() ?? ''
          : '';
      if (path.isEmpty) {
        await _resumeScanning();
        return;
      }

      final BarcodeCapture? capture = await _controller.analyzeImage(path);
      final String rawValue = _extractRawValue(
        capture?.barcodes ?? <Barcode>[],
      );
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

      // 如果识别到课表导入码，则在本页弹窗询问并根据选择跳转或继续扫码
      try {
        final decoded = QrTransferCodec.tryDecode(rawValue);
        if (decoded != null && decoded.type == 'schedule') {
          setState(() {
            _isHandling = true;
          });
          _lastHandledRaw = rawValue;
          _lastHandledAt = DateTime.now();

          if (!mounted) return;
          final BuildContext dialogCallerContext = context;
          if (!dialogCallerContext.mounted) {
            await _resumeScanning();
            return;
          }
          _controller.stop();

          final bool? go = await showDialog<bool>(
            context: dialogCallerContext,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('识别到课表导入码'),
                content: const Text('扫描结果为课表导入码，是否跳转到课表导入页面以导入该课表？'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('跳转'),
                  ),
                ],
              );
            },
          );

          if (go == true) {
            if (!mounted) return;
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => TablePage(initialImportRaw: rawValue),
              ),
              (Route<dynamic> route) => false,
            );
            return;
          }

          await _resumeScanning();
          return;
        }
      } catch (_) {
        // ignore
      }

      // 如果与上次处理的内容相同且在冷却期内，则忽略此次识别
      if (_lastHandledRaw != null && _lastHandledRaw == rawValue) {
        final DateTime now = DateTime.now();
        if (_lastHandledAt != null &&
            now.difference(_lastHandledAt!) < _duplicateCooldown) {
          await _resumeScanning();
          return;
        }
      }

      _lastHandledRaw = rawValue;
      _lastHandledAt = DateTime.now();

      await _finishWithRaw(rawValue);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '图片识别失败：$error', variant: AppToastVariant.error);
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
            tooltip: _torchEnabled ? '关闭闪光灯' : '打开闪光灯',
            onPressed: _isHandling ? null : _toggleTorch,
            icon: Icon(
              _torchEnabled
                  ? Icons.flashlight_on_rounded
                  : Icons.flashlight_off_rounded,
            ),
          ),
          IconButton(
            tooltip: '选择图片扫码',
            onPressed: _isHandling ? null : _scanFromImage,
            icon: const Icon(Icons.photo_library_outlined),
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          if (_isHandling)
            const ColoredBox(color: Colors.black)
          else ...<Widget>[
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
          ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Text(
                  _isHandling ? '正在解析二维码，请稍候...' : '将门锁配置二维码放入取景框中，或点击右上角从图片识别',
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
