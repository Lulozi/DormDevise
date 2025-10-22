// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/services/update/update_download_service.dart';

/// 关于页面，汇总版本信息与更新逻辑。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  /// 创建页面状态以处理更新检查与 UI 展示。
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;
  bool _hasNewerVersion = false;
  String _currentVersion = '';
  late final UpdateDownloadService _downloadService;
  late final UpdateDownloadCoordinator _downloadCoordinator;
  late final VoidCallback _downloadListener;
  List<String>? _cachedSupportedAbis;
  Future<List<String>>? _supportedAbisFuture;
  _DownloadSession? _activeDownloadSession;
  _VersionActionMode _versionActionMode = _VersionActionMode.checkUpdate;

  /// 初始化监听器并预加载版本与设备信息。
  @override
  void initState() {
    super.initState();
    _downloadService = UpdateDownloadService.instance;
    _downloadCoordinator = _downloadService.coordinator;
    _downloadListener = () {
      if (!mounted) return;
      setState(() {});
    };
    _downloadCoordinator.addListener(_downloadListener);
    unawaited(_initPackageInfo());
    unawaited(_primeLatestVersionStatus());
    unawaited(_ensureSupportedAbis());
  }

  /// 移除下载监听，防止内存泄漏。
  @override
  void dispose() {
    _downloadCoordinator.removeListener(_downloadListener);
    final _DownloadSession? session = _activeDownloadSession;
    if (session != null) {
      session.cancelRequested = true;
      session.dispose();
      _activeDownloadSession = null;
    }
    super.dispose();
  }

  /// 更新版本按钮的点击模式。
  void _setVersionActionMode(_VersionActionMode mode) {
    if (_versionActionMode == mode || !mounted) {
      _versionActionMode = mode;
      return;
    }
    setState(() => _versionActionMode = mode);
  }

  /// 读取当前应用版本并触发更新状态检查。
  Future<void> _initPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      if (_currentVersion != info.version) {
        setState(() => _currentVersion = info.version);
        unawaited(_primeLatestVersionStatus());
      }
    } catch (error) {
      debugPrint('获取应用版本失败：${_mapErrorMessage(error)}');
    }
  }

  /// 预判远端是否存在更新版本。
  Future<void> _primeLatestVersionStatus() async {
    try {
      final latest = await _fetchLatestReleaseInfo();
      if (!mounted) return;
      final latestVersion = latest?.version;
      final currentVersion = _safeParseVersion(_currentVersion);
      final hasNewer = latestVersion != null && currentVersion != null
          ? latestVersion > currentVersion
          : latestVersion != null;
      if (_hasNewerVersion != hasNewer) {
        setState(() => _hasNewerVersion = hasNewer);
      }
    } catch (error) {
      if (!mounted) return;
      if (_hasNewerVersion) {
        setState(() => _hasNewerVersion = false);
      }
      debugPrint('预检查更新失败：${_mapErrorMessage(error)}');
    }
  }

  /// 手动触发更新检查逻辑并提示用户。
  Future<void> _handleCheckForUpdates() async {
    final _DownloadSession? activeSession = _activeDownloadSession;
    if (activeSession != null && activeSession.isActive) {
      await _presentDownloadDialog(activeSession);
      return;
    }

    if (_versionActionMode == _VersionActionMode.showDownload) {
      _setVersionActionMode(_VersionActionMode.checkUpdate);
    }

    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);

    try {
      final latest = await _fetchLatestReleaseInfo();
      if (!mounted) return;

      if (latest == null) {
        _showToastMessage('暂未找到可用的发布信息', variant: AppToastVariant.warning);
        return;
      }

      final latestVersion = latest.version;
      final currentVersion = _safeParseVersion(_currentVersion);
      final supportedAbis = await _ensureSupportedAbis();
      final asset = _selectAndroidAsset(latest.assets, supportedAbis);

      final hasNewer = latestVersion != null && currentVersion != null
          ? latestVersion > currentVersion
          : latestVersion != null;

      if (_hasNewerVersion != hasNewer) {
        setState(() => _hasNewerVersion = hasNewer);
      }

      if (!hasNewer) {
        _showToastMessage('当前已是最新版本');
        return;
      }

      if (asset == null) {
        _showToastMessage(
          supportedAbis.isEmpty
              ? '未找到适用于 Android 的安装包，请前往发布页手动下载'
              : '未找到适用于当前设备架构的安装包，请前往发布页手动下载',
          variant: AppToastVariant.warning,
        );
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

      await _downloadAndInstallUpdate(asset);
    } catch (error) {
      if (!context.mounted) return;
      _showToastMessage(
        '检查更新失败：${_mapErrorMessage(error)}',
        variant: AppToastVariant.error,
      );
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  /// 通过共享下载服务执行更新下载流程并尝试唤起安装程序。
  Future<void> _downloadAndInstallUpdate(_ReleaseAsset asset) async {
    final int? totalHint = asset.size > 0 ? asset.size : null;
    final _DownloadSession? existing = _activeDownloadSession;
    if (existing != null && existing.isActive) {
      await _presentDownloadDialog(existing);
      return;
    }

    if (existing != null && !existing.isActive) {
      existing.dispose();
      _activeDownloadSession = null;
    }

    final _DownloadSession session = _DownloadSession(
      asset: asset,
      totalHint: totalHint,
    );
    _activeDownloadSession = session;
    _downloadCoordinator.markStarted();

    final Future<_DownloadDialogResult?> dialogFuture = _presentDownloadDialog(
      session,
      ensureStarted: true,
    );

    unawaited(
      dialogFuture.then(
        (dialogResult) =>
            _handleDownloadSessionCompletion(session, dialogResult),
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('下载弹窗出现异常：${_mapErrorMessage(error)}');
          session.cancelRequested = true;
          return _handleDownloadSessionCompletion(session, null);
        },
      ),
    );

    await dialogFuture;
  }

  /// 展示下载进度弹窗，必要时启动下载任务。
  Future<_DownloadDialogResult?> _presentDownloadDialog(
    _DownloadSession session, {
    bool ensureStarted = false,
  }) async {
    return showDialog<_DownloadDialogResult>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        var registered = false;
        return StatefulBuilder(
          builder: (stateContext, _) {
            final NavigatorState navigator = Navigator.of(dialogContext);

            if (!registered) {
              registered = true;
              session.updateNavigator(navigator);
              if (!session.started && ensureStarted) {
                Future<void>.microtask(() => _startDownloadSession(session));
              } else if (session.isFinished && !session.dialogClosed) {
                Future<void>.microtask(() {
                  session.popDialog(_mapDialogResult(session.downloadResult));
                });
              }
            } else {
              session.updateNavigator(navigator);
            }

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, __) async {
                if (didPop) {
                  session.clearNavigator();
                  return;
                }

                if (session.downloadCompleted.isCompleted) {
                  session.popDialog(_mapDialogResult(session.downloadResult));
                  return;
                }

                final bool shouldBackground = await _confirmBackgroundDownload(
                  dialogContext,
                );
                if (shouldBackground) {
                  session.backgroundMode = true;
                  _setVersionActionMode(_VersionActionMode.showDownload);
                  session.popDialog(_DownloadDialogResult.background);
                }
              },
              child: ValueListenableBuilder<DownloadProgress>(
                valueListenable: session.progressNotifier,
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
                          if (session.downloadCompleted.isCompleted) {
                            session.popDialog(
                              _mapDialogResult(session.downloadResult),
                            );
                            return;
                          }
                          session.cancelRequested = true;
                          session.popDialog(_DownloadDialogResult.cancelled);
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
  }

  /// 启动后台下载任务并维护会话状态。
  void _startDownloadSession(_DownloadSession session) {
    if (session.started) {
      return;
    }
    session.started = true;
    unawaited(() async {
      try {
        final DownloadRequest request = DownloadRequest(
          uri: Uri.parse(session.asset.browserDownloadUrl),
          fileName: session.asset.name.isEmpty ? null : session.asset.name,
          totalBytesHint: session.totalHint,
        );
        final DownloadResult result = await _downloadService.downloadToTempFile(
          request: request,
          onProgress: (DownloadProgress progress) {
            session.progressNotifier.value = DownloadProgress(
              receivedBytes: progress.receivedBytes,
              totalBytes: progress.totalBytes ?? session.totalHint,
            );
          },
          shouldCancel: () => session.cancelRequested,
          trackCoordinator: false,
        );
        session.downloadResult = result;
      } catch (error) {
        session.downloadResult = DownloadResult.failure(error);
      } finally {
        if (!session.downloadCompleted.isCompleted) {
          session.downloadCompleted.complete();
        }
        if (!session.backgroundMode) {
          session.popDialog(_mapDialogResult(session.downloadResult));
        }
      }
    }());
  }

  /// 在下载会话结束后处理结果并触发安装流程。
  Future<void> _handleDownloadSessionCompletion(
    _DownloadSession session,
    _DownloadDialogResult? dialogResult,
  ) async {
    try {
      final DownloadResult resolvedDownload =
          session.downloadResult ?? DownloadResult.failure('下载任务未返回结果');
      final _DownloadDialogResult resolvedDialog =
          dialogResult ?? _mapDialogResult(session.downloadResult);

      if (resolvedDialog == _DownloadDialogResult.background) {
        if (mounted && _checkingUpdate) {
          setState(() => _checkingUpdate = false);
        }
        if (mounted) {
          _showToastMessage('已切换到后台下载，完成后会自动打开安装程序');
        } else {
          debugPrint('已切换到后台下载，完成后会自动打开安装程序');
        }
      }

      if (!session.downloadCompleted.isCompleted) {
        await session.downloadCompleted.future;
      }

      // FIX 取消下载时显示的是下载失败，应该为：取消下载更新
      if (resolvedDownload.isFailure) {
        final Object? error = resolvedDownload.error;
        final String message = error == null ? '未知错误' : _mapErrorMessage(error);
        if (mounted) {
          _showToastMessage('下载更新失败：$message', variant: AppToastVariant.error);
        } else {
          debugPrint('下载更新失败：$message');
        }
        return;
      }

      if (resolvedDownload.isCancelled ||
          resolvedDialog == _DownloadDialogResult.cancelled) {
        if (mounted) {
          _showToastMessage('下载已取消', variant: AppToastVariant.warning);
        } else {
          debugPrint('Download cancelled before installer launch');
        }
        return;
      }

      final File? file = resolvedDownload.file;
      if (file == null) {
        if (mounted) {
          _showToastMessage('下载完成后未找到安装包。', variant: AppToastVariant.error);
        } else {
          debugPrint('下载完成后未找到安装包');
        }
        return;
      }

      if (resolvedDialog == _DownloadDialogResult.background && mounted) {
        _showToastMessage('下载完成，正在打开安装程序...');
      } else if (resolvedDialog == _DownloadDialogResult.background) {
        debugPrint('下载完成，正在尝试打开安装程序');
      }

      final OpenResult openResult = await OpenFilex.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );

      if (!mounted) {
        if (openResult.type != ResultType.done) {
          final String message = openResult.message;
          final String displayMessage = message.isEmpty ? '请稍后重试' : message;
          debugPrint('无法打开安装包：$displayMessage');
        }
        return;
      }

      if (openResult.type != ResultType.done) {
        final String message = openResult.message;
        final String displayMessage = message.isEmpty ? '请稍后重试' : message;
        _showToastMessage(
          '无法打开安装包：$displayMessage',
          variant: AppToastVariant.error,
        );
      }
    } finally {
      session.dispose();
      if (identical(_activeDownloadSession, session)) {
        _activeDownloadSession = null;
      }
      _setVersionActionMode(_VersionActionMode.checkUpdate);
      _downloadCoordinator.markIdle();
    }
  }

  /// 统一封装的提示入口，便于变更样式。
  void _showToastMessage(
    String message, {
    AppToastVariant variant = AppToastVariant.info,
  }) {
    if (!context.mounted) return;
    AppToast.show(context, message, variant: variant);
  }

  /// 通用外部链接打开方法，传入目标URL字符串
  Future<void> _openExternalUrl(String url) async {
    await _launchExternalUrl(context, Uri.parse(url));
  }

  /// 打开GitHub仓库
  Future<void> _openRepository() async {
    await _openExternalUrl('https://github.com/Lulozi/DormDevise');
  }

  /// 打开版本发布页
  Future<void> _openReleasePage() async {
    await _openExternalUrl('https://github.com/Lulozi/DormDevise/releases');
  }

  /// 打开Issue反馈页
  Future<void> _openIssuePage() async {
    await _openExternalUrl('https://github.com/Lulozi/DormDevise/issues');
  }

  /// 打开Bilibili主页
  Future<void> _openBilibiliPage() async {
    await _openExternalUrl('https://space.bilibili.com/212994722');
  }

  /// 打开开发者GitHub主页
  Future<void> _openGitHubPage() async {
    await _openExternalUrl('https://github.com/Lulozi');
  }

  /// 确保已获取并缓存设备支持的 ABI 列表。
  Future<List<String>> _ensureSupportedAbis() {
    final cached = _cachedSupportedAbis;
    if (cached != null) {
      return Future<List<String>>.value(cached);
    }

    final future = _supportedAbisFuture ??= _loadSupportedAndroidAbis();
    return future.then((abis) {
      _cachedSupportedAbis ??= abis;
      return abis;
    });
  }

  /// 读取 Android 设备支持的处理器架构信息。
  Future<List<String>> _loadSupportedAndroidAbis() async {
    if (!Platform.isAndroid) {
      return const [];
    }
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final abis = info.supportedAbis;
      return abis
          .map((abi) => abi.toLowerCase())
          .where((abi) => abi.isNotEmpty)
          .toList(growable: false);
    } catch (error) {
      debugPrint('无法获取设备 ABI：$error');
      return const [];
    }
  }

  /// 展示开源许可列表的底部弹窗。
  Future<void> _showLicenseDialog() async {
    if (!mounted) return;
    final theme = Theme.of(context);
    final versionLabel = _currentVersion.isEmpty ? '未知版本' : _currentVersion;
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
                        applicationVersion: versionLabel,
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

  /// 构建关于页面主体列表。
  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final versionLabel = _currentVersion.isEmpty ? '未知版本' : _currentVersion;
    final releaseNotesVersion = _currentVersion.isEmpty
        ? null
        : _currentVersion;
    final bool downloadInProgress =
        _activeDownloadSession?.isActive ?? _downloadCoordinator.isDownloading;
    final bool tapDisabled = _checkingUpdate;
    final bool showBusyIndicator = _checkingUpdate;
    final String versionHint =
        _versionActionMode == _VersionActionMode.showDownload
        ? '点击版本查看下载进度'
        : '点击版本检查更新';
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + padding.bottom),
          children: [
            _AboutHeader(
              version: versionLabel,
              busyIndicator: showBusyIndicator,
              hasNewerVersion: _hasNewerVersion,
              versionHint: versionHint,
              tapDisabled: tapDisabled,
              downloadInProgress: downloadInProgress,
              onCheckUpdate: _handleCheckForUpdates,
              onOpenRepository: _openRepository,
              onOpenReleasePage: _openReleasePage,
              onOpenBilibiliPage: _openBilibiliPage,
              onOpenGitHubPage: _openGitHubPage,
            ),
            const SizedBox(height: 16),
            if (releaseNotesVersion != null)
              ReleaseNotesCard(appVersion: releaseNotesVersion),
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

/// 关于页头部卡片，展示当前版本与快捷入口。
class _AboutHeader extends StatelessWidget {
  final String version;
  final bool busyIndicator;
  final bool hasNewerVersion;
  final bool tapDisabled;
  final bool downloadInProgress;
  final String versionHint;
  final Future<void> Function() onCheckUpdate;
  final Future<void> Function() onOpenRepository;
  final Future<void> Function() onOpenReleasePage;
  final Future<void> Function() onOpenBilibiliPage;
  final Future<void> Function() onOpenGitHubPage;

  const _AboutHeader({
    required this.version,
    required this.busyIndicator,
    required this.hasNewerVersion,
    required this.tapDisabled,
    required this.downloadInProgress,
    required this.versionHint,
    required this.onCheckUpdate,
    required this.onOpenRepository,
    required this.onOpenReleasePage,
    required this.onOpenBilibiliPage,
    required this.onOpenGitHubPage,
  });

  /// 构建包含头像、版本状态与快捷按钮的卡片。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

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
            _VersionStatusChip(
              version: version,
              showBusyIndicator: busyIndicator,
              hasNewerVersion: hasNewerVersion,
              disableTap: tapDisabled,
              downloadInProgress: downloadInProgress,
              onCheckUpdate: onCheckUpdate,
            ),
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
              versionHint,
              style: textTheme.labelSmall?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 显示版本状态并支持点击检查更新的徽章。
class _VersionStatusChip extends StatefulWidget {
  final String version;
  final bool showBusyIndicator;
  final bool hasNewerVersion;
  final bool disableTap;
  final bool downloadInProgress;
  final Future<void> Function() onCheckUpdate;

  const _VersionStatusChip({
    required this.version,
    required this.showBusyIndicator,
    required this.hasNewerVersion,
    required this.disableTap,
    required this.downloadInProgress,
    required this.onCheckUpdate,
  });

  @override
  State<_VersionStatusChip> createState() => _VersionStatusChipState();
}

class _VersionStatusChipState extends State<_VersionStatusChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// 初始化动画控制器，根据是否有新版本触发闪烁。
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.hasNewerVersion) {
      _controller.repeat(reverse: true);
    }
  }

  /// 在属性变更后更新动画启停状态。
  @override
  void didUpdateWidget(covariant _VersionStatusChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasNewerVersion && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.hasNewerVersion && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  /// 销毁动画控制器资源。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 绘制能够响应点击与动画的版本状态标签。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseBackground = colorScheme.primary.withValues(alpha: 0.12);
    final highlightBackground = colorScheme.primary.withValues(alpha: 0.32);
    final baseBorder = colorScheme.primary.withValues(alpha: 0.3);
    final highlightBorder = colorScheme.primary.withValues(alpha: 0.65);

    /// 根据当前状态生成前缀图标部件。
    Widget buildAvatar() {
      if (widget.showBusyIndicator) {
        return const SizedBox(
          width: 18,
          height: 18,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      if (widget.downloadInProgress) {
        return const SizedBox(
          width: 18,
          height: 18,
          child: Padding(
            padding: EdgeInsets.all(2),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return Icon(
        Icons.verified_outlined,
        color: colorScheme.primary,
        size: 18,
      );
    }

    return GestureDetector(
      onTap: widget.disableTap ? null : () => unawaited(widget.onCheckUpdate()),
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = widget.hasNewerVersion ? _controller.value : 0.0;
          final backgroundColor = Color.lerp(
            baseBackground,
            highlightBackground,
            progress,
          );
          final borderColor = Color.lerp(baseBorder, highlightBorder, progress);

          return Chip(
            label: Text('版本 ${widget.version}'),
            avatar: buildAvatar(),
            backgroundColor: backgroundColor ?? baseBackground,
            side: BorderSide(color: borderColor ?? baseBorder),
          );
        },
      ),
    );
  }
}

/// 通用分区卡片，用于组织页面段落内容。
class _SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
  });

  /// 构建带图标标题与子内容的卡片。
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

/// 简单的圆点列表项组件。
class _BulletTile extends StatelessWidget {
  final String text;

  const _BulletTile({required this.text});

  /// 绘制带圆点的说明文字。
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

/// 带图标的列表入口项。
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

  /// 构建支持点击跳转的列表项。
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

/// 将异常信息转换为更易读的字符串。
String _mapErrorMessage(Object error) {
  final raw = error.toString();
  if (raw.startsWith('Exception: ')) {
    return raw.substring('Exception: '.length);
  }
  return raw;
}

/// 弹出新版本可用提示并返回用户选择。
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

/// 打开外部链接，必要时优先尝试内嵌浏览器。
Future<void> _launchExternalUrl(BuildContext context, Uri uri) async {
  if (!context.mounted) return;
  // 如果是http/https，尝试用WebView弹窗，否则直接外部调起
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    final openedInSheet = await _showInAppWebSheet(context, uri);
    if (!context.mounted) {
      return;
    }
    if (openedInSheet) {
      return;
    }
  }
  // 其它协议（如bilibili://）直接外部调起
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!context.mounted) {
    return;
  }
  if (launched) {
    return;
  }
  AppToast.show(context, '无法打开链接，请稍后再试', variant: AppToastVariant.error);
}

