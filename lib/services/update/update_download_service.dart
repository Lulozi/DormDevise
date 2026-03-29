import 'dart:async';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dormdevise/services/update/update_installer.dart';
import 'package:dormdevise/services/theme/theme_service.dart';

/// 描述下载任务实时进度的模型。
class DownloadProgress {
  /// 使用已接收和总字节数构造进度对象。
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
  });

  /// 已经接收到的字节数。
  final int receivedBytes;

  /// 资源总字节数，未知时为 null。
  final int? totalBytes;

  /// 以 0~1 表示的进度百分比，未知时返回 null。
  double? get fraction {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (receivedBytes / total).clamp(0.0, 1.0);
  }
}

/// 下载结果的类别。
enum DownloadResultType { success, cancelled, failure }

/// 下载完成后的结果数据。
class DownloadResult {
  /// 内部构造函数，供命名构造封装。
  const DownloadResult._(this.type, this.file, this.error);

  /// 成功且生成了目标文件的结果。
  const DownloadResult.success({required File file})
    : this._(DownloadResultType.success, file, null);

  /// 用户主动取消的结果。
  const DownloadResult.cancelled()
    : this._(DownloadResultType.cancelled, null, null);

  /// 下载过程中出现异常的结果。
  const DownloadResult.failure(Object error)
    : this._(DownloadResultType.failure, null, error);

  /// 结果类别。
  final DownloadResultType type;

  /// 下载成功时写入的文件实例。
  final File? file;

  /// 异常失败时的错误对象。
  final Object? error;

  /// 是否下载成功。
  bool get isSuccess => type == DownloadResultType.success;

  /// 是否被用户取消。
  bool get isCancelled => type == DownloadResultType.cancelled;

  /// 是否出现故障。
  bool get isFailure => type == DownloadResultType.failure;
}

/// 封装下载任务所需的参数。
class DownloadRequest {
  /// 构造下载请求，允许指定文件名、目录与客户端。
  const DownloadRequest({
    required this.uri,
    this.fileName,
    this.totalBytesHint,
    this.targetDirectory,
    this.client,
  });

  /// 资源的网络地址。
  final Uri uri;

  /// 希望保存的文件名，留空时将自动推断。
  final String? fileName;

  /// 资源大小预估，用于优先显示进度。
  final int? totalBytesHint;

  /// 自定义输出目录，默认使用临时目录。
  final Directory? targetDirectory;

  /// 可选的 HTTP 客户端，便于外部统一管理生命周期。
  final http.Client? client;
}

/// 表示下载被外部打断的异常。
class DownloadCancelled implements Exception {
  /// 创建取消异常实例。
  const DownloadCancelled();

  @override
  String toString() => 'DownloadCancelled';
}

/// 协调全局下载状态的单例，提供监听能力。
class UpdateDownloadCoordinator {
  UpdateDownloadCoordinator._();

  /// 全局唯一实例。
  static final UpdateDownloadCoordinator instance =
      UpdateDownloadCoordinator._();

  final ValueNotifier<bool> _isDownloading = ValueNotifier<bool>(false);

  /// 当前是否存在活跃下载任务。
  bool get isDownloading => _isDownloading.value;

  /// 提供给外部组件的可监听对象。
  ValueListenable<bool> get listenable => _isDownloading;

  /// 注册监听。
  void addListener(VoidCallback listener) =>
      _isDownloading.addListener(listener);

  /// 解除监听。
  void removeListener(VoidCallback listener) =>
      _isDownloading.removeListener(listener);

  /// 标记下载开始。
  void markStarted() => _set(true);

  /// 标记下载结束。
  void markIdle() => _set(false);

  void _set(bool value) {
    if (_isDownloading.value == value) {
      return;
    }
    _isDownloading.value = value;
  }
}

/// 提供更新包下载能力的服务。
class UpdateDownloadService {
  UpdateDownloadService._();

  /// 全局唯一实例，便于依赖注入或直接调用。
  static final UpdateDownloadService instance = UpdateDownloadService._();

  final UpdateDownloadCoordinator coordinator =
      UpdateDownloadCoordinator.instance;

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isNotificationsInitialized = false;
  static const int _notificationId = 888;
  static const String _channelId = 'dormdevise_download_channel_v2';
  static const String _channelName = '更新下载';
  static const String _channelDescription = '显示应用更新下载进度';
  static const String _pendingInstallPathKey =
      'update_download_pending_install_path';
  static const String _pendingInstallAwaitingResumeKey =
      'update_download_pending_install_awaiting_resume';
  static const String _installNotificationPayload = 'update_install';
  static const String _androidNotificationIcon = 'icon_dormdevise_notification';
  Color get _androidNotificationColor =>
      ThemeService.instance.notificationPreviewColor;

