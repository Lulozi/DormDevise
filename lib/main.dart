import 'dart:async';

import 'package:dormdevise/app.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用入口，负责初始化桌面微件服务并启动 DormDevise。
Future<void> main() async {
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
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
      await DoorWidgetService.instance.initialize();
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
