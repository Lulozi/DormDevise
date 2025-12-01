import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dormdevise/utils/app_toast.dart';

class DownloadSourceConfigPage extends StatefulWidget {
  const DownloadSourceConfigPage({super.key});

  @override
  State<DownloadSourceConfigPage> createState() =>
      _DownloadSourceConfigPageState();
}

class _DownloadSourceConfigPageState extends State<DownloadSourceConfigPage> {
  String _sourceType = 'auto';
  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _downloadUrlController = TextEditingController();
  bool _isLoading = true;
  bool _advancedExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sourceType = prefs.getString('update_source_type') ?? 'auto';
      _apiUrlController.text = prefs.getString('custom_update_api_url') ?? '';
      final downloadUrl = prefs.getString('custom_download_url_pattern') ?? '';
      _downloadUrlController.text = downloadUrl;
      _advancedExpanded = downloadUrl.isNotEmpty;
      _isLoading = false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('update_source_type', _sourceType);
    await prefs.setString('custom_update_api_url', _apiUrlController.text);
    await prefs.setString(
      'custom_download_url_pattern',
      _downloadUrlController.text,
    );
    if (mounted) {
      AppToast.show(context, '设置已保存');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final colorScheme = Theme.of(context).colorScheme;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.primary, width: 2),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('下载源配置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRadioItem('自动', 'auto'),
          _buildRadioItem('GitHub', 'github'),
          _buildRadioItem('Gitee', 'gitee'),
          _buildRadioItem('自定义', 'custom'),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1.0,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _sourceType == 'custom'
                ? Column(
                    key: const ValueKey('custom_api_input'),
                    children: [
                      const SizedBox(height: 16),
                      TextField(
                        controller: _apiUrlController,
                        decoration: InputDecoration(
                          labelText: '自定义 API 地址',
                          hintText: '例如: https://api.github.com/repos/...',
                          border: inputBorder,
                          enabledBorder: inputBorder,
                          focusedBorder: focusedBorder,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('empty')),
          ),
          const SizedBox(height: 24),
          const Divider(),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8),
            title: Text('高级设置', style: Theme.of(context).textTheme.titleMedium),
            trailing: AnimatedRotation(
              turns: _advancedExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.keyboard_arrow_down),
            ),
            onTap: () {
              setState(() {
                _advancedExpanded = !_advancedExpanded;
              });
            },
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                axisAlignment: -1.0,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _advancedExpanded
                ? Column(
                    key: const ValueKey('advanced_settings'),
                    children: [
                      const SizedBox(height: 8),
                      TextField(
                        controller: _downloadUrlController,
                        decoration: InputDecoration(
                          labelText: '自定义下载路径 (镜像加速)',
                          hintText: '支持变量: \$sanitizedName',
                          helperText: '留空则使用源地址。若填写，将优先选择最快的下载链接。',
                          border: inputBorder,
                          enabledBorder: inputBorder,
                          focusedBorder: focusedBorder,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('advanced_empty')),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _saveConfig,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Widget _buildRadioItem(String title, String value) {
    return RadioListTile<String>(
      title: Text(title),
      value: value,
      groupValue: _sourceType,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onChanged: (newValue) {
        setState(() {
          _sourceType = newValue!;
        });
      },
    );
  }
}
