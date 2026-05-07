import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

/// 个人页面与分享预览共用的身份信息。
const String kPersonDisplayName = '匿名';

/// 未登录时个人页头部显示文本。
const String kPersonLoginEntryText = '点击登录';

/// 个人页面头像资源路径。
const String kPersonAvatarAsset = 'assets/images/person/person0.jpg';

/// 分享预览右侧展示的信息。
const String kPersonShareInfoText = '分享信息';

/// 分享预览右上角应用图标资源。
const String kShareAppIconAsset =
    'assets/images/start/icon_dormdevise_door_launcher.png';

/// 个性签名默认占位文案。
const String kDefaultSignatureText = '这个人很神秘，什么都没写。';

/// 个人身份信息模型。
class PersonIdentityProfile {
  const PersonIdentityProfile({
    required this.isLoggedIn,
    required this.account,
    required this.displayName,
    required this.avatarPath,
    required this.shareInfoText,
    required this.gender,
    required this.birthDate,
    required this.signature,
    required this.uid,
  });

  final bool isLoggedIn;
  final String account;
  final String displayName;
  final String avatarPath;
  final String shareInfoText;
  final String gender;
  final DateTime? birthDate;
  final String signature;
  final int uid;

  /// 头部入口文案：登录后显示昵称，未登录时显示“点击登录”。
  String get headerTitle => isLoggedIn ? displayName : kPersonLoginEntryText;

  /// 性别文案兜底。
  String get genderText => gender.trim().isEmpty ? '未配置' : gender.trim();

  /// 生日文案（yyyy年M月d日）。
  String get birthDateText {
    final DateTime? date = birthDate;
    if (date == null) {
      return '未配置';
    }
    return '${date.year}年${date.month}月${date.day}日';
  }

  /// 使用默认常量构建回退身份信息。
  factory PersonIdentityProfile.defaults() {
    return const PersonIdentityProfile(
      isLoggedIn: false,
      account: '',
      displayName: kPersonDisplayName,
      avatarPath: kPersonAvatarAsset,
      shareInfoText: kPersonShareInfoText,
      gender: '',
      birthDate: null,
      signature: kDefaultSignatureText,
      uid: 0,
    );
  }

  /// 创建修改副本。
  PersonIdentityProfile copyWith({
    bool? isLoggedIn,
    String? account,
    String? displayName,
    String? avatarPath,
    String? shareInfoText,
    String? gender,
    DateTime? birthDate,
    String? signature,
    int? uid,
  }) {
    return PersonIdentityProfile(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      account: account ?? this.account,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      shareInfoText: shareInfoText ?? this.shareInfoText,
      gender: gender ?? this.gender,
      birthDate: birthDate ?? this.birthDate,
      signature: signature ?? this.signature,
      uid: uid ?? this.uid,
    );
  }
}

/// 个人身份信息服务：优先读取本地配置，缺失时回退默认值。
class PersonIdentityService extends ChangeNotifier {
  PersonIdentityService._();

  static final PersonIdentityService instance = PersonIdentityService._();

  static const String _isLoggedInKey = 'person_identity_is_logged_in';
  static const String _accountKey = 'person_identity_account';
  static const String _displayNameKey = 'person_identity_display_name';
  static const String _avatarPathKey = 'person_identity_avatar_path';
  static const String _shareInfoTextKey = 'person_identity_share_info_text';
  static const String _genderKey = 'person_identity_gender';
  static const String _birthDateKey = 'person_identity_birth_date';
  static const String _signatureKey = 'person_identity_signature';
  static const String _uidKey = 'person_identity_uid';
  static const String _localCredentialStoreKey =
      'person_identity_local_credentials';
  static const String _avatarStorageFolderName = 'person_avatar';

  /// 加载当前身份信息。
  Future<PersonIdentityProfile> loadProfile() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    final String account = _resolveOrDefault(prefs.getString(_accountKey), '');
    String displayName = _resolveOrDefault(
      prefs.getString(_displayNameKey),
      kPersonDisplayName,
    );
    // 登录后若昵称仍是默认值，则自动使用账号作为昵称。
    if (isLoggedIn && account.isNotEmpty && displayName == kPersonDisplayName) {
      displayName = account;
    }

