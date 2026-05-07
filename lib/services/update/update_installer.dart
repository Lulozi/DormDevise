import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 通用安装器组件
///
/// 提供一个简单方法：打开指定安装包并在后台尝试清理临时安装包文件。
///
/// 设计要点：
/// - 只在 Android 平台尝试删除 APK；其它平台不做操作。
/// - 删除为异步且延迟的操作（默认 3 秒），以降低与系统安装器的并发访问风险。
/// - 删除失败时只记录日志，不抛出异常。
/// - 提供可选的回调以在宿主 State 中展示吐司或其他 UI 提示（调用者负责检查 mounted）。
class UpdateInstaller {
  UpdateInstaller._();

  /// 事件通道：原生侧在安装完成时会发送包名字符串。
  static const EventChannel _installEventChannel = EventChannel(
    'dormdevise/update/install_events',
  );

  /// 供外部订阅的安装事件流，事件为安装的包名字符串。
  static Stream<String> get onPackageInstalled => _installEventChannel
      .receiveBroadcastStream()
      .map((event) => event as String);

  /// 打开给定的安装包并在后台尝试删除该临时文件。
  ///
  /// 参数：
  /// - [file]：要打开并随后清理的安装包文件。
  /// - [showToast]：可选回调，若提供且安装器成功打开，将调用以通知用户（调用者应负责 mounted 检查）。
  /// - [delay]：删除前的延迟时长，默认为 3 秒。
  static Future<OpenResult> openAndCleanup(
    File file, {
    void Function(String message)? showToast,
    Duration delay = const Duration(seconds: 3),
  }) async {
    final OpenResult result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );

    // 注意：不再自动删除打开后的安装包，清理应由原生安装完成广播触发
    // 如果需要，可在成功打开安装器时给用户一个提示（调用者负责 mounted 检查）
    if (result.type == ResultType.done && showToast != null) {
      try {
        showToast('已打开安装程序');
      } catch (_) {
        // 回调可能依赖于 State.mounted，调用者负责检查 mounted
      }
    }
    return result;
  }

  /// 清理临时目录下的 APK 文件（异步）。通常用于在收到安装完成广播后
  /// 将残留的安装包删除以释放空间。该方法安全失败，不会抛出异常。
  static Future<void> cleanupTemporaryApks() async {
    try {
      final Directory tmp = await getTemporaryDirectory();
      final List<FileSystemEntity> children = tmp.listSync();

      // 收集带版本号的 APK 文件
      final RegExp verReg = RegExp(
        r'v?(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)',
        caseSensitive: false,
      );
      final Map<File, Version> versionedFiles = {};
      final List<File> unversioned = [];

      for (final child in children) {
        if (child is File) {
          final String path = child.path;
          if (!path.toLowerCase().endsWith('.apk')) continue;
          final String name = path.split(Platform.pathSeparator).last;
          final match = verReg.firstMatch(name);
          if (match != null) {
            final String verText = match.group(1) ?? '';
            try {
              final Version v = Version.parse(verText);
              versionedFiles[child] = v;
            } catch (e) {
              // 解析失败视为未解析版本，保留以避免误删
              unversioned.add(child);
            }
          } else {
            unversioned.add(child);
          }
        }
      }

      // 尝试获取当前已安装的应用版本，用于与下载包比较
      Version? currentVersion;
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        final String raw = packageInfo.version.split('+').first;
        currentVersion = Version.parse(raw);
        debugPrint('当前应用版本：${currentVersion.toString()}');
      } catch (e) {
        debugPrint('无法获取当前应用版本，清理时将删除所有 APK：$e');
        currentVersion = null;
      }

      // 根据要求：只保留比当前 app 版本更高的 APK 中的最高版本，其余全部删除。
      // 若无法获取当前版本或没有比当前版本高的 APK，则删除所有 APK。
      if (currentVersion == null) {
        // 无法获取当前版本，删除所有 APK
        for (final child in children) {
          if (child is File && child.path.toLowerCase().endsWith('.apk')) {
            try {
              await child.delete();
              debugPrint('删除 APK（未知 app 版本）：${child.path}');
            } catch (e) {
              debugPrint('删除 APK 失败：$e');
            }
          }
        }
        return;
      }

      // 找到所有版本号严格 > currentVersion 的文件
      final Map<File, Version> higher = {};
      for (final entry in versionedFiles.entries) {
        if (entry.value > currentVersion) {
          higher[entry.key] = entry.value;
        }
      }

      if (higher.isEmpty) {
        // 没有更高版本，删除所有 APK
        for (final child in children) {
          if (child is File && child.path.toLowerCase().endsWith('.apk')) {
            try {
              await child.delete();
              debugPrint('删除 APK（无更高版本）：${child.path}');
            } catch (e) {
              debugPrint('删除 APK 失败：$e');
            }
          }
        }
        return;
      }

      // 在更高版本集合中找到最高版本
      Version? highest;
      for (final v in higher.values) {
        if (highest == null || v > highest) highest = v;
      }

      if (highest == null) {
        // 安全兜底：删除所有
        for (final child in children) {
          if (child is File && child.path.toLowerCase().endsWith('.apk')) {
            try {
              await child.delete();
              debugPrint('删除 APK（未知情况）：${child.path}');
            } catch (e) {
              debugPrint('删除 APK 失败：$e');
            }
          }
        }
        return;
      }

      // 保留版本等于 highest 的文件（可能有多个），删除其它所有 APK
      for (final child in children) {
        if (child is File && child.path.toLowerCase().endsWith('.apk')) {
          final Version? v = versionedFiles[child];
          final bool keep = (v != null && v == highest);
          if (!keep) {
            try {
              await child.delete();
              debugPrint('删除 APK（非最高更高版本）：${child.path}');
            } catch (e) {
              debugPrint('删除 APK 失败：$e');
            }
          } else {
            debugPrint('保留最高且大于当前版本的 APK (${v.toString()}): ${child.path}');
          }
        }
      }
    } catch (e) {
      debugPrint('清理临时 APK 时出现异常：$e');
    }
  }
}
