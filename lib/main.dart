import 'dart:async';

import 'package:dormdevise/app.dart';
import 'package:dormdevise/services/alarm_service.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';

/// 应用入口，负责初始化桌面微件服务并启动 DormDevise。
Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
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
