import 'dart:convert';

import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pub_semver/pub_semver.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 关于按钮的丝巾动画容器
class AboutOpenContainer extends StatelessWidget {
  final String version;
  const AboutOpenContainer({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return OpenContainer(
      transitionType: ContainerTransitionType.fadeThrough,
      openColor: colorScheme.surface,
      closedColor: colorScheme.surfaceContainerHighest,
      closedElevation: 0,
      openElevation: 0,
      closedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      openShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      transitionDuration: const Duration(milliseconds: 600),
      closedBuilder: (context, openContainer) => ListTile(
        leading: Icon(Icons.info_outline, color: colorScheme.primary),
        title: Text(
          '关于',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '版本 $version',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: colorScheme.onSurfaceVariant,
        ),
        onTap: openContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        tileColor: colorScheme.surfaceContainerHighest,
      ),
      openBuilder: (context, _) => AboutPage(version: version),
    );
  }
}

class AboutPage extends StatelessWidget {
  final String version;
  const AboutPage({super.key, required this.version});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final repositoryUri = Uri.parse('https://github.com/Lulozi/DormDevise');
    final bilibiliUri = Uri.parse('https://space.bilibili.com/212994722');
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AboutHeader(
                version: version,
                colorScheme: colorScheme,
                textTheme: textTheme,
              ),
              const SizedBox(height: 24),
              _SectionCard(
                icon: Icons.dashboard_customize_outlined,
                title: '项目简介',
                children: [
                  Text(
                    'DormDevise 致力于打造宿舍智能化的一站式体验，支持开门、课表等核心模块，搭配 Material 3 动效提供沉浸式交互。',
                    style: textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              ReleaseNotesCard(appVersion: version),
              const SizedBox(height: 20),
              _SectionCard(
                icon: Icons.support_agent_outlined,
                title: '团队与支持',
                children: [
                  _InfoTile(
                    icon: Icons.people_alt_outlined,
                    title: '开发者',
                    subtitle: 'Lulo',
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: (context) =>
                        _launchExternalUrl(context, bilibiliUri),
                  ),
                  _InfoTile(
                    icon: Icons.public,
                    title: '官网与开源',
                    subtitle: 'github.com/Lulozi/DormDevise',
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: (context) =>
                        _launchExternalUrl(context, repositoryUri),
                  ),
                  _InfoTile(
                    icon: Icons.mail_outline,
                    title: '联系邮箱',
                    subtitle: 'Lulo@xiaoheiwu.fun',
                    onTap: (context) async {
                      await Clipboard.setData(
                        const ClipboardData(text: 'Lulo@xiaoheiwu.fun'),
                      );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('联系邮箱已复制到剪贴板')),
                      );
                    },
                    trailing: const Icon(Icons.copy, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _SectionCard(
                icon: Icons.verified_user_outlined,
                title: '许可信息',
                children: [
                  _InfoTile(
                    icon: Icons.library_books_outlined,
                    title: '开源许可',
                    subtitle: '查看依赖与第三方组件授权',
                    trailing: const Icon(Icons.open_in_new, size: 18),
                    onTap: (context) async {
                      showLicensePage(
                        context: context,
                        applicationName: 'DormDevise',
                        applicationVersion: version,
                        applicationLegalese: '© 2025 DormDevise',
                      );
                    },
                  ),
                  Text(
                    '所有用户配置均存储在本地 SharedPreferences 内，除非主动授权，不会上传至云端。',
                    style: textTheme.bodyMedium,
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

class _AboutHeader extends StatelessWidget {
  final String version;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _AboutHeader({
    required this.version,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.85),
            colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Image.asset(
              'assets/images/app_icon.png',
              fit: BoxFit.cover,
              errorBuilder: (context, _, __) => Icon(
                Icons.sensor_door_outlined,
                size: 48,
                color: colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '舍设 DormDevise',
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              Chip(
                label: Text('版本 $version'),
                avatar: Icon(
                  Icons.verified_outlined,
                  color: colorScheme.primary,
                  size: 18,
                ),
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                side: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              Chip(
                label: const Text('Material 3'),
                backgroundColor: colorScheme.secondaryContainer.withValues(
                  alpha: 0.4,
                ),
                avatar: Icon(
                  Icons.palette_outlined,
                  color: colorScheme.secondary,
                  size: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '宿舍智能管理，触手可及。用更优雅的方式连接门禁、设备与人。',
            style: textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final spacedChildren = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      spacedChildren.add(children[i]);
      if (i != children.length - 1) {
        spacedChildren.add(const SizedBox(height: 12));
      }
    }
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...spacedChildren,
          ],
        ),
      ),
    );
  }
}

class _BulletTile extends StatelessWidget {
  final String text;

  const _BulletTile({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: textTheme.bodyMedium)),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final Future<void> Function(BuildContext context)? onTap;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(
        title,
        style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle, style: textTheme.bodyMedium),
      trailing: trailing,
      onTap: onTap == null ? null : () => onTap!(context),
    );
  }
}

Future<void> _launchExternalUrl(BuildContext context, Uri uri) async {
  final openedInSheet = await _showInAppWebSheet(context, uri);
  if (openedInSheet) return;
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!context.mounted || launched) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('无法打开链接，请稍后再试')));
}

Future<bool> _showInAppWebSheet(BuildContext context, Uri uri) async {
  if (!context.mounted) return false;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;

  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..enableZoom(true)
    ..loadRequest(uri);

  bool sheetOpened = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      sheetOpened = true;
      final colorScheme = Theme.of(sheetContext).colorScheme;
      return SafeArea(
        top: false,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: WebViewWidget(controller: controller),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  return sheetOpened;
}

class ReleaseNotesCard extends StatefulWidget {
  final String appVersion;

  const ReleaseNotesCard({super.key, required this.appVersion});

  @override
  State<ReleaseNotesCard> createState() => _ReleaseNotesCardState();
}

class _ReleaseNotesCardState extends State<ReleaseNotesCard> {
  late final Future<List<String>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _notesFuture = _fetchReleaseNotes(widget.appVersion);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _notesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _SectionCard(
            icon: Icons.auto_graph_outlined,
            title: '本次更新亮点',
            children: [
              Row(
                children: const [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Expanded(child: Text('正在获取更新说明...')),
                ],
              ),
            ],
          );
        }

        if (snapshot.hasError) {
          return _SectionCard(
            icon: Icons.auto_graph_outlined,
            title: '本次更新亮点',
            children: const [_BulletTile(text: '无法获取更新说明，请稍后重试。')],
          );
        }

        final notes = snapshot.data ?? const [];
        final displayNotes = notes.isEmpty ? ['暂无更新说明，欢迎稍后再试。'] : notes;

        return _SectionCard(
          icon: Icons.auto_graph_outlined,
          title: '本次更新亮点',
          children: displayNotes
              .map((note) => _BulletTile(text: note))
              .toList(),
        );
      },
    );
  }

  Future<List<String>> _fetchReleaseNotes(String appVersionString) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/Lulozi/DormDevise/releases',
    );
    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'DormDevise-App',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('GitHub 返回状态码 ${response.statusCode}');
    }

    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    if (jsonList.isEmpty) return const [];

