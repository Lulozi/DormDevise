import 'package:flutter/material.dart';

/// 定位配置占位页，后续将补充真实功能。
class LocationSettingsPage extends StatefulWidget {
  const LocationSettingsPage({super.key, this.showAppBar = true});

  /// 控制是否渲染顶部 AppBar。
  final bool showAppBar;

  /// 创建状态对象以渲染基础提示界面。
  @override
  State<LocationSettingsPage> createState() => _LocationSettingsPageState();
}

class _LocationSettingsPageState extends State<LocationSettingsPage> {
  /// 构建简单的占位页面内容。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('定位设置')) : null,
      body: const Center(child: Text('定位设置功能开发中...')),
    );
  }
}
