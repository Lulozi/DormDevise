import 'package:dormdevise/services/course_schedule_transfer_service.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/services/course_widget_service.dart';
import 'package:dormdevise/utils/android_soft_input_mode.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/views/screens/table/widgets/schedule_import_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 通过导入码导入整张课表。
class ImportCodeSchedulePage extends StatefulWidget {
  const ImportCodeSchedulePage({super.key});

  @override
  State<ImportCodeSchedulePage> createState() => _ImportCodeSchedulePageState();
}

class _ImportCodeSchedulePageState extends State<ImportCodeSchedulePage>
    with WidgetsBindingObserver {
  final TextEditingController _codeController = TextEditingController();
  bool _isImporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSoftInputModeController.setModeSilently(
      AndroidSoftInputMode.adjustPan,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AndroidSoftInputModeController.setModeSilently(
        AndroidSoftInputMode.adjustPan,
      );
    }
  }

  Future<void> _pasteImportCode() async {
    final ClipboardData? data = await Clipboard.getData('text/plain');
    final String raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '剪贴板内容为空', variant: AppToastVariant.warning);
      return;
    }

    _codeController.text = raw;
    _codeController.selection = TextSelection.collapsed(offset: raw.length);
  }

  Future<void> _submitImport() async {
    if (_isImporting) {
      return;
    }

    final String raw = _codeController.text.trim();
    if (raw.isEmpty) {
      AppToast.show(context, '请输入导入码', variant: AppToastVariant.warning);
      return;
    }

    setState(() {
      _isImporting = true;
    });

    try {
      final CourseScheduleTransferBundle bundle =
          CourseScheduleTransferService.decodeBundle(raw);
      if (!mounted) {
        return;
      }

      final bool confirmed = await ScheduleImportPreviewDialog.show(
        context,
        bundle,
        cancelLabel: '取消',
      );
      if (!mounted || !confirmed) {
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
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '导入失败：$error', variant: AppToastVariant.error);
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  String _resolveImportErrorMessage(String raw, FormatException error) {
    if (CourseScheduleTransferService.isLegacyShareLink(raw)) {
      return '这是旧版分享链接，不含完整课表数据，请重新生成新版分享二维码';
    }
    return error.message;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSoftInputModeController.setModeSilently(
      AndroidSoftInputMode.adjustResize,
    );
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('导入码导入课表')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                '将分享得到的课表导入码粘贴到下方，确认后会先展示导入预览。',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.42,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _codeController,
                      enabled: !_isImporting,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: '请粘贴课表导入码',
                        hintStyle: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isImporting ? null : _pasteImportCode,
                      icon: const Icon(Icons.content_paste_rounded),
                      label: const Text('粘贴导入码'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _isImporting ? null : _submitImport,
                      icon: const Icon(Icons.download_rounded),
                      label: Text(_isImporting ? '正在导入' : '开始导入'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
