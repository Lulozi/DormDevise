import 'package:uuid/uuid.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:dormdevise/models/mqtt_config.dart';
import 'package:dormdevise/models/status_topic_suggestion_builder.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/services/mqtt_config_service.dart';
import 'package:dormdevise/services/mqtt_service.dart';

/// MQTT 配置与调试页面。
class MqttSettingsPage extends StatefulWidget {
  const MqttSettingsPage({super.key, this.showAppBar = true});

  /// 是否显示顶部 AppBar，嵌入标签页时可隐藏。
  final bool showAppBar;

  /// 创建页面状态以处理表单输入与网络交互。
  @override
  State<MqttSettingsPage> createState() => _MqttSettingsPageState();
}

class _MqttSettingsPageState extends State<MqttSettingsPage> {
  static const String _subscribedTopicKey = 'mqtt_last_subscribed_topic';
  final StatusTopicSuggestionBuilder _suggestionBuilder =
      const StatusTopicSuggestionBuilder();
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
  bool _statusMonitorEnabled = false;
  bool _statusEnabledPersisted = false;
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
  final FocusNode _statusTopicFocusNode = FocusNode();

  /// 根据消息内容生成适合预览的字符串。
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

  /// 根据当前输入生成状态主题的联想选项列表。
  Iterable<StatusTopicSuggestion> _buildStatusTopicSuggestions(
    TextEditingValue editingValue,
  ) {
    return _suggestionBuilder.buildSuggestions(
      commandTopic: _topicController.text,
      input: editingValue.text,
    );
  }

  /// 将最近订阅的主题名称持久化。
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

  /// 弹出对话框提示用户具体信息。
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

  /// 更新页面顶部的状态提示。
  void _showStatus(String message, {bool isError = false, IconData? icon}) {
    if (!mounted) return;
    setState(() {
      _status = message;
      _statusIsError = isError;
      _statusIcon =
          icon ?? (isError ? Icons.error_outline : Icons.check_circle_outline);
    });
  }

  /// 追加日志条目并维护日志长度。
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

  /// 初始化焦点监听并加载配置。
  @override
  void initState() {
    super.initState();
    _topicFocusNode.addListener(_handleTopicFocusChange);
    _initAndLoadConfig();
  }

  /// 当主题输入框获得焦点时展开状态设置。
  void _handleTopicFocusChange() {
    if (_topicFocusNode.hasFocus && !_topicExpanded) {
      setState(() => _topicExpanded = true);
    }
  }

