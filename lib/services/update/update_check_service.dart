import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_download_service.dart';

/// 启动页与关于页共用的更新信息。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestRelease,
    required this.latestVersion,
    required this.versionLabel,
    required this.body,
    required this.highlights,
    required this.supportedAbis,
    required this.asset,
  });

  final String currentVersion;
  final UpdateReleaseInfo latestRelease;
  final Version latestVersion;
  final String versionLabel;
  final String? body;
  final List<String> highlights;
  final List<String> supportedAbis;
  final UpdateReleaseAsset? asset;

  bool get hasCompatibleAsset => asset != null;
}

/// 后台更新下载启动结果。
class UpdateStartResult {
  const UpdateStartResult({required this.status, required this.message});

  final UpdateStartStatus status;
  final String message;
}

enum UpdateStartStatus {
  startedDownload,
  openedCachedInstaller,
  alreadyDownloading,
  noCompatibleAsset,
}

/// 标准化后的版本发布信息。
class UpdateReleaseInfo {
  const UpdateReleaseInfo({
    required this.version,
    required this.body,
    required this.name,
    required this.tagName,
    required this.isDraft,
    required this.isPrerelease,
    required this.publishedAt,
    required this.assets,
  });

  factory UpdateReleaseInfo.fromJson(Map<String, dynamic> json) {
    final String name = json['name'] as String? ?? '';
    final String tagName = json['tag_name'] as String? ?? '';
    final String? publishedAtRaw = json['published_at'] as String?;
    final List<dynamic> assetsJson =
        json['assets'] as List<dynamic>? ?? const [];
    return UpdateReleaseInfo(
      version: _parseVersionFromMetadata(name, tagName),
      body: json['body'] as String?,
      name: name.isEmpty ? null : name,
      tagName: tagName.isEmpty ? null : tagName,
      isDraft: json['draft'] as bool? ?? false,
      isPrerelease: json['prerelease'] as bool? ?? false,
      publishedAt: publishedAtRaw == null
          ? null
          : DateTime.tryParse(publishedAtRaw)?.toLocal(),
      assets: assetsJson
          .map(
            (dynamic item) =>
                UpdateReleaseAsset.fromJson(item as Map<String, dynamic>),
          )
          .where(
            (UpdateReleaseAsset asset) => asset.browserDownloadUrl.isNotEmpty,
          )
          .toList(growable: false),
    );
  }

  final Version? version;
  final String? body;
  final String? name;
  final String? tagName;
  final bool isDraft;
  final bool isPrerelease;
  final DateTime? publishedAt;
  final List<UpdateReleaseAsset> assets;

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

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'tag_name': tagName,
      'body': body,
      'draft': isDraft,
      'prerelease': isPrerelease,
      'published_at': publishedAt?.toIso8601String(),
      'assets': assets
          .map((UpdateReleaseAsset asset) => asset.toJson())
          .toList(),
    };
  }
}

/// 版本资源信息。
class UpdateReleaseAsset {
  const UpdateReleaseAsset({
    required this.name,
    required this.browserDownloadUrl,
    required this.contentType,
    required this.size,
  });

