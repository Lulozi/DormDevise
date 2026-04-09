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

enum UpdateTrackPreference {
  stable('stable', '稳定版'),
  preview('preview', '预览版'),
  latest('latest', '最新版');

  const UpdateTrackPreference(this.storageValue, this.label);

  final String storageValue;
  final String label;

  static UpdateTrackPreference fromStorage(String? value) {
    for (final UpdateTrackPreference preference in values) {
      if (preference.storageValue == value) {
        return preference;
      }
    }
    return UpdateTrackPreference.stable;
  }
}

enum UpdateDialogAction { confirm, secondary, dismissed }

enum HomePageUpdatePromptSecondaryAction { postpone, cancel }

class HomePageUpdatePromptPlan {
  const HomePageUpdatePromptPlan({
    required this.result,
    required this.secondaryAction,
    required this.completedDeferrals,
  });

  final UpdateCheckResult result;
  final HomePageUpdatePromptSecondaryAction secondaryAction;
  final int completedDeferrals;

  String get secondaryLabel =>
      secondaryAction == HomePageUpdatePromptSecondaryAction.postpone
      ? '推迟本次更新'
      : '取消本次推送';

  int? get nextDelayDays {
    if (secondaryAction != HomePageUpdatePromptSecondaryAction.postpone) {
      return null;
    }
    if (completedDeferrals >= _homePageUpdatePromptDelayDays.length) {
      return null;
    }
    return _homePageUpdatePromptDelayDays[completedDeferrals];
  }

  String get feedbackMessage {
    final int? delayDays = nextDelayDays;
    if (delayDays != null) {
      return '已推迟本次更新 $delayDays 天';
    }
    return '已取消本次推送，后续仅在主版本或次版本更新后提醒';
  }
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
  static const Duration _sharedReleaseCacheDuration = Duration(hours: 2);
  static const String _prefKeyUpdateTrack = 'update_track_preference';
  static const String _prefKeyHomePromptDeferredVersion =
      'update_home_prompt_deferred_version';
  static const String _prefKeyHomePromptDeferStep =
      'update_home_prompt_defer_step';
  static const String _prefKeyHomePromptDeferUntil =
      'update_home_prompt_defer_until';
  static const String _prefKeyHomePromptCanceledVersion =
      'update_home_prompt_canceled_version';

  DateTime? _lastFetchTime;
  List<UpdateReleaseInfo>? _cachedReleases;
  String? _lastSourceType;
  String? _lastCustomApiUrl;
  Future<List<UpdateReleaseInfo>>? _pendingFetch;
  List<String>? _cachedSupportedAbis;
  Future<List<String>>? _supportedAbisFuture;