/// 使用底部弹窗展示内嵌 WebView。
Future<bool> _showInAppWebSheet(BuildContext context, Uri uri) async {
  if (!context.mounted) return false;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;

  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..enableZoom(true)
    ..setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: (NavigationRequest request) async {
          final reqUri = Uri.tryParse(request.url);
          if (reqUri != null &&
              reqUri.scheme != 'http' &&
              reqUri.scheme != 'https') {
            // 拦截非http/https协议，外部调起
            await launchUrl(reqUri, mode: LaunchMode.externalApplication);
            return NavigationDecision.prevent;
          }
          return NavigationDecision.navigate;
        },
      ),
    )
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

/// 展示指定版本更新亮点的卡片。
class ReleaseNotesCard extends StatefulWidget {
  final String appVersion;

  const ReleaseNotesCard({super.key, required this.appVersion});

  /// 创建用于加载与展示更新说明的状态对象。
  @override
  State<ReleaseNotesCard> createState() => _ReleaseNotesCardState();
}

class _ReleaseNotesCardState extends State<ReleaseNotesCard> {
  late final Future<List<String>> _notesFuture;

  /// 初始化时立即触发更新说明的异步加载。
  @override
  void initState() {
    super.initState();
    _notesFuture = _fetchReleaseNotes(widget.appVersion);
  }

