import 'dart:async';

import 'package:flutter/gestures.dart';

/// 开门触发回调函数类型，供各类开门控件复用。
typedef DoorTriggerCallback = Future<void> Function();

/// 长按开始事件回调类型，封装长按起始细节。
typedef DoorLongPressCallback = void Function(LongPressStartDetails details);

/// 长按结束事件回调类型，封装长按结束细节。
typedef DoorLongPressEndCallback = void Function(LongPressEndDetails details);
