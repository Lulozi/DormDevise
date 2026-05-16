import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:gal/gal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'app_toast.dart';
import 'person_identity.dart';

/// 二维码图片导出服务，统一处理分享与保存能力。
class QrImageExportService {
  QrImageExportService._();

  static const MethodChannel _directShareChannel = MethodChannel(
    'dormdevise/direct_share',
  );

  /// 显示图片分享面板，提供保存到本地、微信、QQ 和其他分享入口。
  static Future<void> showQrShareOptionsSheet({
    required BuildContext context,
    required String qrData,
    required String fileNamePrefix,
    required String qrProjectLabel,
    String? shareText,
    String? shareInfoText,
  }) async {
    // 每次打开分享面板都刷新一次身份信息，确保头像和昵称与个人页保持同步。
    final PersonIdentityProfile profile = await PersonIdentityService.instance
        .loadProfile();
    if (!context.mounted) {
      return;
    }
    final String resolvedShareInfoText =
        (shareInfoText?.trim().isNotEmpty ?? false)
        ? shareInfoText!.trim()
        : profile.shareInfoText;
    final Uint8List normalizedQrImageBytes = await _buildNormalizedQrPngBytes(
      qrData,
    );
    if (!context.mounted) {
      return;
    }
    final GlobalKey previewBoundaryKey = GlobalKey();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '二维码导出',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (BuildContext dialogContext, _, __) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 24,
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _QrSharePreviewCard(
                  previewBoundaryKey: previewBoundaryKey,
                  qrImageBytes: normalizedQrImageBytes,
                  qrProjectLabel: qrProjectLabel,
                  shareInfoText: resolvedShareInfoText,
                  displayName: profile.displayName,
                  avatarPath: profile.avatarPath,
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(dialogContext).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: <Widget>[
                      _QrShareActionButton(
                        icon: FontAwesomeIcons.download,
                        iconBackground: const Color(0xFF5F72FF),
                        label: '保存至本地',
                        onTap: () async {
                          final Uint8List previewImageBytes =
                              await _buildSharePreviewPngBytes(
                                previewBoundaryKey: previewBoundaryKey,
                                fallbackQrData: qrData,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          await saveQrImage(
                            context: context,
                            qrData: qrData,
                            fileNamePrefix: fileNamePrefix,
                            imageBytes: previewImageBytes,
                          );
                        },
                      ),
                      _QrShareActionButton(
                        icon: FontAwesomeIcons.weixin,
                        iconBackground: const Color(0xFF29C046),
                        label: '微信',
                        onTap: () async {
                          final Uint8List previewImageBytes =
                              await _buildSharePreviewPngBytes(
                                previewBoundaryKey: previewBoundaryKey,
                                fallbackQrData: qrData,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          await _shareQrImageToTargetApp(
                            context: context,
                            qrData: qrData,
                            fileNamePrefix: fileNamePrefix,
                            shareText: shareText,
                            target: _DirectShareTarget.wechat,
                            imageBytes: previewImageBytes,
                          );
                        },
                      ),
                      _QrShareActionButton(
                        icon: FontAwesomeIcons.qq,
                        iconBackground: const Color(0xFF2FA8FF),
                        label: 'QQ',
                        onTap: () async {
                          final Uint8List previewImageBytes =
                              await _buildSharePreviewPngBytes(
                                previewBoundaryKey: previewBoundaryKey,
                                fallbackQrData: qrData,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          await _shareQrImageToTargetApp(
                            context: context,
                            qrData: qrData,
                            fileNamePrefix: fileNamePrefix,
                            shareText: shareText,
                            target: _DirectShareTarget.qq,
                            imageBytes: previewImageBytes,
                          );
                        },
                      ),
                      _QrShareActionButton(
                        icon: FontAwesomeIcons.shareNodes,
                        iconBackground: const Color(0xFFFFC429),
                        label: '其他',
                        onTap: () async {
                          final Uint8List previewImageBytes =
                              await _buildSharePreviewPngBytes(
                                previewBoundaryKey: previewBoundaryKey,
                                fallbackQrData: qrData,
                              );
                          if (!context.mounted) {
                            return;
                          }
                          await shareQrImage(
                            context: context,
                            qrData: qrData,
                            fileNamePrefix: fileNamePrefix,
                            shareText: shareText,
                            imageBytes: previewImageBytes,
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        // 与“二维码名片”保持一致：淡入 + 轻微缩放。
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// 针对微信/QQ执行定向分享：优先直达目标应用，失败时回退系统分享。
  static Future<void> _shareQrImageToTargetApp({
    required BuildContext context,
    required String qrData,
    required String fileNamePrefix,
    String? shareText,
    required _DirectShareTarget target,
    Uint8List? imageBytes,
  }) async {
    try {
      final Uint8List pngBytes = imageBytes ?? await _buildQrPngBytes(qrData);
      final String safeFileName = '${_toSafeFileName(fileNamePrefix)}.png';

      // 非 Android 平台不支持包名定向，直接走系统分享。
      if (!Platform.isAndroid) {
        if (!context.mounted) {
          return;
        }
        await shareQrImage(
          context: context,
          qrData: qrData,
          fileNamePrefix: fileNamePrefix,
          shareText: shareText,
          imageBytes: imageBytes,
        );
        return;
      }

      final bool launched =
          await _directShareChannel.invokeMethod<bool>('shareImageToPackage', {
            'bytes': pngBytes,
            'fileName': safeFileName,
            'mimeType': 'image/png',
            'packageName': target.packageName,
            'text': shareText ?? '',
          }) ??
          false;

      if (launched) {
        return;
      }

      if (context.mounted) {
        AppToast.show(
          context,
          '未检测到${target.label}，已切换为系统分享',
          variant: AppToastVariant.warning,
        );
      }
      if (!context.mounted) {
        return;
      }
      await shareQrImage(
        context: context,
        qrData: qrData,
        fileNamePrefix: fileNamePrefix,
        shareText: shareText,
        imageBytes: imageBytes,
      );
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      await shareQrImage(
        context: context,
        qrData: qrData,
        fileNamePrefix: fileNamePrefix,
        shareText: shareText,
        imageBytes: imageBytes,
      );
    }
  }

  /// 直达微信分享二维码，失败时自动回退系统分享。
  static Future<void> shareQrImageToWechat({
    required BuildContext context,
    required String qrData,
    required String fileNamePrefix,
    String? shareText,
    Uint8List? imageBytes,
  }) async {
    await _shareQrImageToTargetApp(
      context: context,
      qrData: qrData,
      fileNamePrefix: fileNamePrefix,
      shareText: shareText,
      target: _DirectShareTarget.wechat,
      imageBytes: imageBytes,
    );
  }

  /// 直达 QQ 分享二维码，失败时自动回退系统分享。
  static Future<void> shareQrImageToQQ({
    required BuildContext context,
    required String qrData,
    required String fileNamePrefix,
    String? shareText,
    Uint8List? imageBytes,
  }) async {
    await _shareQrImageToTargetApp(
      context: context,
      qrData: qrData,
      fileNamePrefix: fileNamePrefix,
      shareText: shareText,
      target: _DirectShareTarget.qq,
      imageBytes: imageBytes,
    );
  }

  /// 生成二维码图片并调起系统分享面板。
  static Future<void> shareQrImage({
    required BuildContext context,
    required String qrData,
    required String fileNamePrefix,
    String? shareText,
    Uint8List? imageBytes,
  }) async {
    try {
      final Uint8List pngBytes = imageBytes ?? await _buildQrPngBytes(qrData);
      final String safeFileName = _toSafeFileName(fileNamePrefix);

      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile.fromData(
              pngBytes,
              mimeType: 'image/png',
              name: '$safeFileName.png',
            ),
          ],
          text: shareText,
          subject: '$safeFileName 二维码',
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppToast.show(context, '分享二维码失败：$error', variant: AppToastVariant.error);
    }
  }

  /// 生成二维码图片并直接保存到系统相册。
  static Future<void> saveQrImage({
    required BuildContext context,
    required String qrData,
    required String fileNamePrefix,
    Uint8List? imageBytes,
  }) async {
    try {
      final Uint8List pngBytes = imageBytes ?? await _buildQrPngBytes(qrData);
      final String safeFileName = _toSafeFileName(fileNamePrefix);

      // 先检查并请求相册写入权限，用户拒绝时直接给出提示。
      final bool hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final bool granted = await Gal.requestAccess();
        if (!granted) {
          if (!context.mounted) {
            return;
          }
          AppToast.show(
            context,
            '未授予相册权限，无法保存图片',
            variant: AppToastVariant.warning,
          );
          return;
        }
      }

      await Gal.putImageBytes(pngBytes, name: safeFileName);
      if (!context.mounted) {
        return;
      }
      AppToast.show(context, '二维码已保存到相册', variant: AppToastVariant.success);
    } on GalException catch (error) {
      if (!context.mounted) {
        return;
      }
      AppToast.show(
        context,
        '保存二维码失败：${error.type.name}',
        variant: AppToastVariant.error,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      AppToast.show(context, '保存二维码失败：$error', variant: AppToastVariant.error);
    }
  }

  /// 渲染二维码为 PNG 字节，用于分享和保存。
  static Future<Uint8List> _buildQrPngBytes(String qrData) async {
    final QrPainter painter = QrPainter(
      data: qrData,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
      gapless: true,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF000000),
      ),
    );

    final ByteData? byteData = await painter.toImageData(1024);
    if (byteData == null) {
      throw const FormatException('二维码渲染失败');
    }
    return byteData.buffer.asUint8List();
  }

  /// 归一化二维码视觉留白：先裁剪内部 quiet-zone，再由外层容器统一留白。
  static Future<Uint8List> _buildNormalizedQrPngBytes(String qrData) async {
    try {
      final Uint8List sourcePngBytes = await _buildQrPngBytes(qrData);
      final ui.Image sourceImage = await _decodeImageFromBytes(sourcePngBytes);
      final ByteData? rgbaData = await sourceImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (rgbaData == null) {
        return sourcePngBytes;
      }

      final int width = sourceImage.width;
      final int height = sourceImage.height;
      int minX = width;
      int minY = height;
      int maxX = -1;
      int maxY = -1;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int pixelOffset = (y * width + x) * 4;
          final int r = rgbaData.getUint8(pixelOffset);
          final int g = rgbaData.getUint8(pixelOffset + 1);
          final int b = rgbaData.getUint8(pixelOffset + 2);
          final int a = rgbaData.getUint8(pixelOffset + 3);

          final bool isDarkPixel = a > 8 && (r + g + b) < (245 * 3);
          if (!isDarkPixel) {
            continue;
          }

          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }

      if (maxX < 0 || maxY < 0) {
        return sourcePngBytes;
      }

      final Rect sourceRect = Rect.fromLTRB(
        minX.toDouble(),
        minY.toDouble(),
        (maxX + 1).toDouble(),
        (maxY + 1).toDouble(),
      );
      final int targetSize = sourceRect.width > sourceRect.height
          ? sourceRect.width.ceil()
          : sourceRect.height.ceil();

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);

      final Rect destRect = Rect.fromLTWH(
        (targetSize - sourceRect.width) / 2,
        (targetSize - sourceRect.height) / 2,
        sourceRect.width,
        sourceRect.height,
      );
      canvas.drawImageRect(
        sourceImage,
        sourceRect,
        destRect,
        Paint()..filterQuality = FilterQuality.none,
      );

      final ui.Image normalizedImage = await recorder.endRecording().toImage(
        targetSize,
        targetSize,
      );
      final ByteData? normalizedPngData = await normalizedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (normalizedPngData == null) {
        return sourcePngBytes;
      }
      return normalizedPngData.buffer.asUint8List();
    } catch (_) {
      return _buildQrPngBytes(qrData);
    }
  }

  /// 将 PNG 字节解码为 UI Image，便于后续像素级裁剪处理。
  static Future<ui.Image> _decodeImageFromBytes(Uint8List bytes) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image image) {
      if (!completer.isCompleted) {
        completer.complete(image);
      }
    });
    return completer.future;
  }

  /// 捕获分享预览卡片整图，失败时回退为纯二维码图。
  static Future<Uint8List> _buildSharePreviewPngBytes({
    required GlobalKey previewBoundaryKey,
    required String fallbackQrData,
  }) async {
    try {
      final BuildContext? boundaryContext = previewBoundaryKey.currentContext;
      final RenderObject? renderObject = boundaryContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        return _buildQrPngBytes(fallbackQrData);
      }

      final ui.Image image = await renderObject.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        return _buildQrPngBytes(fallbackQrData);
      }
      return byteData.buffer.asUint8List();
    } catch (_) {
      return _buildQrPngBytes(fallbackQrData);
    }
  }

  /// 将标题文本转为文件名安全字符串，避免系统非法字符导致保存失败。
  static String _toSafeFileName(String raw) {
    final String trimmed = raw.trim();
    final String source = trimmed.isEmpty ? 'dormdevise_qr' : trimmed;
    return source.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }
}

