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

  /// 是否在空间不足时自动缩放右侧值。
  final bool autoScaleValue;

  /// 左侧标题的 flex 权重（默认 6），短标题可设更小值以靠近右侧内容。
  final int titleFlex;

  /// 右侧值的 flex 权重（默认 5）。
  final int valueFlex;

  /// 是否在空间不足时自动缩放左侧标题文本。
  /// 默认 true（FittedBox 等比缩小），设为 false 保持固定字号不缩放。
  final bool titleAutoScale;

  const ExpandableItem({
    super.key,
    required this.title,
    this.value,
    required this.isExpanded,
    required this.onTap,
    required this.content,
    this.showDivider = true,
    this.autoScaleValue = true,
    this.titleFlex = 6,
    this.valueFlex = 5,
    this.titleAutoScale = true,
  });

  /// 构建标题文本，供 build 方法与 FittedBox 共用。
  Widget _buildTitleText(ColorScheme colorScheme) {
    return Text(
      title,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  flex: titleFlex,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    // 标题保持单行；可通过 titleAutoScale 控制是否自动缩放。
                    child: titleAutoScale
                        ? FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: _buildTitleText(colorScheme),
                          )
                        : _buildTitleText(colorScheme),
                  ),
                ),
                const SizedBox(width: 8),
                if (value != null)
                  Expanded(
                    flex: valueFlex,
                    child: Align(
                      alignment: Alignment.centerRight,
                      // 可按场景关闭自动缩放，交由上层统一控制字号联动。
                      child: autoScaleValue
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: value!,
                            )
                          : value!,
                    ),
                  ),
                if (value != null) const SizedBox(width: 8),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 20,
                  // 与课程编辑页 chevron_right 箭头颜色保持一致
                  color: colorScheme.outline,
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
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: colorScheme.outlineVariant,
          ),
      ],
    );
  }
}