  factory UpdateReleaseAsset.fromJson(Map<String, dynamic> json) {
    return UpdateReleaseAsset(
      name: json['name'] as String? ?? '',
      browserDownloadUrl: json['browser_download_url'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }

  final String name;
  final String browserDownloadUrl;
  final String contentType;
  final int size;

  bool get isAndroidApk {
    final String lowerName = name.toLowerCase();
    final String lowerType = contentType.toLowerCase();
    return lowerName.endsWith('.apk') ||
        lowerType.contains('application/vnd.android.package-archive');
  }

  UpdateReleaseAsset copyWith({
    String? name,
    String? browserDownloadUrl,
    String? contentType,
    int? size,
  }) {
    return UpdateReleaseAsset(
      name: name ?? this.name,
      browserDownloadUrl: browserDownloadUrl ?? this.browserDownloadUrl,
      contentType: contentType ?? this.contentType,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name,
      'browser_download_url': browserDownloadUrl,
      'content_type': contentType,
      'size': size,
    };
  }
}

class UpdateCheckService {
  UpdateCheckService._();

  static final UpdateCheckService instance = UpdateCheckService._();

  DateTime? _lastFetchTime;
  List<UpdateReleaseInfo>? _cachedReleases;
  String? _lastSourceType;
  String? _lastCustomApiUrl;
  Future<List<UpdateReleaseInfo>>? _pendingFetch;
  List<String>? _cachedSupportedAbis;
  Future<List<String>>? _supportedAbisFuture;

  Future<UpdateCheckResult?> fetchAvailableUpdate({
    bool forceRefresh = false,
  }) async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final Version? currentVersion = safeParseVersion(packageInfo.version);
    if (currentVersion == null) {
      return null;
    }

    final UpdateReleaseInfo? latestRelease = await fetchLatestReleaseInfo(
      forceRefresh: forceRefresh,
    );
    if (latestRelease == null || latestRelease.version == null) {
      return null;
    }
    if (latestRelease.version! <= currentVersion) {
      return null;
    }

    final List<String> supportedAbis = await ensureSupportedAbis();
    UpdateReleaseAsset? asset = selectAndroidAsset(
      latestRelease.assets,
      supportedAbis,
    );
    if (asset != null && asset.size <= 0) {
      final int size = await tryFetchAssetSize(asset.browserDownloadUrl);
      if (size > 0) {
        asset = asset.copyWith(size: size);
      }
    }

    return UpdateCheckResult(
      currentVersion: packageInfo.version,
      latestRelease: latestRelease,
      latestVersion: latestRelease.version!,
      versionLabel:
          latestRelease.readableLabel ?? 'v${latestRelease.version.toString()}',
      body: latestRelease.body,
      highlights: extractReleaseHighlights(latestRelease.body ?? ''),
      supportedAbis: supportedAbis,
      asset: asset,
    );
  }

  Future<UpdateReleaseInfo?> fetchLatestReleaseInfo({
    bool forceRefresh = false,
  }) async {
    final List<UpdateReleaseInfo> releases = await _loadReleasesBasedOnConfig(
      forceRefresh: forceRefresh,
    );
    if (releases.isEmpty) {
      return null;
    }

    final List<UpdateReleaseInfo> stable = releases
        .where(
          (UpdateReleaseInfo release) =>
              !release.isDraft && !release.isPrerelease,
        )
        .toList();
    final List<UpdateReleaseInfo> candidates = stable.isNotEmpty
        ? stable
        : releases
              .where((UpdateReleaseInfo release) => !release.isDraft)
              .toList();
    if (candidates.isEmpty) {
      releases.sort(_compareReleaseOrder);
      return releases.first;
    }
    candidates.sort(_compareReleaseOrder);
    return candidates.first;
  }

  Future<List<String>> ensureSupportedAbis() async {
    final List<String>? cached = _cachedSupportedAbis;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final Future<List<String>> future = _supportedAbisFuture ??=
        _loadSupportedAndroidAbis();
    try {
      final List<String> abis = await future;
      _cachedSupportedAbis ??= abis;
      return _cachedSupportedAbis!;
    } finally {
      if (identical(_supportedAbisFuture, future)) {
        _supportedAbisFuture = null;
      }
    }
  }

  Future<List<String>> _loadSupportedAndroidAbis() async {
    if (!Platform.isAndroid) {
      return const <String>[];
    }
    try {
      final AndroidDeviceInfo info = await DeviceInfoPlugin().androidInfo;
      final List<String> abis = info.supportedAbis;
      if (abis.isNotEmpty) {
        return abis;
      }
      return <String>[...info.supported64BitAbis, ...info.supported32BitAbis];
    } catch (_) {
      return const <String>[];
    }
  }

  UpdateReleaseAsset? selectAndroidAsset(
    List<UpdateReleaseAsset> assets,
    List<String> preferredAbis,
  ) {
    if (assets.isEmpty) {
      return null;
    }

    final List<UpdateReleaseAsset> apkAssets = assets
        .where((UpdateReleaseAsset asset) => asset.isAndroidApk)
        .toList();
    if (apkAssets.isEmpty) {
      return null;
    }

    final Map<_AndroidApkVariant, List<UpdateReleaseAsset>> buckets =
        <_AndroidApkVariant, List<UpdateReleaseAsset>>{};
    for (final UpdateReleaseAsset asset in apkAssets) {
      final _AndroidApkVariant variant = _inferAndroidApkVariant(asset);
      buckets.putIfAbsent(variant, () => <UpdateReleaseAsset>[]).add(asset);
    }

    for (final String abi in preferredAbis) {
      final _AndroidApkVariant? variant = _variantForAbi(abi);
      if (variant == null) {
        continue;
      }
      final List<UpdateReleaseAsset>? matches = buckets[variant];
      if (matches == null || matches.isEmpty) {
        continue;
      }
      matches.sort(
        (UpdateReleaseAsset a, UpdateReleaseAsset b) =>
            b.size.compareTo(a.size),
      );
      return matches.first;
    }

    final List<UpdateReleaseAsset>? universal =
        buckets[_AndroidApkVariant.universal];
    if (universal != null && universal.isNotEmpty) {
      universal.sort(
        (UpdateReleaseAsset a, UpdateReleaseAsset b) =>
            b.size.compareTo(a.size),
      );
      return universal.first;
    }

    apkAssets.sort(
      (UpdateReleaseAsset a, UpdateReleaseAsset b) => b.size.compareTo(a.size),
    );
    return apkAssets.first;
  }

  String unsupportedAssetMessage(List<String> supportedAbis) {
    return supportedAbis.isEmpty
        ? '未找到适用于 Android 的安装包，请前往发布页手动下载'
        : '未找到适用于当前设备架构的安装包，请前往发布页手动下载';
  }

  Future<int> tryFetchAssetSize(String url) async {
    try {
      final http.Response response = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final String? contentLength = response.headers['content-length'];
        if (contentLength != null) {
          return int.tryParse(contentLength) ?? 0;
        }
      }
    } catch (_) {}
    return 0;
  }

