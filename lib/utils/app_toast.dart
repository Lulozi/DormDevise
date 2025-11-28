import 'dart:async';

import 'package:flutter/material.dart';

/// 全局轻量浮层提示工具，负责在应用内展示通知。
class AppToast {
  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  /// 显示带有不同状态样式的提示信息。
  static void show(
    BuildContext context,
    String message, {
    AppToastVariant variant = AppToastVariant.info,
    LayerLink? anchorLink,
    Offset? anchorOffset,
    Alignment targetAnchor = Alignment.topCenter,
    Alignment followerAnchor = Alignment.bottomCenter,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _activeTimer?.cancel();
    _activeEntry?.remove();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    late final Color accentColor;
    late final Color backgroundColor;
    late final Color borderColor;
    late final IconData icon;
    late final Duration displayDuration;

    switch (variant) {
      case AppToastVariant.success:
        accentColor = colors.tertiary;
        backgroundColor = colors.tertiaryContainer;
        borderColor = colors.tertiary.withAlpha(51); // 0.2 * 255 ≈ 51
        icon = Icons.check_circle_outline;
        displayDuration = const Duration(milliseconds: 2600);
        break;
      case AppToastVariant.warning:
        accentColor = colors.secondary;
        backgroundColor = colors.secondaryContainer;
        borderColor = colors.secondary.withAlpha(51);
        icon = Icons.info_outline;
        displayDuration = const Duration(milliseconds: 3200);
        break;
      case AppToastVariant.error:
        accentColor = colors.error;
        backgroundColor = colors.errorContainer;
        borderColor = colors.error.withAlpha(51);
        icon = Icons.error_outline;
        displayDuration = const Duration(milliseconds: 3600);
        break;
      case AppToastVariant.info:
        accentColor = colors.primary;
        backgroundColor = colors.primaryContainer;
        borderColor = colors.primary.withAlpha(51);
        icon = Icons.info_outline;
        displayDuration = const Duration(milliseconds: 2800);
        break;
    }
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: accentColor,
      fontWeight: FontWeight.w500,
    );

    final entry = OverlayEntry(
      builder: (entryContext) {
        final toastWidget = TweenAnimationBuilder<double>(
          tween: Tween(begin: 16, end: 0),
          duration: const Duration(milliseconds: 220),
          builder: (context, value, child) {
            return Transform.translate(offset: Offset(0, value), child: child);
          },
          child: Material(
            color: Colors.transparent,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: borderColor, width: 1.4),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 14,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(icon, color: accentColor, size: 20),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        message,
                        style: textStyle,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        if (anchorLink != null) {
          return Positioned(
            width: MediaQuery.of(context).size.width,
            child: CompositedTransformFollower(
              link: anchorLink,
              targetAnchor: targetAnchor,
              followerAnchor: followerAnchor,
              offset: anchorOffset ?? Offset.zero,
              child: IgnorePointer(
                ignoring: true,
                child: Align(alignment: Alignment.center, child: toastWidget),
              ),
            ),
          );
        }

        final mediaQuery = MediaQuery.of(entryContext);
        final bottomPadding = mediaQuery.viewPadding.bottom;
        final navTheme = NavigationBarTheme.of(entryContext);
        final navHeight = navTheme.height ?? kBottomNavigationBarHeight;
        final bottomGap = bottomPadding + navHeight + 24;
        return IgnorePointer(
          ignoring: true,
          child: SafeArea(
            left: false,
            top: false,
            right: false,
            minimum: EdgeInsets.only(bottom: bottomGap),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: toastWidget,
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    _activeEntry = entry;
    _activeTimer = Timer(displayDuration, () {
      entry.remove();
      if (identical(_activeEntry, entry)) {
        _activeEntry = null;
        _activeTimer = null;
      }
    });
  }

  /// 立即关闭当前正在显示的提示。
  static void dismiss() {
    _activeTimer?.cancel();
    _activeEntry?.remove();
    _activeTimer = null;
    _activeEntry = null;
  }
}

enum AppToastVariant { info, success, warning, error }