  /// 构建包含异步加载状态的说明卡片。
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

  /// 拉取指定版本的更新记录，必要时回退至缓存。
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
        // 缓存格式异常时继续从服务器拉取。
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

/// 安全解析版本号字符串，异常时返回 null。
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

  /// 返回优先用于展示的发布标签。
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

  /// 使用 GitHub 返回的字典构造发布信息实例。
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

/// 获取最新的稳定版本信息，若无稳定版则返回候选。
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

/// 从 GitHub API 拉取发布列表。
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

/// 比较两个发布信息的优先顺序。
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

/// 根据 ABI 优先级挑选合适的 Android 安装包资源。
_ReleaseAsset? _selectAndroidAsset(
  List<_ReleaseAsset> assets,
  List<String> preferredAbis,
) {
  if (assets.isEmpty) return null;

  final apkAssets = assets.where((asset) => asset.isAndroidApk).toList();
  if (apkAssets.isEmpty) return null;

  final buckets = <_AndroidApkVariant, List<_ReleaseAsset>>{};
  for (final asset in apkAssets) {
    final variant = _inferAndroidApkVariant(asset);
    buckets.putIfAbsent(variant, () => <_ReleaseAsset>[]).add(asset);
  }

  for (final abi in preferredAbis) {
    final variant = _variantForAbi(abi);
    if (variant == null) continue;
    final matches = buckets[variant];
    if (matches == null || matches.isEmpty) {
      continue;
    }
    matches.sort((a, b) => b.size.compareTo(a.size));
    return matches.first;
  }

  final universal = buckets[_AndroidApkVariant.universal];
  if (universal != null && universal.isNotEmpty) {
    universal.sort((a, b) => b.size.compareTo(a.size));
    return universal.first;
  }

  apkAssets.sort((a, b) => b.size.compareTo(a.size));
  return apkAssets.first;
}

enum _AndroidApkVariant {
  arm64V8a,
  armeabiV7a,
  x86_64,
  x86,
  universal,
  unknown,
}

/// 通过资源名与元数据推断 APK 所属架构。
_AndroidApkVariant _inferAndroidApkVariant(_ReleaseAsset asset) {
  final fingerprint =
      '${asset.name}|${asset.browserDownloadUrl}|${asset.contentType}'
          .toLowerCase();

  bool containsAll(Iterable<String> tokens) =>
      tokens.every((token) => fingerprint.contains(token));

  bool containsAny(Iterable<String> tokens) =>
      tokens.any((token) => fingerprint.contains(token));

  if (containsAll(['arm64', 'v8a']) ||
      fingerprint.contains('arm64v8a') ||
      fingerprint.contains('aarch64')) {
    return _AndroidApkVariant.arm64V8a;
  }

  if ((containsAll(['armeabi', 'v7a']) ||
          fingerprint.contains('armeabiv7a') ||
          fingerprint.contains('armv7')) &&
      !fingerprint.contains('arm64')) {
    return _AndroidApkVariant.armeabiV7a;
  }

  if (fingerprint.contains('x86_64') ||
      fingerprint.contains('x86-64') ||
      (fingerprint.contains('x64') && !fingerprint.contains('arm64')) ||
      fingerprint.contains('amd64')) {
    return _AndroidApkVariant.x86_64;
  }

  final hasStandaloneX86 = RegExp(
    r'(^|[^0-9a-z])x86($|[^0-9a-z])',
  ).hasMatch(fingerprint);
  if ((hasStandaloneX86 || fingerprint.contains('ia32')) &&
      !fingerprint.contains('x86_64') &&
      !fingerprint.contains('x86-64')) {
    return _AndroidApkVariant.x86;
  }

  if (containsAny([
    'universal',
    'all-abi',
    'allabi',
    'multi-abi',
    'multiabi',
    'all_arch',
    'allarch',
    'anycpu',
  ])) {
    return _AndroidApkVariant.universal;
  }

  return _AndroidApkVariant.unknown;
}

/// 将 ABI 字符串映射为内部枚举类型。
_AndroidApkVariant? _variantForAbi(String abi) {
  final normalized = abi.toLowerCase();
  if (normalized.contains('arm64') || normalized.contains('aarch64')) {
    return _AndroidApkVariant.arm64V8a;
  }
  if (normalized.contains('armeabi') || normalized.contains('armv7')) {
    return _AndroidApkVariant.armeabiV7a;
  }
  if (normalized.contains('x86_64') ||
      normalized.contains('x86-64') ||
      (normalized.contains('x64') && !normalized.contains('arm64')) ||
      normalized.contains('amd64')) {
    return _AndroidApkVariant.x86_64;
  }
  if (normalized.contains('x86') || normalized.contains('ia32')) {
    return _AndroidApkVariant.x86;
  }
  if (normalized.contains('universal') || normalized.contains('allabi')) {
    return _AndroidApkVariant.universal;
  }
  return null;
}

/// 将字节大小转换为可读字符串。
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

/// 指示版本按钮当前的点击动作。
enum _VersionActionMode { checkUpdate, showDownload }

/// 表示下载弹窗的关闭状态枚举。
enum _DownloadDialogResult { success, failure, background, cancelled }

/// 封装一次下载交互所需的状态。
class _DownloadSession {
  _DownloadSession({required this.asset, required this.totalHint})
    : progressNotifier = ValueNotifier<DownloadProgress>(
        DownloadProgress(receivedBytes: 0, totalBytes: totalHint),
      );

