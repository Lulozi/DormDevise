import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动时可复用的更新信息。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.currentVersion,
    required this.latestVersion,
    required this.versionLabel,
    required this.body,
    required this.highlights,
  });

  final String currentVersion;
  final Version latestVersion;
  final String versionLabel;
  final String? body;
  final List<String> highlights;
}

class UpdateCheckService {
  UpdateCheckService._();

  static final UpdateCheckService instance = UpdateCheckService._();

  Future<UpdateCheckResult?> fetchAvailableUpdate() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final Version? currentVersion = _safeParseVersion(packageInfo.version);
    if (currentVersion == null) {
      return null;
    }

    final _StartupReleaseInfo? latestRelease = await _fetchLatestReleaseInfo();
    if (latestRelease == null || latestRelease.version == null) {
      return null;
    }
    if (latestRelease.version! <= currentVersion) {
      return null;
    }

    return UpdateCheckResult(
      currentVersion: packageInfo.version,
      latestVersion: latestRelease.version!,
      versionLabel:
          latestRelease.readableLabel ?? 'v${latestRelease.version.toString()}',
      body: latestRelease.body,
      highlights: _extractReleaseHighlights(latestRelease.body ?? ''),
    );
  }

  Future<_StartupReleaseInfo?> _fetchLatestReleaseInfo() async {
    final List<_StartupReleaseInfo> releases =
        await _loadReleasesBasedOnConfig();
    if (releases.isEmpty) {
      return null;
    }

    final List<_StartupReleaseInfo> stable = releases
        .where((release) => !release.isDraft && !release.isPrerelease)
        .toList();
    final List<_StartupReleaseInfo> candidates = stable.isNotEmpty
        ? stable
        : releases.where((release) => !release.isDraft).toList();
    if (candidates.isEmpty) {
      return null;
    }
    candidates.sort(_compareReleaseOrder);
    return candidates.first;
  }

  Future<List<_StartupReleaseInfo>> _loadReleasesBasedOnConfig() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String sourceType = prefs.getString('update_source_type') ?? 'auto';
    final String? customApiUrl = prefs.getString('custom_update_api_url');

    switch (sourceType) {
      case 'github':
        return _loadReleasesFromGitHub();
      case 'gitee':
        return _loadReleasesFromGitee();
      case 'custom':
        if (customApiUrl == null || customApiUrl.isEmpty) {
          return const <_StartupReleaseInfo>[];
        }
        return _loadReleasesFromCustom(customApiUrl);
      case 'auto':
      default:
        final List<_StartupReleaseInfo> github = await _safeFetch(
          _loadReleasesFromGitHub,
        );
        final List<_StartupReleaseInfo> gitee = await _safeFetch(
          _loadReleasesFromGitee,
        );
        if (github.isEmpty && gitee.isEmpty) {
          return const <_StartupReleaseInfo>[];
        }

        final Map<String, _StartupReleaseInfo> merged =
            <String, _StartupReleaseInfo>{};
        for (final _StartupReleaseInfo release in gitee) {
          final String key = _releaseKey(release);
          merged[key] = release;
        }
        for (final _StartupReleaseInfo release in github) {
          final String key = _releaseKey(release);
          final _StartupReleaseInfo? existing = merged[key];
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

  Future<List<_StartupReleaseInfo>> _safeFetch(
    Future<List<_StartupReleaseInfo>> Function() loader,
  ) async {
    try {
      return await loader();
    } catch (_) {
      return const <_StartupReleaseInfo>[];
    }
  }

  String _releaseKey(_StartupReleaseInfo release) {
    if (release.version != null) {
      return release.version.toString();
    }
    return '${release.tagName}|${release.name}|${release.publishedAt?.millisecondsSinceEpoch ?? 0}';
  }

  Future<List<_StartupReleaseInfo>> _loadReleasesFromGitHub() async {
    return _fetchReleases(
      Uri.parse('https://api.github.com/repos/Lulozi/DormDevise/releases'),
    );
  }

  Future<List<_StartupReleaseInfo>> _loadReleasesFromGitee() async {
    return _fetchReleases(
      Uri.parse('https://gitee.com/api/v5/repos/lulo/DormDevise/releases'),
    );
  }

  Future<List<_StartupReleaseInfo>> _loadReleasesFromCustom(String url) async {
    return _fetchReleases(Uri.parse(url));
  }

  Future<List<_StartupReleaseInfo>> _fetchReleases(Uri uri) async {
    final http.Response response = await http.get(
      uri,
      headers: const <String, String>{
        'Accept': 'application/json',
        'User-Agent': 'DormDevise-App',
      },
    );
    if (response.statusCode != 200) {
      throw Exception('API 返回状态码 ${response.statusCode}');
    }
    final List<dynamic> jsonList = jsonDecode(response.body) as List<dynamic>;
    return jsonList
        .map(
          (dynamic item) =>
              _StartupReleaseInfo.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }
}

class _StartupReleaseInfo {
  const _StartupReleaseInfo({
    required this.version,
    required this.body,
    required this.name,
    required this.tagName,
    required this.isDraft,
    required this.isPrerelease,
    required this.publishedAt,
  });

  factory _StartupReleaseInfo.fromJson(Map<String, dynamic> json) {
    final String name = json['name'] as String? ?? '';
    final String tagName = json['tag_name'] as String? ?? '';
    final String? publishedAtRaw = json['published_at'] as String?;
    return _StartupReleaseInfo(
      version: _parseVersionFromMetadata(name, tagName),
      body: json['body'] as String?,
      name: name.isEmpty ? null : name,
      tagName: tagName.isEmpty ? null : tagName,
      isDraft: json['draft'] as bool? ?? false,
      isPrerelease: json['prerelease'] as bool? ?? false,
      publishedAt: publishedAtRaw == null
          ? null
          : DateTime.tryParse(publishedAtRaw)?.toLocal(),
    );
  }

  final Version? version;
  final String? body;
  final String? name;
  final String? tagName;
  final bool isDraft;
  final bool isPrerelease;
  final DateTime? publishedAt;

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
}

Version? _safeParseVersion(String raw) {
  try {
    final String sanitized = raw.split('+').first;
    return Version.parse(sanitized);
  } catch (_) {
    return null;
  }
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

int _compareReleaseOrder(_StartupReleaseInfo a, _StartupReleaseInfo b) {
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

List<String> _extractReleaseHighlights(String body) {
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
