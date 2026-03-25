import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';
import '../../../services/course_schedule_transfer_service.dart';
import '../../widgets/bubble_popup.dart';

/// 课表分享菜单逻辑。
class ScheduleShare {
  /// 显示分享菜单气泡。
  static Future<void> show({
    required BuildContext context,
    required GlobalKey anchorKey,
    required BubblePopupController controller,
    required CourseScheduleTransferBundle bundle,
  }) async {
    final String shareCode = CourseScheduleTransferService.encodeBundle(bundle);

    await showBubblePopup(
      context: context,
      anchorKey: anchorKey,
      controller: controller,
      content: SizedBox(
        width: 160,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShareMenuItem(
              context: context,
              text: '复制导入码',
              icon: FontAwesomeIcons.copy,
              onTap: () => _copyShareCode(
                context: context,
                controller: controller,
                shareCode: shareCode,
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            _buildShareMenuItem(
              context: context,
              text: '分享二维码',
              icon: FontAwesomeIcons.qrcode,
              onTap: () => _showQrCodeDialog(
                context: context,
                controller: controller,
                tableName: bundle.tableName,
                shareCode: shareCode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildShareMenuItem({
    required BuildContext context,
    required String text,
    required IconData icon,
    required Future<void> Function() onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 复制课表导入码。
  static Future<void> _copyShareCode({
    required BuildContext context,
    required BubblePopupController controller,
    required String shareCode,
  }) async {
    await controller.dismiss();
    if (!context.mounted) return;
    await Clipboard.setData(ClipboardData(text: shareCode));
    if (!context.mounted) return;
    AppToast.show(context, '课表导入码已复制');
  }

  /// 展示二维码。
  static Future<void> _showQrCodeDialog({
    required BuildContext context,
    required BubblePopupController controller,
    required String tableName,
    required String shareCode,
  }) async {
    await controller.dismiss();
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('课表分享二维码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tableName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color:
                      Theme.of(dialogContext).cardTheme.color ??
                      colorScheme.surface,
                ),
                child: QrImageView(
                  data: shareCode,
                  size: 200,
                  version: QrVersions.auto,
                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '扫码即可导入整张课表，二维码内容已压缩',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }
}
