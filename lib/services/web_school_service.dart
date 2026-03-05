import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_school.dart';

class WebSchoolCredential {
  const WebSchoolCredential({required this.username, required this.password});

  final String username;
  final String password;
}

/// 网页导入课表学校数据服务，负责学校列表与登录凭据的持久化。
///
/// 学校列表存储在 [SharedPreferences] 中，账号密码等敏感信息
/// 通过 [FlutterSecureStorage] 加密存储。
class WebSchoolService {
  WebSchoolService._();

  static final WebSchoolService instance = WebSchoolService._();

  static const String _schoolsKey = 'web_school_service_schools';
  static const String _credentialLegacyPrefix = 'web_school_credential_';
  static const String _credentialAccountsPrefix = 'web_school_accounts_';
  static const String _credentialLastUserPrefix = 'web_school_last_user_';
  static const String _accountWebDataPrefix = 'web_school_account_web_data_';

  /// 加密存储实例，用于安全保存账号密码。
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 预设学校列表，用户可以从中快速选择。
  static const List<WebSchool> presetSchools = [
    WebSchool(
      name: '福州理工学院',
      url:
          'http://oaa.fitedu.net/jwglxt/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151&layout=default',
    ),
    WebSchool(name: '福建理工学院', url: ''),
  ];

  /// 判断学校是否为预设学校。
  bool isPresetSchool(WebSchool school) {
    return presetSchools.any((preset) => preset.name == school.name);
  }

