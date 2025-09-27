import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class OpenDoorPage extends StatefulWidget {
  const OpenDoorPage({super.key});

  @override
  State<OpenDoorPage> createState() => _OpenDoorPageState();
}

class _OpenDoorPageState extends State<OpenDoorPage> {
  bool isOpen = false;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () async {
              if (!isOpen) {
                setState(() {
                  isOpen = true;
                });
                // 发送POST请求
                try {
                  await http.post(Uri.parse('http://192.168.10.130/api/open'));
                } catch (e) {
                  // 可以根据需要处理异常
                }
                Future.delayed(Duration(seconds: 1), () {
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
        ],
      ),
    );
  }
}
