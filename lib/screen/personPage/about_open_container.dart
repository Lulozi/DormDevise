import 'package:flutter/material.dart';
import 'package:animations/animations.dart';

/// 关于按钮的丝巾动画容器
class AboutOpenContainer extends StatelessWidget {
  final String version;
  const AboutOpenContainer({super.key, required this.version});

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
        leading: const Icon(Icons.info, color: Colors.deepPurple),
        title: const Text('关于', style: TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right),
        onTap: openContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: colorScheme.surfaceContainerHighest,
      ),
      openBuilder: (context, _) => AboutPage(version: version),
    );
  }
}

class AboutPage extends StatelessWidget {
  final String version;
  const AboutPage({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/app_icon.png', width: 80, height: 80),
            const SizedBox(height: 16),
            const Text(
              '舍设',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('版本 $version', style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            const Text(
              '© 2025 DormDevise. All rights reserved.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
