import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

/// 简单包装器：确保应用内的启动画面自应用启动起至少可见 1.2 秒。
/// 本组件与 `flutter_native_splash` 生成的原生启动图配合使用。
class SplashWrapper extends StatefulWidget {
  final DateTime startupBegin;
  final Widget child;

  const SplashWrapper({
    required this.startupBegin,
    required this.child,
    super.key,
  });

  @override
  State<SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<SplashWrapper> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    _ensureMinSplash();
  }

  Future<void> _ensureMinSplash() async {
    // 若 Android 已由原生 `SplashActivity` 保证最短展示时间，
    // 则跳过应用内的额外延时以避免出现双重等待；其他平台仍保留
    // 应用内延时以保证最低可见时长。
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!mounted) return;
      setState(() {
        _showSplash = false;
      });
      return;
    }

    const Duration minDuration = Duration(milliseconds: 1200);
    final Duration elapsed = DateTime.now().difference(widget.startupBegin);
    if (elapsed < minDuration) {
      await Future<void>.delayed(minDuration - elapsed);
    }
    if (!mounted) return;
    setState(() {
      _showSplash = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: Container(
              color: Colors.white,
              child: Center(
                child: Image.asset(
                  'assets/images/start/icon_dormdevise_full.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
