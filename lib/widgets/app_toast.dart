import 'dart:async';

import 'package:flutter/material.dart';

enum AppToastVariant { info, success, warning, error }

class AppToast {
  static OverlayEntry? _activeEntry;
  static Timer? _activeTimer;

  static void show(
    BuildContext context,
    String message, {
    AppToastVariant variant = AppToastVariant.info,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);

    _activeTimer?..cancel();
    _activeEntry?..remove();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    late final Color accentColor;
    late final IconData icon;
    late final Duration displayDuration;

    switch (variant) {
      case AppToastVariant.success:
        accentColor = colors.tertiary;
        icon = Icons.check_circle_outline;
        displayDuration = const Duration(milliseconds: 2600);
        break;
      case AppToastVariant.warning:
        accentColor = colors.secondary;
        icon = Icons.info_outline;
        displayDuration = const Duration(milliseconds: 3200);
        break;
      case AppToastVariant.error:
        accentColor = colors.error;
        icon = Icons.error_outline;
        displayDuration = const Duration(milliseconds: 3600);
        break;
      case AppToastVariant.info:
        accentColor = colors.primary;
        icon = Icons.info_outline;
        displayDuration = const Duration(milliseconds: 2800);
        break;
    }

    Color blend(Color a, Color b, double t) {
      return Color.lerp(a, b, t) ?? a;
    }

    final backgroundColor = blend(
      colors.surfaceContainerHighest,
      accentColor,
      0.12,
    );
    final borderColor = blend(
      accentColor,
      colors.surfaceContainerHighest,
      0.35,
    );
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: accentColor,
      fontWeight: FontWeight.w500,
    );

    final entry = OverlayEntry(
      builder: (entryContext) {
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
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 16, end: 0),
                  duration: const Duration(milliseconds: 220),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, value),
                      child: child,
                    );
                  },
                  child: Material(
                    color: Colors.transparent,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: backgroundColor,
                        borderRadius: BorderRadius.circular(18),
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
                ),
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

  static void dismiss() {
    _activeTimer?..cancel();
    _activeEntry?..remove();
    _activeTimer = null;
    _activeEntry = null;
  }
}
