import 'package:animations/animations.dart';
import 'package:flutter/material.dart';

/// 通用的平滑展开动画容器，用于承载各类设置入口。
class SettingsOpenContainer extends StatelessWidget {
  final IconData icon;
  final String title;
  final WidgetBuilder pageBuilder;
  final Color? iconColor;

  const SettingsOpenContainer({
    super.key,
    required this.icon,
    required this.title,
    required this.pageBuilder,
    this.iconColor,
  });

  /// 构建带有 Material motion 动画的设置入口卡片。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OpenContainer(
      transitionType: ContainerTransitionType.fadeThrough,
      openColor: colorScheme.surface,
      closedColor: colorScheme.surfaceContainerHighest,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      openShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      transitionDuration: const Duration(milliseconds: 600),
      closedBuilder: (context, openContainer) => ListTile(
        leading: Icon(icon, color: iconColor ?? colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right),
        onTap: openContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: colorScheme.surfaceContainerHighest,
      ),
      openBuilder: (context, _) => pageBuilder(context),
    );
  }
}
