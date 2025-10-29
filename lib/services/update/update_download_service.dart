import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
    // 先尝试 CDN 主站，若探测显示速率不足，再退回 GitHub 作为备用下载源。
    // 使用请求提供的 client 或在需要时按需创建。本方法内部的 probe 和下载流程
    // 各自创建/关闭自己的 client，避免共享 client 的生命周期复杂性。
    File? targetFile;

    // 如果原始是 github 的 asset，自动构造主 CDN 下载地址
    Uri? constructAlternativeUri(Uri original, String fileName) {
      // 主源路径规则为: http://download.cdn.xiaoheiwu.fun/App/dormdevise/{filename}
      try {
        final sanitizedName = Uri.encodeComponent(fileName);
        return Uri.parse(
          'http://download.cdn.xiaoheiwu.fun/App/dormdevise/$sanitizedName',
        );
      } catch (_) {
        return null;
      }
    }

    // 之前的流内切换常量已移至探测阶段，如有需要可在请求中参数化。

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

      // 准备候选源列表（主源为首选，备用源可选）
      final String resolvedName = _resolveSanitizedFileName(request);
      final List<Uri> sources = <Uri>[];
      final Uri? cdnUri = constructAlternativeUri(request.uri, resolvedName);
      if (cdnUri != null) {
        sources.add(cdnUri);
      }
      if (sources.isEmpty ||
          sources.first.toString() != request.uri.toString()) {
        sources.add(request.uri);
      }

      // 依据主备源并行测速后的决策选择最终下载地址。
      final Uri chosen;
      try {
        chosen = await _selectPreferredSource(
          primary: sources.first,
          backup: sources.length > 1 ? sources[1] : null,
          shouldCancel: shouldCancel,
        );
      } on DownloadCancelled {
        return const DownloadResult.cancelled();
      }

      // 从选定的源开始完整下载（单源，不在中途切换）
      final http.Client client = request.client ?? http.Client();
      final bool ownsLocalClient = request.client == null;
      try {
        final http.Request httpRequest = http.Request('GET', chosen);
        final http.StreamedResponse response = await client.send(httpRequest);
        if (response.statusCode != 200) {
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
              DownloadProgress(receivedBytes: received, totalBytes: totalBytes),
            );
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        return DownloadResult.success(file: targetFile);
      } on DownloadCancelled {
        await safeDelete(targetFile);
        if (shouldCancel?.call() ?? false) {
          return const DownloadResult.cancelled();
        }
        return const DownloadResult.cancelled();
      } catch (error) {
        await safeDelete(targetFile);
        return DownloadResult.failure(error);
      } finally {
        if (ownsLocalClient) {
          client.close();
        }
      }

      // 所有流程已完成或失败，控制流将在上面返回相应结果。
    } finally {
      if (trackCoordinator) {
        coordinator.markIdle();
      }
    }
  }

  /// 并行探测主备源下载速度，快速决定最终下载地址。
  Future<Uri> _selectPreferredSource({
    required Uri primary,
    Uri? backup,
    bool Function()? shouldCancel,
  }) async {
    if (backup == null) {
      return primary;
    }

    if (shouldCancel?.call() ?? false) {
      throw const DownloadCancelled();
    }

    final _DownloadProbe primaryProbe = _DownloadProbe(primary);
    final _DownloadProbe backupProbe = _DownloadProbe(backup);
    await Future.wait(<Future<void>>[
      primaryProbe.start(),
      backupProbe.start(),
    ]);

    const Duration decisionWindow = Duration(seconds: 3);
    const Duration backupCheckWindow = Duration(seconds: 5);
    const double backupSpeedThreshold = 400 * 1024; // 400 KB/s

    final Stopwatch stopwatch = Stopwatch()..start();
    Uri? provisional;
    bool provisionalIsBackup = false;

    try {
      while (stopwatch.elapsed < backupCheckWindow) {
        if (shouldCancel?.call() ?? false) {
          throw const DownloadCancelled();
        }

        await Future.delayed(const Duration(milliseconds: 120));

        final Duration elapsed = stopwatch.elapsed;
        if (provisional == null && elapsed >= decisionWindow) {
          final double primarySpeed = primaryProbe.speedAt(decisionWindow) ?? 0;
          final double backupSpeed = backupProbe.speedAt(decisionWindow) ?? 0;

          if (backupSpeed > primarySpeed && backupSpeed > 0) {
            provisional = backup;
            provisionalIsBackup = true;
          } else if (primaryProbe.isReachable) {
            provisional = primary;
            provisionalIsBackup = false;
            break;
          } else if (backupSpeed > 0) {
            provisional = backup;
            provisionalIsBackup = true;
          }
        }

        if (elapsed >= backupCheckWindow) {
          break;
        }
      }

      final bool primaryUsable = primaryProbe.isReachable;
      final bool backupUsable = backupProbe.isReachable;

      Uri? finalSelection = provisional;
      if (finalSelection == null) {
        finalSelection = primaryUsable
            ? primary
            : (backupUsable ? backup : primary);
      } else if (provisionalIsBackup) {
        final double backupSpeedForCheck =
            backupProbe.speedAt(backupCheckWindow) ??
            backupProbe.currentAverageSpeed;
        if (backupSpeedForCheck < backupSpeedThreshold && primaryUsable) {
          finalSelection = primary;
        }
      }

      return finalSelection;
    } finally {
      primaryProbe.stop();
      backupProbe.stop();
      await Future.wait(<Future<void>>[
        primaryProbe.completed,
        backupProbe.completed,
      ]);
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

/// 探测速时记录的采样点。
class _ProbeSample {
  const _ProbeSample(this.elapsed, this.bytes);

  final Duration elapsed;
  final int bytes;
}

/// 负责对单个地址执行限时限量的并行测速。
class _DownloadProbe {
  _DownloadProbe(this.uri);

  static const int _limitBytes = 512 * 1024; // 最多下载 512KB 用于测速
  static const Duration _maxDuration = Duration(seconds: 5);

  final Uri uri;
  final http.Client _client = http.Client();
  final Stopwatch _stopwatch = Stopwatch();
  final Completer<void> _doneCompleter = Completer<void>();
  final List<_ProbeSample> _samples = <_ProbeSample>[];

  StreamSubscription<List<int>>? _subscription;
  Timer? _timer;
  int _received = 0;
  bool _completed = false;
  bool _reachable = false;

  /// 是否已经成功收到数据。
  bool get isReachable => _reachable;

  /// 当前平均下载速度（字节/秒）。
  double get currentAverageSpeed {
    if (_samples.isEmpty) {
      return 0;
    }
    final _ProbeSample last = _samples.last;
    final int millis = last.elapsed.inMilliseconds;
    if (millis <= 0) {
      return 0;
    }
    return last.bytes / (millis / 1000.0);
  }

  /// 等待测速流程结束。
  Future<void> get completed => _doneCompleter.future;

  /// 启动测速流程。
  Future<void> start() async {
    if (_completed) {
      return;
    }

    try {
      final http.Request request = http.Request('GET', uri)
        ..headers['Range'] = 'bytes=0-${_limitBytes - 1}'
        ..headers['Accept-Encoding'] = 'identity';
      final http.StreamedResponse response = await _client
          .send(request)
          .timeout(_maxDuration);
      if (response.statusCode != 200 && response.statusCode != 206) {
        _complete();
        return;
      }

      _reachable = true;
      _stopwatch.start();
      _timer = Timer(_maxDuration, _complete);
      _subscription = response.stream.listen(
        (List<int> chunk) {
          if (_completed) {
            return;
          }
          _received += chunk.length;
          final Duration elapsed = _stopwatch.elapsed;
          _samples.add(_ProbeSample(elapsed, _received));
          if (_received >= _limitBytes) {
            _complete();
          }
        },
        onDone: _complete,
        onError: (Object _, StackTrace __) {
          _complete();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _complete();
    }
  }

  /// 停止测速流程，释放网络资源。
  void stop() {
    _complete();
  }

  /// 在指定时间点估算平均速度（字节/秒）。
  double? speedAt(Duration duration) {
    if (_samples.isEmpty) {
      return null;
    }
    _ProbeSample? candidate;
    for (final _ProbeSample sample in _samples) {
      candidate = sample;
      if (sample.elapsed >= duration) {
        break;
      }
    }
    candidate ??= _samples.last;
    final int millis = candidate.elapsed >= duration
        ? duration.inMilliseconds
        : candidate.elapsed.inMilliseconds;
    if (millis <= 0) {
      return null;
    }
    return candidate.bytes / (millis / 1000.0);
  }

  void _complete() {
    if (_completed) {
      return;
    }
    _completed = true;
    _timer?.cancel();
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
    }
    _timer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _client.close();
    if (!_doneCompleter.isCompleted) {
      _doneCompleter.complete();
    }
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
