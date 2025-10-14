import 'package:flutter/material.dart';
import 'package:animations/animations.dart';
import 'config_mtqq.dart';

/// 用于包裹MQTT设置按钮，实现Material3风格的丝巾展开动画
class MqttSettingsOpenContainer extends StatelessWidget {
  const MqttSettingsOpenContainer({super.key});

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
        leading: const Icon(Icons.settings, color: Colors.blueAccent),
        title: const Text(
          'MQTT配置',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: openContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: colorScheme.surfaceContainerHighest,
      ),
      openBuilder: (context, _) => const ConfigMqttPage(),
    );
  }
}
