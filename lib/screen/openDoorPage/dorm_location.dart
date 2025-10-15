import 'package:flutter/material.dart';

class ConfigLocationPage extends StatefulWidget {
  const ConfigLocationPage({super.key});

  @override
  State<ConfigLocationPage> createState() => _ConfigLocationPage();
}

class _ConfigLocationPage extends State<ConfigLocationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('定位设置')),
      // 使用高德api，需要用户自行设置
      // 需要显示用户设置的位置反馈给用户，并显示一个范围这个范围为50米
      // 创建一个按钮，点击后可以打开地图选择宿舍位置并保存这个位置
      // 再创建一个按钮，设置高德api key
    );
  }
}
