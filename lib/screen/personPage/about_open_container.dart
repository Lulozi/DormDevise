import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animations/animations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 关于按钮的开合容器
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
      openBuilder: (context, _) => AboutPage(version: version),
      closedBuilder: (context, openContainer) => ListTile(
        leading: Icon(Icons.info_outline, color: colorScheme.primary),
        title: Text(
          '关于',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        trailing: Icon(Icons.chevron_right, color: colorScheme.outline),
        onTap: openContainer,
      ),
    );
  }
}

class AboutPage extends StatefulWidget {
  final String version;

  const AboutPage({super.key, required this.version});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;

  Future<void> _handleCheckForUpdates() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    try {
      final latest = await _fetchLatestReleaseInfo();
      if (!mounted) return;

      if (latest == null) {
        _showSnackBar('暂未找到可用的发布信息');
        return;
      }

      final latestVersion = latest.version;
      final currentVersion = _safeParseVersion(widget.version);
      final asset = _selectAndroidAsset(latest.assets);

      final hasNewer = latestVersion != null && currentVersion != null
          ? latestVersion > currentVersion
          : latestVersion != null;

      if (!hasNewer) {
        _showSnackBar('当前已是最新版本');
        return;
      }

      if (asset == null) {
        _showSnackBar('未找到适用于 Android 的安装包，请前往发布页手动下载');
        return;
      }

      final shouldUpdate = await _showUpdateAvailableDialog(
        context,
        latest,
        asset,
      );
      if (!mounted) return;
      if (shouldUpdate != true) {
        return;
      }

      await _downloadAndInstallUpdate(context, asset);
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('检查更新失败：${_mapErrorMessage(error)}');
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openRepository() async {
    await _launchExternalUrl(
      context,
      Uri.parse('https://github.com/Lulozi/DormDevise'),
    );
  }

  Future<void> _openReleasePage() async {
    await _launchExternalUrl(
      context,
      Uri.parse('https://github.com/Lulozi/DormDevise/releases'),
    );
  }

  Future<void> _openIssuePage() async {
    await _launchExternalUrl(
      context,
      Uri.parse('https://github.com/Lulozi/DormDevise/issues'),
    );
  }

  Future<void> _openBilibiliPage() async {
    await _launchExternalUrl(
      context,
      Uri.parse('https://space.bilibili.com/212994722'),
    );
  }

  Future<void> _openGitHubPage() async {
    await _launchExternalUrl(context, Uri.parse('https://github.com/Lulozi'));
  }

  Future<void> _showLicenseDialog() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
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
                    child: Theme(
                      data: theme,
                      child: LicensePage(
                        applicationName: 'DormDevise',
                        applicationVersion: widget.version,
                        applicationLegalese: '© 2025 DormDevise',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + padding.bottom),
          children: [
            _AboutHeader(
              version: widget.version,
              checkingUpdate: _checkingUpdate,
              onCheckUpdate: _handleCheckForUpdates,
              onOpenRepository: _openRepository,
              onOpenReleasePage: _openReleasePage,
              onOpenBilibiliPage: _openBilibiliPage,
              onOpenGitHubPage: _openGitHubPage,
            ),
            const SizedBox(height: 16),
            ReleaseNotesCard(appVersion: widget.version),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.link_outlined,
              title: '快速入口',
              children: [
                _InfoTile(
                  icon: Icons.code,
                  title: 'GitHub 仓库',
                  subtitle: '查看源码、提交 Issue 或参与贡献',
                  onTap: (_) => _openRepository(),
                ),
                _InfoTile(
                  icon: Icons.new_releases_outlined,
                  title: '版本发布页',
                  subtitle: '浏览历史版本与更新说明',
                  onTap: (_) => _openReleasePage(),
                ),
                _InfoTile(
                  icon: Icons.support_agent_outlined,
                  title: '反馈问题',
                  subtitle: '给我们留言，帮助 DormDevise 做得更好',
                  onTap: (_) => _openIssuePage(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.verified_user_outlined,
              title: '许可信息',
              children: [
                _InfoTile(
                  icon: Icons.library_books_outlined,
                  title: '开源许可',
                  subtitle: '查看依赖与第三方组件授权',
                  onTap: (_) => _showLicenseDialog(),
                ),
                Text('所有用户配置均存储在本地 SharedPreferences 内，除非主动授权，不会上传至云端。'),
              ],
            ),
            const SizedBox(height: 16),
            _SectionCard(
              icon: Icons.favorite_outline,
              title: '开发者的话',
              children: const [
                _BulletTile(text: '感谢使用 DormDevise，欢迎向同学们分享。'),
                _BulletTile(text: '项目遵循开源协议，期待你的建议或 PR。'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutHeader extends StatelessWidget {
  final String version;
  final bool checkingUpdate;
  final Future<void> Function() onCheckUpdate;
  final Future<void> Function() onOpenRepository;
  final Future<void> Function() onOpenReleasePage;
  final Future<void> Function() onOpenBilibiliPage;
  final Future<void> Function() onOpenGitHubPage;

  const _AboutHeader({
    required this.version,
    required this.checkingUpdate,
    required this.onCheckUpdate,
    required this.onOpenRepository,
    required this.onOpenReleasePage,
    required this.onOpenBilibiliPage,
    required this.onOpenGitHubPage,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget buildVersionChip() {
      final avatar = checkingUpdate
          ? const SizedBox(
              width: 18,
              height: 18,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : Icon(Icons.verified_outlined, color: colorScheme.primary, size: 18);

      return GestureDetector(
        onTap: checkingUpdate ? null : () => unawaited(onCheckUpdate()),
        behavior: HitTestBehavior.opaque,
        child: Chip(
          label: Text('版本 $version'),
          avatar: avatar,
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 36,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(
                Icons.meeting_room_outlined,
                size: 36,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '设舍',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '服务于宿舍的一站式工具。',
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            buildVersionChip(),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                ActionChip(
                  avatar: FaIcon(
                    FontAwesomeIcons.github,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  label: const Text('GitHub'),
                  onPressed: () => unawaited(onOpenGitHubPage()),
                ),
                ActionChip(
                  avatar: FaIcon(
                    FontAwesomeIcons.bilibili,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  label: const Text('Bilibili'),
                  onPressed: () => unawaited(onOpenBilibiliPage()),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '点击版本检查更新',
              style: textTheme.labelSmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
  final Future<void> Function(BuildContext context)? onTap;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
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
      onTap: onTap == null ? null : () => onTap!(context),
    );
  }
}

String _mapErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  return raw;
}

Future<bool?> _showUpdateAvailableDialog(
  BuildContext context,
  _ReleaseInfo release,
  _ReleaseAsset asset,
) {
  final highlights = _extractReleaseHighlights(release.body ?? '');
  final description = release.body?.trim();
  final versionLabel =
      release.readableLabel ??
      (release.version != null ? 'v${release.version}' : '最新版本');
  final sizeLabel = _formatFileSize(asset.size);

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      final textTheme = Theme.of(dialogContext).textTheme;
      final colorScheme = Theme.of(dialogContext).colorScheme;
      return AlertDialog(
        title: Text('发现新版本 $versionLabel'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('安装包大小：$sizeLabel', style: textTheme.bodyMedium),
              if (highlights.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('更新亮点：', style: textTheme.titleSmall),
                const SizedBox(height: 8),
                ...highlights.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(color: colorScheme.primary),
                        ),
                        Expanded(child: Text(item)),
                      ],
                    ),
                  ),
                ),
              ] else if (description != null && description.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(description),
              ] else ...[
                const SizedBox(height: 16),
                Text('暂无更新说明，是否继续下载并安装？'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('立即更新'),
          ),
        ],
      );
    },
  );
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
                  child: WebViewWidget(
                    controller: controller,
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                        () => EagerGestureRecognizer(),
                      ),
                    },
                  ),
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
            children: const [_BulletTile(text: '无法获取更新说明，请稍请检查网络后重试。')],
          );
        }

        final notes = snapshot.data ?? const [];
        final displayNotes = notes.isEmpty ? ['暂无更新说明。'] : notes;

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
    final normalizedVersion = appVersionString.split('+').first;
    final cacheKey = 'release_notes_$normalizedVersion';
    final prefs = await SharedPreferences.getInstance();

    final cachedValue = prefs.getString(cacheKey);
    if (cachedValue != null) {
      try {
        final cachedList = List<String>.from(jsonDecode(cachedValue) as List);
        return cachedList;
      } catch (_) {
        // Fall through to refetch if cache is corrupted.
      }
    }

    final allReleases = await _loadReleasesFromApi();
    if (allReleases.isEmpty) return const [];

    final releases = allReleases
        .where((info) => info.version != null && !info.isDraft)
        .toList();
    if (releases.isEmpty) return const [];

    final appVersion = _safeParseVersion(appVersionString);
    releases.sort(_compareReleaseOrder);

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

    final notes = _extractReleaseHighlights(body);

    await prefs.setString(cacheKey, jsonEncode(notes));
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
  final String? name;
  final String? tagName;
  final bool isDraft;
  final bool isPrerelease;
  final DateTime? publishedAt;
  final List<_ReleaseAsset> assets;

  _ReleaseInfo({
    required this.version,
    required this.body,
    required this.name,
    required this.tagName,
    required this.isDraft,
    required this.isPrerelease,
    required this.publishedAt,
    required this.assets,
  });

  String? get readableLabel {
    if (tagName != null && tagName!.isNotEmpty) {
      return tagName;
    }
    if (name != null && name!.isNotEmpty) {
      return name;
    }
    if (version != null) {
      return 'v${version.toString()}';
    }
    return null;
  }

  factory _ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final name = json['name'] as String? ?? '';
    final tag = json['tag_name'] as String? ?? '';
    final body = json['body'] as String?;
    final draft = json['draft'] as bool? ?? false;
    final prerelease = json['prerelease'] as bool? ?? false;
    final publishedAtRaw = json['published_at'] as String?;
    final publishedAt = publishedAtRaw == null
        ? null
        : DateTime.tryParse(publishedAtRaw)?.toLocal();

    final assetsJson = json['assets'] as List<dynamic>? ?? const [];
    final assets = assetsJson
        .map((item) => _ReleaseAsset.fromJson(item as Map<String, dynamic>))
        .where((asset) => asset.browserDownloadUrl.isNotEmpty)
        .toList();

    final version = _parseVersionFromMetadata(name, tag);
    return _ReleaseInfo(
      version: version,
      body: body,
      name: name.isEmpty ? null : name,
      tagName: tag.isEmpty ? null : tag,
      isDraft: draft,
      isPrerelease: prerelease,
      publishedAt: publishedAt,
      assets: assets,
    );
  }
}

Future<_ReleaseInfo?> _fetchLatestReleaseInfo() async {
  final releases = await _loadReleasesFromApi();
  if (releases.isEmpty) return null;

  final stable = releases
      .where((release) => !release.isDraft && !release.isPrerelease)
      .toList();
  final candidates = stable.isNotEmpty
      ? stable
      : releases.where((release) => !release.isDraft).toList();

  if (candidates.isEmpty) {
    releases.sort(_compareReleaseOrder);
    return releases.first;
  }

  candidates.sort(_compareReleaseOrder);
  return candidates.first;
}

Future<List<_ReleaseInfo>> _loadReleasesFromApi() async {
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

  return jsonList
      .map((item) => _ReleaseInfo.fromJson(item as Map<String, dynamic>))
      .toList();
}

int _compareReleaseOrder(_ReleaseInfo a, _ReleaseInfo b) {
  final Version? versionA = a.version;
  final Version? versionB = b.version;
  if (versionA != null && versionB != null) {
    final versionOrder = versionB.compareTo(versionA);
    if (versionOrder != 0) return versionOrder;
  } else if (versionA != null) {
    return -1;
  } else if (versionB != null) {
    return 1;
  }

  final DateTime? dateA = a.publishedAt;
  final DateTime? dateB = b.publishedAt;
  if (dateA != null && dateB != null) {
    final dateOrder = dateB.compareTo(dateA);
    if (dateOrder != 0) return dateOrder;
  } else if (dateA != null) {
    return -1;
  } else if (dateB != null) {
    return 1;
  }

  return 0;
}

_ReleaseAsset? _selectAndroidAsset(List<_ReleaseAsset> assets) {
  if (assets.isEmpty) return null;

  final apkAssets = assets.where((asset) => asset.isAndroidApk).toList();
  if (apkAssets.isEmpty) return null;

  apkAssets.sort((a, b) => b.size.compareTo(a.size));
  return apkAssets.first;
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final precision = unitIndex == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
}

enum _DownloadDialogResult { success, failure, background, cancelled }

class _DownloadCancelled implements Exception {
  const _DownloadCancelled();

  @override
  String toString() => 'DownloadCancelled';
}

class _DownloadProgress {
  final int receivedBytes;
  final int? totalBytes;

  const _DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    if (total == 0) return null;
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

String _describeProgress(_DownloadProgress progress) {
  if (progress.receivedBytes <= 0) {
    return '正在准备下载...';
  }

  final downloadedLabel = _formatFileSize(progress.receivedBytes);
  final total = progress.totalBytes;
  if (total == null || total <= 0) {
    return '已下载 $downloadedLabel';
  }

  final totalLabel = _formatFileSize(total);
  final percent = ((progress.fraction ?? 0) * 100)
      .clamp(0, 100)
      .toStringAsFixed(0);
  return '已下载 $percent% ($downloadedLabel / $totalLabel)';
}

Future<bool> _confirmBackgroundDownload(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('切换为后台下载？'),
        content: const Text('下载将继续在后台进行，完成后会自动唤起安装程序。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续等待'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('后台下载'),
          ),
        ],
      );
    },
  );

  return result ?? false;
}

Future<void> _downloadAndInstallUpdate(
  BuildContext context,
  _ReleaseAsset asset,
) async {
  final totalHint = asset.size > 0 ? asset.size : null;
  final progressNotifier = ValueNotifier<_DownloadProgress>(
    _DownloadProgress(receivedBytes: 0, totalBytes: totalHint),
  );

  final downloadCompleted = Completer<void>();
  File? downloadedFile;
  Object? downloadError;
  var backgroundMode = false;
  var cancelRequested = false;
  var dialogClosed = false;
  final httpClient = http.Client();

  Future<void> runDownload(NavigatorState navigator) async {
    try {
      final file = await _downloadReleaseAsset(
        asset,
        onProgress: (received, total) {
          final effectiveTotal = total ?? totalHint;
          progressNotifier.value = _DownloadProgress(
            receivedBytes: received,
            totalBytes: effectiveTotal,
          );
        },
        client: httpClient,
        shouldCancel: () => cancelRequested,
      );
      downloadedFile = file;
    } catch (error) {
      if (cancelRequested) {
        downloadError = const _DownloadCancelled();
      } else {
        downloadError = error;
      }
    } finally {
      if (!downloadCompleted.isCompleted) {
        downloadCompleted.complete();
      }

      if (!backgroundMode && navigator.mounted && !dialogClosed) {
        dialogClosed = true;
        navigator.pop(
          downloadError == null
              ? _DownloadDialogResult.success
              : _DownloadDialogResult.failure,
        );
      }
    }
  }

  final dialogResult = await showDialog<_DownloadDialogResult>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      var started = false;
      return StatefulBuilder(
        builder: (stateContext, _) {
          final navigator = Navigator.of(dialogContext);
          if (!started) {
            started = true;
            Future<void>.microtask(() => runDownload(navigator));
          }

          return PopScope(
            canPop: false,
            onPopInvokedWithResult: (didPop, __) async {
              if (didPop) {
                return;
              }

              if (downloadCompleted.isCompleted) {
                if (navigator.mounted) {
                  dialogClosed = true;
                  navigator.pop(
                    downloadError == null
                        ? _DownloadDialogResult.success
                        : _DownloadDialogResult.failure,
                  );
                }
                return;
              }

              final shouldBackground = await _confirmBackgroundDownload(
                dialogContext,
              );
              if (shouldBackground) {
                backgroundMode = true;
                if (navigator.mounted) {
                  dialogClosed = true;
                  navigator.pop(_DownloadDialogResult.background);
                }
              }
            },
            child: ValueListenableBuilder<_DownloadProgress>(
              valueListenable: progressNotifier,
              builder: (context, progress, __) {
                return AlertDialog(
                  title: const Text('下载更新'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: progress.fraction),
                      const SizedBox(height: 12),
                      Text(_describeProgress(progress)),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        if (downloadCompleted.isCompleted) {
                          dialogClosed = true;
                          navigator.pop(_DownloadDialogResult.cancelled);
                          return;
                        }
                        cancelRequested = true;
                        httpClient.close();
                        dialogClosed = true;
                        navigator.pop(_DownloadDialogResult.cancelled);
                      },
                      child: const Text('取消'),
                    ),
                  ],
                );
              },
            ),
          );
        },
      );
    },
  );

  progressNotifier.dispose();

  final resolvedResult =
      dialogResult ??
      (downloadError == null
          ? _DownloadDialogResult.success
          : _DownloadDialogResult.failure);

  if (!downloadCompleted.isCompleted) {
    await downloadCompleted.future;
  }

  httpClient.close();

  if (resolvedResult == _DownloadDialogResult.background && context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('已切换到后台下载，完成后会自动打开安装程序')));
  }

  if (!context.mounted) {
    return;
  }

  if (downloadError != null) {
    if (downloadError is _DownloadCancelled ||
        resolvedResult == _DownloadDialogResult.cancelled) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('下载已取消')));
      return;
    }
    final message = _mapErrorMessage(downloadError!);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('下载更新失败：$message')));
    return;
  }

  final file = downloadedFile;
  if (file == null) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('下载完成后未找到安装包。')));
    return;
  }

  if (resolvedResult == _DownloadDialogResult.background) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('下载完成，正在打开安装程序...')));
  }

  final openResult = await OpenFilex.open(file.path);
  if (!context.mounted) return;

  if (openResult.type != ResultType.done) {
    final message = openResult.message;
    final displayMessage = message.isEmpty ? '请稍后重试' : message;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('无法打开安装包：$displayMessage')));
  }
}