  final _ReleaseAsset asset;
  final int? totalHint;
  final ValueNotifier<DownloadProgress> progressNotifier;
  final Completer<void> downloadCompleted = Completer<void>();
  DownloadResult? downloadResult;
  bool cancelRequested = false;
  bool backgroundMode = false;
  bool started = false;
  bool dialogClosed = true;
  NavigatorState? _navigator;

  /// 是否仍有下载任务活跃。
  bool get isActive => !downloadCompleted.isCompleted;

  /// 下载是否已经结束。
  bool get isFinished => downloadCompleted.isCompleted;

  /// 记录当前弹窗关联的导航器并重置背景状态。
  void updateNavigator(NavigatorState navigatorState) {
    _navigator = navigatorState;
    dialogClosed = false;
    backgroundMode = false;
  }

  /// 清除已关联的导航器引用。
  void clearNavigator() {
    _navigator = null;
    dialogClosed = true;
  }

  /// 根据给定结果尝试关闭当前弹窗。
  void popDialog(_DownloadDialogResult result) {
    final NavigatorState? nav = _navigator;
    if (nav == null || !nav.mounted || dialogClosed) {
      return;
    }
    dialogClosed = true;
    _navigator = null;
    nav.pop(result);
  }

  /// 释放会话持有的资源。
  void dispose() {
    progressNotifier.dispose();
    _navigator = null;
  }
}

/// 根据下载进度生成描述文本。
String _describeProgress(DownloadProgress progress) {
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

/// 询问用户是否切换到后台下载模式。
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

/// 将下载服务返回的结果映射为对话框的结束状态。
_DownloadDialogResult _mapDialogResult(DownloadResult? result) {
  final DownloadResult? resolved = result;
  if (resolved == null) {
    return _DownloadDialogResult.failure;
  }
  if (resolved.isCancelled) {
    return _DownloadDialogResult.cancelled;
  }
  if (resolved.isFailure) {
    return _DownloadDialogResult.failure;
  }
  return _DownloadDialogResult.success;
}

/// 从发布说明文本中抽取项目符号高亮。
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

  /// 判断当前资源是否为 Android 安装包。
  bool get isAndroidApk {
    final lowerName = name.toLowerCase();
    final lowerType = contentType.toLowerCase();
    return lowerName.endsWith('.apk') ||
        lowerType.contains('application/vnd.android.package-archive');
  }

  /// 从 GitHub 返回的 JSON 实例化资源信息。
  factory _ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return _ReleaseAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}

/// 从发布名称或标签中推断语义化版本号。
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
