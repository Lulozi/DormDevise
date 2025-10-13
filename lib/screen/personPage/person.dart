import 'package:flutter/material.dart';
import 'package:dormdevise/screen/personPage/config_mtqq.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PersonPage extends StatefulWidget {
  const PersonPage({super.key});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

//! TODO 个人页面
class _PersonPageState extends State<PersonPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _initPackageInfo();
  }

  Future<void> _initPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    setState(() {
      _version = info.version;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              //扩展高度
              expandedHeight: 160.0,
              //是否随着滑动隐藏标题
              floating: false,
              //标题栏是否固定在顶部
              pinned: true,
              //定义滚动空间
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 0),
                title: _buildHead(),
                centerTitle: true,
                background: Container(color: const Color(0xFF007AFF)),
              ),
            ),
          ];
        },
        body: Container(
          color: const Color(0xFFF5F5F5),
          child: ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('MQTT配置'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ConfigMqttPage(),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info),
                title: const Text('关于'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: '舍设',
                    applicationVersion: _version,
                    applicationIcon: Image.asset(
                      'assets/images/app_icon.png',
                      width: 50,
                      height: 50,
                    ),
                    applicationLegalese:
                        '© 2025 DormDevise. All rights reserved.',
                  );
                },
              ),
              const Divider(height: 1),
            ],
          ),
        ),
        // TODO 课程表配置页面
      ),
    );
  }
}

_buildHead() {
  return Row(
    children: [
      ClipRRect(
        child: CachedNetworkImage(
          imageUrl: 'https://q1.qlogo.cn/g?b=qq&nk=123456789&s=640',
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          placeholder: (context, url) => const CircularProgressIndicator(),
          errorWidget: (context, url, error) => const Icon(Icons.error),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        'User Name',
        style: const TextStyle(fontSize: 11, color: Colors.white),
      ),
    ],
  );
}
