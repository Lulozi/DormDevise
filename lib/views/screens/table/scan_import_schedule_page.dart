import 'package:dormdevise/services/course_schedule_transfer_service.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final String rawValue = capture.barcodes
        .map((Barcode barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .firstWhere((String value) => value.isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) {
      return;
    }
    await _handleImport(rawValue);
  }

  Future<void> _handleImport(String raw) async {
    if (_isHandling) {
      return;
    }

    setState(() {
      _isHandling = true;
    });
    await _controller.stop();

    try {
      final CourseScheduleTransferBundle bundle =
          CourseScheduleTransferService.decodeBundle(raw);
      if (!mounted) {
        return;
      }

      final bool confirmed = await _showImportPreview(bundle);
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

  Future<void> _importFromClipboard() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    final String raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '剪贴板内容为空', variant: AppToastVariant.warning);
      return;
    }
    await _handleImport(raw);
  }

  Future<bool> _showImportPreview(CourseScheduleTransferBundle bundle) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('导入课表'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _InfoLine(label: '名称', value: bundle.tableName),
              _InfoLine(
                label: '学期开始',
                value: _formatDate(bundle.semesterStart),
              ),
              _InfoLine(label: '课程数量', value: '${bundle.courses.length} 门'),
              _InfoLine(label: '最大周数', value: '${bundle.maxWeek} 周'),
              _InfoLine(label: '周末显示', value: bundle.showWeekend ? '显示' : '隐藏'),
              _InfoLine(
                label: '锁定状态',
                value: bundle.isScheduleLocked ? '已锁定' : '未锁定',
              ),
              const SizedBox(height: 8),
              Text(
                '将作为一张新课表导入，若重名会自动追加“导入”后缀。',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('继续扫描'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: const Text('确认导入'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    return result == true;
  }

  String _formatDate(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
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
            tooltip: '粘贴导入码',
            onPressed: _isHandling ? null : _importFromClipboard,
            icon: const Icon(Icons.content_paste_rounded),
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
                width: 248,
                height: 248,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: colorScheme.primary, width: 3),
                ),
              ),
            ),
          ),
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
                      '也可以直接粘贴剪贴板中的导入码',
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

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
