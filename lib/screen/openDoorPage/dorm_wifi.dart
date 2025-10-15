import 'package:flutter/material.dart';

class ConfigWifiPage extends StatefulWidget {
  const ConfigWifiPage({super.key});

  @override
  State<ConfigWifiPage> createState() => _ConfigWifiPage();
}

class _ConfigWifiPage extends State<ConfigWifiPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wifi设置')),
      // 用户添加设置wifi名称的设置，让用户可以选择搜索到的wifi，也运行用户自主添加
      // 检测用户的wifi，检测到匹配的wifi显示出来告知用户
    );
  }
}
