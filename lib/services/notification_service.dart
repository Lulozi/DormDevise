import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import '../models/course.dart';
import '../models/course_schedule_config.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static final Int64List _messageVibrationPattern = Int64List.fromList(<int>[
    0,
    120,
    80,
    180,
  ]);

  String _buildReminderTitle(String courseName) => '课程：$courseName';

  String _buildReminderBody({
    required int reminderMinutes,
    required String location,
  }) {
    final String timingText = reminderMinutes == 0
        ? '现在将开始上课'
        : '距离上课还有 $reminderMinutes 分钟';
    return '$timingText\n地点：$location';
  }

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Android 原生提醒通道：使用系统 AlarmManager 调度，降低进程被回收后的丢提醒风险。
  static const MethodChannel _alarmChannel = MethodChannel(
    'dormdevise/alarm_notifications',
  );

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      tz.initializeTimeZones();
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      final String rawName = timezoneInfo.identifier;
      // 部分设备/模拟器返回非标准时区名称（如 TimezoneInfo(...)），需要健壮处理
      try {
        tz.setLocalLocation(tz.getLocation(rawName));
      } catch (_) {
        // 尝试从非标准字符串中提取 IANA 时区名称
        final match = RegExp(r'[A-Za-z]+/[A-Za-z_]+').firstMatch(rawName);
        if (match != null) {
          try {
            tz.setLocalLocation(tz.getLocation(match.group(0)!));
          } catch (_) {
            tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
          }
        } else {
          // 无法解析时使用中文环境默认时区
          tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
        }
      }
    } catch (e) {
      debugPrint('时区初始化异常，回退到 Asia/Shanghai: $e');
      try {
        tz.initializeTimeZones();
        tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      } catch (_) {
        try {
          tz.setLocalLocation(tz.getLocation('UTC'));
        } catch (_) {}
      }
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _notificationsPlugin.initialize(initializationSettings);
    await _ensureAndroidChannels();
    _isInitialized = true;
  }

  Future<void> requestPermissions() async {
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestExactAlarmsPermission();
  }

  Future<void> cancelAllReminders() async {
    await _notificationsPlugin.cancelAll();
    await _cancelNativeAlarms();
  }

  /// 重新调度所有课程提醒
  /// [courses] 所有课程列表
  /// [config] 课程表时间配置
  /// [semesterStart] 学期开始日期
  /// [reminderMinutes] 提前多少分钟提醒
  /// [method] 提醒方式 (目前仅支持 'notification')
  Future<void> scheduleReminders({
    required List<Course> courses,
    required CourseScheduleConfig config,
    required DateTime semesterStart,
    required int reminderMinutes,
    required String method,
    required bool enableVibration,
  }) async {
    if (!_isInitialized) await initialize();
    await cancelAllReminders();
    // 同时取消所有系统闹钟（简单起见，这里假设 ID 范围重叠，实际可能需要更复杂的 ID 管理）
    // 由于 AlarmService 没有 cancelAll，我们只能依赖 ID 覆盖或手动管理
    // 但为了防止旧闹钟残留，最好能取消。
    // 暂时我们只负责调度新的。

    if (reminderMinutes < 0) return;

    // 获取当前时间
    final now = DateTime.now();
    // 提前调度更长时间，减少后台停留后提醒失效的概率。
    final endSchedule = now.add(Duration(days: method == 'alarm' ? 7 : 30));

    // 生成所有节次的时间表
    final sections = config.generateSections();
    final sectionMap = {for (var s in sections) s.index: s.start};

    int notificationId = 0;
    int scheduledCount = 0;

    debugPrint(
      'Scheduling reminders: ${courses.length} courses, method: $method, minutes: $reminderMinutes',
    );

    for (final course in courses) {
      for (final session in course.sessions) {
        // 计算该 session 在未来一周内的所有上课时间点
        final classTimes = _calculateClassTimes(
          session,
          sectionMap,
          semesterStart,
          now,
          endSchedule,
        );

        for (final classTime in classTimes) {
          final reminderTime = classTime.subtract(
            Duration(minutes: reminderMinutes),
          );
          final String title = _buildReminderTitle(course.name);
          final String body = _buildReminderBody(
            reminderMinutes: reminderMinutes,
            location: session.location,
          );
          final bool isAlarm = method == 'alarm';

          // 如果提醒时间在当前时间之后，则进行调度
          // 或者如果是“立即”提醒且时间就在刚刚（2分钟内），则立即发送
          if (reminderTime.isAfter(now)) {
            if (isAlarm && !classTime.isAfter(now)) {
              continue;
            }

            if (Platform.isAndroid) {
              await _scheduleAndroidReminder(
                id: notificationId++,
                title: title,
                body: body,
                scheduledDate: reminderTime,
                isAlarm: isAlarm,
                enableVibration: enableVibration,
              );
            } else {
              await _scheduleNotification(
                id: notificationId++,
                title: title,
                body: body,
                scheduledDate: reminderTime,
                method: method,
                enableVibration: enableVibration,
              );
            }
            scheduledCount++;
          } else if (reminderMinutes == 0 &&
              reminderTime.isAfter(now.subtract(const Duration(minutes: 2)))) {
            debugPrint('Showing immediate notification for ${course.name}');

            if (isAlarm &&
                (classTime.day != now.day || !classTime.isAfter(now))) {
              continue;
            }

            if (Platform.isAndroid) {
              await _showAndroidReminder(
                id: notificationId++,
                title: title,
                body: _buildReminderBody(
                  reminderMinutes: 0,
                  location: session.location,
                ),
                isAlarm: isAlarm,
                enableVibration: enableVibration,
              );
            } else {
              await _showNotification(
                id: notificationId++,
                title: title,
                body: _buildReminderBody(
                  reminderMinutes: 0,
                  location: session.location,
                ),
                method: method,
                enableVibration: enableVibration,
              );
            }
            scheduledCount++;
          }
        }
      }
    }

    debugPrint('Scheduled $scheduledCount reminders.');
  }

  Future<void> _ensureAndroidChannels() async {
    if (!Platform.isAndroid) {
      return;
    }
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        _notificationsPlugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (androidImplementation == null) {
      return;
    }

    await androidImplementation.createNotificationChannel(
      AndroidNotificationChannel(
        'course_notification_channel_v7',
        '课程消息提醒',
        description: '用于发送类似消息横幅的上课提醒',
        importance: Importance.max,
        enableVibration: true,
        vibrationPattern: _messageVibrationPattern,
        enableLights: true,
        playSound: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
    await androidImplementation.createNotificationChannel(
      const AndroidNotificationChannel(
        'course_notification_channel_v7_silent',
        '课程消息提醒（无振动）',
        description: '用于发送无振动的消息横幅提醒',
        importance: Importance.max,
        enableVibration: false,
        enableLights: true,
        playSound: false,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
    );
  }

  Future<void> _showNotification({
    required int id,
    required String title,
    required String body,
    required String method,
    required bool enableVibration,
  }) async {
    final isAlarm = method == 'alarm';
    final String channelId = _resolveChannelId(
      isAlarm: isAlarm,
      enableVibration: enableVibration,
    );
    final String channelName = _resolveChannelName(
      isAlarm: isAlarm,
      enableVibration: enableVibration,
    );
    final String channelDescription = _resolveChannelDescription(
      isAlarm: isAlarm,
      enableVibration: enableVibration,
    );
    await _notificationsPlugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.max,
          priority: Priority.max,
          ticker: '课程提醒',
          visibility: NotificationVisibility.public,
          category: isAlarm
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.message,
          audioAttributesUsage: isAlarm
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          styleInformation: BigTextStyleInformation(body),
          enableVibration: isAlarm ? true : enableVibration,
          vibrationPattern: isAlarm || !enableVibration
              ? null
              : _messageVibrationPattern,
          // 闹钟模式下启用全屏通知（如果权限允许）
          fullScreenIntent: isAlarm,
          // 使用 additionalFlags 开启 FLAG_INSISTENT (4)，使声音循环播放直到用户处理
          additionalFlags: isAlarm ? Int32List.fromList(<int>[4]) : null,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'dismiss_$id',
              '关闭',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: true,
          presentBanner: true,
          presentList: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  Future<void> _scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required String method,
    required bool enableVibration,
  }) async {
    final isAlarm = method == 'alarm';
    final String channelId = _resolveChannelId(
      isAlarm: isAlarm,
      enableVibration: enableVibration,
    );
    final String channelName = _resolveChannelName(
      isAlarm: isAlarm,
      enableVibration: enableVibration,
    );
    final String channelDescription = _resolveChannelDescription(
      isAlarm: isAlarm,
      enableVibration: enableVibration,
    );

    // 检查是否具有精确闹钟权限 (Android 12+)
    // 如果没有权限，zonedSchedule 可能会失败或不准确
    // 只有当时间确实已经过去时，才直接显示，否则即使只有 1 秒也进行调度，确保整点触发
    if (scheduledDate.isBefore(DateTime.now())) {
      await _showNotification(
        id: id,
        title: title,
        body: body,
        method: method,
        enableVibration: enableVibration,
      );
      return;
    }

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelDescription,
          importance: Importance.max,
          priority: Priority.max,
          ticker: '课程提醒',
          visibility: NotificationVisibility.public,
          category: isAlarm
              ? AndroidNotificationCategory.alarm
              : AndroidNotificationCategory.message,
          audioAttributesUsage: isAlarm
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notification,
          styleInformation: BigTextStyleInformation(body),
          enableVibration: isAlarm ? true : enableVibration,
          vibrationPattern: isAlarm || !enableVibration
              ? null
              : _messageVibrationPattern,
          fullScreenIntent: isAlarm,
          // 使用 additionalFlags 开启 FLAG_INSISTENT (4)，使声音循环播放直到用户处理
          additionalFlags: isAlarm ? Int32List.fromList(<int>[4]) : null,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'dismiss_$id',
              '关闭',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          presentSound: true,
          presentBanner: true,
          presentList: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      androidScheduleMode: isAlarm
          ? AndroidScheduleMode.alarmClock
          : AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  String _resolveChannelId({
    required bool isAlarm,
    required bool enableVibration,
  }) {
    if (isAlarm) {
      return 'course_alarm_channel_v4';
    }
    return enableVibration
        ? 'course_notification_channel_v7'
        : 'course_notification_channel_v7_silent';
  }

  String _resolveChannelName({
    required bool isAlarm,
    required bool enableVibration,
  }) {
    if (isAlarm) {
      return '课程闹钟';
    }
    return enableVibration ? '课程消息提醒' : '课程消息提醒（无振动）';
  }

  String _resolveChannelDescription({
    required bool isAlarm,
    required bool enableVibration,
  }) {
    if (isAlarm) {
      return '用于发送上课前的强提醒';
    }
    return enableVibration ? '用于发送类似消息横幅的上课提醒' : '用于发送无振动的消息横幅提醒';
  }

  Future<void> _scheduleAndroidReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    required bool isAlarm,
    required bool enableVibration,
  }) async {
    if (!Platform.isAndroid) {
      await _scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        method: isAlarm ? 'alarm' : 'notification',
        enableVibration: enableVibration,
      );
      return;
    }

    try {
      await _alarmChannel.invokeMethod('schedule', <String, dynamic>{
        'id': id,
        'triggerAtMillis': scheduledDate.millisecondsSinceEpoch,
        'title': title,
        'body': body,
        'isAlarm': isAlarm,
        'enableVibration': enableVibration,
      });
    } catch (e) {
      debugPrint('Android reminder schedule failed, fallback to plugin: $e');
      await _scheduleNotification(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        method: isAlarm ? 'alarm' : 'notification',
        enableVibration: enableVibration,
      );
    }
  }

  Future<void> _showAndroidReminder({
    required int id,
    required String title,
    required String body,
    required bool isAlarm,
    required bool enableVibration,
  }) async {
    if (!Platform.isAndroid) {
      await _showNotification(
        id: id,
        title: title,
        body: body,
        method: isAlarm ? 'alarm' : 'notification',
        enableVibration: enableVibration,
      );
      return;
    }

    try {
      await _alarmChannel.invokeMethod('showNow', <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'isAlarm': isAlarm,
        'enableVibration': enableVibration,
      });
    } catch (e) {
      debugPrint('Android reminder show failed, fallback to plugin: $e');
      await _showNotification(
        id: id,
        title: title,
        body: body,
        method: isAlarm ? 'alarm' : 'notification',
        enableVibration: enableVibration,
      );
    }
  }

  /// 清理所有原生闹钟，避免旧 PendingIntent 残留。
  Future<void> _cancelNativeAlarms() async {
    if (!Platform.isAndroid) return;
    try {
      await _alarmChannel.invokeMethod('cancelAll');
    } catch (e) {
      debugPrint('Native alarm cancel failed: $e');
    }
  }

  /// 获取原生已注册闹钟的 ID 列表
  Future<Set<int>> getNativeAlarmIds() async {
    if (!Platform.isAndroid) return <int>{};
    try {
      final List<dynamic>? result = await _alarmChannel.invokeMethod('list');
      if (result == null) return <int>{};
      return result.map((e) => e as int).toSet();
    } catch (e) {
      debugPrint('Failed to get native alarm IDs: $e');
      return <int>{};
    }
  }

  /// 计算某个 Session 在指定时间范围内的所有上课时间
  List<DateTime> _calculateClassTimes(
    CourseSession session,
    Map<int, TimeOfDay> sectionMap,
    DateTime semesterStart,
    DateTime startRange,
    DateTime endRange,
  ) {
    final List<DateTime> times = [];

    // 规范化 semesterStart 到周一 00:00:00
    // 保持与 TablePage 逻辑一致：将 semesterStart 视为第一周，并回退到该周周一
    final startOfDay = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    );
    final baseDate = startOfDay.subtract(
      Duration(days: startOfDay.weekday - 1),
    );

    // 遍历每一天
    for (
      var d = startRange;
      !d.isAfter(endRange);
      d = d.add(const Duration(days: 1))
    ) {
      // 检查星期几
      if (d.weekday != session.weekday) continue;

      // 计算周次
      final diffDays = d.difference(baseDate).inDays;
      if (diffDays < 0) continue; // 在学期开始前
      final currentWeek = (diffDays / 7).floor() + 1;

      // debugPrint('Checking ${course.name}: Date=$d, Week=$currentWeek, SessionWeeks=${session.startWeek}-${session.endWeek}');

      // 检查周次是否符合 session 要求
      if (currentWeek < session.startWeek || currentWeek > session.endWeek) {
        continue;
      }

      bool isWeekValid = false;
      if (session.customWeeks.isNotEmpty) {
        if (session.customWeeks.contains(currentWeek)) isWeekValid = true;
      } else {
        switch (session.weekType) {
          case CourseWeekType.all:
            isWeekValid = true;
            break;
          case CourseWeekType.single:
            isWeekValid = currentWeek % 2 != 0;
            break;
          case CourseWeekType.double:
            isWeekValid = currentWeek % 2 == 0;
            break;
        }
      }

      if (!isWeekValid) continue;

      // 获取上课时间
      final timeOfDay = sectionMap[session.startSection];
      if (timeOfDay == null) continue;

      final classDateTime = DateTime(
        d.year,
        d.month,
        d.day,
        timeOfDay.hour,
        timeOfDay.minute,
      );
      times.add(classDateTime);
    }

    return times;
  }
}
