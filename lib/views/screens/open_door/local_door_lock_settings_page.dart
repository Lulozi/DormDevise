import 'package:flutter/material.dart';

/// 本地门锁配置页面（占位）
class LocalDoorLockSettingsPage extends StatelessWidget {
  const LocalDoorLockSettingsPage({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: showAppBar ? AppBar(title: const Text('本地门锁配置')) : null,
      body: const Center(child: Text('功能开发中...')),
    );
  }
}
