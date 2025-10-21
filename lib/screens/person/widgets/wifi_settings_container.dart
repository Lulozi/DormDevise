import 'package:animations/animations.dart';
import 'package:dormdevise/screens/open_door/wifi_settings_page.dart';
import 'package:flutter/material.dart';

/// 用于包裹WiFi设置按钮，实现Material3风格的丝巾展开动画
class WifiSettingsContainer extends StatelessWidget {
  const WifiSettingsContainer({super.key});

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
        leading: const Icon(Icons.wifi, color: Colors.blueAccent),
        title: const Text(
          'WiFi设置',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: openContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: colorScheme.surfaceContainerHighest,
      ),
      openBuilder: (context, _) => const WifiSettingsPage(),
    );
  }
}