  Future<String> pickFastestUrl(String original, String custom) async {
    final Completer<String> completer = Completer<String>();
    bool originalFailed = false;
    bool customFailed = false;

    Future<void> check(String url, bool isOriginal) async {
      final http.Client client = http.Client();
      try {
        final Uri uri = Uri.parse(url);
        final http.Response response = await client
            .head(uri)
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          if (!completer.isCompleted) {
            completer.complete(url);
          }
        } else if (isOriginal) {
          originalFailed = true;
        } else {
          customFailed = true;
        }
      } catch (_) {
        if (isOriginal) {
          originalFailed = true;
        } else {
          customFailed = true;
        }
      }

      if (originalFailed && customFailed && !completer.isCompleted) {
        completer.complete(original);
      }
      client.close();
    }

    unawaited(check(original, true));
    unawaited(check(custom, false));

    try {
      return await completer.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      return original;
    }
  }

  Future<bool?> showUpdateAvailableDialog(
    BuildContext context,
    UpdateCheckResult result, {
    String confirmLabel = '立即更新',
  }) {
    final UpdateReleaseAsset? asset = result.asset;
    final List<String> highlights = result.highlights;
    final String? description = result.body?.trim();
    final String sizeLabel = formatUpdateFileSize(asset?.size ?? 0);

    return showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextTheme textTheme = Theme.of(dialogContext).textTheme;
        final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: Text('发现新版本 ${result.versionLabel}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '当前版本 ${result.currentVersion}',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Text('安装包大小：$sizeLabel', style: textTheme.bodyMedium),
                if (highlights.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text('更新亮点：', style: textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...highlights.map(
                    (String item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '• ',
                            style: TextStyle(color: colorScheme.primary),
                          ),
                          Expanded(child: Text(item)),
                        ],
                      ),
                    ),
                  ),
                ] else if (description != null &&
                    description.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Text(description),
                ] else ...<Widget>[
                  const SizedBox(height: 16),
                  const Text('暂无更新说明，是否继续下载并安装？'),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('稍后'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
  }

  Future<UpdateStartResult> startBackgroundUpdate({
    required UpdateReleaseAsset? asset,
    required Version? releaseVersion,
  }) async {
    if (asset == null) {
      return const UpdateStartResult(
        status: UpdateStartStatus.noCompatibleAsset,
        message: '未找到可用安装包',
      );
    }

    final UpdateDownloadService downloadService =
        UpdateDownloadService.instance;
    if (downloadService.coordinator.isDownloading) {
      return const UpdateStartResult(
        status: UpdateStartStatus.alreadyDownloading,
        message: '更新正在后台下载',
      );
    }

    UpdateReleaseAsset effectiveAsset = asset;
    if (effectiveAsset.size <= 0) {
      final int size = await tryFetchAssetSize(
        effectiveAsset.browserDownloadUrl,
      );
      if (size > 0) {
        effectiveAsset = effectiveAsset.copyWith(size: size);
      }
    }

    final String downloadUrl = await _resolveDownloadUrl(
      effectiveAsset,
      releaseVersion,
    );
    final int? totalHint = effectiveAsset.size > 0 ? effectiveAsset.size : null;
    final DownloadRequest request = DownloadRequest(
      uri: Uri.parse(downloadUrl),
      fileName: effectiveAsset.name,
      totalBytesHint: totalHint,
    );

    final File? cachedFile = await downloadService.findCachedFile(
      request: request,
      expectedBytes: totalHint,
    );
    if (cachedFile != null) {
      await downloadService.registerDownloadedFileForInstall(
        cachedFile,
        openNow: true,
      );
      return const UpdateStartResult(
        status: UpdateStartStatus.openedCachedInstaller,
        message: '检测到已下载的安装包，正在继续安装',
      );
    }

    unawaited(downloadService.startBackgroundDownload(request: request));
    return const UpdateStartResult(
      status: UpdateStartStatus.startedDownload,
      message: '已开始后台下载更新',
    );
  }

  Future<String> _resolveDownloadUrl(
    UpdateReleaseAsset asset,
    Version? releaseVersion,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? customPattern = prefs.getString(
      'custom_download_url_pattern',
    );
    String downloadUrl = asset.browserDownloadUrl;

    if (customPattern != null && customPattern.isNotEmpty) {
      String candidateUrl;
      if (customPattern.contains(r'$sanitizedName')) {
        candidateUrl = customPattern.replaceAll(r'$sanitizedName', asset.name);
      } else {
        final String prefix = customPattern.endsWith('/')
            ? customPattern
            : '$customPattern/';

        String filename = asset.name;
        if (releaseVersion != null) {
          final _AndroidApkVariant variant = _inferAndroidApkVariant(asset);
          String? arch;
          switch (variant) {
            case _AndroidApkVariant.arm64V8a:
              arch = 'arm64-v8a';
              break;
            case _AndroidApkVariant.armeabiV7a:
              arch = 'armeabi-v7a';
              break;
            case _AndroidApkVariant.x86_64:
              arch = 'x86_64';
              break;
            case _AndroidApkVariant.x86:
              arch = 'x86';
              break;
            case _AndroidApkVariant.universal:
              arch = 'universal';
              break;
            case _AndroidApkVariant.unknown:
              arch = null;
              break;
          }
          if (arch != null) {
            filename =
                'com.lulo.dormdevise-v${releaseVersion.toString()}-$arch-release.apk';
          }
        }
        candidateUrl = '$prefix$filename';
      }

      downloadUrl = await pickFastestUrl(
        asset.browserDownloadUrl,
        candidateUrl,
      );
    }

    return downloadUrl;
  }

  Future<List<UpdateReleaseInfo>> _loadReleasesBasedOnConfig({
    bool forceRefresh = false,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String sourceType = prefs.getString('update_source_type') ?? 'auto';
    final String? customApiUrl = prefs.getString('custom_update_api_url');
    final String lastAttemptKey = 'update_last_attempt_time';
    final String cacheDataKey = 'update_cached_releases_data';

    if (!forceRefresh &&
        _cachedReleases != null &&
        _lastFetchTime != null &&
        _lastSourceType == sourceType &&
        _lastCustomApiUrl == customApiUrl &&
        DateTime.now().difference(_lastFetchTime!) <
            const Duration(seconds: 5)) {
      return _cachedReleases!;
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    final int lastAttempt = prefs.getInt(lastAttemptKey) ?? 0;
    if (!forceRefresh && (now - lastAttempt) < 60000) {
      final String? cachedJson = prefs.getString(cacheDataKey);
      if (cachedJson != null) {
        try {
          final List<dynamic> list = jsonDecode(cachedJson) as List<dynamic>;
          final List<UpdateReleaseInfo> releases = list
              .map(
                (dynamic item) =>
                    UpdateReleaseInfo.fromJson(item as Map<String, dynamic>),
              )
              .toList(growable: false);
          if (releases.isNotEmpty) {
            _cachedReleases = releases;
            _lastFetchTime = DateTime.now();
            _lastSourceType = sourceType;
            _lastCustomApiUrl = customApiUrl;
            return releases;
          }
        } catch (_) {}
      }
    }

    if (_pendingFetch != null) {
      return _pendingFetch!;
    }

    Future<List<UpdateReleaseInfo>> executeFetch() async {
      Future<List<UpdateReleaseInfo>> fetchOnce() async {
        switch (sourceType) {
          case 'github':
            return _loadReleasesFromGitHub();
          case 'gitee':
            return _loadReleasesFromGitee();
          case 'custom':
            if (customApiUrl == null || customApiUrl.isEmpty) {
              return const <UpdateReleaseInfo>[];
            }
            return _loadReleasesFromCustom(customApiUrl);
          case 'auto':
          default:
            final List<UpdateReleaseInfo> github = await _safeFetch(
              _loadReleasesFromGitHub,
            );
            final List<UpdateReleaseInfo> gitee = await _safeFetch(
              _loadReleasesFromGitee,
            );
            if (github.isEmpty && gitee.isEmpty) {
              throw Exception('All sources failed in auto mode');
            }

            final Map<String, UpdateReleaseInfo> merged =
                <String, UpdateReleaseInfo>{};
            for (final UpdateReleaseInfo release in gitee) {
              merged[_releaseKey(release)] = release;
            }
            for (final UpdateReleaseInfo release in github) {
              final String key = _releaseKey(release);
              final UpdateReleaseInfo? existing = merged[key];
              if (existing == null) {
                merged[key] = release;
                continue;
              }
              final String existingBody = existing.body?.trim() ?? '';
              final String newBody = release.body?.trim() ?? '';
              if (newBody.isNotEmpty || existingBody.isEmpty) {
                merged[key] = release;
              }
            }
            return merged.values.toList(growable: false);
        }
      }

      List<UpdateReleaseInfo> releases = <UpdateReleaseInfo>[];
      try {
        releases = await fetchOnce();
      } catch (_) {
        await Future<void>.delayed(const Duration(seconds: 5));
        try {
          releases = await fetchOnce();
        } catch (error) {
          debugPrint('获取发布信息最终失败: $error');
          await prefs.setInt(
            lastAttemptKey,
            DateTime.now().millisecondsSinceEpoch,
          );
          final String? cachedJson = prefs.getString(cacheDataKey);
          if (cachedJson != null) {
            try {
              final List<dynamic> list =
                  jsonDecode(cachedJson) as List<dynamic>;
              return list
                  .map(
                    (dynamic item) => UpdateReleaseInfo.fromJson(
                      item as Map<String, dynamic>,
                    ),
                  )
                  .toList(growable: false);
            } catch (_) {}
          }
          return const <UpdateReleaseInfo>[];
        }
      }

      if (releases.isNotEmpty) {
        _cachedReleases = releases;
        _lastFetchTime = DateTime.now();
        _lastSourceType = sourceType;
        _lastCustomApiUrl = customApiUrl;
        await prefs.setInt(
          lastAttemptKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        await prefs.setString(
          cacheDataKey,
          jsonEncode(
            releases
                .map((UpdateReleaseInfo release) => release.toJson())
                .toList(),
          ),
        );
      }

      return releases;
    }

    _pendingFetch = executeFetch();
    try {
      return await _pendingFetch!;
    } finally {
      _pendingFetch = null;
    }
  }

  Future<List<UpdateReleaseInfo>> _safeFetch(
    Future<List<UpdateReleaseInfo>> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return const <UpdateReleaseInfo>[];
    }
  }

  String _releaseKey(UpdateReleaseInfo release) {
    if (release.version != null) {
      return release.version.toString();
    }
    return '${release.tagName}|${release.name}|${release.publishedAt?.millisecondsSinceEpoch ?? 0}';
  }

  Future<List<UpdateReleaseInfo>> _loadReleasesFromGitHub() async {
    return _fetchReleases(
      Uri.parse('https://api.github.com/repos/Lulozi/DormDevise/releases'),
    );
  }

  Future<List<UpdateReleaseInfo>> _loadReleasesFromGitee() async {
    return _fetchReleases(
      Uri.parse('https://gitee.com/api/v5/repos/lulo/DormDevise/releases'),
    );
  }

  Future<List<UpdateReleaseInfo>> _loadReleasesFromCustom(String url) async {
    return _fetchReleases(Uri.parse(url));
  }

  Future<List<UpdateReleaseInfo>> _fetchReleases(Uri uri) async {
    final http.Response response = await http.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'DormDevise-App',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('API 返回状态码 ${response.statusCode} ($uri)');
    }
    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map(
          (dynamic item) =>
              UpdateReleaseInfo.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }
}

enum _AndroidApkVariant {
  arm64V8a,
  armeabiV7a,
  x86_64,
  x86,
  universal,
  unknown,
}

Version? safeParseVersion(String raw) {
  try {
    final String sanitized = raw.split('+').first;
    return Version.parse(sanitized);
  } catch (_) {
    return null;
  }
}

int _compareReleaseOrder(UpdateReleaseInfo a, UpdateReleaseInfo b) {
  final Version? versionA = a.version;
  final Version? versionB = b.version;
  if (versionA != null && versionB != null) {
    final int versionOrder = versionB.compareTo(versionA);
    if (versionOrder != 0) {
      return versionOrder;
    }
  } else if (versionA != null) {
    return -1;
  } else if (versionB != null) {
    return 1;
  }

  final DateTime? dateA = a.publishedAt;
  final DateTime? dateB = b.publishedAt;
  if (dateA != null && dateB != null) {
    final int dateOrder = dateB.compareTo(dateA);
    if (dateOrder != 0) {
      return dateOrder;
    }
  } else if (dateA != null) {
    return -1;
  } else if (dateB != null) {
    return 1;
  }

  return 0;
}

_AndroidApkVariant _inferAndroidApkVariant(UpdateReleaseAsset asset) {
  final String fingerprint =
      '${asset.name}|${asset.browserDownloadUrl}|${asset.contentType}'
          .toLowerCase();

  bool containsAll(Iterable<String> tokens) =>
      tokens.every((String token) => fingerprint.contains(token));

  bool containsAny(Iterable<String> tokens) =>
      tokens.any((String token) => fingerprint.contains(token));

  if (containsAll(<String>['arm64', 'v8a']) ||
      fingerprint.contains('arm64v8a') ||
      fingerprint.contains('aarch64')) {
    return _AndroidApkVariant.arm64V8a;
  }

  if ((containsAll(<String>['armeabi', 'v7a']) ||
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

  final bool hasStandaloneX86 = RegExp(
    r'(^|[^0-9a-z])x86($|[^0-9a-z])',
  ).hasMatch(fingerprint);
  if ((hasStandaloneX86 || fingerprint.contains('ia32')) &&
      !fingerprint.contains('x86_64') &&
      !fingerprint.contains('x86-64')) {
    return _AndroidApkVariant.x86;
  }

  if (containsAny(<String>[
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

_AndroidApkVariant? _variantForAbi(String abi) {
  final String normalized = abi.toLowerCase();
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

String formatUpdateFileSize(int bytes) {
  if (bytes <= 0) {
    return '未知大小';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double size = bytes.toDouble();
  int unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final int precision = unitIndex == 0 ? 0 : 1;
  return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
}

List<String> extractReleaseHighlights(String body) {
  final List<String> lines = body.split(RegExp(r'\r?\n'));
  final List<String> notes = <String>[];
  for (final String line in lines) {
    final String trimmed = line.trim();
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

Version? _parseVersionFromMetadata(String name, String tag) {
  final List<String?> candidates = <String?>[
    tag,
    RegExp(
      r'v(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)',
    ).firstMatch(name)?.group(1),
    RegExp(
      r'DormDevise-v(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)',
    ).firstMatch(name)?.group(1),
  ];
  for (final String? candidate in candidates) {
    if (candidate == null || candidate.isEmpty) {
      continue;
    }
    final String normalized = candidate.startsWith('v')
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
