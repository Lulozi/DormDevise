import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/course.dart';
import '../models/course_schedule_config.dart';
import '../models/course_schedule_snapshot.dart';
import '../models/schedule_metadata.dart';
import 'notification_service.dart';

/// 课表数据变更事件。
class CourseDataChangeEvent {
  CourseDataChangeEvent({
    required this.scope,
    this.scheduleId,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now();

  /// 变更范围标识，例如 courses/config/current_schedule。
  final String scope;

  /// 受影响的课表 ID；为空表示全局变更。
  final String? scheduleId;

  /// 事件发出时间。
  final DateTime emittedAt;
}

/// 课程表数据服务，负责课程和配置的持久化。
class CourseService {
  CourseService._();

  static final CourseService instance = CourseService._();
  final StreamController<CourseDataChangeEvent> _changesController =
      StreamController<CourseDataChangeEvent>.broadcast();
  final Map<String, CourseScheduleSnapshot> _scheduleSnapshotCache =
      <String, CourseScheduleSnapshot>{};

  /// 课表数据变更流，用于跨页面刷新。
  Stream<CourseDataChangeEvent> get changes => _changesController.stream;

  static const String _coursesKey = 'course_service_courses';
  static const String _configKey = 'course_service_config';
  static const String _semesterStartKey = 'course_service_semester_start';
  static const String _maxWeekKey = 'course_service_max_week';
  static const String _tableNameKey = 'course_service_table_name';
  static const String _showWeekendKey = 'course_service_show_weekend';
  static const String _showNonCurrentWeekKey =
      'course_service_show_non_current_week';
  static const String _scheduleLockedKey = 'course_service_schedule_locked';
  static const String _reminderEnabledKey = 'course_service_reminder_enabled';
  static const String _reminderTimeKey = 'course_service_reminder_time';
  static const String _reminderMethodKey = 'course_service_reminder_method';
  static const String _reminderVibrationKey =
      'course_service_reminder_vibration';

  static const String _schedulesKey = 'course_service_schedules';
  static const String _currentScheduleIdKey =
      'course_service_current_schedule_id';

  Future<String> _resolveTargetScheduleId([
    String? scheduleId,
    SharedPreferences? prefs,
  ]) async {
    if (scheduleId != null && scheduleId.isNotEmpty) {
      return scheduleId;
    }
    final SharedPreferences resolvedPrefs =
        prefs ?? await SharedPreferences.getInstance();
    return resolvedPrefs.getString(_currentScheduleIdKey) ?? 'default';
  }

  String _buildScheduleScopedKey(String baseKey, String scheduleId) {
    if (scheduleId == 'default') {
      return baseKey;
    }
    return '${baseKey}_$scheduleId';
  }

  void _invalidateScheduleSnapshotCache([String? scheduleId]) {
    if (scheduleId == null || scheduleId.isEmpty) {
      _scheduleSnapshotCache.clear();
      return;
    }
    _scheduleSnapshotCache.remove(scheduleId);
  }

  void _updateScheduleSnapshotCache(
    String scheduleId,
    CourseScheduleSnapshot Function(CourseScheduleSnapshot current) update,
  ) {
    final CourseScheduleSnapshot? current = _scheduleSnapshotCache[scheduleId];
    if (current == null) {
      return;
    }
    _scheduleSnapshotCache[scheduleId] = update(current);
  }

  CourseScheduleConfig _cloneConfig(CourseScheduleConfig config) {
    return CourseScheduleConfig.fromJson(config.toJson());
  }

  DateTime _cloneDateTime(DateTime value) {
    return DateTime.fromMillisecondsSinceEpoch(value.millisecondsSinceEpoch);
  }

  void _emitDataChange({required String scope, String? scheduleId}) {
    if (_changesController.isClosed) {
      return;
    }
    _changesController.add(
      CourseDataChangeEvent(scope: scope, scheduleId: scheduleId),
    );
  }

  List<Course> _decodeCourses(String? raw) {
    if (raw == null || raw.isEmpty) {
      return const <Course>[];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return CourseScheduleSnapshot.cloneCourses(
        list
            .map((dynamic e) => Course.fromJson(e as Map<String, dynamic>))
            .toList(growable: false),
      );
    } catch (e) {
      debugPrint('加载课程失败: $e');
      return const <Course>[];
    }
  }

  CourseScheduleConfig _decodeConfig(String? raw) {
    if (raw == null || raw.isEmpty) {
      return CourseScheduleConfig.njuDefaults();
    }
    try {
      return CourseScheduleConfig.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (e) {
      debugPrint('加载配置失败: $e');
      return CourseScheduleConfig.njuDefaults();
    }
  }

  Future<CourseScheduleSnapshot> _readScheduleSnapshot(
    SharedPreferences prefs,
    String scheduleId,
  ) async {
    final String? tableNameValue = prefs.getString(
      _buildScheduleScopedKey(_tableNameKey, scheduleId),
    );
    String resolvedTableName = tableNameValue ?? '我的课表';
    if (tableNameValue == null) {
      final List<ScheduleMetadata> schedules = await loadSchedules();
      final ScheduleMetadata metadata = schedules.firstWhere(
        (ScheduleMetadata item) => item.id == scheduleId,
        orElse: () => ScheduleMetadata(id: 'default', name: '我的课表'),
      );
      resolvedTableName = metadata.name;
    }

    return CourseScheduleSnapshot(
      scheduleId: scheduleId,
      courses: _decodeCourses(
        prefs.getString(_buildScheduleScopedKey(_coursesKey, scheduleId)),
      ),
      config: _decodeConfig(
        prefs.getString(_buildScheduleScopedKey(_configKey, scheduleId)),
      ),
      semesterStart: (() {
        final int? millis = prefs.getInt(
          _buildScheduleScopedKey(_semesterStartKey, scheduleId),
        );
        if (millis == null) {
          return null;
        }
        return DateTime.fromMillisecondsSinceEpoch(millis);
      })(),
      maxWeek:
          prefs.getInt(_buildScheduleScopedKey(_maxWeekKey, scheduleId)) ?? 20,
      tableName: resolvedTableName,
      showWeekend:
          prefs.getBool(_buildScheduleScopedKey(_showWeekendKey, scheduleId)) ??
          false,
      showNonCurrentWeek:
          prefs.getBool(
            _buildScheduleScopedKey(_showNonCurrentWeekKey, scheduleId),
          ) ??
          true,
      isScheduleLocked:
          prefs.getBool(
            _buildScheduleScopedKey(_scheduleLockedKey, scheduleId),
          ) ??
          false,
    );
  }

  /// 加载完整课表快照，优先使用内存缓存。
  Future<CourseScheduleSnapshot> loadScheduleSnapshot({
    String? scheduleId,
    bool forceRefresh = false,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    if (!forceRefresh) {
      final CourseScheduleSnapshot? cached = _scheduleSnapshotCache[targetId];
      if (cached != null) {
        return cached.copy();
      }
    }

    final CourseScheduleSnapshot snapshot = await _readScheduleSnapshot(
      prefs,
      targetId,
    );
    _scheduleSnapshotCache[targetId] = snapshot;
    return snapshot.copy();
  }

  /// 获取当前 Schedule ID
  Future<String> getCurrentScheduleId() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentScheduleIdKey) ?? 'default';
  }

  /// 获取当前 Schedule ID 对应的 Key
  Future<String> _getKey(String baseKey, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    return _buildScheduleScopedKey(baseKey, targetId);
  }

  /// 加载所有课程表元数据
  Future<List<ScheduleMetadata>> loadSchedules() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_schedulesKey);
    if (raw == null || raw.isEmpty) {
      // 如果没有多课表数据，假设存在一个默认课表
      return [ScheduleMetadata(id: 'default', name: '我的课表')];
    }
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ScheduleMetadata.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('加载课程表列表失败: $e');
      return [ScheduleMetadata(id: 'default', name: '我的课表')];
    }
  }

  /// 保存课程表元数据列表
  Future<void> _saveSchedules(List<ScheduleMetadata> schedules) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String raw = jsonEncode(schedules.map((s) => s.toJson()).toList());
    await prefs.setString(_schedulesKey, raw);
    _emitDataChange(scope: 'schedules');
  }

  /// 创建新课程表
  Future<String> createSchedule(String name) async {
    final schedules = await loadSchedules();
    if (schedules.any((s) => s.name == name)) {
      throw Exception('课程表名称已存在');
    }
    final newId = const Uuid().v4();
    final newSchedule = ScheduleMetadata(id: newId, name: name);
    // 新建课表放到列表起始位置，保证新课表在界面上“置顶”可见
    schedules.insert(0, newSchedule);
    await _saveSchedules(schedules);
    return newId;
  }

  /// 导入一个新的课程表，并自动处理重名。
  Future<String> createImportedSchedule({
    required String desiredName,
    required List<Course> courses,
    required CourseScheduleConfig config,
    required DateTime semesterStart,
    required int maxWeek,
    required bool showWeekend,
    required bool showNonCurrentWeek,
    required bool isScheduleLocked,
  }) async {
    final String resolvedName = await _buildImportedScheduleName(desiredName);
    final String scheduleId = await createSchedule(resolvedName);
    await saveCourses(courses, scheduleId);
    await saveConfig(config, scheduleId);
    await saveSemesterStart(semesterStart, scheduleId);
    await saveMaxWeek(maxWeek, scheduleId);
    await saveTableName(resolvedName, scheduleId);
    await saveShowWeekend(showWeekend, scheduleId);
    await saveShowNonCurrentWeek(showNonCurrentWeek, scheduleId);
    await saveScheduleLocked(isScheduleLocked, scheduleId);
    await switchSchedule(scheduleId);
    return scheduleId;
  }

  /// 更新课程表顺序
  Future<void> updateScheduleOrder(List<ScheduleMetadata> schedules) async {
    await _saveSchedules(schedules);
  }

  Future<String> _buildImportedScheduleName(String desiredName) async {
    final String baseName = desiredName.trim().isEmpty
        ? '导入课表'
        : desiredName.trim();
    final List<ScheduleMetadata> schedules = await loadSchedules();
    if (!schedules.any((ScheduleMetadata item) => item.name == baseName)) {
      return baseName;
    }

    final String importedBase = '$baseName（导入）';
    if (!schedules.any((ScheduleMetadata item) => item.name == importedBase)) {
      return importedBase;
    }

    int suffix = 2;
    while (true) {
      final String candidate = '$baseName（导入$suffix）';
      if (!schedules.any((ScheduleMetadata item) => item.name == candidate)) {
        return candidate;
      }
      suffix++;
    }
  }

  /// 切换当前课程表
  Future<void> switchSchedule(String id) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentScheduleIdKey, id);
    _emitDataChange(scope: 'current_schedule', scheduleId: id);
  }

  /// 加载所有课程。
  Future<List<Course>> loadCourses([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return CourseScheduleSnapshot.cloneCourses(snapshot.courses);
  }

  /// 保存所有课程。
  Future<void> saveCourses(List<Course> courses, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_coursesKey, targetId);
    final String raw = jsonEncode(courses.map((c) => c.toJson()).toList());
    await prefs.setString(key, raw);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) => current.copyWith(
        courses: CourseScheduleSnapshot.cloneCourses(courses),
      ),
    );
    _emitDataChange(scope: 'courses', scheduleId: targetId);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程表配置。
  Future<CourseScheduleConfig> loadConfig([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return CourseScheduleConfig.fromJson(snapshot.config.toJson());
  }

  /// 保存课程表配置。
  Future<void> saveConfig(
    CourseScheduleConfig config, [
    String? scheduleId,
  ]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_configKey, targetId);
    final String raw = jsonEncode(config.toJson());
    await prefs.setString(key, raw);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) =>
          current.copyWith(config: _cloneConfig(config)),
    );
    _emitDataChange(scope: 'config', scheduleId: targetId);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载学期开始时间。
  Future<DateTime?> loadSemesterStart([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return snapshot.semesterStart == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            snapshot.semesterStart!.millisecondsSinceEpoch,
          );
  }

  /// 保存学期开始时间。
  Future<void> saveSemesterStart(DateTime date, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_semesterStartKey, targetId);
    await prefs.setInt(key, date.millisecondsSinceEpoch);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) =>
          current.copyWith(semesterStart: _cloneDateTime(date)),
    );
    _emitDataChange(scope: 'semester_start', scheduleId: targetId);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载最大周数。
  Future<int> loadMaxWeek([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return snapshot.maxWeek;
  }

  /// 保存最大周数。
  Future<void> saveMaxWeek(int maxWeek, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_maxWeekKey, targetId);
    await prefs.setInt(key, maxWeek);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) => current.copyWith(maxWeek: maxWeek),
    );
    _emitDataChange(scope: 'max_week', scheduleId: targetId);
  }

  /// 加载课程表名称。
  Future<String> loadTableName([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return snapshot.tableName;
  }

  /// 保存课程表名称。
  Future<void> saveTableName(String name, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_tableNameKey, targetId);
    await prefs.setString(key, name);

    final schedules = await loadSchedules();
    final index = schedules.indexWhere((s) => s.id == targetId);
    if (index != -1) {
      // 检查重名（排除自己）
      if (schedules.any((s) => s.name == name && s.id != targetId)) {
        throw Exception('课程表名称已存在');
      }
      schedules[index] = ScheduleMetadata(id: targetId, name: name);
      await _saveSchedules(schedules);
    }
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) => current.copyWith(tableName: name),
    );
    _emitDataChange(scope: 'table_name', scheduleId: targetId);
  }

  /// 加载是否显示周末。
  Future<bool> loadShowWeekend([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return snapshot.showWeekend;
  }

  /// 保存是否显示周末。
  Future<void> saveShowWeekend(bool show, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_showWeekendKey, targetId);
    await prefs.setBool(key, show);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) => current.copyWith(showWeekend: show),
    );
    _emitDataChange(scope: 'show_weekend', scheduleId: targetId);
  }

  /// 加载是否显示非本周课程。
  Future<bool> loadShowNonCurrentWeek([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return snapshot.showNonCurrentWeek;
  }

  /// 保存是否显示非本周课程。
  Future<void> saveShowNonCurrentWeek(bool show, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(
      _showNonCurrentWeekKey,
      targetId,
    );
    await prefs.setBool(key, show);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) =>
          current.copyWith(showNonCurrentWeek: show),
    );
    _emitDataChange(scope: 'show_non_current_week', scheduleId: targetId);
  }

  /// 加载课程表是否锁定。
  Future<bool> loadScheduleLocked([String? scheduleId]) async {
    final CourseScheduleSnapshot snapshot = await loadScheduleSnapshot(
      scheduleId: scheduleId,
    );
    return snapshot.isScheduleLocked;
  }

  /// 保存课程表是否锁定。
  Future<void> saveScheduleLocked(bool locked, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String targetId = await _resolveTargetScheduleId(scheduleId, prefs);
    final String key = _buildScheduleScopedKey(_scheduleLockedKey, targetId);
    await prefs.setBool(key, locked);
    _updateScheduleSnapshotCache(
      targetId,
      (CourseScheduleSnapshot current) =>
          current.copyWith(isScheduleLocked: locked),
    );
    _emitDataChange(scope: 'schedule_locked', scheduleId: targetId);
  }

  /// 删除课程表
  Future<void> deleteSchedules(List<String> ids) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final schedules = await loadSchedules();
    final currentId = await getCurrentScheduleId();

    // 过滤掉要删除的 ID
    schedules.removeWhere((s) => ids.contains(s.id));

    // 如果删除了当前课程表，或列表被清空，就需要重新设置当前课程表
    if (ids.contains(currentId) || schedules.isEmpty) {
      if (schedules.isNotEmpty) {
        await switchSchedule(schedules.first.id);
      } else {
        // 如果删空了，自动追加一个默认课表并切换至该课表
        final newId = const Uuid().v4();
        schedules.add(ScheduleMetadata(id: newId, name: '我的课表'));
        await switchSchedule(newId);

        // 初始化默认配置
        final now = DateTime.now();
        DateTime defaultStart;
        if (now.month >= 1 && now.month <= 7) {
          // 上半年，默认2月开学
          defaultStart = DateTime(now.year, 2, 20);
        } else {
          // 下半年，默认9月开学
          defaultStart = DateTime(now.year, 9, 1);
        }
        await saveSemesterStart(defaultStart, newId);
        await saveConfig(CourseScheduleConfig.njuDefaults(), newId);
        await saveMaxWeek(20, newId);
        await saveShowWeekend(false, newId);
        await saveShowNonCurrentWeek(true, newId);
        await saveScheduleLocked(false, newId);
      }
    }

    await _saveSchedules(schedules);

    // 清理相关数据 (可选，为了保持存储整洁)
    for (final id in ids) {
      await prefs.remove('${_coursesKey}_$id');
      await prefs.remove('${_configKey}_$id');
      await prefs.remove('${_semesterStartKey}_$id');
      await prefs.remove('${_maxWeekKey}_$id');
      await prefs.remove('${_tableNameKey}_$id');
      await prefs.remove('${_showWeekendKey}_$id');
      await prefs.remove('${_showNonCurrentWeekKey}_$id');
      await prefs.remove('${_scheduleLockedKey}_$id');
      await prefs.remove('${_reminderEnabledKey}_$id');
      await prefs.remove('${_reminderTimeKey}_$id');
      await prefs.remove('${_reminderMethodKey}_$id');
      await prefs.remove('${_reminderVibrationKey}_$id');
      _invalidateScheduleSnapshotCache(id);
    }
    _invalidateScheduleSnapshotCache();
    _emitDataChange(scope: 'delete_schedules');
  }

  /// 加载是否启用课程提醒
  Future<bool> loadReminderEnabled([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderEnabledKey, scheduleId);
    return prefs.getBool(key) ?? false;
  }

  /// 保存是否启用课程提醒
  Future<void> saveReminderEnabled(bool enabled, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderEnabledKey, scheduleId);
    await prefs.setBool(key, enabled);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程提醒时间（分钟）
  Future<int> loadReminderTime([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderTimeKey, scheduleId);
    return prefs.getInt(key) ?? 15;
  }

  /// 保存课程提醒时间
  Future<void> saveReminderTime(int minutes, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderTimeKey, scheduleId);
    await prefs.setInt(key, minutes);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程提醒方式
  Future<String> loadReminderMethod([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderMethodKey, scheduleId);
    return prefs.getString(key) ?? 'notification';
  }

  /// 保存课程提醒方式
  Future<void> saveReminderMethod(String method, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderMethodKey, scheduleId);
    await prefs.setString(key, method);
    await _rescheduleReminders(scheduleId);
  }

  /// 加载课程提醒振动开关。
  Future<bool> loadReminderVibration([String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String key = await _getKey(_reminderVibrationKey, scheduleId);
    return prefs.getBool(key) ?? true;
  }

  /// 保存课程提醒振动开关。
  Future<void> saveReminderVibration(bool enabled, [String? scheduleId]) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String key = await _getKey(_reminderVibrationKey, scheduleId);
    await prefs.setBool(key, enabled);
    await _rescheduleReminders(scheduleId);
  }

  /// 批量保存课程提醒设置
  Future<void> saveAllReminderSettings({
    required bool enabled,
    required int time,
    required String method,
    required bool vibrationEnabled,
    String? scheduleId,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final enabledKey = await _getKey(_reminderEnabledKey, scheduleId);
    final timeKey = await _getKey(_reminderTimeKey, scheduleId);
    final methodKey = await _getKey(_reminderMethodKey, scheduleId);
    final vibrationKey = await _getKey(_reminderVibrationKey, scheduleId);

    await prefs.setBool(enabledKey, enabled);
    await prefs.setInt(timeKey, time);
    await prefs.setString(methodKey, method);
    await prefs.setBool(vibrationKey, vibrationEnabled);

    await _rescheduleReminders(scheduleId);
  }

  /// 初始化/刷新提醒（通常在应用启动时调用）。
  /// 为了避免系统回收后出现“本地记录还在，但实际闹钟已丢失”的假状态，
  /// 启动时会先尝试恢复原生持久化的提醒；恢复失败时再按当前课程数据重排。
  Future<void> initializeReminders({bool force = false}) async {
    final enabled = await loadReminderEnabled();
    if (!enabled) {
      await NotificationService.instance.cancelAllReminders();
      return;
    }

    if (!force) {
      await NotificationService.instance.restoreNativeReminders();
      final nativeIds = await NotificationService.instance.getNativeAlarmIds();
      if (nativeIds.isNotEmpty) {
        debugPrint('Native reminder schedule restored from persisted entries.');
        return;
      }
    } else {
      debugPrint('Force refresh reminder schedule requested.');
    }
    await _rescheduleReminders();
  }

  /// 重新调度提醒
  Future<void> _rescheduleReminders([String? scheduleId]) async {
    final enabled = await loadReminderEnabled(scheduleId);
    if (!enabled) {
      await NotificationService.instance.cancelAllReminders();
      return;
    }

    // 确保已请求通知权限
    await NotificationService.instance.requestPermissions();

    final courses = await loadCourses(scheduleId);
    final config = await loadConfig(scheduleId);
    final semesterStart = await loadSemesterStart(scheduleId);
    final reminderTime = await loadReminderTime(scheduleId);
    final reminderMethod = await loadReminderMethod(scheduleId);
    final reminderVibration = await loadReminderVibration(scheduleId);

    // 如果未设置开学时间，使用默认策略（与 TablePage/deleteSchedules 逻辑尽量保持一致）
    final DateTime effectiveStart =
        semesterStart ??
        (() {
          final now = DateTime.now();
          if (now.month >= 1 && now.month <= 7) {
            return DateTime(now.year, 2, 20);
          } else {
            return DateTime(now.year, 9, 1);
          }
        })();

    await NotificationService.instance.scheduleReminders(
      courses: courses,
      config: config,
      semesterStart: effectiveStart,
      reminderMinutes: reminderTime,
      method: reminderMethod,
      enableVibration: reminderMethod == 'notification' && reminderVibration,
    );
  }
}
