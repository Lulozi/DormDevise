import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'mqtt_client.dart';

class ConfigMqttPage extends StatefulWidget {
  const ConfigMqttPage({super.key});

  @override
  State<ConfigMqttPage> createState() => _ConfigMqttPageState();
}

class _ConfigMqttPageState extends State<ConfigMqttPage> {
  static const String _subscribedTopicKey = 'mqtt_last_subscribed_topic';
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
  String _statusPreview = '';

  bool _statusFetching = false;
  bool _topicExpanded = false;
  bool _isConfigReady = false;
  bool _isDisposing = false;
  bool _hasSubscribed = false;
  MqttService? _statusSubscriptionService;

  // controller 只在变量变更时重建，避免 labelText 闪烁
  late TextEditingController _hostController;
  late TextEditingController _portController;
  late TextEditingController _topicController;
  late TextEditingController _statusTopicController;
  late TextEditingController _clientIdController;
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  late TextEditingController _caPathController;
  late TextEditingController _certPathController;
  late TextEditingController _keyPathController;
  late TextEditingController _keyPwdController;
  late TextEditingController _customMsgController;
  final FocusNode _topicFocusNode = FocusNode();

  String _formatStatusPreview(Map<String, dynamic> data) {
    if (data.length == 1 && data.containsKey('payload')) {
      final value = data['payload'];
      if (value is String) return value;
      if (value == null) return 'null';
      if (value is Map || value is List) {
        try {
          return const JsonEncoder.withIndent('  ').convert(value);
        } catch (_) {
          return value.toString();
        }
      }
      return value.toString();
    }
    try {
      return const JsonEncoder.withIndent('  ').convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  Future<void> _persistSubscribedTopic(
    String? topic, {
    SharedPreferences? cachedPrefs,
  }) async {
    final prefs = cachedPrefs ?? await SharedPreferences.getInstance();
    final trimmed = topic?.trim() ?? '';
    if (trimmed.isEmpty) {
      await prefs.remove(_subscribedTopicKey);
    } else {
      await prefs.setString(_subscribedTopicKey, trimmed);
    }
  }

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

  void _showStatus(String message, {bool isError = false, IconData? icon}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = isError;
      _statusIcon =
          icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline);
    });
  }

  void _appendLog(String line) {
    if (!mounted || _isDisposing) return;
    setState(() {
      _logLines.add(line);
      if (_logLines.length > 200) _logLines.removeAt(0);
    });
  }

  bool _sending = false;
  bool _loading = false;
  String _status = '';
  bool _statusIsError = false;
  IconData _statusIcon = Icons.check_circle_outline;

  @override
  void initState() {
    super.initState();
    _topicFocusNode.addListener(_handleTopicFocusChange);
    _initAndLoadConfig();
  }

  void _handleTopicFocusChange() {
    if (_topicFocusNode.hasFocus && !_topicExpanded) {
      setState(() => _topicExpanded = true);
    }
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
    await _stopStatusSubscription(silent: true);
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('mqtt_host') ?? '';
    final port = prefs.getString('mqtt_port') ?? '1883';
    final topic = prefs.getString('mqtt_topic') ?? '';
    final username = prefs.getString('mqtt_username') ?? '';
    final password = prefs.getString('mqtt_password') ?? '';
    final clientId =
        prefs.getString('mqtt_clientId') ?? (defaultClientId ?? '');
    final caPath = prefs.getString('mqtt_ca') ?? 'assets/certs/ca.pem';
    final certPath = prefs.getString('mqtt_cert') ?? '';
    final keyPath = prefs.getString('mqtt_key') ?? '';
    final keyPwd = prefs.getString('mqtt_key_pwd') ?? '';
    final withTls = prefs.getBool('mqtt_with_tls') ?? false;
    final loadedStatusTopic = prefs.getString('mqtt_status_topic') ?? '';
    final lastSubscribedTopic = prefs.getString(_subscribedTopicKey) ?? '';
    final oldControllers = _isConfigReady
        ? <TextEditingController>[
            _hostController,
            _portController,
            _topicController,
            _statusTopicController,
            _clientIdController,
            _usernameController,
            _passwordController,
            _caPathController,
            _certPathController,
            _keyPathController,
            _keyPwdController,
            _customMsgController,
          ]
        : const <TextEditingController>[];
    setState(() {
      _host = host;
      _port = port;
      _topic = topic;
      _username = username;
      _password = password;
      _clientId = clientId;
      _caPath = caPath;
      _certPath = certPath;
      _keyPath = keyPath;
      _keyPwd = keyPwd;
      _withTls = withTls;
      _customMsg = 'OPEN';
      _topicExpanded = loadedStatusTopic.isNotEmpty;
      _statusPreview = '';
      _hasSubscribed = topic.isNotEmpty && lastSubscribedTopic.isNotEmpty
          ? lastSubscribedTopic == topic
          : false;
      // 重新创建 controller
      _hostController = TextEditingController(text: _host);
      _portController = TextEditingController(text: _port);
      _topicController = TextEditingController(text: _topic);
      _statusTopicController = TextEditingController(text: loadedStatusTopic);
      _clientIdController = TextEditingController(text: _clientId);
      _usernameController = TextEditingController(text: _username);
      _passwordController = TextEditingController(text: _password);
      _caPathController = TextEditingController(text: _caPath);
      _certPathController = TextEditingController(text: _certPath);
      _keyPathController = TextEditingController(text: _keyPath);
      _keyPwdController = TextEditingController(text: _keyPwd);
      _customMsgController = TextEditingController(text: _customMsg);
      _isConfigReady = true;
    });
    for (final controller in oldControllers) {
      controller.dispose();
    }
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
    await prefs.setString('mqtt_status_topic', _statusTopicController.text);
    await prefs.setBool('mqtt_with_tls', _withTls);
    if (!mounted) return;
    _showStatus('配置已保存');
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
      'mqtt_status_topic': _statusTopicController.text,
      'mqtt_with_tls': _withTls,
      // 不导出 clientId/uuid
    };
    final jsonStr = JsonEncoder.withIndent('  ').convert(config);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    _showStatus('配置已导出到剪贴板');
    _showBubble(context, '配置已导出到剪贴板\n\n$jsonStr');
  }

  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.trim().isEmpty) {
      if (!mounted) return;
      _showStatus('剪贴板内容为空', isError: true, icon: Icons.info_outline);
      _showBubble(context, '剪贴板内容为空');
      return;
    }
    try {
      final map = jsonDecode(data.text!);
      if (map is! Map) throw Exception('格式错误');
      await _stopStatusSubscription(silent: true);
      final oldControllers = _isConfigReady
          ? <TextEditingController>[
              _hostController,
              _portController,
              _topicController,
              _statusTopicController,
              _usernameController,
              _passwordController,
              _caPathController,
              _certPathController,
              _keyPathController,
              _keyPwdController,
            ]
          : const <TextEditingController>[];
      final importedStatusTopic = map['mqtt_status_topic'] ?? '';
      final prefs = await SharedPreferences.getInstance();
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
        _topicExpanded = importedStatusTopic.isNotEmpty;
        _statusPreview = '';
        _hasSubscribed = false;
        // 重新创建 controller
        _hostController = TextEditingController(text: _host);
        _portController = TextEditingController(text: _port);
        _topicController = TextEditingController(text: _topic);
        _statusTopicController = TextEditingController(
          text: importedStatusTopic,
        );
        _usernameController = TextEditingController(text: _username);
        _passwordController = TextEditingController(text: _password);
        _caPathController = TextEditingController(text: _caPath);
        _certPathController = TextEditingController(text: _certPath);
        _keyPathController = TextEditingController(text: _keyPath);
        _keyPwdController = TextEditingController(text: _keyPwd);
      });
      for (final controller in oldControllers) {
        controller.dispose();
      }
      unawaited(_persistSubscribedTopic(null, cachedPrefs: prefs));
      // 只保存配置到本地，不弹“配置已保存”弹窗
      await prefs.setString('mqtt_host', _host);
      await prefs.setString('mqtt_port', _port);
      await prefs.setString('mqtt_topic', _topic);
      await prefs.setString('mqtt_username', _username);
      await prefs.setString('mqtt_password', _password);
      await prefs.setString('mqtt_ca', _caPath);
      await prefs.setString('mqtt_cert', _certPath);
      await prefs.setString('mqtt_key', _keyPath);
      await prefs.setString('mqtt_key_pwd', _keyPwd);
      await prefs.setString('mqtt_status_topic', importedStatusTopic);
      await prefs.setBool('mqtt_with_tls', _withTls);
      final importStr = JsonEncoder.withIndent('  ').convert(map);
      if (!mounted) return;
      _showStatus('配置已从剪贴板导入');
      _showBubble(context, '配置已从剪贴板导入\n\n$importStr\n\n点击确定保存配置');
    } catch (e) {
      if (!mounted) return;
      _showStatus('导入失败: $e', isError: true);
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
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      _showStatus('请先填写订阅主题', isError: true, icon: Icons.info_outline);
      _showBubble(context, '请先填写订阅主题');
      unawaited(_persistSubscribedTopic(null));
      return;
    }
    setState(() {
      _loading = true;
      _hasSubscribed = false;
    });
    _showStatus('正在连接...', icon: Icons.hourglass_top);
    await _persistSubscribedTopic(null);
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
        onNotification: (topic, data) {
          debugPrint('MQTT notification <$topic>: $data');
          _appendLog('MQTT notification <$topic>: ${jsonEncode(data)}');
          final statusTopic = _statusTopicController.text.trim();
          if (statusTopic.isNotEmpty &&
              topic == statusTopic &&
              mounted &&
              _statusSubscriptionService != null) {
            final preview = _formatStatusPreview(data);
            setState(() {
              _statusPreview = preview;
            });
          }
        },
        log: (msg) {
          debugPrint(msg);
          _appendLog(msg);
        },
        onError: (e, [st]) {
          debugPrint('MQTT error: $e');
          _appendLog('MQTT error: $e');
        },
      );
      await service.connect();
      await service.subscribe(topic);
      await _persistSubscribedTopic(topic);
      if (!mounted) {
        await service.dispose();
        return;
      }
      final infoLines = <String>['订阅成功: $topic'];
      _showStatus('已订阅');
      setState(() {
        _hasSubscribed = true;
      });
      _showBubble(context, infoLines.join('\n\n'));
      await service.dispose();
    } catch (e) {
      await _persistSubscribedTopic(null);
      if (!mounted) return;
      setState(() {
        _logLines.add('连接失败: $e');
        if (_logLines.length > 200) _logLines.removeAt(0);
        _hasSubscribed = false;
      });
      _showStatus('连接失败: $e', isError: true);
      _showBubble(context, '连接失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      } else {
        _loading = false;
      }
    }
  }

  Future<void> _toggleStatusSubscription() async {
    if (_statusSubscriptionService != null) {
      await _stopStatusSubscription();
      return;
    }
    await _subscribeStatusTopic();
  }

  Future<void> _subscribeStatusTopic() async {
    final statusTopic = _statusTopicController.text.trim();
    if (statusTopic.isEmpty) {
      _showStatus('请先填写状态主题', isError: true, icon: Icons.info_outline);
      return;
    }
    if (!_topicExpanded) {
      setState(() => _topicExpanded = true);
    }
    setState(() {
      _statusFetching = true;
      _statusPreview = '';
    });
    SecurityContext? sc;
    MqttService? service;
    try {
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
      service = MqttService(
        host: _hostController.text,
        port: int.tryParse(_portController.text) ?? 1883,
        clientId: _clientIdController.text.isNotEmpty
            ? '${_clientIdController.text}_status'
            : 'flutter_client_status',
        username: _usernameController.text.isNotEmpty
            ? _usernameController.text
            : null,
        password: _passwordController.text.isNotEmpty
            ? _passwordController.text
            : null,
        securityContext: sc,
        onNotification: (topic, data) {
          if (topic != statusTopic || !mounted) return;
          final preview = _formatStatusPreview(data);
          setState(() {
            _statusPreview = preview;
          });
        },
        log: (msg) {
          debugPrint(msg);
          _appendLog(msg);
        },
        onError: (e, [st]) {
          debugPrint('MQTT error: $e');
          _appendLog('MQTT error: $e');
        },
      );
      await service.connect();
      await service.subscribe(statusTopic);
      if (!mounted) {
        await service.dispose();
        return;
      }
      setState(() {
        _statusSubscriptionService = service;
        _statusFetching = false;
      });
      service = null;
      _appendLog('已订阅状态主题: $statusTopic');
      _showStatus('状态主题订阅成功');
    } catch (e) {
      debugPrint('订阅状态主题失败: $e');
      _appendLog('订阅状态失败: $e');
      if (mounted) {
        _showStatus('订阅状态失败: $e', isError: true);
      }
    } finally {
      if (service != null) {
        await service.dispose();
      }
      if (mounted && _statusSubscriptionService == null) {
        setState(() {
          _statusFetching = false;
        });
      }
    }
  }

  Future<void> _stopStatusSubscription({bool silent = false}) async {
    final service = _statusSubscriptionService;
    if (service == null) {
      return;
    }
    setState(() {
      _statusSubscriptionService = null;
      _statusFetching = false;
      _statusPreview = '';
    });
    try {
      await service.dispose();
      if (!silent) {
        _appendLog('已取消状态主题订阅');
        _showStatus('状态主题订阅已停止');
      }
    } catch (e) {
      debugPrint('取消状态主题订阅失败: $e');
      _appendLog('取消状态订阅失败: $e');
      if (!silent) {
        _showStatus('取消状态订阅失败: $e', isError: true);
      }
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _topicFocusNode.removeListener(_handleTopicFocusChange);
    _topicFocusNode.dispose();
    unawaited(_statusSubscriptionService?.dispose());
    _statusSubscriptionService = null;
    if (_isConfigReady) {
      _hostController.dispose();
      _portController.dispose();
      _topicController.dispose();
      _statusTopicController.dispose();
      _clientIdController.dispose();
      _usernameController.dispose();
      _passwordController.dispose();
      _caPathController.dispose();
      _certPathController.dispose();
      _keyPathController.dispose();
      _keyPwdController.dispose();
      _customMsgController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isConfigReady) {
      return Scaffold(
        appBar: AppBar(title: const Text('MQTT配置')),
        body: const Center(child: CircularProgressIndicator()),
      );
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
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    const buttonPadding = EdgeInsets.symmetric(vertical: 14);
    final statusSubscribed = _statusSubscriptionService != null;

    InputDecoration decoration(
      String label, {
      String? hint,
      Widget? prefixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: focusedBorder,
        prefixIcon: prefixIcon,
      );
    }

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
                        decoration: decoration(
                          '服务器地址',
                          prefixIcon: const Icon(Icons.dns_outlined),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('port'),
                        controller: _portController,
                        decoration: decoration(
                          '端口',
                          prefixIcon: const Icon(Icons.numbers),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('topic'),
                        controller: _topicController,
                        focusNode: _topicFocusNode,
                        decoration: decoration(
                          '主题',
                          prefixIcon: const Icon(Icons.subject_outlined),
                        ),
                        onTap: () {
                          if (!_topicExpanded) {
                            setState(() => _topicExpanded = true);
                          }
                        },
                        onChanged: (value) {
                          if (_hasSubscribed) {
                            setState(() => _hasSubscribed = false);
                            unawaited(_persistSubscribedTopic(null));
                          }
                        },
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child:
                            !_topicExpanded &&
                                _statusTopicController.text.isEmpty &&
                                _statusPreview.isEmpty
                            ? const SizedBox.shrink()
                            : Column(
                                key: const ValueKey('statusTopicPanel'),
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  TextField(
                                    key: const ValueKey('statusTopic'),
                                    controller: _statusTopicController,
                                    decoration: decoration(
                                      '状态主题 (可选)',
                                      prefixIcon: const Icon(
                                        Icons.receipt_long_outlined,
                                      ),
                                    ),
                                    onChanged: (value) {
                                      if (_statusSubscriptionService != null) {
                                        unawaited(
                                          _stopStatusSubscription(silent: true),
                                        );
                                      }
                                      setState(() {
                                        if (!_topicExpanded) {
                                          _topicExpanded = true;
                                        }
                                        _statusPreview = '';
                                      });
                                    },
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: colorScheme
                                                .surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: _statusPreview.isEmpty
                                              ? Text(
                                                  '等待订阅消息…',
                                                  style: TextStyle(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                )
                                              : SelectableText(
                                                  _statusPreview,
                                                  style: TextStyle(
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 40,
                                        child: FilledButton.icon(
                                          onPressed: _statusFetching
                                              ? null
                                              : _toggleStatusSubscription,
                                          style: FilledButton.styleFrom(
                                            shape: buttonShape,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                            ),
                                          ),
                                          icon: _statusFetching
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : Icon(
                                                  statusSubscribed
                                                      ? Icons
                                                            .stop_circle_outlined
                                                      : Icons.podcasts_outlined,
                                                ),
                                          label: Text(
                                            _statusFetching
                                                ? (statusSubscribed
                                                      ? '取消订阅...'
                                                      : '订阅中...')
                                                : (statusSubscribed
                                                      ? '取消订阅'
                                                      : '订阅状态主题'),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('username'),
                        controller: _usernameController,
                        decoration: decoration(
                          '用户名',
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('password'),
                        controller: _passwordController,
                        decoration: decoration(
                          '密码',
                          prefixIcon: const Icon(Icons.lock_outline),
                        ),
                        obscureText: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        key: const ValueKey('clientId'),
                        controller: _clientIdController,
                        decoration: decoration(
                          'Client ID (默认使用UUID)',
                          prefixIcon: const Icon(Icons.badge_outlined),
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
                              decoration: decoration(
                                'CA证书路径',
                                prefixIcon: const Icon(
                                  Icons.file_present_outlined,
                                ),
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
                              decoration: decoration(
                                '客户端证书路径(可选)',
                                prefixIcon: const Icon(
                                  Icons.assignment_turned_in_outlined,
                                ),
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
                              decoration: decoration(
                                '客户端私钥路径(可选)',
                                prefixIcon: const Icon(Icons.vpn_key_outlined),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          key: const ValueKey('keyPwd'),
                          controller: _keyPwdController,
                          decoration: decoration(
                            '私钥密码(可选)',
                            prefixIcon: const Icon(Icons.password_outlined),
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
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _saveConfig,
                      style: OutlinedButton.styleFrom(
                        shape: buttonShape,
                        padding: buttonPadding,
                      ),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('保存配置'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _testConnect,
                      style: FilledButton.styleFrom(
                        shape: buttonShape,
                        padding: buttonPadding,
                      ),
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_sync_outlined),
                      label: Text(
                        _loading
                            ? '正在连接...'
                            : (_hasSubscribed ? '已订阅' : '订阅连接'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _exportConfig,
                      style: OutlinedButton.styleFrom(
                        shape: buttonShape,
                        padding: buttonPadding,
                      ),
                      icon: const Icon(Icons.upload_outlined),
                      label: const Text('导出配置'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _importConfigFromClipboard,
                      style: OutlinedButton.styleFrom(
                        shape: buttonShape,
                        padding: buttonPadding,
                      ),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('导入配置'),
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
                        child: SizedBox(
                          height: 56,
                          child: TextField(
                            controller: _customMsgController,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: decoration(
                              '自定义发送消息',
                              hint: '输入mqtt接收开门的消息',
                              prefixIcon: const Icon(Icons.chat_bubble_outline),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 40,
                        child: FilledButton.icon(
                          onPressed: _sending
                              ? null
                              : () async {
                                  final msg = _customMsgController.text.trim();
                                  if (msg.isEmpty) return;
                                  setState(() {
                                    _sending = true;
                                  });
                                  _showStatus(
                                    '正在发送...',
                                    icon: Icons.hourglass_top,
                                  );
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
                                    _showStatus('消息已发送');
                                    await service.dispose();
                                  } catch (e) {
                                    _showStatus('发送失败: $e', isError: true);
                                  } finally {
                                    setState(() {
                                      _sending = false;
                                    });
                                  }
                                },
                          style: FilledButton.styleFrom(
                            shape: buttonShape,
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                          ),
                          icon: _sending
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_outlined),
                          label: Text(_sending ? '发送中...' : '测试发送'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _status.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        key: ValueKey(
                          '${_status}_${_statusIsError}_${_statusIcon.codePoint}',
                        ),
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _statusIsError
                                ? colorScheme.errorContainer
                                : colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                _statusIcon,
                                color: _statusIsError
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.onSecondaryContainer,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _status,
                                  style: TextStyle(
                                    color: _statusIsError
                                        ? colorScheme.onErrorContainer
                                        : colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
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
