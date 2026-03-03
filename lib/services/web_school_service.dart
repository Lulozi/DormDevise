import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/web_school.dart';

/// 网页导入课表学校数据服务，负责学校列表与登录凭据的持久化。
///
/// 学校列表存储在 [SharedPreferences] 中，账号密码等敏感信息
/// 通过 [FlutterSecureStorage] 加密存储。
class WebSchoolService {
  WebSchoolService._();

  static final WebSchoolService instance = WebSchoolService._();

  static const String _schoolsKey = 'web_school_service_schools';

  /// 加密存储实例，用于安全保存账号密码。
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  /// 预设学校列表，用户可从中快速选择。
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
      // 同时清除该学校的登录凭据
      await deleteCredentials(school.name);
    }
  }

  /// 批量删除学校。
  Future<void> deleteSchools(List<int> indices) async {
    final schools = await loadSchools();
    // 按降序排列索引以避免删除时索引偏移
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
  Future<void> saveCredentials({
    required String schoolName,
    required String username,
    required String password,
  }) async {
    final key = _credentialKey(schoolName);
    final data = jsonEncode({'username': username, 'password': password});
    await _secureStorage.write(key: key, value: data);
  }

  /// 读取学校登录凭据。
  Future<({String username, String password})?> loadCredentials(
    String schoolName,
  ) async {
    final key = _credentialKey(schoolName);
    final raw = await _secureStorage.read(key: key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> data = jsonDecode(raw) as Map<String, dynamic>;
      return (
        username: data['username'] as String? ?? '',
        password: data['password'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('读取登录凭据失败: $e');
      return null;
    }
  }

  /// 删除学校登录凭据。
  Future<void> deleteCredentials(String schoolName) async {
    final key = _credentialKey(schoolName);
    await _secureStorage.delete(key: key);
  }

  /// 生成凭据存储 key，基于学校名称。
  String _credentialKey(String schoolName) =>
      'web_school_credential_$schoolName';
}
