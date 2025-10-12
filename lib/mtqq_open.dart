import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:uuid/uuid.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:developer'; // 顶部添加
// MAYBE 重新设计UI

// 添加静态方法，方便其他页面调用
class MqttConfigPage extends StatefulWidget {
  const MqttConfigPage({super.key});

  @override
  State<MqttConfigPage> createState() => _MqttConfigPageState();

  // 静态方法：连接并返回客户端
  static Future<MqttServerClient> connectStatic() async {
    final prefs = await SharedPreferences.getInstance();
    final broker = prefs.getString('mqtt_broker') ?? 'broker.emqx.io';
    final port = int.tryParse(prefs.getString('mqtt_port') ?? '1883') ?? 1883;
    final clientId = prefs.getString('mqtt_clientId') ?? 'flutter_client';
    final username = prefs.getString('mqtt_username') ?? '';
    final password = prefs.getString('mqtt_password') ?? '';

    final client = MqttServerClient(broker, clientId);
    client.port = port;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onConnected = () => log('连接成功');
    client.onDisconnected = () => log('断开连接');
    client.onSubscribed = (topic) => log('已订阅: $topic');
    client.onUnsubscribed = (topic) => log('取消订阅: $topic');
    client.onSubscribeFail = (topic) => log('订阅失败: $topic');
    client.pongCallback = () => log('Ping响应');

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean();
    client.connectionMessage = connMess;

    try {
      await client.connect();
    } catch (e) {
      print('连接异常: $e');
      client.disconnect();
    }
    return client;
  }

  // 静态方法：获取保存的 topic
  static Future<String> getSavedTopic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('mqtt_topic') ?? 'test/topic';
  }
}

class _MqttConfigPageState extends State<MqttConfigPage> {
  final _brokerController = TextEditingController();
  final _portController = TextEditingController();
  final _topicController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String clientId = '正在获取...';

  @override
  void initState() {
    super.initState();
    _initClientId();
    _loadConfig();
  }

  Future<void> _initClientId() async {
    final prefs = await SharedPreferences.getInstance();
    String? id = prefs.getString('device_uuid');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('device_uuid', id);
    }
    setState(() {
      clientId = id!;
    });
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _brokerController.text =
          prefs.getString('mqtt_broker') ?? 'broker.emqx.io';
      _portController.text = prefs.getString('mqtt_port') ?? '1883';
      _topicController.text = prefs.getString('mqtt_topic') ?? 'test/topic';
      _usernameController.text = prefs.getString('mqtt_username') ?? '';
      _passwordController.text = prefs.getString('mqtt_password') ?? '';
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mqtt_broker', _brokerController.text);
    await prefs.setString('mqtt_port', _portController.text);
    await prefs.setString('mqtt_clientId', clientId); // 强制保存为设备唯一标识
    await prefs.setString('mqtt_topic', _topicController.text);
    await prefs.setString('mqtt_username', _usernameController.text);
    await prefs.setString('mqtt_password', _passwordController.text);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('配置已保存')));
  }

  Future<MqttServerClient> connect() async {
    final broker = _brokerController.text;
    final port = int.tryParse(_portController.text) ?? 1883;
    final username = _usernameController.text;
    final password = _passwordController.text;
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString('mqtt_clientId') ?? this.clientId;

    final client = MqttServerClient(broker, clientId);
    client.port = port;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    client.onConnected = () => log('连接成功');
    client.onDisconnected = () => log('断开连接');
    client.onSubscribed = (topic) => log('已订阅: $topic');
    client.onUnsubscribed = (topic) => log('取消订阅: $topic');
    client.onSubscribeFail = (topic) => log('订阅失败: $topic');
    client.pongCallback = () => log('Ping响应');

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .authenticateAs(username, password)
        .startClean();
    client.connectionMessage = connMess;

    try {
      await client.connect();
    } catch (e) {
      log('连接异常: $e');
      client.disconnect();
    }
    return client;
  }

  Future<void> _exportConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final config = {
      'mqtt_broker': prefs.getString('mqtt_broker') ?? '',
      'mqtt_port': prefs.getString('mqtt_port') ?? '',
      // 'mqtt_clientId': prefs.getString('mqtt_clientId') ?? '', // 排除Client ID
      'mqtt_topic': prefs.getString('mqtt_topic') ?? '',
      'mqtt_username': prefs.getString('mqtt_username') ?? '',
      'mqtt_password': prefs.getString('mqtt_password') ?? '',
    };
    final exportText = jsonEncode(config);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('导出配置文本'),
        content: SelectableText(exportText),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: exportText));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('已复制到剪贴板')));
            },
            child: Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _importConfigFromClipboard() async {
    final clipboardData = await Clipboard.getData('text/plain');
    if (clipboardData == null ||
        clipboardData.text == null ||
        clipboardData.text!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('剪贴板内容为空')));
      return;
    }
    try {
      final config = jsonDecode(clipboardData.text!);
      final prefs = await SharedPreferences.getInstance();
      if (config is Map) {
        if (config.containsKey('mqtt_broker')) {
          await prefs.setString('mqtt_broker', config['mqtt_broker'] ?? '');
        }
        if (config.containsKey('mqtt_port')) {
          await prefs.setString('mqtt_port', config['mqtt_port'] ?? '');
        }
        if (config.containsKey('mqtt_topic')) {
          await prefs.setString('mqtt_topic', config['mqtt_topic'] ?? '');
        }
        if (config.containsKey('mqtt_username')) {
          await prefs.setString('mqtt_username', config['mqtt_username'] ?? '');
        }
        if (config.containsKey('mqtt_password')) {
          await prefs.setString('mqtt_password', config['mqtt_password'] ?? '');
        }
        await _loadConfig();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('配置导入成功')));
      } else {
        throw Exception('格式错误');
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('MQTT配置')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          physics: NeverScrollableScrollPhysics(), // 禁止滑动
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _brokerController,
                decoration: InputDecoration(labelText: 'Broker地址'),
              ),
              TextField(
                controller: _portController,
                decoration: InputDecoration(labelText: '端口'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _topicController,
                decoration: InputDecoration(labelText: '主题'),
              ),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              ListTile(
                title: Text('Client ID（设备唯一标识）'),
                subtitle: Text(clientId),
              ),
              SizedBox(height: 24),
              // 按钮区域居中且大小一致
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveConfig,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('保存配置'),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final client = await connect();
                        final topic = _topicController.text;
                        try {
                          client.subscribe(topic, MqttQos.atLeastOnce);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('订阅成功: $topic')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('订阅失败: $e')));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('订阅'),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final client = await connect();
                        final topic = _topicController.text;
                        final builder = MqttClientPayloadBuilder();
                        builder.addString('OPEN');
                        try {
                          client.publishMessage(
                            topic,
                            MqttQos.atLeastOnce,
                            builder.payload!,
                          );
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('OPEN消息已发送')));
                        } catch (e) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('发送失败: $e')));
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('测试发送OPEN'),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _exportConfig,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('导出配置'),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _importConfigFromClipboard,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(0, 48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      child: Text('从剪贴板导入配置'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
