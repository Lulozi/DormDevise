import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:dormdevise/services/theme/theme_service.dart';
import 'package:dormdevise/utils/person_identity.dart';
import 'package:dormdevise/utils/person_signature_layout.dart';
import 'package:flutter/material.dart';

import '../open_door/door_lock_config_page.dart';
import 'about_page.dart';
import 'door_widget_settings_page.dart';
import 'download_source_config_page.dart';
import 'theme_settings_page.dart';
import 'user_login_dialog.dart';
import 'user_profile_settings_page.dart';
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
  PersonIdentityProfile _profile = PersonIdentityProfile.defaults();

  @override
  void initState() {
    super.initState();
    // 页面初始化时读取身份信息，并订阅后续资料变化以实现跨页同步。
    PersonIdentityService.instance.addListener(_handleIdentityChanged);
    unawaited(_reloadIdentityProfile());
  }

  @override
  void dispose() {
    PersonIdentityService.instance.removeListener(_handleIdentityChanged);
    super.dispose();
  }

  /// 监听身份信息变化并刷新头部显示。
  void _handleIdentityChanged() {
    unawaited(_reloadIdentityProfile());
  }

  /// 从本地服务读取最新身份信息。
  Future<void> _reloadIdentityProfile() async {
    final PersonIdentityProfile profile = await PersonIdentityService.instance
        .loadProfile();
    if (!mounted) {
      return;
    }
    setState(() => _profile = profile);
  }

  /// 点击头像/昵称：未登录先弹出登录，登录后进入用户设置页。
  Future<void> _handleProfileEntryTap() async {
    if (!_profile.isLoggedIn) {
      final bool loggedIn = await UserLoginDialog.show(context);
      if (!mounted || !loggedIn) {
        return;
      }
      await _reloadIdentityProfile();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const UserProfileSettingsPage()),
    );
    if (!mounted) {
      return;
    }
    await _reloadIdentityProfile();
  }

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

    // body滑动动画：progress=0时完全显示，progress=0.1后开始滑出，progress=1时完全隐藏。
    final double bodyProgress = progress <= 0.1
        ? 1.0
        : 1.0 - ((progress - 0.1) / 0.9).clamp(0.0, 1.0);

    final List<Widget> cards = [
      // body内容，按顺序排列
      _buildSettingsEntry(
        icon: Icons.door_front_door_outlined,
        title: '门锁配置',
        builder: (context) => const OpenDoorSettingsPage(),
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
                      ? _buildHead(
                          context,
                          titleColor,
                          profile: _profile,
                          onTap: _handleProfileEntryTap,
                        )
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

Widget _buildHead(
  BuildContext context,
  Color textColor, {
  required PersonIdentityProfile profile,
  required VoidCallback onTap,
}) {
  const double avatarRadius = 24;
  const double avatarSize = avatarRadius * 2;
  final (String signatureText, bool isSignatureTwoLines) =
      formatSignatureForAvatarInfo(profile.signature, maxCharsPerLine: 13);
  final TextStyle nicknameTextStyle = TextStyle(
    fontSize: 13,
    color: textColor,
    fontWeight: FontWeight.w600,
    height: 1.1,
  );
  // 个人页签名字号下调两个档位，避免在头部区域显得过大。
  final double signatureFontSize = isSignatureTwoLines ? 8 : 9;
  final TextStyle signatureTextStyle = nicknameTextStyle.copyWith(
    fontSize: signatureFontSize,
    fontWeight: FontWeight.w400,
    color: textColor.withValues(alpha: 0.82),
  );
  final double signatureTopGap = computeAvatarInfoSignatureTopGap(
    avatarSize: avatarSize,
    nicknameStyle: nicknameTextStyle,
    signatureStyle: signatureTextStyle,
    twoLines: isSignatureTwoLines,
  );
  final double signatureValueMaxWidth = min(
    190.0,
    max(120.0, MediaQuery.sizeOf(context).width * 0.46),
  );

  return Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 12),
    child: InkWell(
      borderRadius: BorderRadius.circular(32),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(avatarRadius),
              child: _ProfileAvatarImage(path: profile.avatarPath),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: avatarSize,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // 个人页昵称整体向下偏移 6px。
                    const SizedBox(height: 6),
                    Text(
                      profile.headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nicknameTextStyle,
                    ),
                    SizedBox(height: signatureTopGap),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: signatureValueMaxWidth,
                      ),
                      child: Text(
                        signatureText,
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                        style: signatureTextStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 根据路径渲染头像：优先本地文件，失败时回退默认资源头像。
class _ProfileAvatarImage extends StatelessWidget {
  const _ProfileAvatarImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final String normalized = path.trim();

    Widget buildFallbackAvatar() {
      return Image.asset(
        kPersonAvatarAsset,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
      );
    }

    final bool isLikelyLocalFilePath =
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized);
    if (isLikelyLocalFilePath) {
      return Image.file(
        File(normalized),
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => buildFallbackAvatar(),
      );
    }

    return Image.asset(
      normalized.isEmpty ? kPersonAvatarAsset : normalized,
      width: 48,
      height: 48,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => buildFallbackAvatar(),
    );
  }
}
