import 'package:dormdevise/services/theme/theme_service.dart';
import 'package:flutter/material.dart';

import '../open_door/local_door_lock_settings_page.dart';
import '../open_door/mqtt_settings_page.dart';
import 'about_page.dart';
import 'door_widget_settings_page.dart';
import 'download_source_config_page.dart';
import 'theme_settings_page.dart';
import 'widgets/settings_open_container.dart';

/// 个人中心页面，汇总多类设置入口及动画。
class PersonPage extends StatefulWidget {
  final double appBarProgress;
  final ValueChanged<bool>? onInteractionLockChanged;

  const PersonPage({
    super.key,
    this.appBarProgress = 0.0,
    this.onInteractionLockChanged,
  });

  /// 创建状态对象以驱动 UI 动画。
  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonPageState extends State<PersonPage> {
  /// 构建包含折叠头部与设置列表的界面。
  @override
  Widget build(BuildContext context) {
    // 渐变区间 0.0~1.0，0.0为不透明，1.0为完全透明
    final double progress = widget.appBarProgress.clamp(0.0, 1.0);
    final colorScheme = Theme.of(context).colorScheme;
    final Color scaffoldBg = Theme.of(context).scaffoldBackgroundColor;

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
        icon: Icons.lock_outline,
        title: 'HTTP配置',
        builder: (context) => const LocalDoorLockSettingsPage(),
      ),
      _buildSettingsEntry(
        icon: Icons.dashboard_customize,
        title: '桌面微件',
        builder: (context) => const DoorWidgetSettingsPage(),
      ),
      _buildSettingsEntry(
        icon: Icons.palette_outlined,
        title: '个性主题',
        builder: (context) => const ThemeSettingsPage(),
      ),
      _buildSettingsEntry(
        icon: Icons.cloud_download_outlined,
        title: '下载源',
        builder: (context) => const DownloadSourceConfigPage(),
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
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
              backgroundColor: Colors.transparent,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      // 使用与开关预览一致的颜色：
                      // 洁白模式用 grey.shade700，彩色模式用 primary
                      Color.lerp(
                        _resolveTopGradientColor(colorScheme),
                        scaffoldBg,
                        progress,
                      )!,
                      Color.lerp(
                        colorScheme.primaryContainer,
                        scaffoldBg,
                        progress,
                      )!,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: FlexibleSpaceBar(
                  titlePadding: const EdgeInsets.only(left: 0),
                  // 上滑后从不使用半透明，快速消失而非渐隐
                  title: progress < 0.3
                      ? _buildHead(titleColor)
                      : const SizedBox.shrink(),
                  centerTitle: true,
                ),
              ),
            ),
          ];
        },
        body: Container(
          decoration: BoxDecoration(
            // 从 header 底边色（primaryContainer）柔和过渡到 scaffold 底色，
            // 使用较长的过渡带消除割裂感
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.08, 0.25],
              colors: [
                Color.lerp(colorScheme.primaryContainer, scaffoldBg, progress)!,
                Color.lerp(
                  colorScheme.primaryContainer,
                  scaffoldBg,
                  (progress + 0.3).clamp(0.0, 1.0),
                )!,
                scaffoldBg,
              ],
            ),
          ),
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

  /// 构建单项设置入口并包装为动效容器。
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
        enableTransition: widget.appBarProgress <= 0.05,
        onInteractionLockChanged: widget.onInteractionLockChanged,
      ),
    );
  }
}

/// 构建个人中心的头像与标题区域。
/// 计算个人页面顶部渐变起始色，与开关预览颜色保持一致。
///
/// - 洁白/乌黑模式：使用 grey.shade700（与 Switch track 相同）
/// - 彩色模式：使用 primary 的 HSL 柔化版本
Color _resolveTopGradientColor(ColorScheme colorScheme) {
  final bool isWhite = ThemeService.instance.isWhiteMode;
  if (isWhite) {
    return Colors.grey.shade700;
  }
  // 彩色模式：稍微降低饱和度、提升亮度，使顶部柔和
  return HSLColor.fromColor(
    colorScheme.primary,
  ).withLightness(0.45).withSaturation(0.6).toColor();
}

Widget _buildHead(Color textColor) {
  return Row(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: Image.asset(
            'assets/images/person/person0.jpg',
            width: 48,
            height: 48,
            fit: BoxFit.cover,
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
