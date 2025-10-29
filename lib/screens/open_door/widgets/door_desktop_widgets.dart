import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../door_callbacks.dart';

/// 滑动开关控件，根据方向拖动至末端后触发开门。
class DoorSlideTile extends StatefulWidget {
  final DoorTriggerCallback onTrigger;
  final bool busy;
  final Axis axis;
  final Duration reboundDuration;
  final int? resetToken;

  const DoorSlideTile({
    super.key,
    required this.onTrigger,
    required this.busy,
    required this.axis,
    this.resetToken,
    this.reboundDuration = const Duration(milliseconds: 260),
  });

  /// 创建状态对象以处理拖动与回弹动画。
  @override
  State<DoorSlideTile> createState() => _DoorSlideTileState();
}

class _DoorSlideTileState extends State<DoorSlideTile>
    with SingleTickerProviderStateMixin {
  static const double _travelInsetFraction = 0.15;
  late AnimationController _progressController;
  bool _triggered = false;
  Size _lastSize = Size.zero;
  int? _lastResetToken;

  /// 初始化进度控制器用于控制滑块位置。
  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: widget.reboundDuration,
      lowerBound: 0,
      upperBound: 1,
    );
  }

  /// 释放动画控制器资源。
  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  /// 记录有效滑动区域尺寸，供拖动计算使用。
  void _updateTrackSize(Size size) {
    _lastSize = size;
  }

  /// 处理拖动起始事件，重置触发标记。
  void _handlePanStart(DragStartDetails details) {
    if (widget.busy) {
      return;
    }
    if (widget.resetToken != null && widget.resetToken != _lastResetToken) {
      _progressController.value = 0;
      _lastResetToken = widget.resetToken;
    }
    _triggered = false;
    _progressController.stop();
  }

  /// 根据拖动偏移更新进度，当到达末端时触发开门。
  void _handlePanUpdate(DragUpdateDetails details) {
    if (widget.busy) {
      return;
    }
    final double dimension = widget.axis == Axis.horizontal
        ? _lastSize.width
        : _lastSize.height;
    if (dimension <= 0) {
      return;
    }
    final double delta = widget.axis == Axis.horizontal
        ? details.delta.dx
        : -details.delta.dy;
    final double nextValue = (_progressController.value + delta / dimension)
        .clamp(0.0, 1.0);
    _progressController.value = nextValue;
    if (!_triggered && nextValue >= 1.0) {
      _triggered = true;
      unawaited(_triggerAndReset());
    }
  }

  /// 在拖动结束时回弹复位，未触发时直接返回起点。
  void _handlePanEnd(DragEndDetails details) {
    if (widget.busy) {
      return;
    }
    if (_triggered) {
      return;
    }
    unawaited(
      _progressController.animateTo(
        0,
        duration: widget.reboundDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }

  /// 调用外部开门逻辑，并在完成后自动归位。
  Future<void> _triggerAndReset() async {
    await widget.onTrigger();
    if (!mounted) {
      return;
    }
    await _progressController.animateTo(
      0,
      duration: widget.reboundDuration,
      curve: Curves.easeOutCubic,
    );
    _lastResetToken = widget.resetToken;
  }

  /// 绘制滑槽与滑块，展示当前进度位置。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (widget.resetToken != null && widget.resetToken != _lastResetToken) {
          _lastResetToken = widget.resetToken;
          _triggered = false;
          _progressController.value = 0;
        }
        return GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onPanCancel: () => _handlePanEnd(DragEndDetails()),
          child: AnimatedBuilder(
            animation: _progressController,
            builder: (context, _) {
              final double progress = _progressController.value;
              final double horizontalPadding = widget.axis == Axis.horizontal
                  ? constraints.maxWidth * _travelInsetFraction
                  : 0;
              final double verticalPadding = widget.axis == Axis.horizontal
                  ? 0
                  : constraints.maxHeight * _travelInsetFraction;
              final double trackWidth =
                  constraints.maxWidth - horizontalPadding * 2;
              final double trackHeight =
                  constraints.maxHeight - verticalPadding * 2;
              _updateTrackSize(Size(trackWidth, trackHeight));

              final Alignment alignment = widget.axis == Axis.horizontal
                  ? Alignment(-1 + progress * 2, 0)
                  : Alignment(0, 1 - progress * 2);

              final double trackThickness = widget.axis == Axis.horizontal
                  ? trackHeight
                  : trackWidth;
              final double handleThickness = math.min(trackThickness, 56.0);
              final double handleLength = widget.axis == Axis.horizontal
                  ? math.min(trackWidth * 0.65, handleThickness * 1.6)
                  : math.min(trackHeight * 0.65, handleThickness * 1.6);
              final double handleWidth = widget.axis == Axis.horizontal
                  ? handleLength
                  : handleThickness;
              final double handleHeight = widget.axis == Axis.horizontal
                  ? handleThickness
                  : handleLength;
              final double handleRadius =
                  (widget.axis == Axis.horizontal
                      ? handleHeight
                      : handleWidth) /
                  2;

              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          widget.axis == Axis.horizontal
                              ? trackHeight / 2
                              : trackWidth / 2,
                        ),
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primaryContainer.withAlpha(
                              (0.3 * 255).round(),
                            ),
                            colorScheme.surface.withAlpha((0.7 * 255).round()),
                          ],
                          begin: widget.axis == Axis.horizontal
                              ? Alignment.centerLeft
                              : Alignment.bottomCenter,
                          end: widget.axis == Axis.horizontal
                              ? Alignment.centerRight
                              : Alignment.topCenter,
                        ),
                      ),
                    ),
                    Align(
                      alignment: alignment,
                      child: Container(
                        width: handleWidth,
                        height: handleHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(handleRadius),
                          color: colorScheme.primary,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withAlpha(
                                (0.28 * 255).round(),
                              ),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          widget.axis == Axis.horizontal
                              ? Icons.arrow_forward_rounded
                              : Icons.keyboard_arrow_up_rounded,
                          color: colorScheme.onPrimary,
                          size: 28,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}