  /// 初始化默认客户端 ID 并载入本地配置。
  Future<void> _initAndLoadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    String? cid = prefs.getString('mqtt_clientId');
    if (cid == null || cid.isEmpty) {
      cid = const Uuid().v4();
      await prefs.setString('mqtt_clientId', cid);
    }
    await _loadConfig(defaultClientId: cid);
  }

  /// 从本地存储加载配置并刷新表单控件。
  Future<void> _loadConfig({String? defaultClientId}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    MqttConfig config = await MqttConfigService.instance.loadConfig(
      forceRefresh: true,
    );
    if ((config.clientId.isEmpty) &&
        defaultClientId != null &&
        defaultClientId.isNotEmpty) {
      config = config.copyWith(clientId: defaultClientId);
      await MqttConfigService.instance.saveConfig(config);
    }
    final String lastSubscribedTopic =
        prefs.getString(_subscribedTopicKey) ?? '';
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
    _statusMonitorEnabled = config.statusEnabled;
    _statusEnabledPersisted = config.statusEnabled;
    setState(() {
      _host = config.host;
      _port = config.port.toString();
      _topic = config.commandTopic;
      _username = config.username ?? '';
      _password = config.password ?? '';
      _clientId = config.clientId;
      _caPath = config.caPath;
      _certPath = config.certPath ?? '';
      _keyPath = config.keyPath ?? '';
      _keyPwd = config.keyPassword ?? '';
      _withTls = config.withTls;
      _customMsg = config.customMessage;
      _topicExpanded = (config.statusTopic ?? '').isNotEmpty;
      _statusPreview = '';
      _hasSubscribed = _topic.isNotEmpty && lastSubscribedTopic.isNotEmpty
          ? lastSubscribedTopic == _topic
          : false;
      // 重新创建 controller
      _hostController = TextEditingController(text: _host);
      _portController = TextEditingController(text: _port);
      _topicController = TextEditingController(text: _topic);
      _statusTopicController = TextEditingController(
        text: config.statusTopic ?? '',
      );
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
    if (config.statusEnabled &&
        (config.statusTopic?.isNotEmpty ?? false) &&
        mounted) {
      unawaited(_subscribeStatusTopic(autoResume: true));
    }
  }

  /// 将当前表单配置写入本地存储。
  /// 根据当前表单输入生成标准配置对象。
  MqttConfig _buildConfigFromInputs() {
    final String host = _hostController.text.trim();
    final int port = int.tryParse(_portController.text.trim()) ?? 1883;
    final String topic = _topicController.text.trim();
    final String clientId = _clientIdController.text.trim();
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();
    final String caPath = _caPathController.text.trim();
    final String certPath = _certPathController.text.trim();
    final String keyPath = _keyPathController.text.trim();
    final String keyPwd = _keyPwdController.text.trim();
    final String statusTopic = _statusTopicController.text.trim();
    final String customMsg = _customMsgController.text.trim().isEmpty
        ? 'OPEN'
        : _customMsgController.text.trim();
    String resolvedClientId = clientId;
    if (resolvedClientId.isEmpty) {
      resolvedClientId = _clientId.isNotEmpty ? _clientId : const Uuid().v4();
    }
    return MqttConfig(
      host: host,
      port: port,
      commandTopic: topic,
      clientId: resolvedClientId,
      username: username.isEmpty ? null : username,
      password: password.isEmpty ? null : password,
      withTls: _withTls,
      caPath: caPath.isEmpty ? 'assets/certs/ca.pem' : caPath,
      certPath: certPath.isEmpty ? null : certPath,
      keyPath: keyPath.isEmpty ? null : keyPath,
      keyPassword: keyPwd.isEmpty ? null : keyPwd,
      statusTopic: statusTopic.isEmpty ? null : statusTopic,
      statusEnabled: _statusEnabledPersisted || _statusMonitorEnabled,
      customMessage: customMsg,
    );
  }

  Future<void> _saveConfig() async {
    final MqttConfig config = _buildConfigFromInputs();
    await MqttConfigService.instance.saveConfig(config);
    if (!mounted) return;
    await _subscribeMainTopic(triggeredBySave: true);
    // 保存状态主题后立即刷新桌面微件的状态订阅。
    await DoorWidgetService.instance.refreshStatusListener();
  }

  /// 将配置导出为 JSON 并复制到剪贴板。
  Future<void> _exportConfig() async {
    final MqttConfig config = _buildConfigFromInputs();
    final Map<String, Object?> exportMap = <String, Object?>{
      'mqtt_host': config.host,
      'mqtt_port': config.port.toString(),
      'mqtt_topic': config.commandTopic,
      'mqtt_username': config.username ?? '',
      'mqtt_password': config.password ?? '',
      'mqtt_ca': config.caPath,
      'mqtt_cert': config.certPath ?? '',
      'mqtt_key': config.keyPath ?? '',
      'mqtt_key_pwd': config.keyPassword ?? '',
      'mqtt_status_topic': config.statusTopic ?? '',
      'mqtt_with_tls': config.withTls,
      'custom_open_msg': config.customMessage,
      'mqtt_status_enabled': config.statusEnabled,
    };
    final jsonStr = JsonEncoder.withIndent('  ').convert(exportMap);
    await Clipboard.setData(ClipboardData(text: jsonStr));
    if (!mounted) return;
    _showStatus('配置已导出到剪贴板');
    _showBubble(context, '配置已导出到剪贴板\n\n$jsonStr');
  }

  /// 从剪贴板导入配置并刷新表单。
  Future<void> _importConfigFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data == null || data.text == null || data.text!.trim().isEmpty) {
      if (!mounted) return;
      _showStatus('剪贴板内容为空', isError: true, icon: Icons.info_outline);
      _showBubble(context, '剪贴板内容为空');
      return;
    }
    try {
      final dynamic decoded = jsonDecode(data.text!);
      if (decoded is! Map) throw Exception('格式错误');
      final Map<String, Object?> storageMap = <String, Object?>{
        'mqtt_host': decoded['mqtt_host'],
        'mqtt_port': decoded['mqtt_port'],
        'mqtt_topic': decoded['mqtt_topic'],
        'mqtt_username': decoded['mqtt_username'],
        'mqtt_password': decoded['mqtt_password'],
        'mqtt_ca': decoded['mqtt_ca'],
        'mqtt_cert': decoded['mqtt_cert'],
        'mqtt_key': decoded['mqtt_key'],
        'mqtt_key_pwd': decoded['mqtt_key_pwd'],
        'mqtt_status_topic': decoded['mqtt_status_topic'],
        'mqtt_with_tls': decoded['mqtt_with_tls'],
        'custom_open_msg': decoded['custom_open_msg'],
        'mqtt_status_enabled': decoded['mqtt_status_enabled'],
        'mqtt_clientId': decoded['mqtt_clientId'],
      };
      final MqttConfig config = MqttConfig.fromStorage(storageMap);
      await _stopStatusSubscription(silent: true);
      await MqttConfigService.instance.saveConfig(config);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      unawaited(_persistSubscribedTopic(null, cachedPrefs: prefs));
      await _loadConfig();
      final importStr = JsonEncoder.withIndent('  ').convert(decoded);
      if (!mounted) return;
      _showStatus('配置已从剪贴板导入');
      _showBubble(context, '配置已从剪贴板导入\n\n$importStr\n\n点击确定保存配置');
    } catch (e) {
      if (!mounted) return;
      _showStatus('导入失败: $e', isError: true);
      _showBubble(context, '导入失败: $e');
    }
  }

  /// 打开文件选择器并回填路径。
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

  /// 测试订阅连接以确认配置有效。
  /// 使用当前配置尝试订阅主主题，并根据触发来源调整提示。
  Future<bool> _subscribeMainTopic({bool triggeredBySave = false}) async {
    final topic = _topicController.text.trim();
    if (topic.isEmpty) {
      final msg = triggeredBySave ? '配置已保存，但订阅失败：请先填写订阅主题' : '请先填写订阅主题';
      _showStatus(msg, isError: true, icon: Icons.info_outline);
      _showBubble(context, msg);
      unawaited(_persistSubscribedTopic(null));
      return false;
    }
    setState(() {
      _loading = true;
      _hasSubscribed = false;
    });
    final workingStatus = triggeredBySave ? '配置已保存，正在订阅...' : '正在连接...';
    _showStatus(workingStatus, icon: Icons.hourglass_top);
    await _persistSubscribedTopic(null);
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
        return true;
      }
      final info = '订阅成功: $topic';
      setState(() {
        _hasSubscribed = true;
        _logLines.add(info);
        if (_logLines.length > 200) _logLines.removeAt(0);
      });
      final successMsg = triggeredBySave ? '配置已保存并已订阅' : '已订阅';
      _showStatus(successMsg);
      if (triggeredBySave) {
        _showBubble(context, successMsg);
      } else {
        _showBubble(context, info);
      }
      return true;
    } catch (e) {
      await _persistSubscribedTopic(null);
      final failMsg = triggeredBySave ? '配置已保存，但订阅失败: $e' : '连接失败: $e';
      if (mounted) {
        setState(() {
          _logLines.add(failMsg);
          if (_logLines.length > 200) _logLines.removeAt(0);
          _hasSubscribed = false;
        });
        _showStatus(failMsg, isError: true);
        _showBubble(context, failMsg);
      }
      return false;
    } finally {
      if (service != null) {
        await service.dispose();
      }
      if (mounted) {
        setState(() {
          _loading = false;
        });
      } else {
        _loading = false;
      }
    }
  }

  /// 触发主主题订阅测试，用于按钮操作。
  Future<void> _testConnect() async {
    await _subscribeMainTopic();
  }

  /// 根据当前状态切换状态主题订阅。
  Future<void> _toggleStatusSubscription() async {
    if (_statusEnabledPersisted || _statusMonitorEnabled) {
      await _stopStatusSubscription();
      return;
    }
    await _subscribeStatusTopic();
  }

  /// 发起状态主题订阅并展示最新消息。
  Future<void> _subscribeStatusTopic({bool autoResume = false}) async {
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
      if (!autoResume) {
        _statusPreview = '';
      }
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
        _statusMonitorEnabled = true;
        _statusEnabledPersisted = true;
      });
      service = null;
      _appendLog('已订阅状态主题: $statusTopic');
      if (!autoResume) {
        _showStatus('状态主题订阅成功');
      }
      await MqttConfigService.instance.setStatusEnabled(true);
      await DoorWidgetService.instance.refreshStatusListener();
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

  /// 取消状态主题订阅并清空预览。
  Future<void> _stopStatusSubscription({bool silent = false}) async {
    final service = _statusSubscriptionService;
    setState(() {
      _statusSubscriptionService = null;
      _statusFetching = false;
      _statusMonitorEnabled = false;
      _statusEnabledPersisted = false;
      _statusPreview = '';
    });
    await MqttConfigService.instance.setStatusEnabled(false);
    await DoorWidgetService.instance.refreshStatusListener();
    try {
      if (service != null) {
        await service.dispose();
      }
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

  /// 当状态主题变更时重置订阅状态。
  void _onStatusTopicChanged(String value) {
    setState(() {
      if (!_topicExpanded) {
        _topicExpanded = true;
      }
      _statusPreview = '';
    });
  }

  /// 释放所有控制器与资源。
  @override
  void dispose() {
    _isDisposing = true;
    _topicFocusNode.removeListener(_handleTopicFocusChange);
    _topicFocusNode.dispose();
    _statusTopicFocusNode.dispose();
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

  /// 构建 MQTT 配置表单与工具组件。
  @override
  Widget build(BuildContext context) {
    if (!_isConfigReady) {
      return Scaffold(
        appBar: widget.showAppBar ? AppBar(title: const Text('MQTT配置')) : null,
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
    final statusSubscribed = _statusEnabledPersisted || _statusMonitorEnabled;

    /// 生成统一的输入框装饰样式。
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
      appBar: widget.showAppBar
          ? AppBar(
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
            )
          : null,
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
                        duration: const Duration(milliseconds: 400),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        transitionBuilder: (child, animation) {
                          return ClipRect(
                            child: SizeTransition(
                              sizeFactor: animation,
                              axisAlignment: -1.0,
                              child: child,
                            ),
                          );
                        },
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
                                  RawAutocomplete<StatusTopicSuggestion>(
                                    key: const ValueKey('statusTopic'),
                                    textEditingController:
                                        _statusTopicController,
                                    focusNode: _statusTopicFocusNode,
                                    optionsBuilder:
                                        _buildStatusTopicSuggestions,
                                    displayStringForOption: (option) =>
                                        option.display,
                                    onSelected: (option) {
                                      final value = option.value;
                                      _statusTopicController.text = value;
                                      _statusTopicController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(offset: value.length),
                                          );
                                      _onStatusTopicChanged(value);
                                    },
                                    optionsViewBuilder:
                                        (context, onSelected, options) {
                                          if (options.isEmpty) {
                                            return const SizedBox.shrink();
                                          }
                                          final cs = Theme.of(
                                            context,
                                          ).colorScheme;
                                          return Align(
                                            alignment: Alignment.topLeft,
                                            child: Material(
                                              elevation: 4,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              color: cs.surface,
                                              child: ConstrainedBox(
                                                constraints:
                                                    const BoxConstraints(
                                                      maxHeight: 160,
                                                      maxWidth: 360,
                                                    ),
                                                child: ListView.builder(
                                                  shrinkWrap: true,
                                                  padding: EdgeInsets.zero,
                                                  itemCount: options.length,
                                                  itemBuilder:
                                                      (context, index) {
                                                        final option = options
                                                            .elementAt(index);
                                                        return ListTile(
                                                          dense: true,
                                                          title: Text(
                                                            option.display,
                                                          ),
                                                          onTap: () =>
                                                              onSelected(
                                                                option,
                                                              ),
                                                        );
                                                      },
                                                ),
                                              ),
                                            ),
                                          );
                                        },
                                    fieldViewBuilder:
                                        (
                                          context,
                                          textEditingController,
                                          focusNode,
                                          onFieldSubmitted,
                                        ) {
                                          return TextField(
                                            controller: textEditingController,
                                            focusNode: focusNode,
                                            decoration: decoration(
                                              '状态主题 (可选)',
                                              prefixIcon: const Icon(
                                                Icons.receipt_long_outlined,
                                              ),
                                            ),
                                            onChanged: _onStatusTopicChanged,
                                          );
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
