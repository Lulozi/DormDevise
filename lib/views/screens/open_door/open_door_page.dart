import 'dart:async';

import 'door_callbacks.dart';
import 'open_door_settings_page.dart';
import 'package:dormdevise/services/door_trigger_service.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 开门控制主页面，提供快速开门及进入设置的入口。
class OpenDoorPage extends StatefulWidget {
  const OpenDoorPage({super.key});

  /// 创建页面状态以处理动画与交互。
  @override
  State<OpenDoorPage> createState() => _OpenDoorPageState();
}

class _OpenDoorPageState extends State<OpenDoorPage> {
  Timer? _longPressTimer;
  double _longPressProgress = 0.0;
  bool isOpen = false;
  DateTime? lastTapTime;
  bool _opening = false;

  /// 长按开始时启动计时，结束后进入配置页面。
  void _handleLongPressStart(LongPressStartDetails details) {
    _longPressTimer?.cancel();
    _longPressProgress = 0.0;
    const int totalMs = 2000;
    int elapsed = 0;
    const int tick = 50;
    _longPressTimer = Timer.periodic(const Duration(milliseconds: tick), (
      timer,
    ) {
      elapsed += tick;
      setState(() {
        _longPressProgress = (elapsed / totalMs).clamp(0.0, 1.0);
      });
      if (elapsed >= totalMs) {
        timer.cancel();
        _longPressProgress = 0.0;
        if (!mounted) {
          return;
        }
        Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const OpenDoorSettingsPage()));
      }
    });
  }

  /// 长按结束时重置进度条状态。
  void _handleLongPressEnd(LongPressEndDetails details) {
    _longPressTimer?.cancel();
    setState(() {
      _longPressProgress = 0.0;
    });
  }

  /// 执行一次开门动作，复用统一服务并同步桌面微件状态。
  Future<void> _triggerDoorOpen() async {
    if (_opening) {
      return;
    }
    final DateTime now = DateTime.now();
    if (lastTapTime != null &&
        now.difference(lastTapTime!) < const Duration(seconds: 4)) {
      return;
    }
    lastTapTime = now;
    if (isOpen) {
      return;
    }
    setState(() {
      _opening = true;
    });
    if (DoorWidgetService.instance.settings.enableHaptics) {
      await HapticFeedback.mediumImpact();
    }
    await DoorWidgetService.instance.markManualTriggerStart();
    final DoorTriggerResult result = await DoorTriggerService.instance
        .triggerDoor();
    if (mounted) {
      if (result.success) {
        setState(() {
          isOpen = true;
        });
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) {
            return;
          }
          setState(() {
            isOpen = false;
          });
        });
      } else {
        AppToast.show(context, result.message, variant: AppToastVariant.error);
      }
    }
    await DoorWidgetService.instance.recordManualTriggerResult(result);
    if (!mounted) {
      _opening = false;
      return;
    }
    setState(() {
      _opening = false;
    });
  }

  /// 构建开门页面主体。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Card(
                elevation: 0,
                color: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 36,
                  ),
                  child: SizedBox(
                    width: 260,
                    height: 320,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _CoolDoorButton(
                              isOpen: isOpen,
                              onTrigger: _triggerDoorOpen,
                              onLongPressStart: _handleLongPressStart,
                              onLongPressEnd: _handleLongPressEnd,
                              busy: _opening,
                            ),
                            const SizedBox(height: 24),
                          ],
                        ),
                        if (_longPressProgress > 0)
                          Positioned(
                            bottom: 32,
                            left: 0,
                            right: 0,
                            child: Column(
                              children: [
                                LinearProgressIndicator(
                                  value: _longPressProgress,
                                  minHeight: 6,
                                  backgroundColor:
                                      colorScheme.surfaceContainerHighest,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '长按2秒进入配置设置',
                                  style: TextStyle(
                                    color: colorScheme.outline,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 开门按钮组件，负责展示动画与处理点击逻辑。
class _CoolDoorButton extends StatefulWidget {
  final bool isOpen;
  final DoorTriggerCallback onTrigger;
  final DoorLongPressCallback? onLongPressStart;
  final DoorLongPressEndCallback? onLongPressEnd;
  final bool busy;
  const _CoolDoorButton({
    required this.isOpen,
    required this.onTrigger,
    this.onLongPressStart,
    this.onLongPressEnd,
    required this.busy,
  });

  /// 创建按钮状态用于管理动画控制器。
  @override
  State<_CoolDoorButton> createState() => _CoolDoorButtonState();
}

class _CoolDoorButtonState extends State<_CoolDoorButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _glowAnim;
  bool _pressed = false;

  /// 初始化动画控制器及相关补间。
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _scaleAnim = Tween<double>(
      begin: 1.0,
      end: 1.15,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
    _glowAnim = Tween<double>(
      begin: 0.0,
      end: 30.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  /// 更新状态时根据开门状态触发动画。
  @override
  void didUpdateWidget(covariant _CoolDoorButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _controller.forward(from: 0);
    }
  }

  /// 释放动画控制器资源。
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 处理点击动作并委托外部回调。
  void _handleTap() {
    if (widget.busy) {
      return;
    }
    unawaited(widget.onTrigger());
  }

  /// 绘制带有多层动画效果的开门按钮。
  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: _handleTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onLongPressStart: widget.onLongPressStart,
      onLongPressEnd: widget.onLongPressEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final double scale = _pressed ? 0.93 : _scaleAnim.value;
          final double glow = _glowAnim.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: widget.isOpen ? 240 : 140,
                height: widget.isOpen ? 240 : 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.isOpen
                          ? colorScheme.primary.withAlpha((0.45 * 255).toInt())
                          : colorScheme.secondary.withAlpha(
                              (0.25 * 255).toInt(),
                            ),
                      blurRadius: glow + 30,
                      spreadRadius: glow / 2,
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: scale,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 500),
                  width: widget.isOpen ? 200 : 120,
                  height: widget.isOpen ? 200 : 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: SweepGradient(
                      colors: widget.isOpen
                          ? [
                              colorScheme.primary,
                              colorScheme.primaryContainer,
                              colorScheme.tertiary,
                              colorScheme.primary,
                            ]
                          : [
                              colorScheme.secondary,
                              colorScheme.secondaryContainer,
                              colorScheme.tertiaryContainer,
                              colorScheme.secondary,
                            ],
                      stops: const [0.0, 0.5, 0.8, 1.0],
                      startAngle: 0,
                      endAngle: 6.28,
                      transform: GradientRotation(_controller.value * 6.28),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.isOpen
                            ? colorScheme.primary.withAlpha(
                                (0.25 * 255).toInt(),
                              )
                            : colorScheme.secondary.withAlpha(
                                (0.13 * 255).toInt(),
                              ),
                        blurRadius: 30,
                        spreadRadius: 2,
                      ),
                    ],
                    border: Border.all(
                      color: widget.isOpen
                          ? colorScheme.onPrimary
                          : colorScheme.outlineVariant,
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 400),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(opacity: animation, child: child),
                          child: Icon(
                            widget.isOpen
                                ? Icons.lock_open_rounded
                                : Icons.lock_outline_rounded,
                            key: ValueKey<bool>(widget.isOpen),
                            color: colorScheme.onPrimary,
                            size: 60,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ),
              if (_pressed)
                Container(
                  width: widget.isOpen ? 220 : 120,
                  height: widget.isOpen ? 220 : 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.onPrimary.withAlpha(
                      (0.13 * 255).toInt(),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
