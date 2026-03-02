import 'package:flutter/material.dart';

/// 扫码导入课表页面。
class ScanImportSchedulePage extends StatelessWidget {
  const ScanImportSchedulePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('扫码导入课表')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.qr_code_scanner, size: 56, color: colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              '扫码导入功能开发中',
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
