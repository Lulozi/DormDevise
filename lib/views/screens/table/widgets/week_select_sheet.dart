import 'package:flutter/material.dart';

/// 周次选择弹窗组件。
///
/// 允许用户在网格视图中选择要查看的周次，并提供快速跳转到「本周」的功能。
class WeekSelectSheet extends StatelessWidget {
  /// 当前实际周次 (currentWeek)（用于「本周」按钮）。
  final int currentWeek;

  /// 当前选中的周次 (selectedWeek)（高亮显示）。
  final int selectedWeek;

  /// 最大周次数量 (maxWeek)。
  final int maxWeek;

  /// 周次选择回调 (onWeekSelected)。
  final ValueChanged<int> onWeekSelected;

  const WeekSelectSheet({
    super.key,
    required this.currentWeek,
    required this.selectedWeek,
    required this.maxWeek,
    required this.onWeekSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Center(
                  child: Text(
                    '切换周课表',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.black54),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1,
                ),
                itemCount: maxWeek,
                itemBuilder: (context, index) {
                  final int week = index + 1;
                  final bool isSelected = week == selectedWeek;
                  final bool isCurrentWeek = week == currentWeek;

                  return InkWell(
                    onTap: () {
                      onWeekSelected(week);
                      Navigator.pop(context);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFE8F0FF) // 选中状态为浅蓝色
                            : const Color(0xFFF5F5F5), // 其他状态为灰色
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected
                            ? Border.all(
                                color: Color.fromRGBO(30, 105, 255, 0.3),
                                width: 1.5,
                              )
                            : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        isCurrentWeek ? '本周' : '$week',
                        style: TextStyle(
                          fontSize: isCurrentWeek ? 15 : 16,
                          fontWeight: isSelected || isCurrentWeek
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isSelected
                              ? const Color(0xFF1E69FF)
                              : (isCurrentWeek
                                    ? const Color(0xFF1E69FF)
                                    : Colors.black87),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
