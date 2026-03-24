import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'door_config_qr_scan_page.dart';

/// 门锁配置的通用分享/导入菜单。
class DoorConfigShareSheet {
  static Future<void> show({
    required BuildContext context,
    required String configLabel,
    required String payload,
    required Future<void> Function(String raw) onImport,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('分享配置（复制到剪贴板）'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  await Clipboard.setData(ClipboardData(text: payload));
                  if (!context.mounted) {
                    return;
                  }
                  AppToast.show(context, '$configLabel 已复制到剪贴板');
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_2_rounded),
                title: const Text('二维码导出'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  if (!context.mounted) {
                    return;
                  }
                  await _showQrCodeDialog(
                    context: context,
                    configLabel: configLabel,
                    payload: payload,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('导入配置（从剪贴板）'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final ClipboardData? data = await Clipboard.getData(
                    'text/plain',
                  );
                  final String raw = data?.text?.trim() ?? '';
                  if (raw.isEmpty) {
                    if (!context.mounted) {
                      return;
                    }
                    AppToast.show(
                      context,
                      '剪贴板内容为空',
                      variant: AppToastVariant.warning,
                    );
                    return;
                  }
                  await onImport(raw);
                },
              ),
              ListTile(
                leading: const Icon(Icons.qr_code_scanner_rounded),
                title: const Text('扫码导入'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  if (!context.mounted) {
                    return;
                  }
                  final String? raw = await Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) =>
                          DoorConfigQrScanPage(title: '扫描$configLabel二维码'),
                    ),
                  );
                  if (raw == null || raw.trim().isEmpty) {
                    return;
                  }
                  await onImport(raw);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static Future<void> _showQrCodeDialog({
    required BuildContext context,
    required String configLabel,
    required String payload,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('$configLabel 二维码'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color:
                      Theme.of(dialogContext).cardTheme.color ??
                      colorScheme.surface,
                ),
                child: QrImageView(
                  data: payload,
                  size: 220,
                  version: QrVersions.auto,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '扫码即可导入当前$configLabel',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: <Widget>[
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
