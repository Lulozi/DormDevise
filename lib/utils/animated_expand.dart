import 'package:flutter/material.dart';

/// 通用的渐进展开收起动画容器，保持与 MQTT 配置页一致的动效。
class AnimatedExpand extends StatelessWidget {
  /// 控制是否展开子内容。
  final bool expand;

  /// 展开时显示的子组件。
  final Widget child;

  /// 动画时长，默认 300 毫秒。
  final Duration duration;

  /// 展开时使用的插值曲线，默认 [Curves.easeOut].
  final Curve curve;

  /// 收起时使用的插值曲线，默认 [Curves.easeIn].
  final Curve reverseCurve;

  const AnimatedExpand({
    super.key,
    required this.expand,
    required this.child,
    this.duration = const Duration(milliseconds: 300),
    this.curve = Curves.easeOut,
    this.reverseCurve = Curves.easeIn,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: curve,
      switchOutCurve: reverseCurve,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ClipRect(
          child: SizeTransition(
            sizeFactor: animation,
            axisAlignment: -1.0,
            child: child,
          ),
        );
      },
      child: expand
          ? child
          : const SizedBox.shrink(key: ValueKey<String>('collapsed')),
    );
  }
}
