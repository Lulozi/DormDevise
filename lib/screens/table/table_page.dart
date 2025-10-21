import 'package:flutter/material.dart';

/// 课表页面占位符，后续将承载课程数据。
class TablePage extends StatefulWidget {
  const TablePage({super.key});

  /// 创建页面状态以渲染占位内容。
  @override
  State<TablePage> createState() => _TablePageState();
}

class _TablePageState extends State<TablePage> {
  /// 构建课表页面的基本占位界面。
  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Center(child: Text('Table Page')));
  }
}