/// 分享面板上的单个动作按钮。
class _QrShareActionButton extends StatelessWidget {
  const _QrShareActionButton({
    required this.icon,
    required this.iconBackground,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircleAvatar(
                radius: 24,
                backgroundColor: iconBackground,
                foregroundColor: Colors.white,
                child: Icon(icon, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 定向分享目标应用。
enum _DirectShareTarget {
  wechat('微信', 'com.tencent.mm'),
  qq('QQ', 'com.tencent.mobileqq');

  const _DirectShareTarget(this.label, this.packageName);

  final String label;
  final String packageName;
}

/// 分享预览卡片，右上角使用 DormDevise 品牌图。
class _QrSharePreviewCard extends StatelessWidget {
  const _QrSharePreviewCard({
    required this.previewBoundaryKey,
    required this.qrImageBytes,
    required this.qrProjectLabel,
    required this.shareInfoText,
    required this.displayName,
    required this.avatarPath,
  });

  final GlobalKey previewBoundaryKey;
  final Uint8List qrImageBytes;
  final String qrProjectLabel;
  final String shareInfoText;
  final String displayName;
  final String avatarPath;

  /// 为连续英文/数字注入零宽断行点，避免无法自然换行导致文本被裁切。
  String _injectSoftBreakForAlphaNumeric(String text) {
    return text.replaceAllMapped(RegExp(r'[A-Za-z0-9_]{8,}'), (Match match) {
      final String token = match.group(0)!;
      return token.split('').join('\u200B');
    });
  }

  /// 按宽度与字符长度动态缩小字号，优先保证两行内可读且无省略号。
  double _resolveAdaptiveFontSize({
    required double baseSize,
    required int charCount,
    required double maxWidth,
    required double minSize,
  }) {
    double size = baseSize;
    if (maxWidth < 150 || charCount > 10) {
      size = baseSize - 1;
    }
    if (maxWidth < 120 || charCount > 16) {
      size = baseSize - 2;
    }
    if (maxWidth < 96 || charCount > 24) {
      size = baseSize - 3;
    }
    if (size < minSize) {
      size = minSize;
    }
    return size;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final String projectLabel = qrProjectLabel.trim().isEmpty
        ? '二维码分享'
        : qrProjectLabel.trim();
    final String rightInfo = shareInfoText.trim().isEmpty
        ? kPersonShareInfoText
        : shareInfoText.trim();
    const double qrFrameSize = 240;
    const double qrOuterPadding = 8;

    final TextStyle projectLabelStyle =
        (Theme.of(context).textTheme.titleSmall ??
                const TextStyle(fontSize: 14))
            .copyWith(
              fontSize:
                  ((Theme.of(context).textTheme.titleSmall?.fontSize ?? 14) +
                  2),
              fontWeight: FontWeight.w700,
            );
    final TextStyle nicknameStyle =
        (Theme.of(context).textTheme.bodyMedium ??
                const TextStyle(fontSize: 14))
            .copyWith(
              fontSize:
                  ((Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14) +
                  2),
              fontWeight: FontWeight.w600,
            );
    final TextStyle shareInfoStyle =
        (Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12))
            .copyWith(
              fontSize:
                  ((Theme.of(context).textTheme.bodySmall?.fontSize ?? 12) + 2),
              color: colorScheme.onSurfaceVariant,
            );

    return RepaintBoundary(
      key: previewBoundaryKey,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Image.asset(
                    kShareAppIconAsset,
                    width: 28,
                    height: 28,
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      projectLabel,
                      textAlign: TextAlign.left,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: projectLabelStyle,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  width: qrFrameSize,
                  height: qrFrameSize,
                  padding: const EdgeInsets.all(qrOuterPadding),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Image.memory(
                    qrImageBytes,
                    width: qrFrameSize - qrOuterPadding * 2,
                    height: qrFrameSize - qrOuterPadding * 2,
                    fit: BoxFit.fill,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    flex: 6,
                    child: Row(
                      children: <Widget>[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: _ShareAvatarImage(path: avatarPath),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (
                              BuildContext context,
                              BoxConstraints constraints,
                            ) {
                              final String safeDisplayName =
                                  _injectSoftBreakForAlphaNumeric(displayName);
                              final double adaptiveNicknameFontSize =
                                  _resolveAdaptiveFontSize(
                                    baseSize: nicknameStyle.fontSize ?? 16,
                                    charCount: displayName.runes.length,
                                    maxWidth: constraints.maxWidth,
                                    minSize: 11,
                                  );
                              return Text(
                                safeDisplayName,
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.visible,
                                style: nicknameStyle.copyWith(
                                  fontSize: adaptiveNicknameFontSize,
                                  height: 1.15,
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 5,
                    child: LayoutBuilder(
                      builder: (
                        BuildContext context,
                        BoxConstraints constraints,
                      ) {
                        final String safeRightInfo =
                            _injectSoftBreakForAlphaNumeric(rightInfo);
                        final double adaptiveShareInfoFontSize =
                            _resolveAdaptiveFontSize(
                              baseSize: shareInfoStyle.fontSize ?? 14,
                              charCount: rightInfo.runes.length,
                              maxWidth: constraints.maxWidth,
                              minSize: 10,
                            );
                        return Text(
                          safeRightInfo,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          softWrap: true,
                          overflow: TextOverflow.visible,
                          style: shareInfoStyle.copyWith(
                            fontSize: adaptiveShareInfoFontSize,
                            height: 1.15,
                          ),
                        );
                      },
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

/// 分享卡头像组件：优先本地文件，失败时回退默认资产头像。
class _ShareAvatarImage extends StatelessWidget {
  const _ShareAvatarImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final String normalized = path.trim();
    final bool isLikelyLocalFilePath =
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized);
    if (isLikelyLocalFilePath) {
      return Image.file(
        File(normalized),
        width: 36,
        height: 36,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Image.asset(
          kPersonAvatarAsset,
          width: 36,
          height: 36,
          fit: BoxFit.cover,
        ),
      );
    }

    return Image.asset(
      normalized.isEmpty ? kPersonAvatarAsset : normalized,
      width: 36,
      height: 36,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Image.asset(
        kPersonAvatarAsset,
        width: 36,
        height: 36,
        fit: BoxFit.cover,
      ),
    );
  }
}
