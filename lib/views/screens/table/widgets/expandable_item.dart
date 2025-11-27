import 'package:flutter/material.dart';

/// 一个可展开的列表项组件
class ExpandableItem extends StatelessWidget {
  /// 标题 (title)
  final String title;

  /// 右侧显示的值 (value)（可选）
  final Widget? value;

  /// 是否展开 (isExpanded)
  final bool isExpanded;

  /// 点击回调 (onTap)
  final VoidCallback onTap;

  /// 展开后显示的内容 (content)
  final Widget content;

  /// 是否显示底部分割线 (showDivider)
  final bool showDivider;

  const ExpandableItem({
    super.key,
    required this.title,
    this.value,
    required this.isExpanded,
    required this.onTap,
    required this.content,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
                Row(
                  children: [
                    if (value != null) value!,
                    const SizedBox(width: 8),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                      color: Colors.black26,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: Container(),
          secondChild: content,
          crossFadeState: isExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 300),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 16, color: Color(0xFFE5E5EA)),
      ],
    );
  }
}
