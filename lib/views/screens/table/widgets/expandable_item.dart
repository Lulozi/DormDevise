import 'package:flutter/material.dart';

class ExpandableItem extends StatelessWidget {
  final String title;
  final Widget? value;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget content;
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
        InkWell(
          onTap: onTap,
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
