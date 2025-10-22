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
    final http.Client client = request.client ?? http.Client();
    final bool ownsClient = request.client == null;
    File? targetFile;
    try {
      final http.Request httpRequest = http.Request('GET', request.uri);
      final http.StreamedResponse response = await client.send(httpRequest);
      if (response.statusCode != 200) {
        throw Exception('下载失败，状态码 ${response.statusCode}');
      }
      final int? totalBytes = response.contentLength ?? request.totalBytesHint;
      final Directory directory =
          request.targetDirectory ?? await getTemporaryDirectory();
      final String resolvedName = sanitizeFileName(
        request.fileName ?? _resolveNameFromUri(request.uri),
      );
      final String filePath =
          '${directory.path}${Platform.pathSeparator}$resolvedName';
      targetFile = File(filePath);
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
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      return const DownloadResult.cancelled();
    } catch (error) {
      if (targetFile != null && await targetFile.exists()) {
        await targetFile.delete();
      }
      return DownloadResult.failure(error);
    } finally {
      if (ownsClient) {
        client.close();
      }
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
}

/// 清理文件名中的非法字符，避免写入失败。
String sanitizeFileName(String raw) {
  final sanitized = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (sanitized.trim().isEmpty) {
    return 'DormDevise-update-${DateTime.now().millisecondsSinceEpoch}.apk';
  }
  return sanitized;
}
