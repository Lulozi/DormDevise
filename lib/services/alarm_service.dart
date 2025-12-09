import 'dart:io';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';

class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    if (Platform.isAndroid) {
      await AndroidAlarmManager.initialize();
    }
    _isInitialized = true;
  }

  /// 调度一个系统闹钟
  /// [id] 唯一ID
  /// [triggerTime] 闹钟响铃时间
  /// [title] 闹钟标题（课程名）
  /// [message] 闹钟备注（教室）
  Future<void> scheduleSystemAlarm({
    required int id,
    required DateTime triggerTime,
    required String title,
    required String message,
  }) async {
    if (!Platform.isAndroid) return;
    if (!_isInitialized) await initialize();

    // 计算设置闹钟的时间：提前 1 分钟
    // 如果 triggerTime 距离现在不足 1 分钟，则立即设置
    final now = DateTime.now();
    DateTime setupTime = triggerTime.subtract(const Duration(minutes: 1));

    if (setupTime.isBefore(now)) {
      setupTime = now.add(const Duration(seconds: 5));
    }

    debugPrint(
      'Scheduling system alarm setup for $title at $setupTime (Alarm time: $triggerTime)',
    );

    await AndroidAlarmManager.oneShotAt(
      setupTime,
      id,
      alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      params: {
        'hour': triggerTime.hour,
        'minute': triggerTime.minute,
        'title': title,
        'message': message,
      },
    );
  }

  /// 取消闹钟
  Future<void> cancelAlarm(int id) async {
    if (!Platform.isAndroid) return;
    await AndroidAlarmManager.cancel(id);
  }
}

/// 顶层回调函数，运行在后台 Isolate
@pragma('vm:entry-point')
void alarmCallback(int id, Map<String, dynamic> params) {
  final int hour = params['hour'] as int;
  final int minute = params['minute'] as int;
  final String title = params['title'] as String;
  final String message = params['message'] as String;

  debugPrint(
    'AlarmService callback triggered: Setting alarm for $hour:$minute - $title',
  );

  final intent = AndroidIntent(
    action: 'android.intent.action.SET_ALARM',
    arguments: <String, dynamic>{
      'android.intent.extra.alarm.MESSAGE': '$title - $message',
      'android.intent.extra.alarm.HOUR': hour,
      'android.intent.extra.alarm.MINUTES': minute,
      'android.intent.extra.alarm.SKIP_UI': true,
    },
    flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
  );

  try {
    intent.launch();
  } catch (e) {
    debugPrint('Failed to launch alarm intent: $e');
  }
}
