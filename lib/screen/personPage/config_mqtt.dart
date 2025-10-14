import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../openDoorPage/mqtt_client.dart';

class ConfigMqttPage extends StatefulWidget {
  const ConfigMqttPage({super.key});

  @override
  State<ConfigMqttPage> createState() => _ConfigMqttPageState();
}

class _ConfigMqttPageState extends State<ConfigMqttPage> {
  final List<String> _logLines = [];
  // 配置变量
  String _host = '';
  String _port = '1883';
  String _topic = '';
  String _clientId = '';
  String _username = '';
  String _password = '';
  String _caPath = 'assets/certs/ca.pem';
  String _certPath = '';
  String _keyPath = '';
  String _keyPwd = '';
  bool _withTls = false;
  String _customMsg = 'OPEN';

  // controller 只在变量变更时重建，避免 labelText 闪烁
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _topicController;
  late TextEditingController _clientIdController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _caPathController;
  late TextEditingController _certPathController;
  late TextEditingController _keyPathController;
  late TextEditingController _keyPwdController;
  late TextEditingController _customMsgController;

  void _showBubble(BuildContext context, String msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  bool _sending = false;
  bool _loading = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _initAndLoadConfig();
  }

  Future<void> _initAndLoadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    String? cid = prefs.getString('mqtt_clientId');
    if (cid == null || cid.isEmpty) {
      cid = const Uuid().v4();
      await prefs.setString('mqtt_clientId', cid);
    }
    await _loadConfig(defaultClientId: cid);
  }

  Future<void> _loadConfig({String? defaultClientId}) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _host = prefs.getString('mqtt_host') ?? '';
      _port = prefs.getString('mqtt_port') ?? '1883';
      _topic = prefs.getString('mqtt_topic') ?? '';
      _username = prefs.getString('mqtt_username') ?? '';
      _password = prefs.getString('mqtt_password') ?? '';
      _clientId = prefs.getString('mqtt_clientId') ?? (defaultClientId ?? '');
      _caPath = prefs.getString('mqtt_ca') ?? 'assets/certs/ca.pem';
      _certPath = prefs.getString('mqtt_cert') ?? '';
      _keyPath = prefs.getString('mqtt_key') ?? '';
      _keyPwd = prefs.getString('mqtt_key_pwd') ?? '';
      _withTls = prefs.getBool('mqtt_with_tls') ?? false;
      _customMsg = 'OPEN';
      // 重新创建 controller
      _hostController = TextEditingController(text: _host);
      _portController = TextEditingController(text: _port);
      _topicController = TextEditingController(text: _topic);
      _clientIdController = TextEditingController(text: _clientId);
      _usernameController = TextEditingController(text: _username);
      _passwordController = TextEditingController(text: _password);
      _caPathController = TextEditingController(text: _caPath);
      _certPathController = TextEditingController(text: _certPath);
      _keyPathController = TextEditingController(text: _keyPath);
      _keyPwdController = TextEditingController(text: _keyPwd);
      _customMsgController = TextEditingController(text: _customMsg);
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_host', _hostController.text);
    await prefs.setString('mqtt_port', _portController.text);
    await prefs.setString('mqtt_topic', _topicController.text);
    await prefs.setString('mqtt_clientId', _clientIdController.text);
    await prefs.setString('mqtt_username', _usernameController.text);
    await prefs.setString('mqtt_password', _passwordController.text);
    await prefs.setString('mqtt_ca', _caPathController.text);
    await prefs.setString('mqtt_cert', _certPathController.text);
    await prefs.setString('mqtt_key', _keyPathController.text);
    await prefs.setString('mqtt_key_pwd', _keyPwdController.text);
    await prefs.setBool('mqtt_with_tls', _withTls);
    if (!mounted) return;
    setState(() {
      _status = '配置已保存';
      // setState 里同步调用 _showBubble，context 不跨异步
      _showBubble(context, '配置已保存');
    });
  }

  Future<void> _exportConfig() async {
    final config = {
      'mqtt_host': _hostController.text,
      'mqtt_port': _portController.text,
      'mqtt_topic': _topicController.text,
      'mqtt_username': _usernameController.text,
      'mqtt_password': _passwordController.text,
      'mqtt_ca': _caPathController.text,
      'mqtt_cert': _certPathController.text,
      'mqtt_key': _keyPathController.text,
      'mqtt_key_pwd': _keyPwdController.text,
      'mqtt_with_tls': _withTls,
      // 不导出 clientId/uuid
    };
    final jsonStr = JsonEncoder.withIndent('  ').convert(config);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    setState(() {
      _status = '配置已导出到剪贴板';
    });
    _showBubble(context, '配置已导出到剪贴板\n\n$jsonStr');
  }

  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _status = '剪贴板内容为空';
      });
      _showBubble(context, '剪贴板内容为空');
      return;
    }
    try {
      final map = jsonDecode(data.text!);
      if (map is! Map) throw Exception('格式错误');
      setState(() {
        _host = map['mqtt_host'] ?? '';
        _port = map['mqtt_port'] ?? '1883';
        _topic = map['mqtt_topic'] ?? '';
        _username = map['mqtt_username'] ?? '';
        _password = map['mqtt_password'] ?? '';
        _caPath = map['mqtt_ca'] ?? 'assets/certs/ca.pem';
        _certPath = map['mqtt_cert'] ?? '';
        _keyPath = map['mqtt_key'] ?? '';
        _keyPwd = map['mqtt_key_pwd'] ?? '';
        _withTls = map['mqtt_with_tls'] ?? false;
        _status = '配置已从剪贴板导入';
        // 重新创建 controller
        _hostController = TextEditingController(text: _host);
        _portController = TextEditingController(text: _port);
        _topicController = TextEditingController(text: _topic);
        _usernameController = TextEditingController(text: _username);
        _passwordController = TextEditingController(text: _password);
        _caPathController = TextEditingController(text: _caPath);
        _certPathController = TextEditingController(text: _certPath);
        _keyPathController = TextEditingController(text: _keyPath);
        _keyPwdController = TextEditingController(text: _keyPwd);
      });
      // 只保存配置到本地，不弹“配置已保存”弹窗
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mqtt_host', _host);
      await prefs.setString('mqtt_port', _port);
      await prefs.setString('mqtt_topic', _topic);
      await prefs.setString('mqtt_username', _username);
      await prefs.setString('mqtt_password', _password);
      await prefs.setString('mqtt_ca', _caPath);
      await prefs.setString('mqtt_cert', _certPath);
      await prefs.setString('mqtt_key', _keyPath);
      await prefs.setString('mqtt_key_pwd', _keyPwd);
      await prefs.setBool('mqtt_with_tls', _withTls);
      final importStr = JsonEncoder.withIndent('  ').convert(map);
      if (!mounted) return;
      _showBubble(context, '配置已从剪贴板导入\n\n$importStr\n\n点击确定保存配置');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '导入失败: $e';
      });
      _showBubble(context, '导入失败: $e');
    }
  }

  Future<void> _pickFile(
    TextEditingController controller, {
    String? dialogTitle,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: dialogTitle,
    );
    if (result != null && result.files.single.path != null) {
      setState(() {
        controller.text = result.files.single.path!;
      });
    }
  }

  Future<void> _testConnect() async {
    setState(() {
      _loading = true;
      _status = '正在连接...';
    });
    try {
      SecurityContext? sc;
      if (_withTls) {
        sc = await buildSecurityContext(
          caAsset: _caPathController.text,
          clientCertAsset: _certPathController.text.isNotEmpty
              ? _certPathController.text
              : null,
          clientKeyAsset: _keyPathController.text.isNotEmpty
              ? _keyPathController.text
              : null,
          clientKeyPassword: _keyPwdController.text.isNotEmpty
              ? _keyPwdController.text
              : null,
        );
      }
      final service = MqttService(
        host: _hostController.text,
        port: int.tryParse(_portController.text) ?? 1883,
        clientId: _clientIdController.text.isNotEmpty
            ? _clientIdController.text
            : 'flutter_client',
        username: _usernameController.text.isNotEmpty
            ? _usernameController.text
            : null,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        securityContext: sc,
        log: (msg) {
          debugPrint(msg);
          setState(() {
            _logLines.add(msg);
            if (_logLines.length > 200) _logLines.removeAt(0);
          });
        },
        onError: (e, [st]) {
          debugPrint('MQTT error: $e');
          setState(() {
            _logLines.add('MQTT error: $e');
            if (_logLines.length > 200) _logLines.removeAt(0);
          });
        },
      );
      await service.connect();
      // 自动订阅主题
      final topic = _topicController.text.trim();
      if (topic.isNotEmpty) {
        await service.subscribe(topic);
      }
      if (!mounted) return;
      setState(() {
        _status = '连接成功';
      });
      _showBubble(context, '连接成功');
      await service.dispose();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = '连接失败: $e';
        _logLines.add('连接失败: $e');
        if (_logLines.length > 200) _logLines.removeAt(0);
      });
      _showBubble(context, '连接失败: $e');
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _topicController.dispose();
    _clientIdController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _caPathController.dispose();
    _certPathController.dispose();
    _keyPathController.dispose();
    _keyPwdController.dispose();
    _customMsgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT配置'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded),
            tooltip: '查看MQTT连接情况',
            onPressed: () {
              final info = StringBuffer();
              info.writeln(
                '服务器: ${_hostController.text}:${_portController.text}',
              );
              info.writeln('Client ID: ${_clientIdController.text}');
              info.writeln('用户名: ${_usernameController.text}');
              info.writeln('主题: ${_topicController.text}');
              info.writeln('TLS: ${_withTls ? '启用' : '未启用'}');
              String statusText;
              if (_status.contains('连接成功') || _status.contains('订阅连接')) {
                statusText = '已连接，已订阅';
              } else if (_status.contains('消息已发送')) {
                statusText = '已连接，消息已发送';
              } else if (_status.contains('连接失败')) {
                statusText = '连接失败';
              } else if (_status.contains('发送失败')) {
                statusText = '发送失败';
              } else if (_status.contains('正在连接')) {
                statusText = '正在连接...';
              } else {
                statusText = _status.isNotEmpty ? _status : '未知';
              }
              info.writeln('连接状态: $statusText');
              _showBubble(context, info.toString());
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      TextField(
                        key: const ValueKey('host'),
                        controller: _hostController,
                        decoration: InputDecoration(
                          labelText: '服务器地址',
                          border: inputBorder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('port'),
                        controller: _portController,
                        decoration: InputDecoration(
                          labelText: '端口',
                          border: inputBorder,
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('topic'),
                        controller: _topicController,
                        decoration: InputDecoration(
                          labelText: '主题',
                          border: inputBorder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('username'),
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: '用户名',
                          border: inputBorder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('password'),
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: '密码',
                          border: inputBorder,
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('clientId'),
                        controller: _clientIdController,
                        decoration: InputDecoration(
                          labelText: 'Client ID (默认使用UUID)',
                          border: inputBorder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile(
                        title: const Text('启用TLS/SSL'),
                        value: _withTls,
                        onChanged: (v) => setState(() => _withTls = v),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        tileColor: colorScheme.surface,
                        contentPadding: EdgeInsets.zero,
                      ),
                      if (_withTls) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _pickFile(
                            _caPathController,
                            dialogTitle: '选择CA证书',
                          ),
                          child: AbsorbPointer(
                            child: TextField(
                              key: const ValueKey('caPath'),
                              controller: _caPathController,
                              decoration: InputDecoration(
                                labelText: 'CA证书路径',
                                border: inputBorder,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _pickFile(
                            _certPathController,
                            dialogTitle: '选择客户端证书',
                          ),
                          child: AbsorbPointer(
                            child: TextField(
                              key: const ValueKey('certPath'),
                              controller: _certPathController,
                              decoration: InputDecoration(
                                labelText: '客户端证书路径(可选)',
                                border: inputBorder,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _pickFile(
                            _keyPathController,
                            dialogTitle: '选择客户端私钥',
                          ),
                          child: AbsorbPointer(
                            child: TextField(
                              key: const ValueKey('keyPath'),
                              controller: _keyPathController,
                              decoration: InputDecoration(
                                labelText: '客户端私钥路径(可选)',
                                border: inputBorder,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('keyPwd'),
                          controller: _keyPwdController,
                          decoration: InputDecoration(
                            labelText: '私钥密码(可选)',
                            border: inputBorder,
                          ),
                          obscureText: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _loading ? null : _saveConfig,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('保存配置'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _loading ? null : _testConnect,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('订阅连接'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _exportConfig,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('导出配置'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _loading ? null : _importConfigFromClipboard,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('导入配置'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Card(
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _customMsgController,
                          decoration: InputDecoration(
                            labelText: '自定义发送消息',
                            hintText: '输入mqtt接收开门的消息',
                            border: inputBorder,
                          ),
                          minLines: 1,
                          maxLines: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 40,
                        child: FilledButton(
                          onPressed: _sending
                              ? null
                              : () async {
                                  final msg = _customMsgController.text.trim();
                                  if (msg.isEmpty) return;
                                  setState(() {
                                    _sending = true;
                                    _status = '正在发送...';
                                  });
                                  try {
                                    SecurityContext? sc;
                                    if (_withTls) {
                                      sc = await buildSecurityContext(
                                        caAsset: _caPathController.text,
                                        clientCertAsset:
                                            _certPathController.text.isNotEmpty
                                            ? _certPathController.text
                                            : null,
                                        clientKeyAsset:
                                            _keyPathController.text.isNotEmpty
                                            ? _keyPathController.text
                                            : null,
                                        clientKeyPassword:
                                            _keyPwdController.text.isNotEmpty
                                            ? _keyPwdController.text
                                            : null,
                                      );
                                    }
                                    final service = MqttService(
                                      host: _hostController.text,
                                      port:
                                          int.tryParse(_portController.text) ??
                                          1883,
                                      clientId:
                                          _clientIdController.text.isNotEmpty
                                          ? _clientIdController.text
                                          : 'flutter_client',
                                      username:
                                          _usernameController.text.isNotEmpty
                                          ? _usernameController.text
                                          : null,
                                      password:
                                          _passwordController.text.isNotEmpty
                                          ? _passwordController.text
                                          : null,
                                      securityContext: sc,
                                      log: (msg) => debugPrint(msg),
                                      onError: (e, [st]) =>
                                          debugPrint('MQTT error: $e'),
                                    );
                                    await service.connect();
                                    final topic = _topicController.text.trim();
                                    if (topic.isEmpty) {
                                      throw Exception('Topic不能为空');
                                    }
                                    await service.publishText(topic, msg);
                                    setState(() {
                                      _status = '消息已发送';
                                    });
                                    await service.dispose();
                                  } catch (e) {
                                    setState(() {
                                      _status = '发送失败: $e';
                                    });
                                  } finally {
                                    setState(() {
                                      _sending = false;
                                    });
                                  }
                                },
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          child: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('测试发送'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  color: _status.contains('成功') ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Container(
                    height: 120,
                    padding: const EdgeInsets.all(8),
                    child: ListView(
                      children:
                          (_logLines.length > 20
                                  ? _logLines.sublist(_logLines.length - 20)
                                  : _logLines)
                              .map(
                                (e) => Text(
                                  e,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              )
                              .toList(),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
