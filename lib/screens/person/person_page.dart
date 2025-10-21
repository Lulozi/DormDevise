import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:dormdevise/screens/open_door/location_settings_page.dart';
import 'package:dormdevise/screens/open_door/mqtt_settings_page.dart';
import 'package:dormdevise/screens/open_door/wifi_settings_page.dart';
import 'package:dormdevise/screens/person/about_page.dart';
import 'package:dormdevise/screens/person/widgets/settings_open_container.dart';

class PersonPage extends StatefulWidget {
  final double appBarProgress;
  const PersonPage({super.key, this.appBarProgress = 0.0});

  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  @override
  Widget build(BuildContext context) {
    // 渐变区间 0.0~1.0，0.0为不透明，1.0为完全透明
    final double progress = widget.appBarProgress.clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    // 渐变色：primary/primaryContainer -> 完全透明
    final Color appBarColor = Color.lerp(
      Color.lerp(colorScheme.primary, colorScheme.primaryContainer, progress)!,
      Colors.transparent,
      progress,
    )!;
    final Color titleColor = Color.lerp(
      Colors.white,
      colorScheme.onSurface,
      progress,
    )!;

    // body滑动动画：progress=0时完全显示，progress=0.1后开始滑出，progress=1时完全隐藏
    double bodyProgress = 1.0;
    if (progress <= 0.1 && progress >= 0.0) {
      bodyProgress = 1.0;
    } else if (progress > 0.1 && progress <= 1.0) {
      bodyProgress = 1.0 - ((progress - 0.1) / 0.9).clamp(0.0, 1.0);
    } else if (progress > 1.0) {
      bodyProgress = 0.0;
    }

    final List<Widget> cards = [
      // body内容，按顺序排列
      _buildSettingsEntry(
        icon: Icons.api_rounded,
        title: 'MQTT配置',
        builder: (context) => const MqttSettingsPage(),
      ),
      _buildSettingsEntry(
        icon: Icons.wifi,
        title: 'WiFi设置',
        builder: (context) => const WifiSettingsPage(),
      ),
      _buildSettingsEntry(
        icon: Icons.location_on,
        title: '定位设置',
        builder: (context) => const LocationSettingsPage(),
      ),
      _buildSettingsEntry(
        icon: Icons.info_outline,
        title: '关于',
        builder: (context) => const AboutPage(),
      ),
    ];

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) {
          return <Widget>[
            SliverAppBar(
              expandedHeight: 160.0,
              floating: false,
              pinned: true,
              surfaceTintColor: colorScheme.surface,
              backgroundColor: appBarColor,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: 0),
                title: Opacity(
                  opacity: 1.0 - progress,
                  child: _buildHead(titleColor),
                ),
                centerTitle: true,
                background: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Color.lerp(
                          colorScheme.primary,
                          Colors.transparent,
                          progress,
                        )!,
                        Color.lerp(
                          colorScheme.primaryContainer,
                          Colors.transparent,
                          progress,
                        )!,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),
          ];
        },
        body: Container(
          color: colorScheme.surface,
          child: ListView.builder(
            itemCount: cards.length,
            itemBuilder: (context, index) {
              // 每个子项的动画延迟0.2（200ms）
              double delay = 0.2 * index;
              double itemProgress = ((bodyProgress - delay) / (1 - delay))
                  .clamp(0.0, 1.0);
              return Transform.translate(
                offset: Offset(100 * (1 - itemProgress), 0),
                child: Opacity(opacity: itemProgress, child: cards[index]),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsEntry({
    required IconData icon,
    required String title,
    required WidgetBuilder builder,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SettingsOpenContainer(
        icon: icon,
        title: title,
        pageBuilder: builder,
      ),
    );
  }
}

Widget _buildHead(Color textColor) {
  return Row(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: CachedNetworkImage(
            imageUrl:
                'http://minio.xiaoheiwu.fun/imgs/2025-10-13-20:08:59-4ce88e37c9914ac5be496592a103f08d.jpg',
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            placeholder: (context, url) => const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            errorWidget: (context, url, error) => const Icon(Icons.error),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        'Your Name',
        style: TextStyle(
          fontSize: 13,
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}
