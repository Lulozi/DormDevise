import 'package:dormdevise/services/course_schedule_transfer_service.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/views/screens/table/widgets/schedule_import_preview_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码导入课表页面。
class ScanImportSchedulePage extends StatefulWidget {
  const ScanImportSchedulePage({super.key});

  @override
  State<ScanImportSchedulePage> createState() => _ScanImportSchedulePageState();
}

class _ScanImportSchedulePageState extends State<ScanImportSchedulePage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isHandling = false;
  bool _torchEnabled = false;

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    await _handleImport(_extractRawValue(capture.barcodes));
  }

  String _extractRawValue(Iterable<Barcode> barcodes) {
    return barcodes
        .map((Barcode barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
  }

  Future<void> _handleImport(
    String raw, {
    bool shouldPauseScanner = true,
    bool skipBusyCheck = false,
  }) async {
    if (raw.isEmpty) {
      return;
    }
    if (!skipBusyCheck && _isHandling) {
      return;
    }

    if (!_isHandling) {
      setState(() {
        _isHandling = true;
      });
    }
    if (shouldPauseScanner) {
      await _controller.stop();
    }

    try {
      final CourseScheduleTransferBundle bundle =
          CourseScheduleTransferService.decodeBundle(raw);
      if (!mounted) {
        return;
      }

      final bool confirmed = await ScheduleImportPreviewDialog.show(
        context,
        bundle,
      );
      if (!mounted) {
        return;
      }
      if (!confirmed) {
        await _resumeScanning();
        return;
      }

      await CourseService.instance.createImportedSchedule(
        desiredName: bundle.tableName,
        courses: bundle.courses,
        config: bundle.scheduleConfig,
        semesterStart: bundle.semesterStart,
        maxWeek: bundle.maxWeek,
        showWeekend: bundle.showWeekend,
        showNonCurrentWeek: bundle.showNonCurrentWeek,
        isScheduleLocked: bundle.isScheduleLocked,
      );
      if (!mounted) {
        return;
      }
      AppToast.show(context, '课表已导入');
      Navigator.of(context).pop(true);
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(
        context,
        _resolveImportErrorMessage(raw, error),
        variant: AppToastVariant.warning,
      );
      await _resumeScanning();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '导入失败：$error', variant: AppToastVariant.error);
      await _resumeScanning();
    }
  }

  Future<void> _resumeScanning() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _isHandling = false;
    });
    await _controller.start();
  }

  String _resolveImportErrorMessage(String raw, FormatException error) {
    if (CourseScheduleTransferService.isLegacyShareLink(raw)) {
      return '这是旧版分享链接，不含完整课表数据，请重新生成新版分享二维码';
    }
    return error.message;
  }

  Future<void> _scanFromImage() async {
    if (_isHandling) {
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
      final String raw = _extractRawValue(capture?.barcodes ?? <Barcode>[]);
      if (raw.isEmpty) {
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

      await _handleImport(raw, shouldPauseScanner: false, skipBusyCheck: true);
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
        title: const Text('扫码导入课表'),
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
                  width: 248,
                  height: 248,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: colorScheme.primary, width: 3),
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            left: 20,
            right: 20,
            bottom: 40,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _isHandling
                          ? '正在解析二维码，请稍候...'
                          : '将课表分享二维码放入取景框中，识别后会先展示导入预览',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '也可以点击右上角从图片中识别课表二维码',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                      ),
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
