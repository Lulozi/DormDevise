import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../door_callbacks.dart';

/// 桌面组件预览面板，展示多种交互方式的开门控件。
class DoorDesktopWidgetPanel extends StatelessWidget {
  final DoorTriggerCallback onTrigger;
  final bool busy;

  const DoorDesktopWidgetPanel({
    super.key,
    required this.onTrigger,
    required this.busy,
  });

  /// 构建组件预览列表，按照尺寸展示不同交互形态。
  @override
  Widget build(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('桌面组件预览', style: textTheme.titleMedium),
        const SizedBox(height: 12),
        Expanded(
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _WidgetTileFrame(
                  width: 96,
                  height: 96,
                  label: '1×1 长按开关',
                  child: DoorHoldTile(onTrigger: onTrigger, busy: busy),
                ),
                _WidgetTileFrame(
                  width: 96,
                  height: 212,
                  label: '1×2 滑动开关',
                  child: DoorSlideTile(
                    onTrigger: onTrigger,
                    busy: busy,
                    axis: Axis.vertical,
                  ),
                ),
                _WidgetTileFrame(
                  width: 212,
                  height: 96,
                  label: '2×1 滑动开关',
                  child: DoorSlideTile(
                    onTrigger: onTrigger,
                    busy: busy,
                    axis: Axis.horizontal,
                  ),
                ),
                _WidgetTileFrame(
                  width: 212,
                  height: 212,
                  label: '2×2 旋钮开关',
                  child: DoorKnobTile(onTrigger: onTrigger, busy: busy),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 搭建圆角卡片框架，用于承载具体交互控件。
class _WidgetTileFrame extends StatelessWidget {
  final double width;
  final double height;
  final String label;
  final Widget child;

  const _WidgetTileFrame({
    required this.width,
    required this.height,
    required this.label,
    required this.child,
  });

  /// 绘制带阴影的容器，并在底部添加标签文字。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: colorScheme.shadow.withAlpha((0.18 * 255).round()),
                blurRadius: 18,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// 1×1 长按开关控件，实现按住一段时间后触发。
class DoorHoldTile extends StatefulWidget {
  final DoorTriggerCallback onTrigger;
  final bool busy;
  final Duration holdDuration;

  const DoorHoldTile({
    super.key,
    required this.onTrigger,
    required this.busy,
    this.holdDuration = const Duration(milliseconds: 900),
  });

  /// 创建状态对象以管理按压进度动画。
  @override
  State<DoorHoldTile> createState() => _DoorHoldTileState();
}

class _DoorHoldTileState extends State<DoorHoldTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _completed = false;

  /// 初始化动画控制器并监听完成状态。
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.holdDuration,
    )..addStatusListener(_handleStatusChange);
  }

  /// 释放动画控制器资源。
  @override
  void dispose() {
    _controller.removeStatusListener(_handleStatusChange);
    _controller.dispose();
    super.dispose();
  }

  /// 监听动画完成，触发开门逻辑并复位进度。
  void _handleStatusChange(AnimationStatus status) {
    if (status == AnimationStatus.completed && !_completed) {
      _completed = true;
      unawaited(_triggerAndReset());
    }
  }

  /// 处理长按开始事件，启动进度动画。
  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.busy) {
      return;
    }
    _completed = false;
    _controller.forward(from: 0);
  }

  /// 处理长按结束事件，未完成时立即回弹。
  void _handleLongPressEnd(LongPressEndDetails details) {
    if (_completed) {
      return;
    }
    _controller.reverse(from: _controller.value);
  }

  /// 调用开门回调并在结束后复位动画。
  Future<void> _triggerAndReset() async {
    if (widget.busy) {
      return;
    }
    await widget.onTrigger();
    if (!mounted) {
      return;
    }
    await _controller.reverse();
  }

  /// 绘制圆形进度按钮，并展示实时百分比。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onLongPressStart: _handleLongPressStart,
      onLongPressEnd: _handleLongPressEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final double value = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.primary.withAlpha((0.22 * 255).round()),
                      colorScheme.primaryContainer.withAlpha(
                        (0.65 * 255).round(),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 8,
                  backgroundColor: colorScheme.surfaceContainerHighest
                      .withAlpha((0.4 * 255).round()),
                  color: colorScheme.primary,
                ),
              ),
              Text(
                '${(value * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 1×2 或 2×1 滑动开关控件，根据方向触发开门。
class DoorSlideTile extends StatefulWidget {
  final DoorTriggerCallback onTrigger;
  final bool busy;
  final Axis axis;
  final Duration reboundDuration;

  const DoorSlideTile({
    super.key,
    required this.onTrigger,
    required this.busy,
    required this.axis,
    this.reboundDuration = const Duration(milliseconds: 260),
  });

  /// 创建状态对象以处理拖动与回弹动画。
  @override
  State<DoorSlideTile> createState() => _DoorSlideTileState();
}

class _DoorSlideTileState extends State<DoorSlideTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  bool _triggered = false;
  Size _lastSize = Size.zero;

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

  /// 记录布局尺寸，供拖动计算使用。
  void _onConstraintsChanged(BoxConstraints constraints) {
    _lastSize = Size(constraints.maxWidth, constraints.maxHeight);
  }

  /// 处理拖动起始事件，重置触发标记。
  void _handlePanStart(DragStartDetails details) {
    if (widget.busy) {
      return;
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
  }

  /// 绘制滑槽与滑块，展示当前进度位置。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        _onConstraintsChanged(constraints);
        return GestureDetector(
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onPanCancel: () => _handlePanEnd(DragEndDetails()),
          child: AnimatedBuilder(
            animation: _progressController,
            builder: (context, _) {
              final double progress = _progressController.value;
              final double sliderSize = 52;
              final Alignment alignment = widget.axis == Axis.horizontal
                  ? Alignment(-1 + progress * 2, 0)
                  : Alignment(0, 1 - progress * 2);
              return Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primaryContainer.withAlpha(
                            (0.25 * 255).round(),
                          ),
                          colorScheme.surface.withAlpha((0.6 * 255).round()),
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
                      width: widget.axis == Axis.horizontal
                          ? sliderSize
                          : math.min(sliderSize, constraints.maxWidth),
                      height: widget.axis == Axis.horizontal
                          ? math.min(sliderSize, constraints.maxHeight)
                          : sliderSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        color: colorScheme.primary,
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.primary.withAlpha(
                              (0.3 * 255).round(),
                            ),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
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
              );
            },
          ),
        );
      },
    );
  }
}

