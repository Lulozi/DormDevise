import 'package:flutter/material.dart';

/// 显示气泡弹窗
///
/// [context] 上下文
/// [content] 弹窗内容
/// [anchorKey] 锚点组件的 GlobalKey，用于定位弹窗位置
/// [verticalOffset] 垂直偏移量，默认为 10.0
/// [alignment] 弹窗对齐方式，默认为右上角对齐
Future<T?> showBubblePopup<T>({
  required BuildContext context,
  required Widget content,
  required GlobalKey anchorKey,
  double verticalOffset = 10.0,
  Alignment alignment = Alignment.topRight,
}) {
  final RenderBox button =
      anchorKey.currentContext!.findRenderObject() as RenderBox;
  final RenderBox overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;

  final Offset buttonBottomRight = button.localToGlobal(
    button.size.bottomRight(Offset.zero),
    ancestor: overlay,
  );

  // 计算位置
  // 如果是右上角对齐，rightOffset 是距离右边的距离
  final double rightOffset = overlay.size.width - buttonBottomRight.dx;
  final double topOffset = buttonBottomRight.dy + verticalOffset;

  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, __) {
        return Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.translucent,
              child: Container(color: Colors.transparent),
            ),
            Positioned(
              top: topOffset,
              right: rightOffset,
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutBack,
                  reverseCurve: Curves.easeIn,
                ),
                alignment: alignment,
                child: FadeTransition(
                  opacity: animation,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(20),
                    color: Colors.white,
                    child: content,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