Future<File> _downloadReleaseAsset(
  _ReleaseAsset asset, {
  required void Function(int receivedBytes, int? totalBytes) onProgress,
  http.Client? client,
  bool Function()? shouldCancel,
}) async {
  final downloadUri = Uri.parse(asset.browserDownloadUrl);
  final httpClient = client ?? http.Client();
  final ownsClient = client == null;
  try {
    final request = http.Request('GET', downloadUri);
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      throw Exception('下载失败，状态码 ${response.statusCode}');
    }

    final totalBytes =
        response.contentLength ?? (asset.size > 0 ? asset.size : null);
    final tempDir = await getTemporaryDirectory();
    final fileName = _sanitizeFileName(
      asset.name.isEmpty ? 'DormDevise-update.apk' : asset.name,
    );
    final filePath = '${tempDir.path}${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    final sink = file.openWrite();
    var received = 0;
    var success = false;
    onProgress(0, totalBytes);
    try {
      await for (final chunk in response.stream) {
        if (shouldCancel?.call() ?? false) {
          throw const _DownloadCancelled();
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress(received, totalBytes);
      }
      success = true;
    } finally {
      await sink.flush();
      await sink.close();
      if (!success && await file.exists()) {
        await file.delete();
      }
    }

    return file;
  } finally {
    if (ownsClient) {
      httpClient.close();
    }
  }
}

String _sanitizeFileName(String raw) {
  final sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (sanitized.trim().isEmpty) {
    return 'DormDevise-update-${DateTime.now().millisecondsSinceEpoch}.apk';
  }
  return sanitized;
}

List<String> _extractReleaseHighlights(String body) {
  final lines = body.split(RegExp(r'\r?\n'));
  final notes = <String>[];
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
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

class _ReleaseAsset {
  final String name;
  final String browserDownloadUrl;
  final String contentType;
  final int size;

  const _ReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.contentType,
    required this.size,
  });

  bool get isAndroidApk {
    final lowerName = name.toLowerCase();
    final lowerType = contentType.toLowerCase();
    return lowerName.endsWith('.apk') ||
        lowerType.contains('application/vnd.android.package-archive');
  }

  factory _ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return _ReleaseAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
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
