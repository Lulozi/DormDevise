import 'dart:async';

import 'package:dormdevise/screens/open_door/widgets/door_desktop_widgets.dart';
import 'package:dormdevise/services/door_trigger_service.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面微件唤起的弹窗对话框，提供滑动触发开门的交互。
class DoorWidgetDialog extends StatelessWidget {
  const DoorWidgetDialog({super.key});

  /// 构建对话框壳层并嵌入核心面板。
  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: DoorWidgetPanel(onClose: () => Navigator.of(context).maybePop()),
    );
  }
}

/// 提供滑动触发开门交互的核心面板，可嵌入弹窗或底部浮层。
class DoorWidgetPanel extends StatefulWidget {
  const DoorWidgetPanel({super.key, this.onClose});

  /// 弹窗关闭回调，外层用于收尾界面。
  final VoidCallback? onClose;

  /// 创建面板状态以管理滑动触发逻辑。
  @override
  State<DoorWidgetPanel> createState() => _DoorWidgetPanelState();
}

class _DoorWidgetPanelState extends State<DoorWidgetPanel> {
  bool _opening = false;
  String? _statusMessage;
  late final DoorWidgetService _service;
  static const String _defaultStatus = '准备滑动触发开门';

  @override
  /// 初始化服务引用并读取上次结果文案。
  void initState() {
    super.initState();
    _service = DoorWidgetService.instance;
    _statusMessage = _service.state.lastResultMessage?.isNotEmpty == true
        ? _service.state.lastResultMessage
        : _defaultStatus;
  }

  /// 处理滑动触发事件，串联微件服务与开门逻辑。
  Future<void> _handleTrigger() async {
    if (_opening) {
      return;
    }
    setState(() {
      _opening = true;
      _statusMessage = '正在开门，请稍候…';
    });
    await _service.markManualTriggerStart();
    if (_service.settings.enableHaptics) {
      await HapticFeedback.mediumImpact();
    }
    final DoorTriggerResult result = await DoorTriggerService.instance
        .triggerDoor();
    await _service.recordManualTriggerResult(result);
    if (!mounted) {
      return;
    }
    setState(() {
      _opening = false;
      _statusMessage = result.message;
    });
    if (result.success && mounted) {
      // 成功后稍作停留再自动关闭浮层，并重置文案至默认提示。
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 800)).then((_) {
          if (mounted) {
            setState(() {
              _statusMessage = _defaultStatus;
            });
            widget.onClose?.call();
          }
        }),
      );
    }
  }

  @override
  /// 构建滑动面板主体内容与状态展示。
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '滑动开门',
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
          const SizedBox(height: 12),
          Text(
            '向右滑动手柄触发开门。请确认当前已靠近宿舍门禁。',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 72,
            child: DoorSlideTile(
              onTrigger: _handleTrigger,
              busy: _opening,
              axis: Axis.horizontal,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (_opening)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              if (_opening) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusMessage ?? _defaultStatus,
                  style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