/// 2×2 旋钮控件，转动半圈后触发开门并自动回位。
class DoorKnobTile extends StatefulWidget {
  final DoorTriggerCallback onTrigger;
  final bool busy;
  final Duration reboundDuration;

  const DoorKnobTile({
    super.key,
    required this.onTrigger,
    required this.busy,
    this.reboundDuration = const Duration(milliseconds: 320),
  });

  /// 创建状态对象以处理旋钮角度与动画。
  @override
  State<DoorKnobTile> createState() => _DoorKnobTileState();
}

class _DoorKnobTileState extends State<DoorKnobTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  double? _lastAngle;
  double _accumulated = 0;
  bool _triggered = false;

  /// 初始化进度控制器以映射旋转到进度。
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

  /// 计算当前触点相对于中心的夹角。
  double _computeAngle(Offset localPosition) {
    final RenderBox box = context.findRenderObject() as RenderBox;
    final Offset center = box.size.center(Offset.zero);
    final Offset vector = localPosition - center;
    return math.atan2(vector.dy, vector.dx);
  }

  /// 归一化角度差，保持在 -π 到 π 之间。
  double _normalizeAngle(double angle) {
    double value = angle;
    while (value > math.pi) {
      value -= 2 * math.pi;
    }
    while (value < -math.pi) {
      value += 2 * math.pi;
    }
    return value;
  }

  /// 拖动开始时重置累积角度并记录起始角度。
  void _handlePanStart(DragStartDetails details) {
    if (widget.busy) {
      return;
    }
    _progressController.stop();
    _lastAngle = _computeAngle(details.localPosition);
    _accumulated = 0;
    _triggered = false;
  }

  /// 拖动更新时叠加角度，并在半圈后触发。
  void _handlePanUpdate(DragUpdateDetails details) {
    if (widget.busy) {
      return;
    }
    final double current = _computeAngle(details.localPosition);
    final double previous = _lastAngle ?? current;
    final double delta = _normalizeAngle(current - previous);
    _accumulated += delta;
    _lastAngle = current;
    final double progress = (_accumulated.abs() / math.pi).clamp(0.0, 1.0);
    _progressController.value = progress;
    if (!_triggered && progress >= 1.0) {
      _triggered = true;
      unawaited(_triggerAndReset());
    }
  }

  /// 拖动结束时处理回弹逻辑，未触发则回到原点。
  void _handlePanEnd(DragEndDetails details) {
    _lastAngle = null;
    if (_triggered || widget.busy) {
      return;
    }
    unawaited(
      _progressController.animateTo(
        0,
        duration: widget.reboundDuration,
        curve: Curves.easeOutBack,
      ),
    );
  }

  /// 调用开门回调并在完成后复位进度。
  Future<void> _triggerAndReset() async {
    await widget.onTrigger();
    if (!mounted) {
      return;
    }
    await _progressController.animateTo(
      0,
      duration: widget.reboundDuration,
      curve: Curves.easeOutBack,
    );
  }

  /// 绘制旋钮与刻度，展示旋转进度指示。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onPanStart: _handlePanStart,
      onPanUpdate: _handlePanUpdate,
      onPanEnd: _handlePanEnd,
      onPanCancel: () => _handlePanEnd(DragEndDetails()),
      child: AnimatedBuilder(
        animation: _progressController,
        builder: (context, _) {
          final double sweep = _progressController.value * math.pi;
          return CustomPaint(
            painter: _KnobPainter(
              progress: _progressController.value,
              colorScheme: colorScheme,
              sweep: sweep,
            ),
          );
        },
      ),
    );
  }
}

/// 自定义画笔绘制旋钮外观与进度弧线。
class _KnobPainter extends CustomPainter {
  final double progress;
  final ColorScheme colorScheme;
  final double sweep;

  const _KnobPainter({
    required this.progress,
    required this.colorScheme,
    required this.sweep,
  });

  /// 绘制旋钮外环、刻度与进度指示。
  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = math.min(size.width, size.height) / 2 - 10;
    final Paint basePaint = Paint()
      ..color = colorScheme.surfaceContainerHighest
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, basePaint);

    final Paint borderPaint = Paint()
      ..color = colorScheme.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, radius, borderPaint);

    final Paint progressPaint = Paint()
      ..color = colorScheme.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final Rect arcRect = Rect.fromCircle(center: center, radius: radius - 6);
    canvas.drawArc(arcRect, -math.pi / 2, sweep, false, progressPaint);

    final Paint indicatorPaint = Paint()
      ..color = colorScheme.primary
      ..style = PaintingStyle.fill;
    final double angle = -math.pi / 2 + sweep;
    final Offset indicator = Offset(
      center.dx + (radius - 6) * math.cos(angle),
      center.dy + (radius - 6) * math.sin(angle),
    );
    canvas.drawCircle(indicator, 10, indicatorPaint);

    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  /// 指示自定义画布无需重绘外部状态。
  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.sweep != sweep;
  }
}