  /// 加载用户保存的学校列表。
  ///
  /// 首次使用时返回默认的预设学校（仅福州理工学院）。
  Future<List<WebSchool>> loadSchools() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_schoolsKey);
    if (raw == null || raw.isEmpty) {
      // 首次使用，初始化默认学校
      final List<WebSchool> defaults = [presetSchools.first];
      await _saveSchools(defaults);
      return defaults;
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WebSchool.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('加载学校列表失败: $e');
      return [presetSchools.first];
    }
  }

  /// 保存学校列表。
  Future<void> _saveSchools(List<WebSchool> schools) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(schools.map((s) => s.toJson()).toList());
    await prefs.setString(_schoolsKey, raw);
  }

  /// 添加一所学校。
  Future<void> addSchool(WebSchool school) async {
    final schools = await loadSchools();
    schools.add(school);
    await _saveSchools(schools);
  }

  /// 更新指定索引的学校信息。
  Future<void> updateSchool(int index, WebSchool school) async {
    final schools = await loadSchools();
    if (index >= 0 && index < schools.length) {
      schools[index] = school;
      await _saveSchools(schools);
    }
  }

  /// 删除指定索引的学校。
  Future<void> deleteSchool(int index) async {
    final schools = await loadSchools();
    if (index >= 0 && index < schools.length) {
      final school = schools[index];
      schools.removeAt(index);
      await _saveSchools(schools);
      // 同时清除该学校的登录凭据和账号网页数据
      await deleteCredentials(school.name);
    }
  }

  /// 批量删除学校。
  Future<void> deleteSchools(List<int> indices) async {
    final schools = await loadSchools();
    // 按降序排序索引以避免删除时索引偏移
    final sortedIndices = indices.toList()..sort((a, b) => b.compareTo(a));
    for (final index in sortedIndices) {
      if (index >= 0 && index < schools.length) {
        final school = schools[index];
        schools.removeAt(index);
        await deleteCredentials(school.name);
      }
    }
    await _saveSchools(schools);
  }

  /// 保存学校登录凭据（加密存储）。
  ///
  /// 同一学校可保存多个账号，按最近使用顺序排列。
  Future<void> saveCredentials({
    required String schoolName,
    required String username,
    required String password,
  }) async {
    final String normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      return;
    }

    await _migrateLegacyCredentialIfNeeded(schoolName);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> usernames = _loadAccountUsernames(prefs, schoolName);
    usernames.removeWhere((value) => value == normalizedUsername);
    usernames.insert(0, normalizedUsername);

    final String key = _credentialKey(schoolName, normalizedUsername);
    final String data = jsonEncode({
      'username': normalizedUsername,
      'password': password,
    });

    await _secureStorage.write(key: key, value: data);
    await _saveAccountUsernames(prefs, schoolName, usernames);
    await prefs.setString(
      _credentialLastUserKey(schoolName),
      normalizedUsername,
    );
  }

  /// 读取学校登录凭据。
  ///
  /// [username] 为空时优先返回上次使用账号，否则返回最近保存的账号。
  Future<({String username, String password})?> loadCredentials(
    String schoolName, {
    String? username,
  }) async {
    await _migrateLegacyCredentialIfNeeded(schoolName);

    final List<WebSchoolCredential> accounts = await loadCredentialAccounts(
      schoolName,
    );
    if (accounts.isEmpty) {
      return null;
    }

    if (username != null && username.trim().isNotEmpty) {
      final String target = username.trim();
      for (final WebSchoolCredential account in accounts) {
        if (account.username == target) {
          return (username: account.username, password: account.password);
        }
      }
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? lastUsername = prefs.getString(
      _credentialLastUserKey(schoolName),
    );

    WebSchoolCredential selected = accounts.first;
    if (lastUsername != null && lastUsername.isNotEmpty) {
      for (final WebSchoolCredential account in accounts) {
        if (account.username == lastUsername) {
          selected = account;
          break;
        }
      }
    }

    await prefs.setString(
      _credentialLastUserKey(schoolName),
      selected.username,
    );
    return (username: selected.username, password: selected.password);
  }

  /// 加载某个学校下已保存的全部账号。
  Future<List<WebSchoolCredential>> loadCredentialAccounts(
    String schoolName,
  ) async {
    await _migrateLegacyCredentialIfNeeded(schoolName);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> usernames = _loadAccountUsernames(prefs, schoolName);

    final List<WebSchoolCredential> result = <WebSchoolCredential>[];
    bool usernamesChanged = false;

    for (final String username in usernames) {
      final String key = _credentialKey(schoolName, username);
      final String? raw = await _secureStorage.read(key: key);
      if (raw == null || raw.isEmpty) {
        usernamesChanged = true;
        continue;
      }

      try {
        final Map<String, dynamic> data =
            jsonDecode(raw) as Map<String, dynamic>;
        final String loadedUsername = (data['username'] as String? ?? username)
            .trim();
        final String loadedPassword = data['password'] as String? ?? '';
        if (loadedUsername.isEmpty) {
          usernamesChanged = true;
          continue;
        }
        result.add(
          WebSchoolCredential(
            username: loadedUsername,
            password: loadedPassword,
          ),
        );
      } catch (e) {
        usernamesChanged = true;
        debugPrint('读取登录凭据失败: $e');
      }
    }

    if (usernamesChanged) {
      await _saveAccountUsernames(
        prefs,
        schoolName,
        result.map((account) => account.username).toList(),
      );

      final String? last = prefs.getString(_credentialLastUserKey(schoolName));
      if (last != null &&
          last.isNotEmpty &&
          result.every((account) => account.username != last)) {
        if (result.isEmpty) {
          await prefs.remove(_credentialLastUserKey(schoolName));
        } else {
          await prefs.setString(
            _credentialLastUserKey(schoolName),
            result.first.username,
          );
        }
      }
    }

    return result;
  }

  /// 删除学校登录凭据。
  ///
  /// [username] 不为空时仅删除该账号；为空时删除该学校全部账号。
  Future<void> deleteCredentials(String schoolName, {String? username}) async {
    await _migrateLegacyCredentialIfNeeded(schoolName);

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String normalizedUsername = username?.trim() ?? '';

    if (normalizedUsername.isNotEmpty) {
      await _secureStorage.delete(
        key: _credentialKey(schoolName, normalizedUsername),
      );
      await deleteAccountWebData(
        schoolName: schoolName,
        username: normalizedUsername,
      );

      final List<String> usernames = _loadAccountUsernames(prefs, schoolName);
      usernames.removeWhere((value) => value == normalizedUsername);
      await _saveAccountUsernames(prefs, schoolName, usernames);

      final String? lastUsername = prefs.getString(
        _credentialLastUserKey(schoolName),
      );
      if (lastUsername == normalizedUsername) {
        if (usernames.isEmpty) {
          await prefs.remove(_credentialLastUserKey(schoolName));
        } else {
          await prefs.setString(
            _credentialLastUserKey(schoolName),
            usernames.first,
          );
        }
      }
      return;
    }

    final List<String> usernames = _loadAccountUsernames(prefs, schoolName);
    for (final String value in usernames) {
      await _secureStorage.delete(key: _credentialKey(schoolName, value));
      await deleteAccountWebData(schoolName: schoolName, username: value);
    }

    await _secureStorage.delete(key: _legacyCredentialKey(schoolName));
    await prefs.remove(_credentialAccountsKey(schoolName));
    await prefs.remove(_credentialLastUserKey(schoolName));
  }

  /// 保存当前账号的 Cookie 登录态。
  Future<void> saveAccountWebData({
    required String schoolName,
    required String username,
    required String loginUrl,
    required List<Cookie> cookies,
  }) async {
    final String normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || cookies.isEmpty) {
      return;
    }

    final String data = jsonEncode({
      'loginUrl': loginUrl,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
      'cookies': cookies.map((cookie) => cookie.toJson()).toList(),
    });

    await _secureStorage.write(
      key: _accountWebDataKey(schoolName, normalizedUsername),
      value: data,
    );
  }

  /// 恢复当前账号的 Cookie 登录态。
  /// 返回 `true` 表示成功恢复到有效 Cookie。
  Future<bool> restoreAccountWebData({
    required String schoolName,
    required String username,
    required String loginUrl,
  }) async {
    final String normalizedUsername = username.trim();
    final CookieManager cookieManager = CookieManager.instance();

    // 切换账号前优先清理全局 Cookie，保证账号隔离。
    await cookieManager.deleteAllCookies();

    if (normalizedUsername.isEmpty) {
      return false;
    }

    final String? raw = await _secureStorage.read(
      key: _accountWebDataKey(schoolName, normalizedUsername),
    );
    if (raw == null || raw.isEmpty) {
      return false;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      final List<dynamic> cookieData =
          data['cookies'] as List<dynamic>? ?? <dynamic>[];
      final String fallbackUrl = (data['loginUrl'] as String? ?? loginUrl)
          .trim();
      int restored = 0;

      for (final dynamic item in cookieData) {
        if (item is! Map) {
          continue;
        }

        final Map<String, dynamic> cookieMap = Map<String, dynamic>.from(item);
        final Cookie? cookie = Cookie.fromMap(cookieMap);
        if (cookie == null) {
          continue;
        }

        final String cookieName = cookie.name.trim();
        if (cookieName.isEmpty) {
          continue;
        }

        final String normalizedDomain = _normalizeCookieDomain(cookie.domain);
        final WebUri targetUrl = _resolveCookieUrl(
          cookie: cookie,
          fallbackUrl: fallbackUrl.isEmpty ? loginUrl : fallbackUrl,
        );

        await cookieManager.setCookie(
          url: targetUrl,
          name: cookieName,
          value: cookie.value?.toString() ?? '',
          path: _normalizeCookiePath(cookie.path),
          domain: normalizedDomain.isEmpty ? null : normalizedDomain,
          expiresDate: cookie.expiresDate,
          isSecure: cookie.isSecure,
          isHttpOnly: cookie.isHttpOnly,
          sameSite: cookie.sameSite,
        );
        restored++;
      }
      return restored > 0;
    } catch (e) {
      debugPrint('恢复账号网页数据失败: $e');
      return false;
    }
  }

  /// 删除某个账号对应的网页数据。
  Future<void> deleteAccountWebData({
    required String schoolName,
    required String username,
  }) async {
    final String normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty) {
      return;
    }

    await _secureStorage.delete(
      key: _accountWebDataKey(schoolName, normalizedUsername),
    );
  }

  Future<void> _migrateLegacyCredentialIfNeeded(String schoolName) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> usernames = _loadAccountUsernames(prefs, schoolName);
    if (usernames.isNotEmpty) {
      return;
    }

    final String legacyKey = _legacyCredentialKey(schoolName);
    final String? legacyRaw = await _secureStorage.read(key: legacyKey);
    if (legacyRaw == null || legacyRaw.isEmpty) {
      return;
    }

    try {
      final Map<String, dynamic> data =
          jsonDecode(legacyRaw) as Map<String, dynamic>;
      final String username = (data['username'] as String? ?? '').trim();
      final String password = data['password'] as String? ?? '';
      if (username.isEmpty) {
        await _secureStorage.delete(key: legacyKey);
        return;
      }

      final String newKey = _credentialKey(schoolName, username);
      await _secureStorage.write(
        key: newKey,
        value: jsonEncode({'username': username, 'password': password}),
      );
      await _saveAccountUsernames(prefs, schoolName, <String>[username]);
      await prefs.setString(_credentialLastUserKey(schoolName), username);
      await _secureStorage.delete(key: legacyKey);
    } catch (e) {
      debugPrint('旧版登录凭据迁移失败: $e');
    }
  }

  List<String> _loadAccountUsernames(
    SharedPreferences prefs,
    String schoolName,
  ) {
    final String? raw = prefs.getString(_credentialAccountsKey(schoolName));
    if (raw == null || raw.isEmpty) {
      return <String>[];
    }

    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return _dedupeKeepOrder(
        list
            .map((item) => item.toString().trim())
            .where((value) => value.isNotEmpty),
      );
    } catch (_) {
      return <String>[];
    }
  }

  Future<void> _saveAccountUsernames(
    SharedPreferences prefs,
    String schoolName,
    List<String> usernames,
  ) async {
    final List<String> sanitized = _dedupeKeepOrder(
      usernames.map((value) => value.trim()).where((value) => value.isNotEmpty),
    );

    if (sanitized.isEmpty) {
      await prefs.remove(_credentialAccountsKey(schoolName));
      return;
    }

    await prefs.setString(
      _credentialAccountsKey(schoolName),
      jsonEncode(sanitized),
    );
  }

  List<String> _dedupeKeepOrder(Iterable<String> values) {
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }

  WebUri _resolveCookieUrl({
    required Cookie cookie,
    required String fallbackUrl,
  }) {
    final Uri? fallbackUri = Uri.tryParse(fallbackUrl.trim());
    final String normalizedDomain = _normalizeCookieDomain(cookie.domain);
    final String normalizedPath = _normalizeCookiePath(cookie.path);

    if (normalizedDomain.isNotEmpty) {
      final String fallbackScheme =
          fallbackUri != null &&
              (fallbackUri.scheme == 'http' || fallbackUri.scheme == 'https')
          ? fallbackUri.scheme
          : 'https';
      final String scheme = cookie.isSecure == true ? 'https' : fallbackScheme;
      return WebUri.uri(
        Uri(scheme: scheme, host: normalizedDomain, path: normalizedPath),
      );
    }

    if (fallbackUri != null && fallbackUri.host.isNotEmpty) {
      final String scheme = fallbackUri.scheme.isNotEmpty
          ? fallbackUri.scheme
          : 'https';
      return WebUri.uri(
        Uri(scheme: scheme, host: fallbackUri.host, path: normalizedPath),
      );
    }

    return WebUri('https://localhost$normalizedPath');
  }

  String _normalizeCookieDomain(String? domain) {
    if (domain == null) {
      return '';
    }
    return domain.trim().replaceFirst(RegExp(r'^\.+'), '');
  }

  String _normalizeCookiePath(String? path) {
    final String normalized = (path ?? '/').trim();
    if (normalized.isEmpty) {
      return '/';
    }
    return normalized.startsWith('/') ? normalized : '/$normalized';
  }

  String _credentialAccountsKey(String schoolName) =>
      '$_credentialAccountsPrefix${_encodeKeyPart(schoolName)}';

  String _credentialLastUserKey(String schoolName) =>
      '$_credentialLastUserPrefix${_encodeKeyPart(schoolName)}';

  String _legacyCredentialKey(String schoolName) =>
      '$_credentialLegacyPrefix$schoolName';

  String _credentialKey(String schoolName, String username) =>
      '$_credentialLegacyPrefix${_encodeKeyPart(schoolName)}_${_encodeKeyPart(username)}';

  String _accountWebDataKey(String schoolName, String username) =>
      '$_accountWebDataPrefix${_encodeKeyPart(schoolName)}_${_encodeKeyPart(username)}';

  String _encodeKeyPart(String value) => base64UrlEncode(utf8.encode(value));
}
