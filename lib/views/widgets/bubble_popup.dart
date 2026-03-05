import 'dart:async';
import 'package:flutter/material.dart';

/// 气泡弹窗控制器，用于外部关闭弹窗
class BubblePopupController {
  VoidCallback? _dismiss;

  /// 关闭弹窗
  Future<void> dismiss() async {
    _dismiss?.call();
  }
}

/// 显示气泡弹窗（使用 Overlay 实现，不阻塞底层滚动）
///
/// [context] 上下文
/// [content] 弹窗内容
/// [anchorKey] 锚点组件的 GlobalKey，用于定位弹窗位置
/// [verticalOffset] 垂直偏移量，默认为 10.0
/// [alignment] 弹窗对齐方式，默认为右上角对齐
/// [controller] 可选的控制器，用于外部手动关闭弹窗
Future<void> showBubblePopup({
  required BuildContext context,
  required Widget content,
  required GlobalKey anchorKey,
  double verticalOffset = 10.0,
  Alignment alignment = Alignment.topRight,
  BubblePopupController? controller,
}) async {
  final RenderBox button =
      anchorKey.currentContext!.findRenderObject() as RenderBox;
  final overlayState = Overlay.of(context);
  final RenderBox overlayBox =
      overlayState.context.findRenderObject() as RenderBox;

  final Offset buttonBottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );

  // 计算位置：右上角对齐
  final double rightOffset = overlayBox.size.width - buttonBottomRight.dx;
  final double topOffset = buttonBottomRight.dy + verticalOffset;
  final MediaQueryData mediaQuery = MediaQuery.of(context);
  final double rawScale = mediaQuery.textScaler.scale(14) / 14;
  final double bubbleScale = rawScale.clamp(0.9, 1.0).toDouble();

  final completer = Completer<void>();
  late OverlayEntry barrierEntry;
  late OverlayEntry bubbleEntry;

  final animController = AnimationController(
    vsync: overlayState,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 200),
  );
  final scaleAnim = CurvedAnimation(
    parent: animController,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeIn,
  );

  bool closing = false;
  Future<void> dismiss() async {
    if (closing) return;
    closing = true;
    await animController.reverse();
    barrierEntry.remove();
    bubbleEntry.remove();
    animController.dispose();
    if (!completer.isCompleted) completer.complete();
  }

  // 绑定控制器
  controller?._dismiss = dismiss;

  // 透明屏障层：仅拦截点击（tap）用以关闭弹窗，不阻塞滚动等手势
  barrierEntry = OverlayEntry(
    builder: (_) => Positioned.fill(
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => dismiss(),
      ),
    ),
  );

  bubbleEntry = OverlayEntry(
    builder: (_) => Positioned(
      top: topOffset,
      right: rightOffset,
      child: ScaleTransition(
        scale: scaleAnim,
        alignment: alignment,
        child: FadeTransition(
          opacity: scaleAnim,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias, // 裁剪子项，防止波纹/阴影溢出
            color:
                Theme.of(context).cardTheme.color ??
                Theme.of(context).colorScheme.surface,
            child: MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(bubbleScale),
              ),
              child: content,
            ),
          ),
        ),
      ),
    ),
  );

  overlayState.insertAll([barrierEntry, bubbleEntry]);
  animController.forward();

  return completer.future;
}