  Future<UpdateTrackPreference> getUpdateTrackPreference() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return UpdateTrackPreference.fromStorage(
      prefs.getString(_prefKeyUpdateTrack),
    );
  }

  Future<void> setUpdateTrackPreference(
    UpdateTrackPreference preference,
  ) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final UpdateTrackPreference current = UpdateTrackPreference.fromStorage(
      prefs.getString(_prefKeyUpdateTrack),
    );
    if (current == preference) {
      return;
    }
    await prefs.setString(_prefKeyUpdateTrack, preference.storageValue);
    await clearHomePageUpdatePromptState(prefs: prefs);
  }

  Future<UpdateCheckResult?> fetchAvailableUpdate({
    bool forceRefresh = false,
    bool allowNetwork = true,
  }) async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final Version? currentVersion = safeParseVersion(packageInfo.version);
    if (currentVersion == null) {
      return null;
    }

    final UpdateReleaseInfo? latestRelease = await fetchLatestReleaseInfo(
      forceRefresh: forceRefresh,
      allowNetwork: allowNetwork,
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

  Future<HomePageUpdatePromptPlan?> fetchHomePageUpdatePrompt({
    bool forceRefresh = false,
  }) async {
    final UpdateCheckResult? result = await fetchAvailableUpdate(
      forceRefresh: forceRefresh,
    );
    if (result == null) {
      return null;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Version latestVersion = result.latestVersion;
    final Version? canceledVersion = _readStoredVersion(
      prefs,
      _prefKeyHomePromptCanceledVersion,
    );
    if (canceledVersion != null) {
      if (!hasMajorOrMinorUpdate(latestVersion, canceledVersion)) {
        return null;
      }
      await _clearHomePageCancelState(prefs: prefs);
    }

    final Version? deferredVersion = _readStoredVersion(
      prefs,
      _prefKeyHomePromptDeferredVersion,
    );
    final int storedStep = _readDeferredStep(prefs);
    final int deferUntilMillis =
        prefs.getInt(_prefKeyHomePromptDeferUntil) ?? 0;
    if (deferredVersion == null) {
      if (storedStep > 0 || deferUntilMillis > 0) {
        await _clearHomePageDelayState(prefs: prefs);
      }
      return HomePageUpdatePromptPlan(
        result: result,
        secondaryAction: HomePageUpdatePromptSecondaryAction.postpone,
        completedDeferrals: 0,
      );
    }

    if (latestVersion != deferredVersion) {
      await _clearHomePageDelayState(prefs: prefs);
      return HomePageUpdatePromptPlan(
        result: result,
        secondaryAction: HomePageUpdatePromptSecondaryAction.postpone,
        completedDeferrals: 0,
      );
    }

    if (deferUntilMillis > DateTime.now().millisecondsSinceEpoch) {
      return null;
    }

    return HomePageUpdatePromptPlan(
      result: result,
      secondaryAction: storedStep >= _homePageUpdatePromptDelayDays.length
          ? HomePageUpdatePromptSecondaryAction.cancel
          : HomePageUpdatePromptSecondaryAction.postpone,
      completedDeferrals: storedStep,
    );
  }

  Future<void> deferHomePageUpdatePrompt(Version releaseVersion) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Version? storedVersion = _readStoredVersion(
      prefs,
      _prefKeyHomePromptDeferredVersion,
    );
    final int previousStep =
        storedVersion != null && storedVersion == releaseVersion
        ? _readDeferredStep(prefs)
        : 0;
    final int nextStep = previousStep >= _homePageUpdatePromptDelayDays.length
        ? _homePageUpdatePromptDelayDays.length
        : previousStep + 1;
    final int delayDays = _homePageUpdatePromptDelayDays[nextStep - 1];

    await prefs.setString(
      _prefKeyHomePromptDeferredVersion,
      releaseVersion.toString(),
    );
    await prefs.setInt(_prefKeyHomePromptDeferStep, nextStep);
    await prefs.setInt(
      _prefKeyHomePromptDeferUntil,
      DateTime.now().add(Duration(days: delayDays)).millisecondsSinceEpoch,
    );
    await _clearHomePageCancelState(prefs: prefs);
  }

  Future<void> cancelHomePageUpdatePrompt(Version releaseVersion) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKeyHomePromptCanceledVersion,
      releaseVersion.toString(),
    );
    await _clearHomePageDelayState(prefs: prefs);
  }

  Future<void> clearHomePageUpdatePromptState({
    SharedPreferences? prefs,
  }) async {
    final SharedPreferences effectivePrefs =
        prefs ?? await SharedPreferences.getInstance();
    await _clearHomePageCancelState(prefs: effectivePrefs);
    await _clearHomePageDelayState(prefs: effectivePrefs);
  }

  Future<UpdateReleaseInfo?> fetchLatestReleaseInfo({
    bool forceRefresh = false,
    UpdateTrackPreference? trackPreference,
    bool allowNetwork = true,
  }) async {
    final UpdateTrackPreference effectiveTrack =
        trackPreference ?? await getUpdateTrackPreference();
    if (effectiveTrack == UpdateTrackPreference.stable) {
      return _loadLatestStableReleaseBasedOnConfig(
        forceRefresh: forceRefresh,
        allowNetwork: allowNetwork,
      );
    }

    final List<UpdateReleaseInfo> releases = await _loadReleasesBasedOnConfig(
      forceRefresh: forceRefresh,
      allowNetwork: allowNetwork,
    );
    if (releases.isEmpty) {
      return null;
    }

    return selectPreferredRelease(releases, preference: effectiveTrack);
  }

  UpdateReleaseInfo? selectPreferredRelease(
    List<UpdateReleaseInfo> releases, {
    required UpdateTrackPreference preference,
  }) {
    final List<UpdateReleaseInfo> published = releases
        .where((UpdateReleaseInfo release) => !release.isDraft)
        .toList();
    if (published.isEmpty) {
      return null;
    }

    List<UpdateReleaseInfo> candidates;
    switch (preference) {
      case UpdateTrackPreference.stable:
        candidates = published
            .where((UpdateReleaseInfo release) => !release.isPrerelease)
            .toList();
        break;
      case UpdateTrackPreference.preview:
        candidates = published
            .where((UpdateReleaseInfo release) => release.isPrerelease)
            .toList();
        if (candidates.isEmpty) {
          candidates = published
              .where((UpdateReleaseInfo release) => !release.isPrerelease)
              .toList();
        }
        break;
      case UpdateTrackPreference.latest:
        candidates = List<UpdateReleaseInfo>.from(published);
        break;
    }

    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(_compareReleaseFeedOrder);
    return candidates.first;
  }

  Future<UpdateReleaseInfo?> _loadLatestStableReleaseBasedOnConfig({
    bool forceRefresh = false,
    bool allowNetwork = true,
  }) async {
    if (!allowNetwork) {
      return _pickLatestStableFromFeed(
        await _loadReleasesBasedOnConfig(allowNetwork: false),
      );
    }

    if (!forceRefresh) {
      return _pickLatestStableFromFeed(
        await _loadReleasesBasedOnConfig(
          forceRefresh: false,
          allowNetwork: true,
        ),
      );
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String sourceType = prefs.getString('update_source_type') ?? 'auto';
    final String? customApiUrl = prefs.getString('custom_update_api_url');

    switch (sourceType) {
      case 'github':
        return await _safeFetchSingle(_loadLatestReleaseFromGitHub) ??
            _pickLatestStableFromFeed(
              await _loadReleasesBasedOnConfig(forceRefresh: forceRefresh),
            );
      case 'gitee':
        return _pickLatestStableFromFeed(
          await _loadReleasesBasedOnConfig(forceRefresh: true),
        );
      case 'custom':
        if (customApiUrl == null || customApiUrl.isEmpty) {
          return null;
        }
        return _pickLatestStableFromFeed(
          await _loadReleasesBasedOnConfig(forceRefresh: true),
        );
      case 'auto':
      default:
        final List<UpdateReleaseInfo> candidates = <UpdateReleaseInfo>[
          ...[
            await _safeFetchSingle(_loadLatestReleaseFromGitHub),
            await _safeFetchSingle(() async {
              final List<UpdateReleaseInfo> releases =
                  await _loadReleasesFromGitee();
              return _pickLatestStableFromFeed(releases);
            }),
          ].whereType<UpdateReleaseInfo>(),
        ];
        final UpdateReleaseInfo? merged = _mergeReleaseCandidates(candidates);
        if (merged != null) {
          return merged;
        }
        return _pickLatestStableFromFeed(
          await _loadReleasesBasedOnConfig(forceRefresh: forceRefresh),
        );
    }
  }

  UpdateReleaseInfo? _pickLatestStableFromFeed(
    List<UpdateReleaseInfo> releases,
  ) {
    final List<UpdateReleaseInfo> stable = releases
        .where(
          (UpdateReleaseInfo release) =>
              !release.isDraft && !release.isPrerelease,
        )
        .toList();
    if (stable.isEmpty) {
      return null;
    }
    stable.sort(_compareReleaseFeedOrder);
    return stable.first;
  }

  UpdateReleaseInfo? _mergeReleaseCandidates(List<UpdateReleaseInfo> releases) {
    if (releases.isEmpty) {
      return null;
    }
    UpdateReleaseInfo selected = releases.first;
    for (final UpdateReleaseInfo candidate in releases.skip(1)) {
      final int order = _compareReleaseFeedOrder(candidate, selected);
      if (order < 0) {
        selected = candidate;
        continue;
      }
      if (order == 0) {
        final String selectedBody = selected.body?.trim() ?? '';
        final String candidateBody = candidate.body?.trim() ?? '';
        if (candidateBody.isNotEmpty && selectedBody.isEmpty) {
          selected = candidate;
        }
      }
    }
    return selected;
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

  Future<UpdateDialogAction> showUpdateAvailableDialog(
    BuildContext context,
    UpdateCheckResult result, {
    String confirmLabel = '立即更新',
    String secondaryLabel = '稍后',
    bool barrierDismissible = true,
    bool allowSystemPop = true,
  }) async {
    final UpdateReleaseAsset? asset = result.asset;
    final List<String> highlights = result.highlights;
    final String? description = result.body?.trim();
    final String sizeLabel = formatUpdateFileSize(asset?.size ?? 0);

    final UpdateDialogAction? action = await showDialog<UpdateDialogAction>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext dialogContext) {
        final TextTheme textTheme = Theme.of(dialogContext).textTheme;
        final ColorScheme colorScheme = Theme.of(dialogContext).colorScheme;
        final Widget dialog = AlertDialog(
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
              onPressed: () =>
                  Navigator.of(dialogContext).pop(UpdateDialogAction.secondary),
              child: Text(secondaryLabel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(UpdateDialogAction.confirm),
              child: Text(confirmLabel),
            ),
          ],
        );
        if (!allowSystemPop) {
          return PopScope(canPop: false, child: dialog);
        }
        return dialog;
      },
    );
    return action ?? UpdateDialogAction.dismissed;
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

    await downloadService.markHomePagePromptDownloadRunning();

    // 启动后台下载（由 DownloadService 自行负责标记与进度更新）
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
    bool allowNetwork = true,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String sourceType = prefs.getString('update_source_type') ?? 'auto';
    final String? customApiUrl = prefs.getString('custom_update_api_url');
    final String lastAttemptKey = 'update_last_attempt_time';
    final String cacheDataKey = 'update_cached_releases_data';

    List<UpdateReleaseInfo>? readCachedReleases() {
      final String? cachedJson = prefs.getString(cacheDataKey);
      if (cachedJson == null) {
        return null;
      }
      try {
        final List<dynamic> list = jsonDecode(cachedJson) as List<dynamic>;
        return list
            .map(
              (dynamic item) =>
                  UpdateReleaseInfo.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false);
      } catch (_) {
        return null;
      }
    }

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
    if (!forceRefresh &&
        (now - lastAttempt) < _sharedReleaseCacheDuration.inMilliseconds) {
      final List<UpdateReleaseInfo>? releases = readCachedReleases();
      if (releases != null && releases.isNotEmpty) {
        _cachedReleases = releases;
        _lastFetchTime = DateTime.now();
        _lastSourceType = sourceType;
        _lastCustomApiUrl = customApiUrl;
        return releases;
      }
      return const <UpdateReleaseInfo>[];
    }

    if (!allowNetwork) {
      final List<UpdateReleaseInfo>? releases = readCachedReleases();
      if (releases != null && releases.isNotEmpty) {
        _cachedReleases = releases;
        _lastFetchTime = DateTime.now();
        _lastSourceType = sourceType;
        _lastCustomApiUrl = customApiUrl;
        return releases;
      }
      return const <UpdateReleaseInfo>[];
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
      } catch (error) {
        debugPrint('获取发布信息失败: $error');
      }

      if (releases.isEmpty) {
        await prefs.setInt(
          lastAttemptKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        final List<UpdateReleaseInfo>? cached = readCachedReleases();
        if (cached != null) {
          return cached;
        }
        return const <UpdateReleaseInfo>[];
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

  int _readDeferredStep(SharedPreferences prefs) {
    final int stored = prefs.getInt(_prefKeyHomePromptDeferStep) ?? 0;
    return stored.clamp(0, _homePageUpdatePromptDelayDays.length).toInt();
  }

  Version? _readStoredVersion(SharedPreferences prefs, String key) {
    final String? raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return safeParseVersion(raw);
  }

  Future<void> _clearHomePageDelayState({
    required SharedPreferences prefs,
  }) async {
    await prefs.remove(_prefKeyHomePromptDeferredVersion);
    await prefs.remove(_prefKeyHomePromptDeferStep);
    await prefs.remove(_prefKeyHomePromptDeferUntil);
  }

  Future<void> _clearHomePageCancelState({
    required SharedPreferences prefs,
  }) async {
    await prefs.remove(_prefKeyHomePromptCanceledVersion);
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

  Future<UpdateReleaseInfo?> _safeFetchSingle(
    Future<UpdateReleaseInfo?> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return null;
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

  Future<UpdateReleaseInfo?> _loadLatestReleaseFromGitHub() async {
    return _fetchRelease(
      Uri.parse(
        'https://api.github.com/repos/Lulozi/DormDevise/releases/latest',
      ),
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

  Future<UpdateReleaseInfo?> _fetchRelease(Uri uri) async {
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
    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;
    return UpdateReleaseInfo.fromJson(json);
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

const List<int> _homePageUpdatePromptDelayDays = <int>[7, 14, 21];

Version? safeParseVersion(String raw) {
  try {
    final String sanitized = raw.split('+').first;
    return Version.parse(sanitized);
  } catch (_) {
    return null;
  }
}

int _compareReleaseFeedOrder(UpdateReleaseInfo a, UpdateReleaseInfo b) {
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

  if (a.isPrerelease != b.isPrerelease) {
    return a.isPrerelease ? 1 : -1;
  }

  return 0;
}

bool hasMajorOrMinorUpdate(Version candidate, Version baseline) {
  if (candidate.major != baseline.major) {
    return candidate.major > baseline.major;
  }
  return candidate.minor > baseline.minor;
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
