import 'package:flutter/widgets.dart';

/// 全局路由观察器，用于监听页面被其他路由覆盖或恢复。
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
