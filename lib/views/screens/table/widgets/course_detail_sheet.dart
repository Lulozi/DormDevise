import 'package:flutter/material.dart';
import '../../../../models/course.dart';

class CourseDetailSheet extends StatelessWidget {
  final List<CourseDetailItem> items;

  const CourseDetailSheet({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF7F8FC),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context),
          Flexible(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                return _buildCourseCard(context, items[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          const Spacer(),
          Text(
            '课程详情',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildCourseCard(BuildContext context, CourseDetailItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: item.course.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.course.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '编辑',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF666666),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildDetailRow('教室', item.session.location),
          const SizedBox(height: 4),
          _buildDetailRow('备注（如老师）', item.course.teacher),
          const SizedBox(height: 4),
          _buildDetailRow(
            '${_weekdayToString(item.session.weekday)} 第 ${item.session.startSection}-${item.session.startSection + item.session.sectionCount - 1} 节',
            '(${_formatTime(item.startTime)} - ${_formatTime(item.endTime)})',
          ),
          const SizedBox(height: 4),
          _buildDetailRow(
            '第 ${item.session.startWeek}-${item.session.endWeek} 周',
            '',
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 13,
          color: Color(0xFF999999),
          height: 1.5,
        ),
        children: [
          TextSpan(text: '$label： '),
          TextSpan(
            text: value,
            style: const TextStyle(color: Color(0xFF666666)),
          ),
        ],
      ),
    );
  }

  String _weekdayToString(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (weekday >= 1 && weekday <= 7) {
      return weekdays[weekday - 1];
    }
    return '';
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class CourseDetailItem {
  final Course course;
  final CourseSession session;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  CourseDetailItem({
    required this.course,
    required this.session,
    required this.startTime,
    required this.endTime,
  });
}
