import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';
import '../../widgets/bubble_popup.dart';

/// 课表分享菜单逻辑。
class ScheduleShare {
  /// 统一生成课表分享链接，避免页面层拼接业务参数。
  static String _buildShareLink({
    required String tableName,
    required String semesterRange,
    required int currentWeek,
  }) {
    final String encodedName = Uri.encodeComponent(tableName);
    final String encodedSemester = Uri.encodeComponent(semesterRange);
    return 'https://dormdevise.app/schedule/share?name=$encodedName&semester=$encodedSemester&week=$currentWeek';
  }

  /// 显示分享菜单气泡。
  static Future<void> show({
    required BuildContext context,
    required GlobalKey anchorKey,
    required BubblePopupController controller,
    required String tableName,
    required String semesterRange,
    required int currentWeek,
  }) async {
    final String shareLink = _buildShareLink(
      tableName: tableName,
      semesterRange: semesterRange,
      currentWeek: currentWeek,
    );

    await showBubblePopup(
      context: context,
      anchorKey: anchorKey,
      controller: controller,
      content: SizedBox(
        width: 180,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildShareMenuItem(
              context: context,
              text: '复制分享链接',
              icon: Icons.link_outlined,
              onTap: () => _copyShareLink(
                context: context,
                controller: controller,
                shareLink: shareLink,
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
            _buildShareMenuItem(
              context: context,
              text: '生成二维码',
              icon: Icons.qr_code,
              onTap: () => _showQrCodeDialog(
                context: context,
                controller: controller,
                shareLink: shareLink,
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

  /// 复制分享链接。
  static Future<void> _copyShareLink({
    required BuildContext context,
    required BubblePopupController controller,
    required String shareLink,
  }) async {
    await controller.dismiss();
    if (!context.mounted) return;
    await Clipboard.setData(ClipboardData(text: shareLink));
    if (!context.mounted) return;
    AppToast.show(context, '分享链接已复制');
  }

  /// 展示二维码。
  static Future<void> _showQrCodeDialog({
    required BuildContext context,
    required BubblePopupController controller,
    required String shareLink,
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
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color:
                      Theme.of(dialogContext).cardTheme.color ??
                      colorScheme.surface,
                ),
                child: QrImageView(data: shareLink, size: 180),
              ),
              const SizedBox(height: 12),
              Text(
                '扫码即可打开分享链接',
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
