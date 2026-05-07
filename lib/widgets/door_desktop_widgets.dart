import 'package:flutter/material.dart';

import '../models/door_widget_state.dart';

/// 状态标签颜色类型
enum StatusColor {
  green, // 成功/在线/已连接/已订阅
  gray, // 待开门/离线/未订阅
  yellow, // 设备异常
  red, // 失败/连接失败
}

/// 简洁版门锁组件 (1x1) - 只显示门锁图标和设备状态
class SimpleDoorLockWidget extends StatefulWidget {
  /// 当前门锁状态
  final DoorWidgetState state;

  /// 双击触发开门回调
  final VoidCallback? onDoubleTap;

  /// 是否正在执行开门操作
  final bool busy;

  const SimpleDoorLockWidget({
    super.key,
    required this.state,
    this.onDoubleTap,
    this.busy = false,
  });

  @override
  State<SimpleDoorLockWidget> createState() => _SimpleDoorLockWidgetState();
}

class _SimpleDoorLockWidgetState extends State<SimpleDoorLockWidget>
    with SingleTickerProviderStateMixin {
  static const Color _pendingIconColor = Color(0xFF111111);
  static const Color _pendingCircleBgColor = Color(0xFFF0F0F0);
  static const Color _pendingCircleBorderColor = Color(0xFFBDBDBD);

  late AnimationController _unlockController;
  late Animation<double> _scaleAnimation;
  bool _isUnlocking = false;

  @override
  void initState() {
    super.initState();
    _unlockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _scaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.1), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.1, end: 1.0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _unlockController, curve: Curves.easeOutBack),
        );

    _unlockController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isUnlocking = false);
      }
    });
  }

  @override
  void dispose() {
    _unlockController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SimpleDoorLockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.doorLockStatus == DoorLockStatus.success &&
        oldWidget.state.doorLockStatus != DoorLockStatus.success) {
      _playUnlockAnimation();
    }
  }

  void _playUnlockAnimation() {
    setState(() => _isUnlocking = true);
    _unlockController.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (widget.busy || widget.onDoubleTap == null) return;
    _playUnlockAnimation();
    widget.onDoubleTap!();
  }

  Color _getStatusColor(StatusColor type, ColorScheme colorScheme) {
    switch (type) {
      case StatusColor.green:
        return const Color(0xFF4CAF50);
      case StatusColor.gray:
        return const Color(0xFF9E9E9E);
      case StatusColor.yellow:
        return const Color(0xFFFFC107);
      case StatusColor.red:
        return const Color(0xFFF44336);
    }
  }

  StatusColor _getDeviceStatusColor() {
    switch (widget.state.deviceStatus) {
      case DeviceStatus.online:
        return StatusColor.green;
      case DeviceStatus.offline:
        return StatusColor.gray;
      case DeviceStatus.abnormal:
        return StatusColor.yellow;
    }
  }

  String _getDeviceStatusText() {
    switch (widget.state.deviceStatus) {
      case DeviceStatus.online:
        return '设备在线';
      case DeviceStatus.offline:
        return '设备离线';
      case DeviceStatus.abnormal:
        return '设备异常';
    }
  }

  Widget _buildStatusChip(
    String text,
    StatusColor colorType,
    ColorScheme colorScheme,
  ) {
    final color = _getStatusColor(colorType, colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha((0.15 * 255).round()),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha((0.5 * 255).round())),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        textScaler: TextScaler.noScaling,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnlocked = widget.state.doorLockStatus == DoorLockStatus.success;
    final isFailed = widget.state.doorLockStatus == DoorLockStatus.failed;

    // 根据状态确定颜色
    Color iconColor;
    Color bgColor;
    Color borderColor;

    if (isUnlocked || _isUnlocking) {
      // 成功 - 绿色
      iconColor = _getStatusColor(StatusColor.green, colorScheme);
      bgColor = iconColor.withAlpha((0.15 * 255).round());
      borderColor = iconColor;
    } else if (isFailed) {
      // 失败 - 红色
      iconColor = _getStatusColor(StatusColor.red, colorScheme);
      bgColor = iconColor.withAlpha((0.15 * 255).round());
      borderColor = iconColor;
    } else {
      // 待开门 - 默认
      iconColor = _pendingIconColor;
      bgColor = _pendingCircleBgColor;
      borderColor = _pendingCircleBorderColor;
    }

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 门锁图标 - 占50%高度
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: _unlockController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _scaleAnimation.value,
                    child: child,
                  );
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.maxHeight * 0.82;
                    return Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgColor,
                        border: Border.all(color: borderColor, width: 1.5),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              (isUnlocked || _isUnlocking)
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_outline_rounded,
                              key: ValueKey(isUnlocked || _isUnlocking),
                              color: iconColor,
                              size: size * 0.64,
                            ),
                          ),
                          if (widget.busy)
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // 设备状态 - 占50%高度
          Expanded(
            child: Center(
              child: _buildStatusChip(
                _getDeviceStatusText(),
                _getDeviceStatusColor(),
                colorScheme,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 门锁组件 - 带状态显示和双击开门功能
class DoorLockWidget extends StatefulWidget {
  /// 当前门锁状态
  final DoorWidgetState state;

  /// 双击触发开门回调
  final VoidCallback? onDoubleTap;

  /// 是否正在执行开门操作
  final bool busy;

  const DoorLockWidget({
    super.key,
    required this.state,
    this.onDoubleTap,
    this.busy = false,
  });

  @override
  State<DoorLockWidget> createState() => _DoorLockWidgetState();
}

class _DoorLockWidgetState extends State<DoorLockWidget>
    with SingleTickerProviderStateMixin {
  static const Color _pendingIconColor = Color(0xFF111111);
  static const Color _pendingCircleBgColor = Color(0xFFF0F0F0);
  static const Color _pendingCircleBorderColor = Color(0xFFBDBDBD);

  late AnimationController _unlockController;
  late Animation<double> _shakeAnimation;
  late Animation<double> _scaleAnimation;
  bool _isUnlocking = false;

  @override
  void initState() {
    super.initState();
    _unlockController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _shakeAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
          TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
          TweenSequenceItem(tween: Tween(begin: -6, end: 4), weight: 2),
          TweenSequenceItem(tween: Tween(begin: 4, end: 0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _unlockController, curve: Curves.easeInOut),
        );

    _scaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 1),
          TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
        ]).animate(
          CurvedAnimation(parent: _unlockController, curve: Curves.easeOutBack),
        );

    _unlockController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isUnlocking = false);
      }
    });
  }

  @override
  void dispose() {
    _unlockController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DoorLockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当开门成功时触发解锁动画
    if (widget.state.doorLockStatus == DoorLockStatus.success &&
        oldWidget.state.doorLockStatus != DoorLockStatus.success) {
      _playUnlockAnimation();
    }
  }

  void _playUnlockAnimation() {
    setState(() => _isUnlocking = true);
    _unlockController.forward(from: 0);
  }

  void _handleDoubleTap() {
    if (widget.busy || widget.onDoubleTap == null) return;
    _playUnlockAnimation();
    widget.onDoubleTap!();
  }

  Color _getStatusColor(StatusColor type, ColorScheme colorScheme) {
    switch (type) {
      case StatusColor.green:
        return const Color(0xFF4CAF50);
      case StatusColor.gray:
        return const Color(0xFF9E9E9E);
      case StatusColor.yellow:
        return const Color(0xFFFFC107);
      case StatusColor.red:
        return const Color(0xFFF44336);
    }
  }

  StatusColor _getDoorLockColor() {
    switch (widget.state.doorLockStatus) {
      case DoorLockStatus.pending:
        return StatusColor.gray;
      case DoorLockStatus.success:
        return StatusColor.green;
      case DoorLockStatus.failed:
        return StatusColor.red;
    }
  }

  String _getDoorLockText() {
    switch (widget.state.doorLockStatus) {
      case DoorLockStatus.pending:
        return '待开门';
      case DoorLockStatus.success:
        return '开门成功';
      case DoorLockStatus.failed:
        return '开门失败';
    }
  }

  StatusColor _getDeviceStatusColor() {
    switch (widget.state.deviceStatus) {
      case DeviceStatus.online:
        return StatusColor.green;
      case DeviceStatus.offline:
        return StatusColor.gray;
      case DeviceStatus.abnormal:
        return StatusColor.yellow;
    }
  }

  String _getDeviceStatusText() {
    switch (widget.state.deviceStatus) {
      case DeviceStatus.online:
        return '设备在线';
      case DeviceStatus.offline:
        return '设备离线';
      case DeviceStatus.abnormal:
        return '设备异常';
    }
  }

  StatusColor _getWifiStatusColor() {
    switch (widget.state.wifiStatus) {
      case WifiStatus.connected:
        return StatusColor.green;
      case WifiStatus.disconnected:
        return StatusColor.gray;
      case WifiStatus.unconfigured:
        return StatusColor.yellow;
    }
  }

  String _getWifiStatusText() {
    switch (widget.state.wifiStatus) {
      case WifiStatus.connected:
        return 'WiFi：已连接';
      case WifiStatus.disconnected:
        return 'WiFi：未连接';
      case WifiStatus.unconfigured:
        return 'WiFi：非配置';
    }
  }

  String _getMqttStatusText() {
    final isConnected =
        widget.state.mqttConnectionStatus == MqttConnectionStatus.connected;
    final isFailed =
        widget.state.mqttConnectionStatus == MqttConnectionStatus.failed;
    final isSubscribed =
        widget.state.mqttSubscriptionStatus ==
        MqttSubscriptionStatus.subscribed;

    // 显示优先级：连接失败 > 未订阅 > 已连接 > 未连接
    if (isFailed) {
      return 'MQTT：连接失败';
    }
    if (!isSubscribed) {
      return 'MQTT：未订阅';
    }
    return isConnected ? 'MQTT：已连接' : 'MQTT：未连接';
  }

  StatusColor _getMqttStatusColor() {
    final isConnected =
        widget.state.mqttConnectionStatus == MqttConnectionStatus.connected;
    final isFailed =
        widget.state.mqttConnectionStatus == MqttConnectionStatus.failed;
    final isSubscribed =
        widget.state.mqttSubscriptionStatus ==
        MqttSubscriptionStatus.subscribed;

    // 显示优先级：连接失败 > 未订阅 > 已连接 > 未连接
    if (isFailed) {
      return StatusColor.red;
    }
    if (!isSubscribed) {
      return StatusColor.yellow;
    }
    if (isConnected) {
      return StatusColor.green;
    }
    return StatusColor.gray;
  }

  Widget _buildStatusChip(
    String text,
    StatusColor colorType,
    ColorScheme colorScheme,
  ) {
    final color = _getStatusColor(colorType, colorScheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha((0.15 * 255).round()),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha((0.5 * 255).round())),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: TextScaler.noScaling,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnlocked = widget.state.doorLockStatus == DoorLockStatus.success;
    final isFailed = widget.state.doorLockStatus == DoorLockStatus.failed;

    // 根据状态确定颜色
    Color iconColor;
    Color bgColor;
    Color borderColor;

    if (isUnlocked || _isUnlocking) {
      // 成功 - 绿色
      iconColor = _getStatusColor(StatusColor.green, colorScheme);
      bgColor = iconColor.withAlpha((0.15 * 255).round());
      borderColor = iconColor;
    } else if (isFailed) {
      // 失败 - 红色
      iconColor = _getStatusColor(StatusColor.red, colorScheme);
      bgColor = iconColor.withAlpha((0.15 * 255).round());
      borderColor = iconColor;
    } else {
      // 待开门 - 默认
      iconColor = _pendingIconColor;
      bgColor = _pendingCircleBgColor;
      borderColor = _pendingCircleBorderColor;
    }

    return GestureDetector(
      onDoubleTap: _handleDoubleTap,
      child: Column(
        children: [
          // 门锁图标 - 占50%高度
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: _unlockController,
                builder: (context, child) {
                  return Transform.translate(
                    offset: Offset(_shakeAnimation.value, 0),
                    child: Transform.scale(
                      scale: _scaleAnimation.value,
                      child: child,
                    ),
                  );
                },
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.maxHeight * 0.8;
                    return Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: bgColor,
                        border: Border.all(color: borderColor, width: 2),
                        boxShadow: widget.busy
                            ? [
                                BoxShadow(
                                  color: colorScheme.primary.withAlpha(
                                    (0.3 * 255).round(),
                                  ),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            transitionBuilder: (child, animation) =>
                                ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                ),
                            child: Icon(
                              (isUnlocked || _isUnlocking)
                                  ? Icons.lock_open_rounded
                                  : Icons.lock_outline_rounded,
                              key: ValueKey(isUnlocked || _isUnlocking),
                              color: iconColor,
                              size: size * 0.68,
                            ),
                          ),
                          if (widget.busy)
                            Positioned.fill(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // 状态区域 - 占50%高度
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 第一行：门锁状态
                          _buildStatusChip(
                            _getDoorLockText(),
                            _getDoorLockColor(),
                            colorScheme,
                          ),
                          const SizedBox(height: 3),

                          // 第二行：设备状态
                          _buildStatusChip(
                            _getDeviceStatusText(),
                            _getDeviceStatusColor(),
                            colorScheme,
                          ),
                          const SizedBox(height: 3),

                          // 第三行：WiFi状态
                          _buildStatusChip(
                            _getWifiStatusText(),
                            _getWifiStatusColor(),
                            colorScheme,
                          ),
                          const SizedBox(height: 3),

                          // 第四行：MQTT状态
                          _buildStatusChip(
                            _getMqttStatusText(),
                            _getMqttStatusColor(),
                            colorScheme,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 课表组件占位 - 暂不实现功能
class ScheduleWidget extends StatelessWidget {
  const ScheduleWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 48,
            color: colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            '课表组件',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '即将推出',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
