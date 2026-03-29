import 'dart:async';

import 'package:dormdevise/app.dart';
import 'package:dormdevise/services/alarm_service.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/services/notification_service.dart';
import 'package:dormdevise/services/theme/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 应用入口，负责初始化各类服务并启动 DormDevise。
Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 记录启动时间，确保原生启动页（splash）至少停留一定时长
      final DateTime startupBegin = DateTime.now();
      await initializeDateFormatting('zh_CN', null);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      );

      // 初始化主题服务（恢复用户主色偏好）
      try {
        await ThemeService.instance.init();
      } catch (e, stack) {
        debugPrint('ThemeService initialization failed: $e\n$stack');
      }

      try {
        await DoorWidgetService.instance.initialize();
      } catch (e, stack) {
        debugPrint('DoorWidgetService initialization failed: $e\n$stack');
      }

      try {
        await AlarmService.instance.initialize();
      } catch (e, stack) {
        debugPrint('AlarmService initialization failed: $e\n$stack');
      }

      try {
        await NotificationService.instance.initialize();
        // 初始化课程提醒（应用启动时不强制重新调度闹钟，避免重复设置）
        await CourseService.instance.initializeReminders();
      } catch (e, stack) {
        debugPrint('NotificationService initialization failed: $e\n$stack');
      }

      // 若不是 Android 平台，补足到最少停留时间（2000ms），以提升视觉体验。
      // Android 已由原生 `SplashActivity` 保证最短展示时间（2s），避免重复延时。
      if (defaultTargetPlatform != TargetPlatform.android) {
        const Duration minSplashDuration = Duration(milliseconds: 2000);
        final Duration elapsed = DateTime.now().difference(startupBegin);
        if (elapsed < minSplashDuration) {
          await Future<void>.delayed(minSplashDuration - elapsed);
        }
      }

      runApp(const DormDeviseApp());
    },
    (Object error, StackTrace stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'main',
          context: ErrorDescription('未捕获的应用级异常'),
        ),
      );
    },
  );
}
