import 'package:flutter/material.dart';
import 'package:dormdevise/mtqq_open.dart';
import 'package:mqtt_client/mqtt_client.dart';

class OpenDoorPage extends StatefulWidget {
  const OpenDoorPage({super.key});

  @override
  State<OpenDoorPage> createState() => _OpenDoorPageState();
}

class _OpenDoorPageState extends State<OpenDoorPage> {
  bool isOpen = false;
  DateTime? lastTapTime;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () async {
              final now = DateTime.now();
              // 3秒内不能再次发送OPEN
              if (lastTapTime != null &&
                  now.difference(lastTapTime!) < Duration(seconds: 4)) {
                return;
              }
              lastTapTime = now;

              if (!isOpen) {
                setState(() {
                  isOpen = true;
                });
                // 发送OPEN
                try {
                  final client = await MqttConfigPage.connectStatic();
                  final topic = await MqttConfigPage.getSavedTopic();
                  final builder = MqttClientPayloadBuilder();
                  builder.addString('OPEN');
                  client.publishMessage(
                    topic,
                    MqttQos.atLeastOnce,
                    builder.payload!,
                  );
                } catch (e) {
                  // 可选：弹窗提示发送失败
                }
                // 2秒后自动关闭
                Future.delayed(Duration(seconds: 2), () {
                  if (mounted) {
                    setState(() {
                      isOpen = false;
                    });
                  }
                });
              }
            },
            child: AnimatedContainer(
              width: isOpen ? 200 : 100,
              height: isOpen ? 200 : 100,
              color: isOpen ? Colors.green : Colors.red,
              duration: Duration(milliseconds: 700),
              curve: Curves.easeInOut,
              alignment: Alignment.center,
              child: Text(
                isOpen ? '已打开' : '点击开门',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
          SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (context) => MqttConfigPage()));
            },
            child: Text('进入MQTT配置页面'),
          ),
        ],
      ),
    );
  }
}