    final String storedAvatarPath = _resolveOrDefault(
      prefs.getString(_avatarPathKey),
      kPersonAvatarAsset,
    );
    final String resolvedAvatarPath = await _resolveAvatarPathForLoad(
      storedAvatarPath,
    );
    if (resolvedAvatarPath != storedAvatarPath) {
      await prefs.setString(_avatarPathKey, resolvedAvatarPath);
    }

    return PersonIdentityProfile(
      isLoggedIn: isLoggedIn,
      account: account,
      displayName: displayName,
      avatarPath: resolvedAvatarPath,
      shareInfoText: _resolveOrDefault(
        prefs.getString(_shareInfoTextKey),
        kPersonShareInfoText,
      ),
      gender: _normalizeGenderFromStorage(prefs.getString(_genderKey)),
      birthDate: _parseDate(prefs.getString(_birthDateKey)),
      signature: _normalizeSignatureFromStorage(prefs.getString(_signatureKey)),
      uid: prefs.getInt(_uidKey) ?? 0,
    );
  }

  /// 本地注册：当前仅在本地设备保存账号与密码哈希。
  ///
  /// 为了便于后续切换远程注册，本方法中将“本地注册逻辑”和“服务器注册模板”
  /// 放在同一位置并用分段注释明确区分：
  /// 1. 继续使用本地注册：保持当前代码不变。
  /// 2. 切换到服务器注册：注释掉“本地注册逻辑”，取消注释“服务器注册模板”。
  Future<void> register({
    required String account,
    required String password,
  }) async {
    final String normalizedAccount = account.trim();
    final String normalizedPassword = password.trim();
    if (normalizedAccount.isEmpty || normalizedPassword.isEmpty) {
      throw const FormatException('账号或密码不能为空');
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // ======================== 本地注册逻辑（当前启用） ========================
    final Map<String, String> localStore = _loadLocalCredentialStore(prefs);
    if (localStore.containsKey(normalizedAccount)) {
      throw const FormatException('账号已存在，请直接登录');
    }
    localStore[normalizedAccount] = _hashPasswordForLocalAuth(
      normalizedPassword,
    );
    await _saveLocalCredentialStore(prefs, localStore);

    // ====================== 服务器注册模板（默认注释） =======================
    // 切换步骤：
    // 1. 注释掉上面的“本地注册逻辑”代码块
    // 2. 取消注释下面这一行
    // 3. 在 _registerWithServer 中接入你的真实 HTTPS 接口
    // await _registerWithServer(
    //   account: normalizedAccount,
    //   password: normalizedPassword,
    // );
  }

  /// 登录：当前启用本地账号校验，并预留了远程服务器校验模板。
  ///
  /// 切换方式与 [register] 保持一致：注释本地逻辑，取消注释服务器逻辑即可。
  Future<void> login({
    required String account,
    required String password,
  }) async {
    final String normalizedAccount = account.trim();
    final String normalizedPassword = password.trim();
    if (normalizedAccount.isEmpty || normalizedPassword.isEmpty) {
      throw const FormatException('账号或密码不能为空');
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // ======================== 本地登录校验（当前启用） ========================
    final Map<String, String> localStore = _loadLocalCredentialStore(prefs);
    final String? storedPasswordHash = localStore[normalizedAccount];
    if (storedPasswordHash == null) {
      throw const FormatException('账号不存在，请先注册');
    }
    final String passwordHash = _hashPasswordForLocalAuth(normalizedPassword);
    if (storedPasswordHash != passwordHash) {
      throw const FormatException('账号密码错误');
    }

    // ====================== 服务器登录模板（默认注释） =======================
    // 切换步骤：
    // 1. 注释掉上面的“本地登录校验”代码块
    // 2. 取消注释下面这一行
    // 3. 在 _loginWithServer 中接入你的真实 HTTPS 接口
    // await _loginWithServer(
    //   account: normalizedAccount,
    //   password: normalizedPassword,
    // );

    await _persistLoginSuccess(prefs: prefs, account: normalizedAccount);
    notifyListeners();
  }

  /// 退出登录并清空用户资料配置，整体回退到默认值。
  Future<void> logout() async {
    await resetProfile();
  }

  /// 保存身份信息，便于后续由设置页写入。
  Future<void> saveProfile({
    required String displayName,
    required String avatarPath,
    required String shareInfoText,
  }) async {
    await updateProfile(
      displayName: displayName,
      avatarPath: avatarPath,
      shareInfoText: shareInfoText,
    );
  }

  /// 更新身份资料字段，更新后广播同步事件。
  Future<void> updateProfile({
    String? displayName,
    String? avatarPath,
    String? shareInfoText,
    String? gender,
    DateTime? birthDate,
    String? signature,
    bool clearBirthDate = false,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (displayName != null) {
      await prefs.setString(
        _displayNameKey,
        _resolveOrDefault(displayName, kPersonDisplayName),
      );
    }
    if (avatarPath != null) {
      final String resolvedAvatarPath = await _resolveAvatarPathForSave(
        avatarPath,
      );
      await prefs.setString(
        _avatarPathKey,
        _resolveOrDefault(resolvedAvatarPath, kPersonAvatarAsset),
      );
    }
    if (shareInfoText != null) {
      await prefs.setString(
        _shareInfoTextKey,
        _resolveOrDefault(shareInfoText, kPersonShareInfoText),
      );
    }
    if (gender != null) {
      await prefs.setString(_genderKey, _normalizeGenderForStorage(gender));
    }
    if (signature != null) {
      await prefs.setString(
        _signatureKey,
        _normalizeSignatureForStorage(signature),
      );
    }
    if (clearBirthDate) {
      await prefs.remove(_birthDateKey);
    } else if (birthDate != null) {
      await prefs.setString(_birthDateKey, birthDate.toIso8601String());
    }
    notifyListeners();
  }

  /// 清除身份信息自定义值，回退到默认常量。
  Future<void> resetProfile() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(_isLoggedInKey);
    await prefs.remove(_accountKey);
    await prefs.remove(_displayNameKey);
    await prefs.remove(_avatarPathKey);
    await prefs.remove(_shareInfoTextKey);
    await prefs.remove(_genderKey);
    await prefs.remove(_birthDateKey);
    await prefs.remove(_signatureKey);
    await prefs.remove(_uidKey);
    notifyListeners();
  }

  static String _resolveOrDefault(String? value, String fallback) {
    final String resolved = value?.trim() ?? '';
    return resolved.isEmpty ? fallback : resolved;
  }

  static DateTime? _parseDate(String? value) {
    final String raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  /// 读取旧版本存储时，统一映射为当前语义（空字符串表示未配置）。
  static String _normalizeGenderFromStorage(String? value) {
    final String normalized = value?.trim() ?? '';
    if (normalized.isEmpty || normalized == '未设置' || normalized == '未配置') {
      return '';
    }
    return normalized;
  }

  /// 写入存储时，未配置统一保存为空字符串。
  static String _normalizeGenderForStorage(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty || normalized == '未设置' || normalized == '未配置') {
      return '';
    }
    return normalized;
  }

  /// 读取签名时，空值统一回退为默认文案。
  static String _normalizeSignatureFromStorage(String? value) {
    final String normalized = value?.trim() ?? '';
    if (normalized.isEmpty) {
      return kDefaultSignatureText;
    }
    return normalized;
  }

  /// 写入签名时，空值统一回写为默认文案。
  static String _normalizeSignatureForStorage(String value) {
    final String normalized = value.trim();
    if (normalized.isEmpty) {
      return kDefaultSignatureText;
    }
    return normalized;
  }

  /// 保存头像前做本地化：本地路径复制到应用目录，URL 下载到应用目录。
  Future<String> _resolveAvatarPathForSave(String avatarPath) async {
    final String normalized = avatarPath.trim();
    if (normalized.isEmpty || normalized == kPersonAvatarAsset) {
      return kPersonAvatarAsset;
    }

    if (normalized.startsWith('assets/')) {
      return normalized;
    }

    if (_isHttpPath(normalized)) {
      return _downloadAvatarToLocalFile(normalized);
    }

    if (_isLikelyLocalFilePath(normalized)) {
      final File source = File(normalized);
      if (!await source.exists()) {
        throw const FileSystemException('头像文件不存在');
      }
      return _copyAvatarToLocalFile(source);
    }

    throw const FormatException('仅支持本地图片路径或 HTTP(S) 图片链接');
  }

  /// 读取头像时做兜底：将历史 URL 迁移到本地，失效文件回退默认头像。
  Future<String> _resolveAvatarPathForLoad(String avatarPath) async {
    final String normalized = avatarPath.trim();
    if (normalized.isEmpty || normalized == kPersonAvatarAsset) {
      return kPersonAvatarAsset;
    }

    if (_isHttpPath(normalized)) {
      try {
        return await _downloadAvatarToLocalFile(normalized);
      } catch (_) {
        return kPersonAvatarAsset;
      }
    }

    if (_isLikelyLocalFilePath(normalized)) {
      final File file = File(normalized);
      return await file.exists() ? normalized : kPersonAvatarAsset;
    }

    return normalized.startsWith('assets/') ? normalized : kPersonAvatarAsset;
  }

  /// 将本地文件复制到应用私有目录，避免外部路径失效。
  Future<String> _copyAvatarToLocalFile(File source) async {
    final Directory directory = await _ensureAvatarStorageDirectory();
    final String sourceExtension = _extractExtension(source.path);
    final String extension = sourceExtension.isEmpty ? '.jpg' : sourceExtension;
    final String fileName =
        'avatar_${DateTime.now().millisecondsSinceEpoch}$extension';
    final File target = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    await source.copy(target.path);
    return target.path;
  }

  /// 下载网络头像并保存到应用私有目录。
  Future<String> _downloadAvatarToLocalFile(String url) async {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || (!uri.isScheme('http') && !uri.isScheme('https'))) {
      throw const FormatException('头像链接无效');
    }

    final http.Response response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('头像下载失败：${response.statusCode}');
    }

    final Directory directory = await _ensureAvatarStorageDirectory();
    final String extension = _resolveDownloadExtension(
      sourcePath: uri.path,
      contentType: response.headers['content-type'],
    );
    final String fileName =
        'avatar_${DateTime.now().millisecondsSinceEpoch}$extension';
    final File target = File(
      '${directory.path}${Platform.pathSeparator}$fileName',
    );
    await target.writeAsBytes(response.bodyBytes, flush: true);
    return target.path;
  }

  /// 获取头像持久化目录，不存在则自动创建。
  Future<Directory> _ensureAvatarStorageDirectory() async {
    final Directory appDirectory = await getApplicationDocumentsDirectory();
    final Directory avatarDirectory = Directory(
      '${appDirectory.path}${Platform.pathSeparator}$_avatarStorageFolderName',
    );
    if (!await avatarDirectory.exists()) {
      await avatarDirectory.create(recursive: true);
    }
    return avatarDirectory;
  }

  /// 判断是否为网络路径。
  static bool _isHttpPath(String path) {
    return path.startsWith('http://') || path.startsWith('https://');
  }

  /// 判断是否为本地文件绝对路径（Windows/Unix）。
  static bool _isLikelyLocalFilePath(String path) {
    return path.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
  }

  /// 提取路径中的扩展名（含点号），无效时返回空字符串。
  static String _extractExtension(String sourcePath) {
    final String cleaned = sourcePath.split('?').first.split('#').first;
    final int dotIndex = cleaned.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= cleaned.length - 1) {
      return '';
    }
    final String extension = cleaned.substring(dotIndex).toLowerCase();
    if (!RegExp(r'^\.[a-z0-9]{1,5}$').hasMatch(extension)) {
      return '';
    }
    return extension;
  }

  /// 解析下载文件扩展名，优先 URL 路径，次选响应头，最终兜底 jpg。
  static String _resolveDownloadExtension({
    required String sourcePath,
    required String? contentType,
  }) {
    final String fromPath = _extractExtension(sourcePath);
    if (fromPath.isNotEmpty) {
      return fromPath;
    }

    final String mime = (contentType ?? '').toLowerCase();
    if (mime.contains('png')) {
      return '.png';
    }
    if (mime.contains('webp')) {
      return '.webp';
    }
    if (mime.contains('gif')) {
      return '.gif';
    }
    if (mime.contains('bmp')) {
      return '.bmp';
    }
    return '.jpg';
  }

  /// 统一处理登录成功后的本地状态写入，避免登录入口重复写字段。
  Future<void> _persistLoginSuccess({
    required SharedPreferences prefs,
    required String account,
  }) async {
    await prefs.setBool(_isLoggedInKey, true);
    await prefs.setString(_accountKey, account);
    // 每次登录都将昵称与账号对齐，确保切换账号后个人页文案即时同步。
    await prefs.setString(_displayNameKey, account);
  }

  /// 读取本地账号仓库（account -> passwordHash）。
  ///
  /// 本方法在数据损坏时会抛出 [FormatException]，用于显式暴露问题，
  /// 避免静默忽略导致登录行为异常且难以排查。
  Map<String, String> _loadLocalCredentialStore(SharedPreferences prefs) {
    final String raw = prefs.getString(_localCredentialStoreKey)?.trim() ?? '';
    if (raw.isEmpty) {
      return <String, String>{};
    }
    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('本地账号数据损坏，请重新注册账号');
    }

    final Map<String, String> result = <String, String>{};
    for (final MapEntry<dynamic, dynamic> entry in decoded.entries) {
      final String account = entry.key.toString().trim();
      final String passwordHash = entry.value.toString().trim();
      if (account.isEmpty || passwordHash.isEmpty) {
        continue;
      }
      result[account] = passwordHash;
    }
    return result;
  }

  /// 持久化本地账号仓库。
  Future<void> _saveLocalCredentialStore(
    SharedPreferences prefs,
    Map<String, String> store,
  ) async {
    await prefs.setString(_localCredentialStoreKey, jsonEncode(store));
  }

  /// 本地模式下的密码摘要算法（SHA-256）。
  ///
  /// 目的：避免明文密码直接落地存储；后续切换远程接口时可整体替换。
  String _hashPasswordForLocalAuth(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /*
  /// ====================== 服务器登录模板（预留） ======================
  ///
  /// 使用说明：
  /// 1. 先在 login() 中注释“本地登录校验”并取消注释 _loginWithServer 调用
  /// 2. 将示例域名和路径替换为你的服务端接口
  /// 3. 按后端协议处理状态码与错误消息
  Future<void> _loginWithServer({
    required String account,
    required String password,
  }) async {
    final Uri uri = Uri.https('api.example.com', '/v1/auth/login');
    final http.Response response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'account': account,
        'password': password,
      }),
    );
    if (response.statusCode != 200) {
      throw FormatException('登录失败：${response.statusCode}');
    }
    final dynamic payload = jsonDecode(response.body);
    if (payload is! Map || payload['success'] != true) {
      throw const FormatException('账号密码错误');
    }
  }

  /// ====================== 服务器注册模板（预留） ======================
  ///
  /// 使用说明：
  /// 1. 先在 register() 中注释“本地注册逻辑”并取消注释 _registerWithServer 调用
  /// 2. 将示例域名和路径替换为你的服务端接口
  /// 3. 按后端协议处理状态码与错误消息
  Future<void> _registerWithServer({
    required String account,
    required String password,
  }) async {
    final Uri uri = Uri.https('api.example.com', '/v1/auth/register');
    final http.Response response = await http.post(
      uri,
      headers: <String, String>{
        'Content-Type': 'application/json; charset=UTF-8',
      },
      body: jsonEncode(<String, String>{
        'account': account,
        'password': password,
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw FormatException('注册失败：${response.statusCode}');
    }
    final dynamic payload = jsonDecode(response.body);
    if (payload is! Map || payload['success'] != true) {
      throw const FormatException('注册失败，请稍后重试');
    }
  }
  */
}