    final appVersion = _safeParseVersion(appVersionString);
    final releases = jsonList
        .map((item) => _ReleaseInfo.fromJson(item as Map<String, dynamic>))
        .where((info) => info.version != null)
        .cast<_ReleaseInfo>()
        .toList();

    if (releases.isEmpty) return const [];

    releases.sort((a, b) => b.version!.compareTo(a.version!));

    _ReleaseInfo? matchedRelease;
    if (appVersion != null) {
      for (final info in releases) {
        if (info.version == appVersion) {
          matchedRelease = info;
          break;
        }
      }

      if (matchedRelease == null) {
        for (final info in releases) {
          if (info.version! <= appVersion) {
            matchedRelease = info;
            break;
          }
        }
      }
    } else {
      matchedRelease = releases.first;
    }

    if (matchedRelease == null) {
      return const [];
    }

    final body = matchedRelease.body?.trim() ?? '';
    if (body.isEmpty) return const [];

    final lines = body.split(RegExp(r'\r?\n'));
    final notes = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.startsWith('•')) {
        notes.add(trimmed.substring(1).trim());
      } else if (trimmed.startsWith('- ')) {
        notes.add(trimmed.substring(2).trim());
      } else if (trimmed.startsWith('* ')) {
        notes.add(trimmed.substring(2).trim());
      }
    }

    return notes;
  }
}

Version? _safeParseVersion(String raw) {
  try {
    final sanitized = raw.split('+').first;
    return Version.parse(sanitized);
  } catch (_) {
    return null;
  }
}

class _ReleaseInfo {
  final Version? version;
  final String? body;

  _ReleaseInfo({required this.version, required this.body});

  factory _ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final tag = json['tag_name'] as String? ?? '';
    final body = json['body'] as String?;

    final version = _parseVersionFromMetadata(name, tag);
    return _ReleaseInfo(version: version, body: body);
  }
}

Version? _parseVersionFromMetadata(String name, String tag) {
  final candidates = <String?>[
    tag,
    RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(name)?.group(1),
    RegExp(r'DormDevise-v(\d+\.\d+\.\d+)').firstMatch(name)?.group(1),
  ];

  for (final candidate in candidates) {
    if (candidate == null || candidate.isEmpty) {
      continue;
    }

    final normalized = candidate.startsWith('v')
        ? candidate.substring(1)
        : candidate;
    try {
      return Version.parse(normalized);
    } catch (_) {
      continue;
    }
  }

  return null;
}
