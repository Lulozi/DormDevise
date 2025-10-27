import 'package:dormdevise/screens/open_door/widgets/door_widget_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 桌面微件专用入口页，从底部浮层形式展示滑动开门面板。
class DoorWidgetPromptPage extends StatefulWidget {
  const DoorWidgetPromptPage({super.key});

  /// 创建页面状态以控制浮层显隐与关闭逻辑。
  @override
  State<DoorWidgetPromptPage> createState() => _DoorWidgetPromptPageState();
}

class _DoorWidgetPromptPageState extends State<DoorWidgetPromptPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _controller;
  bool _closing = false;
  static const MethodChannel _channel = MethodChannel('door_widget/prompt');

  @override
  /// 初始化底部浮层出场动画控制器。
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _playEntranceAnimation();
  }

  @override
  /// 销毁动画控制器释放系统资源。
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  /// 监听生命周期变化，在重新激活时重置动效。
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _playEntranceAnimation();
    }
  }

  /// 播放浮层出现动画并重置关闭标记。
  void _playEntranceAnimation() {
    _closing = false;
    _controller.stop();
    _controller.forward(from: 0);
  }

  /// 执行浮层关闭动作，同时结束当前 FlutterActivity。
  Future<void> _closePrompt() async {
    if (_closing) {
      return;
    }
    _closing = true;
    await _controller.reverse();
    if (!mounted) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('close');
    } catch (_) {
      SystemNavigator.pop();
    }
    _closing = false;
  }

  @override
  /// 构建透明背景与底部浮层组合界面。
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _closePrompt,
              child: Container(color: Colors.transparent),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return SlideTransition(
                      position:
                          Tween<Offset>(
                            begin: const Offset(0, 0.2),
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: _controller,
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                      child: FadeTransition(
                        opacity: CurvedAnimation(
                          parent: _controller,
                          curve: Curves.easeOut,
                        ),
                        child: child,
                      ),
                    );
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: DoorWidgetPanel(onClose: _closePrompt),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
