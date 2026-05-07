import 'package:dormdevise/utils/app_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dormdevise/utils/qr_image_export_service.dart';

import '../../../utils/qr_transfer_codec.dart';
import '../table/table_page.dart';
import 'door_lock_config_page.dart';
import 'door_config_qr_scan_page.dart';

/// 门锁配置的通用分享/导入菜单。
class DoorConfigShareSheet {
  /// 导入处理中标志，防止并发重复弹窗/导入。
  static bool _isImportInProgress = false;
  static Future<void> show({
    required BuildContext context,
    required String configLabel,
    required String payload,
    required Future<void> Function(String raw) onImport,

    /// 是否允许显示导入相关项（剪贴板导入、扫码导入）。
    ///
    /// 当为 false 时，弹窗为“仅分享”模式，不会展示导入项且不分区。
    bool allowImport = true,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: allowImport
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _SectionTitle(title: '剪贴板'),
                      _ActionGroup(
                        children: <Widget>[
                          ListTile(
                            leading: const Icon(Icons.share_outlined),
                            title: const Text('导出到剪贴板'),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await Clipboard.setData(
                                ClipboardData(text: payload),
                              );
                              if (!context.mounted) {
                                return;
                              }
                              AppToast.show(context, '$configLabel 已复制到剪贴板');
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.download_outlined),
                            title: const Text('剪贴板导入'),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              final ClipboardData? data =
                                  await Clipboard.getData('text/plain');
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
                              if (!context.mounted) {
                                return;
                              }
                              await _handleImport(
                                context: context,
                                raw: raw,
                                onImport: onImport,
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _SectionTitle(title: '二维码'),
                      _ActionGroup(
                        children: <Widget>[
                          ListTile(
                            leading: const Icon(Icons.qr_code_2_rounded),
                            title: const Text('导出为二维码'),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              if (!context.mounted) {
                                return;
                              }
                              await _showQrSharePreviewDialog(
                                context: context,
                                configLabel: configLabel,
                                payload: payload,
                              );
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
                              final String? raw = await Navigator.of(context)
                                  .push<String>(
                                    MaterialPageRoute<String>(
                                      builder: (_) => DoorConfigQrScanPage(
                                        title: '扫描$configLabel二维码',
                                      ),
                                    ),
                                  );
                              if (raw == null || raw.trim().isEmpty) {
                                return;
                              }
                              if (!context.mounted) {
                                return;
                              }
                              await _handleImport(
                                context: context,
                                raw: raw,
                                onImport: onImport,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ActionGroup(
                        children: <Widget>[
                          ListTile(
                            leading: const Icon(Icons.share_outlined),
                            title: const Text('导出到剪贴板'),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await Clipboard.setData(
                                ClipboardData(text: payload),
                              );
                              if (!context.mounted) {
                                return;
                              }
                              AppToast.show(context, '$configLabel 已复制到剪贴板');
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.qr_code_2_rounded),
                            title: const Text('导出为二维码'),
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              if (!context.mounted) return;
                              await _showQrSharePreviewDialog(
                                context: context,
                                configLabel: configLabel,
                                payload: payload,
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  static Future<void> _showQrSharePreviewDialog({
    required BuildContext context,
    required String configLabel,
    required String payload,
  }) async {
    final String qrPayload = QrTransferCodec.encodeText(
      type: 'door_config',
      text: payload,
    );
    await QrImageExportService.showQrShareOptionsSheet(
      context: context,
      qrData: qrPayload,
      fileNamePrefix: '$configLabel二维码',
      qrProjectLabel: '$configLabel分享',
      shareText: 'DormDevise $configLabel 导入二维码',
      shareInfoText: configLabel,
    );
  }

  static Future<void> _handleImport({
    required BuildContext context,
    required String raw,
    required Future<void> Function(String raw) onImport,
  }) async {
    final BuildContext safeContext = context;

    // 防止并发重复处理（在弹窗/导入进行中时忽略后续触发）
    if (_isImportInProgress) {
      return;
    }
    _isImportInProgress = true;

    try {
      // 先尝试识别是否为其他类型的本应用负载（例如课表导入码），若是则提示是否跳转到对应页面
      final decoded = QrTransferCodec.tryDecode(raw);
      if (decoded != null && decoded.type != 'door_config') {
        if (decoded.type == 'schedule') {
          final bool? go = await showDialog<bool>(
            context: safeContext,
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
            // 直接导航到课表页面，并把原始二维码内容传入以便自动导入或预览
            if (!safeContext.mounted) return;
            await Navigator.of(safeContext).pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => TablePage(initialImportRaw: raw),
              ),
              (Route<dynamic> route) => false,
            );
            return;
          }
        }
      }

      // 若扫描到门锁配置，先判断其中是否包含 MQTT/HTTP 的独立配置，
      // 并尝试切到对应的标签页（若 caller 在 OpenDoorSettingsPage 下）。
      if (decoded != null && decoded.type == 'door_config') {
        try {
          final dynamic payload = jsonDecode(decoded.text);
          if (payload is Map && safeContext.mounted) {
            final bool hasLocalConfig = payload.keys.any(
              (dynamic k) => k.toString().startsWith('local_'),
            );
            final bool hasMqttConfig = payload.keys.any((dynamic k) {
              final String normalized = k.toString();
              return normalized.startsWith('mqtt_') ||
                  normalized == 'custom_open_msg';
            });
            if (hasMqttConfig && !hasLocalConfig) {
              OpenDoorSettingsPage.switchToTabIfExists(safeContext, 1);
            } else if (hasLocalConfig && !hasMqttConfig) {
              OpenDoorSettingsPage.switchToTabIfExists(safeContext, 0);
            }
          }
        } catch (_) {
          // ignore JSON parse errors
        }
      }

      await onImport(QrTransferCodec.decodeText(raw));
    } catch (error) {
      if (!safeContext.mounted) {
        return;
      }
      AppToast.show(safeContext, '导入失败：$error', variant: AppToastVariant.error);
    } finally {
      // 处理完或发生错误后，允许再次触发导入流程
      _isImportInProgress = false;
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final List<Widget> spacedChildren = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spacedChildren.add(children[i]);
      if (i != children.length - 1) {
        spacedChildren.add(
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outlineVariant,
          ),
        );
      }
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: spacedChildren),
    );
  }
}
