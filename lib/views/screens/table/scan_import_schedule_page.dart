import 'package:dormdevise/services/course_schedule_transfer_service.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/services/course_widget_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/views/screens/table/widgets/schedule_import_preview_dialog.dart';
import 'dart:convert';

import 'package:dormdevise/utils/qr_transfer_codec.dart';
import 'package:dormdevise/views/screens/open_door/door_lock_config_page.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码导入课表页面。
class ScanImportSchedulePage extends StatefulWidget {
  const ScanImportSchedulePage({super.key, this.initialRaw});

  /// 如果通过跳转传入了初始要导入的原始二维码内容，将在页面加载后自动尝试导入。
  final String? initialRaw;

  @override
  State<ScanImportSchedulePage> createState() => _ScanImportSchedulePageState();
}

class _ScanImportSchedulePageState extends State<ScanImportSchedulePage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isHandling = false;
  bool _torchEnabled = false;

  /// 最近一次处理的原始二维码内容与时间，用于防止短时间内重复识别导致重复弹窗。
  String? _lastHandledRaw;
  DateTime? _lastHandledAt;
  static const Duration _duplicateCooldown = Duration(seconds: 2);

  Future<void> _handleBarcodeCapture(BarcodeCapture capture) async {
    final String raw = _extractRawValue(capture.barcodes);
    if (raw.isEmpty) return;

    // 如果与上次处理的内容相同且在冷却期内，则忽略此次识别
    if (_lastHandledRaw != null && _lastHandledRaw == raw) {
      final DateTime now = DateTime.now();
      if (_lastHandledAt != null &&
          now.difference(_lastHandledAt!) < _duplicateCooldown) {
        return;
      }
    }

    // 立即记录以阻止并发重复触发（若用户取消，会通过 _resumeScanning 清除）
    _lastHandledRaw = raw;
    _lastHandledAt = DateTime.now();

    await _handleImport(raw);
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
    // 首先尝试识别是否为本应用自定义的二维码负载，如果是其它类型（例如门锁配置），
    // 则提示用户是否跳转到对应页面进行导入。
    try {
      final decoded = QrTransferCodec.tryDecode(raw);
      if (decoded != null &&
          decoded.type != CourseScheduleTransferService.payloadType) {
        if (decoded.type == 'door_config') {
          // 在展示跳转确认对话前，先进入处理状态并停止相机，防止继续扫码
          if (!_isHandling) {
            setState(() {
              _isHandling = true;
            });
          }
          final BuildContext dialogCallerContext = context;
          if (shouldPauseScanner) {
            _controller.stop();
          }

          final bool? go = await showDialog<bool>(
            context: dialogCallerContext,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('识别到门锁配置'),
                content: const Text('扫描结果为门锁配置，是否跳转到门锁配置页面以导入？'),
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
            // 将已解码的文本传递给门锁配置页，后者会询问是否导入。
            // 使用 pushReplacement 替换当前扫码页面，返回时不回到扫码界面。
            final String decodedText = decoded.text;
            if (!mounted) return;

            int initialTabIndex = 0;
            try {
              final dynamic payload = jsonDecode(decodedText);
              if (payload is Map) {
                final Iterable<String> keys = payload.keys.map(
                  (k) => k.toString(),
                );
                if (keys.any(
                  (k) => k.startsWith('mqtt_') || k == 'custom_open_msg',
                )) {
                  initialTabIndex = 1; // 切到 MQTT 配置页
                }
              }
            } catch (_) {
              // ignore: not a JSON payload
            }

            await Navigator.of(context).pushReplacement(
              MaterialPageRoute<bool>(
                builder: (_) => OpenDoorSettingsPage(
                  initialImportPayload: decodedText,
                  initialTabIndex: initialTabIndex,
                ),
              ),
            );
            return;
          } else {
            // 用户取消：恢复扫描并允许再次识别同一二维码
            await _resumeScanning();
            return;
          }
        }
      }
    } catch (_) {
      // ignore decoding errors here and continue with normal schedule import flow
    }
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
      await CourseWidgetService.instance.syncWidget(
        resetDisplayDateToToday: true,
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
    // 清除去抖记录，允许用户取消后立即重新扫码同一二维码
    _lastHandledRaw = null;
    _lastHandledAt = null;
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
  void initState() {
    super.initState();
    // 如果页面是通过跳转并携带了初始二维码内容，则在首帧后自动处理一次导入。
    if (widget.initialRaw != null && widget.initialRaw!.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleImport(widget.initialRaw!);
      });
    }
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
