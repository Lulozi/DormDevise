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

  final _customMsgController = TextEditingController();
  bool _sending = false;
  final _hostController = TextEditingController();
  final _portController = TextEditingController(text: '1883');
  final _topicController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _caPathController = TextEditingController(text: 'assets/certs/ca.pem');
  final _certPathController = TextEditingController();
  final _keyPathController = TextEditingController();
  final _keyPwdController = TextEditingController();
  bool _withTls = false;
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
      _hostController.text = prefs.getString('mqtt_host') ?? '';
      _portController.text = prefs.getString('mqtt_port') ?? '1883';
      _topicController.text = prefs.getString('mqtt_topic') ?? '';
      _usernameController.text = prefs.getString('mqtt_username') ?? '';
      _passwordController.text = prefs.getString('mqtt_password') ?? '';
      _clientIdController.text =
          prefs.getString('mqtt_clientId') ?? (defaultClientId ?? '');
      _caPathController.text =
          prefs.getString('mqtt_ca') ?? 'assets/certs/ca.pem';
      _certPathController.text = prefs.getString('mqtt_cert') ?? '';
      _keyPathController.text = prefs.getString('mqtt_key') ?? '';
      _keyPwdController.text = prefs.getString('mqtt_key_pwd') ?? '';
      _withTls = prefs.getBool('mqtt_with_tls') ?? false;
      _customMsgController.text = 'OPEN';
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
    setState(() {
      _status = '配置已保存';
    });
    _showBubble(context, '配置已保存');
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
    };
    final jsonStr = JsonEncoder.withIndent('  ').convert(config);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    setState(() {
      _status = '配置已导出到剪贴板';
    });
    _showBubble(context, '配置已导出到剪贴板\n\n$jsonStr');
  }

  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.trim().isEmpty) {
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
        _hostController.text = map['mqtt_host'] ?? '';
        _portController.text = map['mqtt_port'] ?? '1883';
        _topicController.text = map['mqtt_topic'] ?? '';
        _usernameController.text = map['mqtt_username'] ?? '';
        _passwordController.text = map['mqtt_password'] ?? '';
        _clientIdController.text =
            (map['mqtt_clientId'] != null &&
                (map['mqtt_clientId'] as String).isNotEmpty)
            ? map['mqtt_clientId']
            : const Uuid().v4();
        _caPathController.text = map['mqtt_ca'] ?? 'assets/certs/ca.pem';
        _certPathController.text = map['mqtt_cert'] ?? '';
        _keyPathController.text = map['mqtt_key'] ?? '';
        _keyPwdController.text = map['mqtt_key_pwd'] ?? '';
        _withTls = map['mqtt_with_tls'] ?? false;
        _status = '配置已从剪贴板导入';
      });
      await _saveConfig();
      final importStr = JsonEncoder.withIndent('  ').convert(map);
      _showBubble(context, '配置已从剪贴板导入\n\n$importStr');
    } catch (e) {
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
      controller.text = result.files.single.path!;
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
      setState(() {
        _status = '连接成功';
      });
      _showBubble(context, '连接成功');
      await service.dispose();
    } catch (e) {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('MQTT配置'),
        actions: [
          IconButton(
            icon: const Text(
              '≡',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
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
              // 实时判断连接状态
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
              TextField(
                controller: _hostController,
                decoration: const InputDecoration(labelText: '服务器地址'),
              ),
              TextField(
                controller: _portController,
                decoration: const InputDecoration(labelText: '端口'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _topicController,
                decoration: const InputDecoration(labelText: '主题'),
              ),
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              TextField(
                controller: _clientIdController,
                decoration: const InputDecoration(
                  labelText: 'Client ID (默认使用UUID)',
                ),
              ),
              SwitchListTile(
                title: const Text('启用TLS/SSL'),
                value: _withTls,
                onChanged: (v) => setState(() => _withTls = v),
              ),
              if (_withTls) ...[
                GestureDetector(
                  onTap: () =>
                      _pickFile(_caPathController, dialogTitle: '选择CA证书'),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _caPathController,
                      decoration: const InputDecoration(labelText: 'CA证书路径'),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      _pickFile(_certPathController, dialogTitle: '选择客户端证书'),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _certPathController,
                      decoration: const InputDecoration(
                        labelText: '客户端证书路径(可选)',
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      _pickFile(_keyPathController, dialogTitle: '选择客户端私钥'),
                  child: AbsorbPointer(
                    child: TextField(
                      controller: _keyPathController,
                      decoration: const InputDecoration(
                        labelText: '客户端私钥路径(可选)',
                      ),
                    ),
                  ),
                ),
                TextField(
                  controller: _keyPwdController,
                  decoration: const InputDecoration(labelText: '私钥密码(可选)'),
                  obscureText: true,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _saveConfig,
                      child: const Text('保存配置'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _testConnect,
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
                    child: ElevatedButton(
                      onPressed: _loading ? null : _exportConfig,
                      child: const Text('导出配置'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _loading ? null : _importConfigFromClipboard,
                      child: const Text('导入配置'),
                    ),
                  ),
                ],
              ),
              // 自定义消息发送框
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _customMsgController,
                      decoration: const InputDecoration(
                        labelText: '自定义消息',
                        hintText: '输入要发送的消息',
                      ),
                      minLines: 1,
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton(
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
                                  log: (msg) => debugPrint(msg),
                                  onError: (e, [st]) =>
                                      debugPrint('MQTT error: $e'),
                                );
                                await service.connect();
                                final topic = _topicController.text.trim();
                                if (topic.isEmpty) {
                                  throw Exception('Topic不能为空');
                                }
                                // 发送纯文本消息
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
                      child: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('发送'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: TextStyle(
                  color: _status.contains('成功') ? Colors.green : Colors.red,
                ),
              ),
              if (_logLines.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  height: 120,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
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
              ],
            ],
          ),
        ),
      ),
    );
  }
}
