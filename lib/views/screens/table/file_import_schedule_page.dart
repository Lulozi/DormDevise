import 'package:flutter/material.dart';

/// 文件导入课表页面。
class FileImportSchedulePage extends StatelessWidget {
  const FileImportSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('文件导入课表')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.folder_open, size: 56, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              '文件导入功能开发中',
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
