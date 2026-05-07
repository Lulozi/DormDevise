import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/utils/qr_image_export_service.dart';
import 'package:dormdevise/services/course_service.dart';
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
              text: '分享二维码',
              icon: FontAwesomeIcons.qrcode,
              onTap: () => _showQrSharePreviewDialog(
                context: context,
                controller: controller,
                tableName: bundle.tableName,
                shareCode: shareCode,
              ),
            ),
            const Divider(height: 1, thickness: 0.5),
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

  /// 展示居中的分享预览弹窗。
  static Future<void> _showQrSharePreviewDialog({
    required BuildContext context,
    required BubblePopupController controller,
    required String tableName,
    required String shareCode,
  }) async {
    await controller.dismiss();
    if (!context.mounted) return;

    // 优先读取当前课表服务中的名称，确保分享卡展示的是最新实际名称。
    final String latestTableName = await CourseService.instance.loadTableName();
    if (!context.mounted) return;
    final String resolvedTableName = latestTableName.trim().isEmpty
        ? tableName
        : latestTableName.trim();

    await QrImageExportService.showQrShareOptionsSheet(
      context: context,
      qrData: shareCode,
      fileNamePrefix: '课表_$resolvedTableName',
      qrProjectLabel: '课程表分享',
      shareText: 'DormDevise 课表导入二维码',
      shareInfoText: resolvedTableName,
    );
  }
}
