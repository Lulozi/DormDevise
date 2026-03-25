import 'package:dormdevise/services/course_schedule_transfer_service.dart';
import 'package:flutter/material.dart';

/// 课表导入前的预览确认弹窗。
class ScheduleImportPreviewDialog extends StatelessWidget {
  const ScheduleImportPreviewDialog({
    super.key,
    required this.bundle,
    this.cancelLabel = '继续扫描',
  });

  final CourseScheduleTransferBundle bundle;
  final String cancelLabel;

  static Future<bool> show(
    BuildContext context,
    CourseScheduleTransferBundle bundle, {
    String cancelLabel = '继续扫描',
  }) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return ScheduleImportPreviewDialog(
          bundle: bundle,
          cancelLabel: cancelLabel,
        );
      },
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '导入课表',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),
            _InfoLine(label: '名称', value: bundle.tableName),
            _InfoLine(label: '学期开始', value: _formatDate(bundle.semesterStart)),
            _InfoLine(label: '课程数量', value: '${bundle.courses.length} 门'),
            _InfoLine(label: '最大周数', value: '${bundle.maxWeek} 周'),
            _InfoLine(label: '周末显示', value: bundle.showWeekend ? '显示' : '隐藏'),
            _InfoLine(
              label: '锁定状态',
              value: bundle.isScheduleLocked ? '已锁定' : '未锁定',
            ),
            const SizedBox(height: 12),
            Text(
              '将作为一张新课表导入，若重名会自动追加“导入”后缀。',
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: _DialogActionButton(
                    label: cancelLabel,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogActionButton(
                    label: '确认导入',
                    isPrimary: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final String month = value.month.toString().padLeft(2, '0');
    final String day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _DialogActionButton extends StatelessWidget {
  const _DialogActionButton({
    required this.label,
    required this.onTap,
    this.isPrimary = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Color borderColor = isPrimary
        ? colorScheme.primary
        : colorScheme.outline.withValues(alpha: 0.42);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isPrimary ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isPrimary ? colorScheme.onPrimary : colorScheme.onSurface,
          ),
        ),
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
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 74,
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
