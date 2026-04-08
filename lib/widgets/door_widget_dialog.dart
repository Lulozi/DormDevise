import 'dart:async';

import 'door_desktop_widgets.dart';
import 'package:dormdevise/models/door_widget_state.dart';
import 'package:dormdevise/services/door_trigger_service.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面微件唤起的弹窗对话框，展示门锁状态并支持双击开门。
class DoorWidgetDialog extends StatelessWidget {
  const DoorWidgetDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: DoorWidgetPanel(onClose: () => Navigator.of(context).maybePop()),
    );
  }
}

/// 门锁状态面板，可嵌入弹窗或底部浮层，支持双击静默开门。
class DoorWidgetPanel extends StatefulWidget {
  const DoorWidgetPanel({super.key, this.onClose});

  final VoidCallback? onClose;

  @override
  State<DoorWidgetPanel> createState() => _DoorWidgetPanelState();
}

class _DoorWidgetPanelState extends State<DoorWidgetPanel> {
  bool _opening = false;
  DateTime? _lastTriggerTime;
  late final DoorWidgetService _service;
  StreamSubscription<DoorWidgetState>? _stateSubscription;

  /// 防抖间隔（参考开门页面4秒）
  static const Duration _debounceInterval = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _service = DoorWidgetService.instance;
  }

  @override
  void dispose() {
    _stateSubscription?.cancel();
    super.dispose();
  }

  /// 双击触发开门 - 静默执行，无弹窗确认
  Future<void> _handleDoubleTapTrigger() async {
    // 防抖检查
    final now = DateTime.now();
    if (_lastTriggerTime != null &&
        now.difference(_lastTriggerTime!) < _debounceInterval) {
      return;
    }

    if (_opening) return;

    _lastTriggerTime = now;
    setState(() => _opening = true);

    // 双击时统一提供触觉反馈。
    await HapticFeedback.mediumImpact();

    // 静默执行开门
    await _service.markManualTriggerStart();
    final DoorTriggerResult result = await DoorTriggerService.instance
        .triggerDoor();
    await _service.recordManualTriggerResult(result);

    if (!mounted) {
      _opening = false;
      return;
    }

    setState(() => _opening = false);

    // 成功后自动关闭面板
    if (result.success) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 1200)).then((_) {
          if (mounted) {
            widget.onClose?.call();
          }
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '开门组件',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 门锁组件
          LayoutBuilder(
            builder: (context, constraints) {
              final double panelWidth =
                  constraints.maxWidth.isFinite && constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : 320;
              final double widgetHeight = (panelWidth * 0.88).clamp(
                220.0,
                320.0,
              );
              return ValueListenableBuilder<DoorWidgetState>(
                valueListenable: _service.stateNotifier,
                builder: (context, state, _) {
                  return SizedBox(
                    height: widgetHeight,
                    child: DoorLockWidget(
                      state: state,
                      busy: _opening,
                      onDoubleTap: _handleDoubleTapTrigger,
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
