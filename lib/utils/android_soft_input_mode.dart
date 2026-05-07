import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum AndroidSoftInputMode {
  adjustResize('adjustResize'),
  adjustPan('adjustPan'),
  adjustNothing('adjustNothing');

  const AndroidSoftInputMode(this.nativeValue);

  final String nativeValue;
}

class AndroidSoftInputModeController {
  AndroidSoftInputModeController._();

  static const MethodChannel _channel = MethodChannel('dormdevise/window');

  static Future<void> setMode(AndroidSoftInputMode mode) async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setSoftInputMode', <String, String>{
        'mode': mode.nativeValue,
      });
    } on PlatformException {
      // 忽略设置失败，避免影响页面主流程。
    }
  }

  static void setModeSilently(AndroidSoftInputMode mode) {
    unawaited(setMode(mode));
  }
}