  // 全局下载状态管理
  final ValueNotifier<DownloadProgress?> progressNotifier =
      ValueNotifier<DownloadProgress?>(null);
  final ValueNotifier<DownloadResult?> resultNotifier =
      ValueNotifier<DownloadResult?>(null);
  bool _cancelRequested = false;
  http.Client? _activeClient;
  bool _activeClientOwned = false;
  bool _isAppInForeground = false;
  bool _isInstallAttemptInFlight = false;
  DateTime? _lastInstallAttemptAt;
  StreamSubscription<String>? _installSubscription;

  /// 初始化通知插件并请求权限
  Future<void> initializeNotifications() async {
    if (_isNotificationsInitialized) return;

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(_androidNotificationIcon);

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          macOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload == _installNotificationPayload) {
          unawaited(
            Future<void>.delayed(
              const Duration(milliseconds: 300),
              () => resumePendingInstallIfNeeded(force: true),
            ),
          );
        }
      },
    );

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      await androidImplementation?.requestNotificationsPermission();
    }

    _isNotificationsInitialized = true;
    _installSubscription ??= UpdateInstaller.onPackageInstalled.listen((_) {
      unawaited(_clearPendingInstallState());
      unawaited(UpdateInstaller.cleanupTemporaryApks());
    });
  }

  /// 显示或更新进度通知
  Future<void> _showNotification({
    required String title,
    String? body,
    double? progress,
    bool indeterminate = false,
  }) async {
    if (!_isNotificationsInitialized) return;

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          icon: _androidNotificationIcon,
          color: _androidNotificationColor,
          colorized: false,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          playSound: false,
          enableVibration: false,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: progress != null ? (progress * 100).toInt() : 0,
          indeterminate: indeterminate,
          autoCancel: false,
          ongoing: true,
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      _notificationId,
      title,
      body,
      platformChannelSpecifics,
    );
  }

  /// 显示完成或失败通知
  Future<void> _showResultNotification(
    String title,
    String body, {
    String? payload,
  }) async {
    if (!_isNotificationsInitialized) return;

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          icon: _androidNotificationIcon,
          color: _androidNotificationColor,
          colorized: false,
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
          autoCancel: true,
          ongoing: false,
        );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    await _notificationsPlugin.show(
      _notificationId,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  /// 取消通知
  Future<void> _cancelNotification() async {
    if (!_isNotificationsInitialized) return;
    await _notificationsPlugin.cancel(_notificationId);
  }

  /// 启动后台下载任务
  Future<void> startBackgroundDownload({
    required DownloadRequest request,
  }) async {
    if (coordinator.isDownloading) {
      debugPrint('Download already in progress');
      return;
    }

    await initializeNotifications();
    _cancelRequested = false;
    // 不在此处预置具体进度（保持为 null），以便在“准备下载”阶段显示不确定的转圈。
    progressNotifier.value = null;
    resultNotifier.value = null;
    // 提前标记为正在准备/下载，这样 UI（关于页）会以下载状态渲染（先显示转圈）
    coordinator.markStarted();

    // 初始通知（准备下载）
    await _showNotification(title: '准备下载...', indeterminate: true);

    final result = await downloadToTempFile(
      request: request,
      onProgress: (progress) {
        progressNotifier.value = progress;
        _showNotification(
          title: '正在下载更新...',
          body: _formatProgress(progress),
          progress: progress.fraction,
        );
      },
      shouldCancel: () => _cancelRequested,
    );

    resultNotifier.value = result;
    // 下载结束后清理进度通知，确保 UI 在取消/完成后不会残留进度图标
    progressNotifier.value = null;
    _activeClient = null;
    _activeClientOwned = false;

    if (result.isSuccess) {
      final File file = result.file!;
      if (_isAppInForeground) {
        await _showResultNotification(
          '下载完成',
          '正在尝试安装更新...',
          payload: _installNotificationPayload,
        );
        await registerDownloadedFileForInstall(file, openNow: true);
      } else {
        await registerDownloadedFileForInstall(file, openNow: false);
      }
    } else if (result.isCancelled) {
      await _cancelNotification();
    } else {
      await _showResultNotification('下载失败', result.error.toString());
    }
  }

  /// 标记当前应用是否处于前台，便于决定是否立即唤起安装器。
  void setAppInForeground(bool isForeground) {
    _isAppInForeground = isForeground;
  }

  /// 查询当前是否仍有待继续安装的更新包。
  Future<bool> hasPendingInstall() async {
    final _PendingInstallState? state = await _loadPendingInstallState();
    if (state == null) {
      return false;
    }
    final File file = File(state.path);
    if (await file.exists()) {
      return true;
    }
    await _clearPendingInstallState();
    return false;
  }

  /// 注册一个已经下载完成的安装包，并按当前前后台状态决定是否立即安装。
  Future<void> registerDownloadedFileForInstall(
    File file, {
    required bool openNow,
  }) async {
    await initializeNotifications();
    if (!await file.exists()) {
      await _clearPendingInstallState();
      return;
    }
    await _savePendingInstallState(
      file.path,
      awaitingResume: !(openNow && _isAppInForeground),
    );

    if (openNow && _isAppInForeground) {
      await _attemptInstallPendingFile(file);
      return;
    }

    await _showResultNotification(
      '下载完成',
      '点击通知或返回应用继续安装',
      payload: _installNotificationPayload,
    );
  }

  /// 在应用回到前台后继续尝试安装已下载好的更新包。
  Future<void> resumePendingInstallIfNeeded({bool force = false}) async {
    await initializeNotifications();
    final _PendingInstallState? state = await _loadPendingInstallState();
    if (state == null) {
      return;
    }
    if (!force && (!_isAppInForeground || !state.awaitingResume)) {
      return;
    }

    final File file = File(state.path);
    if (!await file.exists()) {
      await _clearPendingInstallState();
      return;
    }
    await _attemptInstallPendingFile(file);
  }

  /// 请求取消当前下载
  void cancelDownload() {
    if (coordinator.isDownloading) {
      _cancelRequested = true;
      // 立即中断当前 HTTP 请求，避免“准备下载”阶段取消延迟。
      if (_activeClientOwned) {
        _activeClient?.close();
      }
      _activeClient = null;
      _activeClientOwned = false;
    }
  }

  String _formatProgress(DownloadProgress progress) {
    final fraction = progress.fraction;
    if (fraction == null) return _formatFileSize(progress.receivedBytes);
    return '${(fraction * 100).toStringAsFixed(0)}%';
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
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  Future<void> _attemptInstallPendingFile(File file) async {
    if (!await file.exists()) {
      await _clearPendingInstallState();
      return;
    }
    if (_isInstallAttemptInFlight) {
      return;
    }
    final DateTime now = DateTime.now();
    if (_lastInstallAttemptAt != null &&
        now.difference(_lastInstallAttemptAt!) < const Duration(seconds: 2)) {
      return;
    }

    _isInstallAttemptInFlight = true;
    _lastInstallAttemptAt = now;
    try {
      final OpenResult openResult = await UpdateInstaller.openAndCleanup(file);
      if (openResult.type == ResultType.done) {
        await _savePendingInstallState(file.path, awaitingResume: false);
        await _showResultNotification(
          '下载完成',
          '已打开安装程序',
          payload: _installNotificationPayload,
        );
      } else {
        await _savePendingInstallState(file.path, awaitingResume: true);
        await _showResultNotification(
          '下载完成',
          '安装程序打开失败，点击通知或返回应用继续安装',
          payload: _installNotificationPayload,
        );
      }
    } catch (error) {
      debugPrint('尝试打开安装程序失败: $error');
      await _savePendingInstallState(file.path, awaitingResume: true);
      await _showResultNotification(
        '下载完成',
        '安装程序打开失败，点击通知或返回应用继续安装',
        payload: _installNotificationPayload,
      );
    } finally {
      _isInstallAttemptInFlight = false;
    }
  }

  Future<_PendingInstallState?> _loadPendingInstallState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? path = prefs.getString(_pendingInstallPathKey);
    if (path == null || path.isEmpty) {
      return null;
    }
    return _PendingInstallState(
      path: path,
      awaitingResume: prefs.getBool(_pendingInstallAwaitingResumeKey) ?? false,
    );
  }

  Future<void> _savePendingInstallState(
    String path, {
    required bool awaitingResume,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInstallPathKey, path);
    await prefs.setBool(_pendingInstallAwaitingResumeKey, awaitingResume);
  }

  Future<void> _clearPendingInstallState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInstallPathKey);
    await prefs.remove(_pendingInstallAwaitingResumeKey);
  }

  /// 根据下载请求推导出最终写入的目标文件。
  Future<File> resolveTargetFile({required DownloadRequest request}) async {
    final String resolvedName = _resolveSanitizedFileName(request);
    final Directory directory =
        request.targetDirectory ?? await getTemporaryDirectory();
    final String filePath =
        '${directory.path}${Platform.pathSeparator}$resolvedName';
    return File(filePath);
  }

  /// 在临时目录中查找匹配下载请求的缓存文件。
  Future<File?> findCachedFile({
    required DownloadRequest request,
    int? expectedBytes,
  }) async {
    final File candidate = await resolveTargetFile(request: request);
    if (!await candidate.exists()) {
      return null;
    }
    if (expectedBytes != null) {
      try {
        final int length = await candidate.length();
        if (length != expectedBytes) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }
    return candidate;
  }

  /// 将网络资源下载至临时目录并返回结果。
  Future<DownloadResult> downloadToTempFile({
    required DownloadRequest request,
    void Function(DownloadProgress progress)? onProgress,
    bool Function()? shouldCancel,
    bool trackCoordinator = true,
  }) async {
    if (trackCoordinator) {
      coordinator.markStarted();
    }
    File? targetFile;

    // 构造 Gitee 备用下载地址
    Uri? constructGiteeUri(Uri original) {
      // GitHub 下载链接示例： https://github.com/Lulozi/DormDevise/releases/download/{tag}/{filename}
      // Gitee 下载链接示例：  https://gitee.com/lulo/DormDevise/releases/download/{tag}/{filename}
      try {
        final String url = original.toString();
        if (url.contains('github.com/Lulozi/DormDevise')) {
          return Uri.parse(
            url
                .replaceFirst('github.com', 'gitee.com')
                .replaceFirst('Lulozi', 'lulo'),
          );
        }
        return null;
      } catch (_) {
        return null;
      }
    }

    try {
      // 辅助函数：安全地删除可能为 null 的文件，忽略异常
      Future<void> safeDelete(File? f) async {
        if (f == null) return;
        try {
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {
          // 忽略删除异常
        }
      }

      // 准备候选源列表（GitHub 为首选，Gitee 为备用）
      final List<Uri> sources = <Uri>[request.uri];
      final Uri? giteeUri = constructGiteeUri(request.uri);
      if (giteeUri != null) {
        sources.add(giteeUri);
      }

      // 尝试下载（依次尝试）
      for (final Uri uri in sources) {
        if (shouldCancel?.call() ?? false) {
          return const DownloadResult.cancelled();
        }

        final http.Client client = request.client ?? http.Client();
        final bool ownsLocalClient = request.client == null;
        _activeClient = client;
        _activeClientOwned = ownsLocalClient;
        try {
          final http.Request httpRequest = http.Request('GET', uri);
          final http.StreamedResponse response = await client.send(httpRequest);

          if (shouldCancel?.call() ?? false) {
            throw const DownloadCancelled();
          }

          if (response.statusCode != 200) {
            // 如果不是最后一个源，则尝试下一个
            if (uri != sources.last) {
              if (ownsLocalClient) client.close();
              continue;
            }
            throw Exception('下载失败，状态码 ${response.statusCode}');
          }

          final int? totalBytes =
              response.contentLength ?? request.totalBytesHint;
          targetFile = await resolveTargetFile(request: request);
          final IOSink sink = targetFile.openWrite();

          int received = 0;
          onProgress?.call(
            DownloadProgress(receivedBytes: 0, totalBytes: totalBytes),
          );
          try {
            await for (final List<int> chunk in response.stream) {
              if (shouldCancel?.call() ?? false) {
                throw const DownloadCancelled();
              }
              received += chunk.length;
              sink.add(chunk);
              onProgress?.call(
                DownloadProgress(
                  receivedBytes: received,
                  totalBytes: totalBytes,
                ),
              );
            }
          } finally {
            await sink.flush();
            await sink.close();
          }

          return DownloadResult.success(file: targetFile);
        } on DownloadCancelled {
          await safeDelete(targetFile);
          return const DownloadResult.cancelled();
        } catch (error) {
          await safeDelete(targetFile);
          if (shouldCancel?.call() ?? false) {
            return const DownloadResult.cancelled();
          }
          // 如果是最后一个源，则返回失败
          if (uri == sources.last) {
            return DownloadResult.failure(error);
          }
        } finally {
          if (identical(_activeClient, client)) {
            _activeClient = null;
            _activeClientOwned = false;
          }
          if (ownsLocalClient) {
            client.close();
          }
        }
      }

      return const DownloadResult.failure('所有下载源均不可用');
    } finally {
      if (trackCoordinator) {
        coordinator.markIdle();
      }
    }
  }

  String _resolveNameFromUri(Uri uri) {
    if (uri.pathSegments.isNotEmpty) {
      final String lastSegment = uri.pathSegments.last.trim();
      if (lastSegment.isNotEmpty) {
        return lastSegment;
      }
    }
    return 'download-${DateTime.now().millisecondsSinceEpoch}.bin';
  }

  /// 生成经过去除非法字符后的文件名。
  String _resolveSanitizedFileName(DownloadRequest request) {
    return sanitizeFileName(
      request.fileName ?? _resolveNameFromUri(request.uri),
    );
  }
}

/// 清理文件名中的非法字符，避免写入失败。
String sanitizeFileName(String raw) {
  final sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (sanitized.trim().isEmpty) {
    return 'DormDevise-update-${DateTime.now().millisecondsSinceEpoch}.apk';
  }
  return sanitized;
}

class _PendingInstallState {
  const _PendingInstallState({
    required this.path,
    required this.awaitingResume,
  });

  final String path;
  final bool awaitingResume;
}
