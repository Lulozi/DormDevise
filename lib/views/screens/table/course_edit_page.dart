import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dormdevise/utils/index.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/utils/course_utils.dart';
import 'package:dormdevise/services/theme/theme_service.dart';
import '../../../../models/course.dart';
import '../../../../models/course_schedule_config.dart';
import '../../../../services/course_service.dart';
import '../../widgets/bottom_sheet_confirm.dart';
import 'widgets/expandable_item.dart';

// 教室分组数据模型

/// 表示一个教室内的一个周次分组（上课周数段），包含该段的周次设置和课程时段列表。
class _WeekGroup {
  /// 起始周次（包含），0 表示未配置。
  int startWeek;

  /// 结束周次（包含），0 表示未配置。
  int endWeek;

  /// 周次类型限制（单双周或全周）。
  CourseWeekType weekType;

  /// 自定义周次列表（若非空，则忽略 weekType，仅匹配列表中的周次）。
  List<int> customWeeks;

  /// 该周次段内的课程时段列表。
  List<CourseSession> sessions;

  _WeekGroup({
    this.startWeek = 0,
    this.endWeek = 0,
    this.weekType = CourseWeekType.all,
    List<int>? customWeeks,
    List<CourseSession>? sessions,
  }) : customWeeks = customWeeks ?? [],
       sessions = sessions ?? [];

  /// 获取该周次分组所有生效的周次集合。
  /// 周次必须为正整数，0 视为未配置。
  Set<int> get effectiveWeeks {
    if (customWeeks.isNotEmpty) return customWeeks.toSet();
    final weeks = <int>{};
    for (int w = startWeek; w <= endWeek; w++) {
      if (w <= 0) continue; // 周次必须为正整数，0 为未配置状态
      if (weekType == CourseWeekType.all ||
          (weekType == CourseWeekType.single && w.isOdd) ||
          (weekType == CourseWeekType.double && w.isEven)) {
        weeks.add(w);
      }
    }
    return weeks;
  }

  /// 该周次分组是否有任何已配置的课程时段。
  bool get hasAnySession => sessions.isNotEmpty;
}

/// 表示一个教室分组，包含教室名和多个上课周数段。
class _ClassroomGroup {
  /// 教室名称。
  String name;

  /// 该教室下的周次分组列表（每个分组代表一个上课周数段）。
  List<_WeekGroup> weekGroups;

  _ClassroomGroup({this.name = '', List<_WeekGroup>? weekGroups})
    : weekGroups = weekGroups ?? [];

  /// 获取该教室组所有生效的周次集合（所有周次分组的并集）。
  /// 周次必须为正整数，0 视为未配置。
  Set<int> get effectiveWeeks {
    final weeks = <int>{};
    for (final wg in weekGroups) {
      weeks.addAll(wg.effectiveWeeks);
    }
    return weeks;
  }

  /// 该教室是否有任何已配置的课程时段。
  bool get hasAnySession => weekGroups.any((wg) => wg.hasAnySession);
}

// 课程编辑页

class CourseEditPage extends StatefulWidget {
  final Course? course;
  final int? initialWeekday;
  final int? initialSection;
  final int maxWeek;
  final List<Course> existingCourses;
  final CourseScheduleConfig? scheduleConfig;

  const CourseEditPage({
    super.key,
    this.course,
    this.initialWeekday,
    this.initialSection,
    this.maxWeek = 20,
    this.existingCourses = const [],
    this.scheduleConfig,
  });

  @override
  State<CourseEditPage> createState() => _CourseEditPageState();
}

/// 课程编辑页统一返回结果。
enum CourseEditResultAction { save, delete }

/// 课程编辑/新建的统一返回协议。
class CourseEditResult {
  final CourseEditResultAction action;
  final Course course;
  final Course? previousCourse;

  const CourseEditResult._({
    required this.action,
    required this.course,
    this.previousCourse,
  });

  factory CourseEditResult.save({
    required Course course,
    Course? previousCourse,
  }) {
    return CourseEditResult._(
      action: CourseEditResultAction.save,
      course: course,
      previousCourse: previousCourse,
    );
  }

  factory CourseEditResult.delete({required Course course}) {
    return CourseEditResult._(
      action: CourseEditResultAction.delete,
      course: course,
    );
  }

  bool get isSave => action == CourseEditResultAction.save;
  bool get isDelete => action == CourseEditResultAction.delete;
}

class _CourseEditPageState extends State<CourseEditPage> {
  static final Set<Course> _openEditingCourses = <Course>{};

  late TextEditingController _nameController;
  late TextEditingController _teacherController;
  late Color _selectedColor;
  late Color _initialSmartColor;
  late List<Course> _existingCourses;
  List<Color> _customColors = [];
  Color? _temporaryAutoColor;
  CourseScheduleConfig? _scheduleConfig;
  final Map<int, Timer> _debounceTimers = {};
  int _pickerResetVersion = 0;
  List<Course> _suggestions = [];

  // 教室分组列表
  /// 所有教室分组，每个分组包含教室名、周次和时段。
  List<_ClassroomGroup> _classroomGroups = [];

  /// AnimatedList 的全局键，用于教室块的添加/删除过渡动画。
  GlobalKey<AnimatedListState> _classroomListKey =
      GlobalKey<AnimatedListState>();

  // 同名教室名合并 debounce（已移除自动合并，保留字段兼容）
  // Timer? _nameMergeTimer;  // 不再需要

  // 展开状态追踪
  /// 当前展开的教室组索引（用于显示时段编辑）。
  int? _expandedClassroomIndex;

  /// 当前展开的周次分组索引（在 _expandedClassroomIndex 对应的教室组内）。
  int? _expandedWeekGroupIndex;

  /// 当前展开的时段索引（在对应周次分组内）。
  int? _expandedSessionIndex;

  /// 各教室组内部的 AnimatedList 键，用于周次分组的添加/删除过渡动画。
  final Map<int, GlobalKey<AnimatedListState>> _weekGroupListKeys = {};

  /// 获取或创建指定教室组的 AnimatedList 键。
  GlobalKey<AnimatedListState> _getWeekGroupListKey(int groupIndex) {
    return _weekGroupListKeys.putIfAbsent(
      groupIndex,
      () => GlobalKey<AnimatedListState>(),
    );
  }

  int get _totalSections {
    if (_scheduleConfig == null) return 12;
    return _scheduleConfig!.segments.fold(
      0,
      (sum, seg) => sum + seg.classCount,
    );
  }

  /// 预设背景色池，引用共享常量。
  final List<Color> _presetColors = List<Color>.of(kCoursePresetColors);

  // 计算属性：所有教室组的总生效周次
  /// 获取所有教室组的生效周次并集。
  Set<int> get _totalEffectiveWeeks {
    final all = <int>{};
    for (final group in _classroomGroups) {
      all.addAll(group.effectiveWeeks);
    }
    return all;
  }

  /// 将周次集合格式化为紧凑的展示字符串。
  /// 空集合返回 "未配置"，其余如 "第1-10周"、"第1、3、7周"。
  String _formatWeeksSet(Set<int> weeks) {
    if (weeks.isEmpty) return '未配置';
    final sorted = weeks.toList()..sort();
    if (sorted.length == 1) return '第${sorted.first}周';

    final buffer = StringBuffer();
    int rangeStart = sorted.first;
    int rangeEnd = sorted.first;

    for (int i = 1; i < sorted.length; i++) {
      if (sorted[i] == rangeEnd + 1) {
        // 连续周次，扩展当前范围
        rangeEnd = sorted[i];
      } else {
        // 结束当前范围，开始新范围
        if (buffer.isNotEmpty) buffer.write('、');
        if (rangeStart == rangeEnd) {
          buffer.write('$rangeStart');
        } else {
          buffer.write('$rangeStart-$rangeEnd');
        }
        rangeStart = sorted[i];
        rangeEnd = sorted[i];
      }
    }
    // 最后一个范围
    if (buffer.isNotEmpty) buffer.write('、');
    if (rangeStart == rangeEnd) {
      buffer.write('$rangeStart');
    } else {
      buffer.write('$rangeStart-$rangeEnd');
    }
    return '第${buffer.toString()}周';
  }

  /// 获取除指定索引外其他教室组的生效周次并集（用于周数互斥）。
  ///
  /// 仅当其他教室组与当前组存在课程时间重叠（相同星期 + 相同节次范围）时，
  /// 才将其周次标记为不可选，避免不同时间段的无关联教室被错误禁用。
  Set<int> _getOtherGroupsWeeks(int excludeIndex) {
    final disabled = <int>{};
    final currentGroup = _classroomGroups[excludeIndex];
    for (int i = 0; i < _classroomGroups.length; i++) {
      if (i == excludeIndex) continue;
      // 仅当两组存在时间重叠的 session 时，才将其周次加入禁用集合。
      if (_groupsShareSessionTime(currentGroup, _classroomGroups[i])) {
        disabled.addAll(_classroomGroups[i].effectiveWeeks);
      }
    }
    return disabled;
  }

  /// 判断两个教室组是否存在课程时间重叠（相同星期 + 相同节次范围）。
  bool _groupsShareSessionTime(_ClassroomGroup a, _ClassroomGroup b) {
    for (final wgA in a.weekGroups) {
      for (final sessionA in wgA.sessions) {
        for (final wgB in b.weekGroups) {
          for (final sessionB in wgB.sessions) {
            if (sessionA.weekday != sessionB.weekday) continue;
            final aEnd = sessionA.startSection + sessionA.sectionCount - 1;
            final bEnd = sessionB.startSection + sessionB.sectionCount - 1;
            // 节次范围有交集即视为时间重叠。
            if (sessionA.startSection <= bEnd &&
                sessionB.startSection <= aEnd) {
              return true;
            }
          }
        }
      }
    }
    return false;
  }

  // 初始化

  @override
  void initState() {
    super.initState();
    if (widget.scheduleConfig != null) {
      _scheduleConfig = widget.scheduleConfig;
    }
    _loadConfig();
    _loadCustomColors();
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _nameController.addListener(_onNameChanged);
    _teacherController = TextEditingController(
      text: widget.course?.teacher ?? '',
    );
    if (widget.course != null) {
      _openEditingCourses.add(widget.course!);
    }
    // 维护一份可更新的课程快照，避免子编辑页保存后父编辑页仍使用旧数据。
    _existingCourses = List<Course>.of(widget.existingCourses);

    // 初始化教室分组
    if (widget.course != null && widget.course!.sessions.isNotEmpty) {
      // 编辑模式：按教室（location）分组现有 sessions
      _classroomGroups = _groupSessionsByLocation(widget.course!.sessions);
      // 导入课程的教室按周数排序
      _sortClassroomGroups();
      _initialSmartColor = widget.course!.color;
      _selectedColor = _initialSmartColor;
    } else {
      // 新建模式：创建默认教室分组
      _classroomGroups = [_createDefaultGroup()];
      // 优先选择未使用的颜色
      final Set<int> usedColorValues = _existingCourses
          .map((c) => c.color.toARGB32())
          .toSet();
      final List<Color> availableColors = _presetColors
          .where((c) => !usedColorValues.contains(c.toARGB32()))
          .toList();

      if (availableColors.isNotEmpty) {
        _initialSmartColor =
            availableColors[Random().nextInt(availableColors.length)];
      } else {
        _initialSmartColor =
            _presetColors[Random().nextInt(_presetColors.length)];
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showColorExhaustedDialog();
        });
      }
      _selectedColor = _initialSmartColor;

      // 如果传入初始节次（从日历点击），则创建对应的时段，但周次范围保持未配置
      if (widget.initialWeekday != null && widget.initialSection != null) {
        int initialCount = 2;
        final int nextSection = widget.initialSection! + 1;

        // 检查下一个节次是否被已有课程占用
        bool nextSectionOccupied = _existingCourses.any((course) {
          return course.sessions.any((session) {
            if (session.weekday != widget.initialWeekday!) return false;
            final int sessionEnd =
                session.startSection + session.sectionCount - 1;
            return session.startSection <= nextSection &&
                sessionEnd >= nextSection;
          });
        });

        if (nextSectionOccupied) {
          initialCount = 1;
        }

        // 创建周次未配置的 WeekGroup（startWeek = 0, endWeek = 0 表示未配置）
        // 并添加点击位置的课程时段
        final firstGroup = _classroomGroups.first;
        firstGroup.weekGroups.add(
          _WeekGroup(
            startWeek: 0, // 周次未配置
            endWeek: 0,
            weekType: CourseWeekType.all,
            sessions: [
              CourseSession(
                weekday: widget.initialWeekday!,
                startSection: widget.initialSection!,
                sectionCount: initialCount,
                location: '',
                startWeek: 0, // 周次未配置
                endWeek: 0,
                weekType: CourseWeekType.all,
              ),
            ],
          ),
        );
      }
    }
  }

  /// 按教室（location）将 sessions 分组为 ClassroomGroup 列表，
  /// 每组内自动按周次范围归并为 WeekGroup。
  List<_ClassroomGroup> _groupSessionsByLocation(List<CourseSession> sessions) {
    final Map<String, List<CourseSession>> grouped = {};
    for (final s in sessions) {
      final key = s.location.trim().isEmpty ? '' : s.location.trim();
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(s);
    }

    if (grouped.isEmpty) {
      return [_createDefaultGroup()];
    }

    return grouped.entries.map((entry) {
      final sList = entry.value;
      // 按周次范围将 sessions 分组为 WeekGroup
      final Map<String, List<CourseSession>> weekGrouped = {};
      for (final s in sList) {
        final weekKey =
            '${s.startWeek}|${s.endWeek}|${s.weekType.name}|${s.customWeeks.join(',')}';
        weekGrouped.putIfAbsent(weekKey, () => []);
        weekGrouped[weekKey]!.add(s);
      }

      final List<_WeekGroup> weekGroups = weekGrouped.entries.map((wgEntry) {
        final sGroup = wgEntry.value;
        final first = sGroup.first;
        return _WeekGroup(
          startWeek: first.startWeek,
          endWeek: first.endWeek,
          weekType: first.weekType,
          customWeeks: List.of(first.customWeeks),
          sessions: sGroup
              .map(
                (s) => CourseSession(
                  weekday: s.weekday,
                  startSection: s.startSection,
                  sectionCount: s.sectionCount,
                  location: entry.key,
                  startWeek: s.startWeek,
                  endWeek: s.endWeek,
                  weekType: s.weekType,
                  customWeeks: List.of(s.customWeeks),
                ),
              )
              .toList(),
        );
      }).toList();

      return _ClassroomGroup(name: entry.key, weekGroups: weekGroups);
    }).toList();
  }

  /// 解析单个 session 的所有生效周次。
  Set<int> _resolveSessionWeeks(CourseSession s) {
    if (s.customWeeks.isNotEmpty) return s.customWeeks.toSet();
    final weeks = <int>{};
    for (int w = s.startWeek; w <= s.endWeek; w++) {
      if (w <= 0) continue;
      if (s.weekType == CourseWeekType.all ||
          (s.weekType == CourseWeekType.single && w.isOdd) ||
          (s.weekType == CourseWeekType.double && w.isEven)) {
        weeks.add(w);
      }
    }
    return weeks;
  }

  /// 创建默认的教室分组（无周次分组，未配置状态）。
  _ClassroomGroup _createDefaultGroup() {
    return _ClassroomGroup(
      name: '',
      weekGroups: [], // 新建课程默认无周次分组
    );
  }

  // 名称变更联想

  void _onNameChanged() {
    final String name = _nameController.text.trim();

    if (name.isEmpty) {
      if (_suggestions.isNotEmpty) {
        setState(() {
          _suggestions = [];
        });
      }
      return;
    }

    // 若是已经输入的课程名已经已经导入（完全匹配且内容一致），则不需要再联想
    final exactMatches = _existingCourses.where((c) => c.name == name);
    if (exactMatches.isNotEmpty) {
      final exactMatch = exactMatches.first;
      final bool isTeacherSame = exactMatch.teacher == _teacherController.text;
      final bool isColorSame =
          exactMatch.color.toARGB32() == _selectedColor.toARGB32();

      if (isTeacherSame && isColorSame) {
        if (_suggestions.isNotEmpty) {
          setState(() {
            _suggestions = [];
          });
        }
        return;
      }
    }

    final lowerName = name.toLowerCase();
    final matches = _existingCourses.where((c) {
      return c.name.toLowerCase().contains(lowerName);
    }).toList();

    final uniqueMatches = <String, Course>{};
    for (var c in matches) {
      if (!uniqueMatches.containsKey(c.name)) {
        uniqueMatches[c.name] = c;
      }
    }

    setState(() {
      _suggestions = uniqueMatches.values.toList();
    });
  }

  // 跨段检测

  bool _isCrossSegment(CourseSession session) {
    if (_scheduleConfig == null) return false;

    bool contained = false;
    int segStart = 1;
    for (var segment in _scheduleConfig!.segments) {
      int segEnd = segStart + segment.classCount - 1;
      final uEnd = session.startSection + session.sectionCount - 1;

      if (session.startSection >= segStart && uEnd <= segEnd) {
        contained = true;
        break;
      }
      segStart += segment.classCount;
    }
    return !contained;
  }

  // 配置加载

  Future<void> _loadConfig() async {
    final config =
        widget.scheduleConfig ?? await CourseService.instance.loadConfig();
    if (mounted) {
      setState(() {
        _scheduleConfig = config;
      });
    }
  }

  // 教室分组操作

  /// 添加一个新的教室分组（默认包含一个未配置的周次分组，无时段）。
  void _addClassroomGroup() {
    final newGroup = _ClassroomGroup(
      name: '',
      weekGroups: [
        // 创建一个未配置的周次分组（startWeek = 0, endWeek = 0），但不包含时段
        _WeekGroup(
          startWeek: 0,
          endWeek: 0,
          weekType: CourseWeekType.all,
          sessions: [],
        ),
      ],
    );
    final insertIndex = _classroomGroups.length;
    _classroomGroups.add(newGroup);
    _classroomListKey.currentState?.insertItem(insertIndex);
    setState(() {
      _pickerResetVersion++;
    });
  }

  /// 删除最后一个教室分组（至少保留一个）。
  void _removeClassroomGroup() {
    if (_classroomGroups.length <= 1) {
      AppToast.show(context, '至少保留一个教室', variant: AppToastVariant.warning);
      return;
    }
    final removedIndex = _classroomGroups.length - 1;
    // 在 removeAt 前捕获数据快照，供删除动画使用（动画异步执行时数据已移除）
    final removedGroup = _classroomGroups[removedIndex];
    _classroomListKey.currentState?.removeItem(
      removedIndex,
      (context, animation) =>
          _buildRemovingClassroomBlock(removedGroup, animation),
      duration: const Duration(milliseconds: 250),
    );
    _classroomGroups.removeAt(removedIndex);
    setState(() {
      if (_expandedClassroomIndex != null &&
          _expandedClassroomIndex! >= _classroomGroups.length) {
        _expandedClassroomIndex = null;
        _expandedSessionIndex = null;
      }
      _pickerResetVersion++;
    });
  }

  /// 按最早生效周次排序教室分组（周次早的在前，空周次排最后）。
  void _sortClassroomGroups() {
    _classroomGroups.sort((a, b) {
      final aWeeks = a.effectiveWeeks;
      final bWeeks = b.effectiveWeeks;
      // 空周次的排在最后
      if (aWeeks.isEmpty && bWeeks.isEmpty) return 0;
      if (aWeeks.isEmpty) return 1;
      if (bWeeks.isEmpty) return -1;
      // 按最早周次排序
      final aMin = aWeeks.reduce((x, y) => x < y ? x : y);
      final bMin = bWeeks.reduce((x, y) => x < y ? x : y);
      return aMin.compareTo(bMin);
    });
  }

  /// 将并集周次应用到目标周次分组的周次配置。
  void _applyUnionWeeksToWeekGroup(_WeekGroup target, Set<int> unionWeeks) {
    if (unionWeeks.isEmpty) {
      target.startWeek = 0;
      target.endWeek = 0;
      target.weekType = CourseWeekType.all;
      target.customWeeks = [];
    } else {
      final sorted = unionWeeks.toList()..sort();
      target.startWeek = sorted.first;
      target.endWeek = sorted.last;
      if (_isFullRangeWeeks(sorted, 1, widget.maxWeek, CourseWeekType.all)) {
        target.weekType = CourseWeekType.all;
        target.customWeeks = [];
      } else if (_isFullRangeWeeks(
        sorted,
        1,
        widget.maxWeek,
        CourseWeekType.single,
      )) {
        target.weekType = CourseWeekType.single;
        target.customWeeks = [];
      } else if (_isFullRangeWeeks(
        sorted,
        1,
        widget.maxWeek,
        CourseWeekType.double,
      )) {
        target.weekType = CourseWeekType.double;
        target.customWeeks = [];
      } else {
        target.weekType = CourseWeekType.all;
        target.customWeeks = sorted;
      }
    }
  }

  /// 检测同名且时间重叠的教室组，返回可合并的组信息列表。
  ///
  /// 仅返回存在至少一对时间重叠 session 的同名组，供保存时弹窗逐项勾选。
  List<_MergeableGroupInfo> _detectMergeableGroups() {
    final Map<String, List<int>> nameToIndices = {};
    for (int i = 0; i < _classroomGroups.length; i++) {
      final rawName = _classroomGroups[i].name.trim();
      final name = rawName.isEmpty ? '' : rawName;
      nameToIndices.putIfAbsent(name, () => []);
      nameToIndices[name]!.add(i);
    }

    final List<_MergeableGroupInfo> result = [];
    for (final entry in nameToIndices.entries) {
      final indices = entry.value;
      if (indices.length <= 1) continue;

      // 使用连通分量找出时间重叠链上的簇。
      final n = indices.length;
      final List<Set<int>> adjacency = List.generate(n, (_) => <int>{});
      for (int i = 0; i < n; i++) {
        for (int j = i + 1; j < n; j++) {
          if (_groupsShareSessionTime(
            _classroomGroups[indices[i]],
            _classroomGroups[indices[j]],
          )) {
            adjacency[i].add(j);
            adjacency[j].add(i);
          }
        }
      }

      final List<bool> visited = List.filled(n, false);
      for (int start = 0; start < n; start++) {
        if (visited[start]) continue;

        // BFS 收集当前簇。
        final List<int> cluster = [];
        final List<int> queue = [start];
        visited[start] = true;
        while (queue.isNotEmpty) {
          final cur = queue.removeAt(0);
          cluster.add(cur);
          for (final neighbor in adjacency[cur]) {
            if (!visited[neighbor]) {
              visited[neighbor] = true;
              queue.add(neighbor);
            }
          }
        }

        if (cluster.length <= 1) continue;

        // 构建该簇的描述信息。
        final List<String> descriptions = [];
        final List<int> clusterIndices = cluster
            .map((c) => indices[c])
            .toList();
        for (final pos in cluster) {
          final group = _classroomGroups[indices[pos]];
          final weekLabel = _formatWeeksSet(group.effectiveWeeks);
          final allGroupSessions = group.weekGroups
              .expand((wg) => wg.sessions)
              .toList();
          final timeLabels = allGroupSessions
              .map((s) {
                final wd = _weekdayToShortString(s.weekday);
                final se = s.sectionCount == 1
                    ? '${s.startSection}节'
                    : '${s.startSection}-${s.startSection + s.sectionCount - 1}节';
                return '$wd $se';
              })
              .join('、');
          final desc = timeLabels.isEmpty ? '（无时段）' : '$weekLabel $timeLabels';
          descriptions.add(desc);
        }

        final displayName = entry.key.isEmpty ? '未命名教室' : entry.key;
        result.add(
          _MergeableGroupInfo(
            name: displayName,
            count: cluster.length,
            descriptions: descriptions,
            groupIndices: clusterIndices,
          ),
        );
      }
    }
    return result;
  }

  /// 构建同名教室合并确认对话框（逐项勾选）。
  Future<Set<int>?> _showMergeConfirmDialog(
    BuildContext ctx,
    List<_MergeableGroupInfo> groups,
  ) async {
    final Set<int> selectedIndexes = {};
    // 默认全部勾选。
    for (int i = 0; i < groups.length; i++) {
      selectedIndexes.add(i);
    }

    final bool? confirmed = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final cs = Theme.of(context).colorScheme;
            return AlertDialog(
              title: const Text('检测到同名教室'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '以下同名教室存在时间重叠，'
                      '请勾选需要合并的组：',
                    ),
                    const SizedBox(height: 12),
                    for (int i = 0; i < groups.length; i++) ...[
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: CheckboxListTile(
                          value: selectedIndexes.contains(i),
                          onChanged: (checked) {
                            setDialogState(() {
                              if (checked == true) {
                                selectedIndexes.add(i);
                              } else {
                                selectedIndexes.remove(i);
                              }
                            });
                          },
                          title: Text(
                            '${groups[i].name}（${groups[i].count}个）',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: groups[i].descriptions.map((desc) {
                              return Text(
                                '· $desc',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              );
                            }).toList(),
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.only(
                            left: 4,
                            right: 8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('跳过合并'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('合并所选'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true) return null;
    if (selectedIndexes.isEmpty) return null;
    return selectedIndexes;
  }

  /// 仅合并用户勾选的同名教室组簇。
  void _mergeSelectedGroups(
    List<_MergeableGroupInfo> groups,
    Set<int> selectedIndexes,
  ) {
    for (final i in selectedIndexes) {
      if (i < 0 || i >= groups.length) continue;
      final groupInfo = groups[i];
      final indices = groupInfo.groupIndices;
      if (indices.length <= 1) continue;

      // 复用连通分量内部的合并逻辑（与 _mergeSameNameGroupsInternal 一致）。
      final targetIdx = indices.first;
      final target = _classroomGroups[targetIdx];

      // 收集所有组的生效周次并集。
      final Set<int> unionWeeks = {};
      for (final idx in indices) {
        unionWeeks.addAll(_classroomGroups[idx].effectiveWeeks);
      }
      // 将并集周次应用到目标的第一个周次分组（或创建新的）
      if (target.weekGroups.isEmpty) {
        target.weekGroups.add(_WeekGroup());
      }
      _applyUnionWeeksToWeekGroup(target.weekGroups.first, unionWeeks);

      // 合并 sessions 并去重。
      final Map<String, CourseSession> deduped = {};
      for (final idx in indices) {
        for (final wg in _classroomGroups[idx].weekGroups) {
          for (final s in wg.sessions) {
            final key = '${s.weekday}|${s.startSection}|${s.sectionCount}';
            if (!deduped.containsKey(key)) {
              deduped[key] = CourseSession(
                weekday: s.weekday,
                startSection: s.startSection,
                sectionCount: s.sectionCount,
                location: target.name,
                startWeek: s.startWeek,
                endWeek: s.endWeek,
                weekType: s.weekType,
                customWeeks: List.of(s.customWeeks),
              );
            }
          }
        }
      }
      // 合并后的 sessions 放入第一个周次分组
      target.weekGroups.first.sessions = _mergeAdjacentSessions(
        deduped.values.toList(),
      );

      // 移除其余同名组（从后往前避免索引错乱）。
      final Set<int> toRemoveSet = {};
      for (int k = 1; k < indices.length; k++) {
        toRemoveSet.add(indices[k]);
      }
      if (toRemoveSet.isNotEmpty) {
        for (int r = _classroomGroups.length - 1; r >= 0; r--) {
          if (toRemoveSet.contains(r)) {
            _classroomGroups.removeAt(r);
          }
        }
      }
    }
  }

  /// 简短星期名称（如"周一"）。
  String _weekdayToShortString(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (weekday >= 1 && weekday <= 7) return weekdays[weekday - 1];
    return '';
  }

  /// 为指定教室组添加一个周次分组（上课周数段）。
  void _addWeekGroupToClassroom(int groupIndex) {
    final group = _classroomGroups[groupIndex];
    final newWeekGroup = _WeekGroup(
      startWeek: 0, // 新周次分组默认未配置
      endWeek: 0,
      weekType: CourseWeekType.all,
    );
    final insertIndex = group.weekGroups.length;
    group.weekGroups.add(newWeekGroup);
    _getWeekGroupListKey(groupIndex).currentState?.insertItem(insertIndex);
    setState(() {
      _pickerResetVersion++;
    });
  }

  /// 删除指定教室组中指定索引的周次分组（至少保留一个）。
  /// [groupIndex] 教室组索引，[weekGroupIndex] 要删除的周次分组在该教室组内的索引。
  void _removeWeekGroupFromClassroom(int groupIndex, int weekGroupIndex) {
    final group = _classroomGroups[groupIndex];
    if (group.weekGroups.length <= 1) {
      AppToast.show(context, '至少保留一个上课周数段', variant: AppToastVariant.warning);
      return;
    }
    if (weekGroupIndex < 0 || weekGroupIndex >= group.weekGroups.length) return;
    // 在 removeAt 前捕获数据快照及按钮显示状态，供删除动画使用（动画异步执行时数据已移除）
    final removedGroup = group.weekGroups[weekGroupIndex];
    final isOnly = group.weekGroups.length == 1;
    final isLast = weekGroupIndex == group.weekGroups.length - 1;
    _getWeekGroupListKey(groupIndex).currentState?.removeItem(
      weekGroupIndex,
      (context, animation) =>
          _buildRemovingWeekGroupBlock(removedGroup, isOnly, isLast, animation),
      duration: const Duration(milliseconds: 250),
    );
    group.weekGroups.removeAt(weekGroupIndex);
    setState(() {
      if (_expandedClassroomIndex == groupIndex) {
        if (_expandedWeekGroupIndex != null) {
          if (_expandedWeekGroupIndex == weekGroupIndex) {
            // 删除了当前展开的周次分组，重置展开状态
            _expandedWeekGroupIndex = null;
            _expandedSessionIndex = null;
          } else if (_expandedWeekGroupIndex! > weekGroupIndex) {
            // 删除了展开项前面的分组，索引需减一
            _expandedWeekGroupIndex = _expandedWeekGroupIndex! - 1;
          }
        }
      }
      _pickerResetVersion++;
    });
  }

  /// 为指定周次分组内的指定时段索引添加一个新时段（由 AnimatedSize 提供过渡动画）。
  ///
  /// 新增时段后延迟短暂时间再自动展开，让 AnimatedSize 尺寸过渡先完成，
  /// 再触发 ExpandableItem 的 AnimatedCrossFade 展开动画，避免两个动画冲突。
  void _addSessionToWeekGroup(int groupIndex, int weekGroupIndex) {
    final group = _classroomGroups[groupIndex];
    if (weekGroupIndex >= group.weekGroups.length) return;
    final targetWeekGroup = group.weekGroups[weekGroupIndex];
    final next = _findNextAvailableSlotForWeekGroup(group, targetWeekGroup);
    if (next == null) {
      AppToast.show(
        context,
        '当前所有教学时段均已排满，无法继续添加新时段！',
        variant: AppToastVariant.warning,
      );
      return;
    }
    final added = CourseSession(
      weekday: next.weekday,
      startSection: next.startSection,
      sectionCount: next.sectionCount,
      location: group.name,
      startWeek: targetWeekGroup.startWeek,
      endWeek: targetWeekGroup.endWeek,
      weekType: targetWeekGroup.weekType,
      customWeeks: List.of(targetWeekGroup.customWeeks),
    );
    final insertIndex = targetWeekGroup.sessions.length;
    setState(() {
      targetWeekGroup.sessions.add(added);
      _expandedClassroomIndex = groupIndex;
      _expandedWeekGroupIndex = weekGroupIndex;
      _pickerResetVersion++;
      // 延迟展开，让 AnimatedSize 插入过渡先完成（250ms），再触发 ExpandableItem 展开动画
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _expandedSessionIndex = insertIndex;
            _pickerResetVersion++;
          });
        }
      });
    });
  }

  /// 删除指定周次分组内的最后一个时段（由 AnimatedSize 提供过渡动画）。
  void _removeSessionFromWeekGroup(int groupIndex, int weekGroupIndex) {
    final group = _classroomGroups[groupIndex];
    if (weekGroupIndex >= group.weekGroups.length) return;
    final weekGroup = group.weekGroups[weekGroupIndex];
    if (weekGroup.sessions.isEmpty) return;
    setState(() {
      weekGroup.sessions.removeLast();
      if (_expandedClassroomIndex == groupIndex &&
          _expandedWeekGroupIndex == weekGroupIndex) {
        if (_expandedSessionIndex != null &&
            _expandedSessionIndex! >= weekGroup.sessions.length) {
          _expandedSessionIndex = null;
        }
      }
      _pickerResetVersion++;
    });
  }

  // 时段更新与智能拆分合并（per-group）

  void _updateSession(
    int groupIndex,
    int weekGroupIndex,
    int sessionIndex,
    CourseSession newSession,
  ) {
    final weekGroup = _classroomGroups[groupIndex].weekGroups[weekGroupIndex];
    setState(() {
      weekGroup.sessions[sessionIndex] = newSession;
    });

    // 防抖处理
    final timerKey = groupIndex * 10000 + weekGroupIndex * 100 + sessionIndex;
    _debounceTimers[timerKey]?.cancel();
    _debounceTimers[timerKey] = Timer(const Duration(milliseconds: 800), () {
      _smartSplitAndMerge(groupIndex, weekGroupIndex, sessionIndex);
      _debounceTimers.remove(timerKey);
    });
  }

  void _smartSplitAndMerge(
    int groupIndex,
    int weekGroupIndex,
    int sessionIndex,
  ) {
    if (!mounted || groupIndex >= _classroomGroups.length) return;
    final group = _classroomGroups[groupIndex];
    if (weekGroupIndex >= group.weekGroups.length) return;
    final weekGroup = group.weekGroups[weekGroupIndex];
    if (sessionIndex >= weekGroup.sessions.length) return;

    var updatedSession = weekGroup.sessions[sessionIndex];

    // 归一化处理
    final currentEnd =
        updatedSession.startSection + updatedSession.sectionCount - 1;
    if (currentEnd < updatedSession.startSection) {
      final newStart = currentEnd;
      final newEnd = updatedSession.startSection;
      final newCount = newEnd - newStart + 1;
      updatedSession = CourseSession(
        weekday: updatedSession.weekday,
        startSection: newStart,
        sectionCount: newCount,
        location: updatedSession.location,
        startWeek: updatedSession.startWeek,
        endWeek: updatedSession.endWeek,
        weekType: updatedSession.weekType,
        customWeeks: updatedSession.customWeeks,
      );
    }

    setState(() {
      _pickerResetVersion++;

      final List<CourseSession> keptSessions = [];
      for (int i = 0; i < weekGroup.sessions.length; i++) {
        if (i == sessionIndex) continue;
        final s = weekGroup.sessions[i];
        if (s.weekday != updatedSession.weekday) {
          keptSessions.add(s);
          continue;
        }
        final sEnd = s.startSection + s.sectionCount - 1;
        final uEnd =
            updatedSession.startSection + updatedSession.sectionCount - 1;
        final bool isOverlapping =
            s.startSection <= uEnd && sEnd >= updatedSession.startSection;
        if (!isOverlapping) {
          keptSessions.add(s);
        }
      }

      List<CourseSession> splits = _calculateSplits(updatedSession);
      weekGroup.sessions = _mergeAdjacentSessions([...keptSessions, ...splits]);

      final newIndex = weekGroup.sessions.indexWhere(
        (s) =>
            s.weekday == updatedSession.weekday &&
            s.startSection == updatedSession.startSection,
      );
      _expandedSessionIndex = newIndex != -1 ? newIndex : null;
      if (_expandedSessionIndex == null && weekGroup.sessions.isEmpty) {
        _expandedWeekGroupIndex = null;
      }
    });
  }

  List<CourseSession> _calculateSplits(CourseSession session) {
    if (_scheduleConfig == null) return [session];

    List<CourseSession> splits = [];
    int currentStart = session.startSection;
    int sessionEnd = currentStart + session.sectionCount - 1;

    int segStart = 1;
    for (var segment in _scheduleConfig!.segments) {
      int segEnd = segStart + segment.classCount - 1;

      if (currentStart <= segEnd && sessionEnd >= segStart) {
        int overlapStart = max(currentStart, segStart);
        int overlapEnd = min(sessionEnd, segEnd);
        int overlapCount = overlapEnd - overlapStart + 1;

        if (overlapCount > 0) {
          splits.add(
            CourseSession(
              weekday: session.weekday,
              startSection: overlapStart,
              sectionCount: overlapCount,
              location: session.location,
              startWeek: session.startWeek,
              endWeek: session.endWeek,
              weekType: session.weekType,
              customWeeks: session.customWeeks,
            ),
          );
        }
      }
      segStart += segment.classCount;
    }

    if (splits.isEmpty) splits.add(session);
    return splits;
  }

  /// 为指定周次分组查找下一个可用时段。
  ({int weekday, int startSection, int sectionCount})?
  _findNextAvailableSlotForWeekGroup(
    _ClassroomGroup group,
    _WeekGroup weekGroup,
  ) {
    final Map<int, List<({int start, int end})>> occupied =
        <int, List<({int start, int end})>>{};
    for (final CourseSession s in weekGroup.sessions) {
      occupied.putIfAbsent(s.weekday, () => <({int start, int end})>[]);
      occupied[s.weekday]!.add((
        start: s.startSection,
        end: s.startSection + s.sectionCount - 1,
      ));
    }

    final List<({int start, int end, int classCount})> segmentRanges =
        <({int start, int end, int classCount})>[];
    if (_scheduleConfig != null) {
      int segStart = 1;
      for (final seg in _scheduleConfig!.segments) {
        final int segEnd = segStart + seg.classCount - 1;
        segmentRanges.add((
          start: segStart,
          end: segEnd,
          classCount: seg.classCount,
        ));
        segStart += seg.classCount;
      }
    }
    if (segmentRanges.isEmpty) {
      segmentRanges.add((
        start: 1,
        end: _totalSections,
        classCount: _totalSections,
      ));
    }

    final List<({int start, int count})> daySlotTemplate =
        <({int start, int count})>[];
    for (final seg in segmentRanges) {
      daySlotTemplate.addAll(_computeSegmentSlots(seg.start, seg.classCount));
    }
    if (daySlotTemplate.isEmpty) {
      daySlotTemplate.add((start: 1, count: 2));
    }

    int startDay = 1;
    int anchorStart = 1;
    int anchorEnd = 1;
    if (weekGroup.sessions.isNotEmpty) {
      startDay = weekGroup.sessions.last.weekday;
      anchorStart = weekGroup.sessions.last.startSection;
      anchorEnd = anchorStart + weekGroup.sessions.last.sectionCount - 1;
    }

    int startSlotIndex = 0;
    if (weekGroup.sessions.isNotEmpty) {
      for (int i = 0; i < daySlotTemplate.length; i++) {
        final slot = daySlotTemplate[i];
        final int slotEnd = slot.start + slot.count - 1;
        if (anchorStart <= slotEnd && anchorEnd >= slot.start) {
          startSlotIndex = i + 1;
          break;
        }
        if (anchorEnd < slot.start) {
          startSlotIndex = i;
          break;
        }
      }
      if (startSlotIndex >= daySlotTemplate.length) {
        startSlotIndex = 0;
      }
    }

    bool canUseSlot(int weekday, ({int start, int count}) slot) {
      final List<({int start, int end})> daySlots =
          occupied[weekday] ?? <({int start, int end})>[];
      return !daySlots.any(
        (({int start, int end}) s) =>
            slot.start <= s.end && slot.start + slot.count - 1 >= s.start,
      );
    }

    for (int i = startSlotIndex; i < daySlotTemplate.length; i++) {
      final slot = daySlotTemplate[i];
      if (canUseSlot(startDay, slot)) {
        return (
          weekday: startDay,
          startSection: slot.start,
          sectionCount: slot.count,
        );
      }
    }

    for (int d = 1; d < 7; d++) {
      final int weekday = (startDay - 1 + d) % 7 + 1;
      for (final slot in daySlotTemplate) {
        if (canUseSlot(weekday, slot)) {
          return (
            weekday: weekday,
            startSection: slot.start,
            sectionCount: slot.count,
          );
        }
      }
    }

    return null;
  }

  /// 将时段按规则切分为槽位。
  static List<({int start, int count})> _computeSegmentSlots(
    int segStart,
    int classCount,
  ) {
    final List<({int start, int count})> slots = <({int start, int count})>[];
    int pos = segStart;
    int remaining = classCount;
    while (remaining > 0) {
      if (remaining <= 3) {
        slots.add((start: pos, count: remaining));
        break;
      }
      slots.add((start: pos, count: 2));
      pos += 2;
      remaining -= 2;
    }
    return slots;
  }

  /// 合并同一天相邻或重叠的会话。
  List<CourseSession> _mergeAdjacentSessions(List<CourseSession> source) {
    if (source.length <= 1) return source;

    final List<CourseSession> sorted = <CourseSession>[...source]
      ..sort((a, b) {
        if (a.weekday != b.weekday) return a.weekday.compareTo(b.weekday);
        return a.startSection.compareTo(b.startSection);
      });

    final List<CourseSession> merged = <CourseSession>[];
    for (final CourseSession current in sorted) {
      if (merged.isEmpty) {
        merged.add(current);
        continue;
      }

      final CourseSession last = merged.last;
      final int lastEnd = last.startSection + last.sectionCount - 1;
      final int currentEnd = current.startSection + current.sectionCount - 1;

      final bool canMergeByRange =
          current.weekday == last.weekday &&
          current.startSection <= lastEnd + 1;
      final bool sameWeekRule = _hasSameWeekRule(last, current);
      final bool canMergeLocation = _canMergeLocation(
        last.location,
        current.location,
      );

      if (!canMergeByRange || !sameWeekRule || !canMergeLocation) {
        merged.add(current);
        continue;
      }

      final int newStart = min(last.startSection, current.startSection);
      final int newEnd = max(lastEnd, currentEnd);
      final CourseSession candidate = CourseSession(
        weekday: last.weekday,
        startSection: newStart,
        sectionCount: newEnd - newStart + 1,
        location: _mergeLocation(last.location, current.location),
        startWeek: last.startWeek,
        endWeek: last.endWeek,
        weekType: last.weekType,
        customWeeks: last.customWeeks,
      );

      if (_isCrossSegment(candidate)) {
        merged.add(current);
        continue;
      }

      merged[merged.length - 1] = candidate;
    }

    return merged;
  }

  bool _hasSameWeekRule(CourseSession a, CourseSession b) {
    if (a.startWeek != b.startWeek ||
        a.endWeek != b.endWeek ||
        a.weekType != b.weekType) {
      return false;
    }
    final Set<int> customA = a.customWeeks.toSet();
    final Set<int> customB = b.customWeeks.toSet();
    return customA.length == customB.length && customA.containsAll(customB);
  }

  bool _canMergeLocation(String a, String b) {
    final String locationA = a.trim();
    final String locationB = b.trim();
    return locationA.isEmpty || locationB.isEmpty || locationA == locationB;
  }

  String _mergeLocation(String a, String b) {
    final String locationA = a.trim();
    final String locationB = b.trim();
    if (locationA.isNotEmpty) return locationA;
    return locationB;
  }

  // 颜色管理

  Future<void> _showColorExhaustedDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final String? action = prefs.getString('course_color_exhausted_action');

    bool? addNew;

    if (action == 'new') {
      addNew = true;
    } else if (action == 'reuse') {
      addNew = false;
    } else {
      addNew = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('课程颜色分配'),
          content: const Text('所有颜色均已被使用，您希望如何处理？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('智能复用'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('自动新增'),
            ),
          ],
        ),
      );

      if (addNew != null && mounted) {
        final bool? remember = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('记住选择'),
            content: const Text('是否记住此选择，下次不再询问？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('每次提醒'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('不再提醒'),
              ),
            ],
          ),
        );

        if (remember == true) {
          await prefs.setString(
            'course_color_exhausted_action',
            addNew ? 'new' : 'reuse',
          );
        }
      }
    }

    if (addNew == true) {
      final Color newColor = _generateRandomColor();
      _temporaryAutoColor = newColor;
      _addCustomColor(newColor, save: false);
      setState(() {
        _initialSmartColor = newColor;
        _selectedColor = newColor;
      });
    }
  }

  Color _generateRandomColor() {
    final random = Random();
    int attempts = 0;
    Color bestColor = Colors.white;
    double maxMinDistance = -1.0;

    final allColors = [..._presetColors, ..._customColors];

    while (attempts < 20) {
      final hsv = HSVColor.fromAHSV(
        1.0,
        random.nextDouble() * 360,
        0.3 + random.nextDouble() * 0.2,
        0.85 + random.nextDouble() * 0.1,
      );
      final candidate = hsv.toColor();

      if (allColors.isEmpty) return candidate;

      double minDistance = double.infinity;
      for (final existing in allColors) {
        final distance = _calculateColorDistance(candidate, existing);
        if (distance < minDistance) {
          minDistance = distance;
        }
      }

      if (minDistance > maxMinDistance) {
        maxMinDistance = minDistance;
        bestColor = candidate;
      }

      if (minDistance > 45) return candidate;

      attempts++;
    }

    return bestColor;
  }

  double _calculateColorDistance(Color c1, Color c2) {
    final rDiff = (c1.r - c2.r) * 255;
    final gDiff = (c1.g - c2.g) * 255;
    final bDiff = (c1.b - c2.b) * 255;
    return sqrt(rDiff * rDiff + gDiff * gDiff + bDiff * bDiff);
  }

  @override
  void dispose() {
    if (widget.course != null) {
      _openEditingCourses.remove(widget.course);
    }
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    AppToast.dismiss();
    _nameController.dispose();
    _teacherController.dispose();
    super.dispose();
  }

  /// 判断某个课程编辑页是否已经打开。
  static bool isEditingCourseOpen(Course course) {
    return _openEditingCourses.contains(course);
  }

  Future<void> _loadCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? colors = prefs.getStringList('custom_course_colors');
    if (colors != null) {
      setState(() {
        _customColors = colors
            .map((c) => colorFromARGB32(int.parse(c)))
            .toList();
      });
    }
  }

  Future<void> _saveCustomColors() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String> colors = _customColors
        .where((c) => c != _temporaryAutoColor)
        .map((c) => c.toARGB32().toString())
        .toList();
    await prefs.setStringList('custom_course_colors', colors);
  }

  void _addCustomColor(Color color, {bool save = true}) {
    if (!_customColors.contains(color) && !_presetColors.contains(color)) {
      setState(() {
        _customColors.add(color);
      });
      if (save) _saveCustomColors();
    }
  }

  void _removeCustomColor(Color color) {
    if (mounted) {
      setState(() {
        _customColors.remove(color);
      });
    } else {
      _customColors.remove(color);
    }
    _saveCustomColors();
  }

  /// 检查 sortedWeeks 是否恰好等于指定类型的全学期周次。
  static bool _isFullRangeWeeks(
    List<int> sorted,
    int minWeek,
    int maxWeek,
    CourseWeekType type,
  ) {
    final List<int> expected = [];
    for (int i = minWeek; i <= maxWeek; i++) {
      if (type == CourseWeekType.all ||
          (type == CourseWeekType.single && i.isOdd) ||
          (type == CourseWeekType.double && i.isEven)) {
        expected.add(i);
      }
    }
    if (expected.length != sorted.length) return false;
    for (int i = 0; i < sorted.length; i++) {
      if (sorted[i] != expected[i]) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      AppToast.show(context, '请输入「 课程名称 」', variant: AppToastVariant.warning);
      return;
    }

    _temporaryAutoColor = null;
    await _saveCustomColors();

    if (!mounted) return;

    // 不再自动合并同名教室组，改为弹窗让用户逐项勾选确认。
    // 检测是否存在同名且时间重叠的教室组，提示用户勾选需要合并的组。
    final mergeableGroups = _detectMergeableGroups();
    if (mergeableGroups.isNotEmpty && mounted) {
      final Set<int>? selected = await _showMergeConfirmDialog(
        context,
        mergeableGroups,
      );
      if (!mounted) return;
      if (selected != null && selected.isNotEmpty) {
        // 仅合并用户勾选的教室组簇。
        _mergeSelectedGroups(mergeableGroups, selected);
      }
    }

    final newCourse = Course(
      name: _nameController.text,
      teacher: _teacherController.text,
      color: _selectedColor,
      sessions: _buildResultSessions(),
    );

    // 检查与已有课程的重叠
    final overlaps = _checkCourseOverlaps(newCourse);
    if (overlaps.isNotEmpty && mounted) {
      final result = await showDialog(
        context: context,
        builder: (ctx) => _buildOverlapDialog(ctx, overlaps),
      );
      if (result == null || !mounted) return;
      if (result is bool && !result) return;
    }

    // 直接写回课程服务，保证当前页面点击“完成”后课表立即同步，
    // 不再完全依赖父页面继续处理返回结果。
    await _persistCurrentDraftIntoService();
    if (!mounted) return;

    Navigator.of(context).pop(
      CourseEditResult.save(course: newCourse, previousCourse: widget.course),
    );
  }

  /// 检查新课程与已有课程的重叠，返回按冲突课程分组的列表。
  List<_CourseOverlapGroup> _checkCourseOverlaps(Course newCourse) {
    final existing = widget.course != null
        ? _existingCourses.where((c) => c != widget.course).toList()
        : _existingCourses;

    // 按冲突课程分组
    final Map<String, _CourseOverlapGroup> groups = {};
    for (final newS in newCourse.sessions) {
      for (final existC in existing) {
        final entries = <_OverlapEntry>[];
        for (final existS in existC.sessions) {
          if (newS.weekday != existS.weekday) {
            continue;
          }
          final newEnd = newS.startSection + newS.sectionCount - 1;
          final existEnd = existS.startSection + existS.sectionCount - 1;
          if (newS.startSection > existEnd || newEnd < existS.startSection) {
            continue;
          }

          final newWeeks = _resolveSessionWeeks(newS);
          final existWeeks = _resolveSessionWeeks(existS);
          final overlapWeeks = newWeeks.intersection(existWeeks);
          if (overlapWeeks.isEmpty) {
            continue;
          }

          final weekdayStr = _weekdayToFullString(newS.weekday);
          final sectionStr = newS.sectionCount == 1
              ? '第${newS.startSection}节'
              : '第${newS.startSection}-$newEnd节';
          final sortedOverlapWeeks = overlapWeeks.toList()..sort();

          entries.add(
            _OverlapEntry(
              timeLabel: '$weekdayStr $sectionStr',
              overlapWeeks: sortedOverlapWeeks,
            ),
          );
        }
        if (entries.isNotEmpty) {
          final key = existC.name;
          groups.putIfAbsent(
            key,
            () => _CourseOverlapGroup(
              existingCourse: existC,
              newCourseName: newCourse.name,
              newCourseColor: newCourse.color,
              entries: [],
            ),
          );
          groups[key]!.entries.addAll(entries);
        }
      }
    }
    return groups.values.toList();
  }

  /// 完整星期名称（如"周一"）。
  String _weekdayToFullString(int weekday) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    if (weekday >= 1 && weekday <= 7) return weekdays[weekday - 1];
    return '';
  }

  /// 构建重叠提示对话框。
  Widget _buildOverlapDialog(
    BuildContext ctx,
    List<_CourseOverlapGroup> groups,
  ) {
    final cs = Theme.of(ctx).colorScheme;
    return AlertDialog(
      title: const Text('课程时间冲突'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final group in groups) ...[
              // 课程名行：课程A（可点→信息），课程B（可点→跳转）
              _buildConflictTitleRow(ctx, group),
              const SizedBox(height: 8),
              for (final entry in group.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 时段标签行
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurfaceVariant,
                          ),
                          children: [
                            const TextSpan(
                              text: '· ',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            TextSpan(
                              text: '「${entry.timeLabel}」在',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 周次标签行（灰色底）
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: [
                            for (final week in entry.overlapWeeks)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '第$week周',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (groups.indexOf(group) < groups.length - 1)
                const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('仍要保存'),
        ),
      ],
    );
  }

  /// 深色模式下课程颜色的适配色。
  Color _dimCourseColor(Color color) {
    return Theme.of(context).brightness == Brightness.dark
        ? dimColorForDark(color)
        : color;
  }

  /// 构建冲突标题行：课程A 可点击（提示已在编辑页），课程B 可点击（跳转编辑）。
  Widget _buildConflictTitleRow(BuildContext ctx, _CourseOverlapGroup group) {
    final cs = Theme.of(ctx).colorScheme;
    final isNew = widget.course == null;
    final pageLabel = isNew ? '新建页面' : '编辑页面';
    const linkColor = Color(0xFF1565C0); // 链接蓝
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        // 课程A
        GestureDetector(
          onTap: () => _showSelfInfoDialog(
            ctx,
            group.newCourseName,
            group.newCourseColor,
            pageLabel,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _dimCourseColor(group.newCourseColor),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                group.newCourseName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: linkColor,
                ),
              ),
            ],
          ),
        ),
        Text(' 与 ', style: TextStyle(fontSize: 16, color: cs.onSurface)),
        // 课程B
        GestureDetector(
          onTap: () => _showJumpToCourseDialog(ctx, group.existingCourse),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _dimCourseColor(group.existingCourse.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                group.existingCourse.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: linkColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 弹窗：当前已在目标课程的编辑页面。
  Future<void> _showSelfInfoDialog(
    BuildContext ctx,
    String courseName,
    Color courseColor,
    String pageLabel,
  ) async {
    final cs = Theme.of(ctx).colorScheme;
    await showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('跳转到冲突课程'),
        content: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            children: [
              const TextSpan(text: '所在位置已经是 '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _dimCourseColor(courseColor),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: courseName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' 的 '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    pageLabel,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              const TextSpan(text: ' 。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  /// 弹窗：确认跳转到冲突课程的编辑页面。
  Future<void> _showJumpToCourseDialog(
    BuildContext ctx,
    Course targetCourse,
  ) async {
    final cs = Theme.of(ctx).colorScheme;
    final confirm = await showDialog<bool>(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text('跳转到冲突课程'),
        content: RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            children: [
              const TextSpan(text: '是否跳转到 '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: _dimCourseColor(targetCourse.color),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              const TextSpan(text: ' '),
              TextSpan(
                text: targetCourse.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const TextSpan(text: ' 的 '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '编辑页面',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              const TextSpan(text: ' ？'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('跳转'),
          ),
        ],
      ),
    );
    if (confirm == true && ctx.mounted) {
      // 先关闭确认弹窗，再关闭冲突弹窗
      Navigator.pop(ctx, false); // 取消保存
      if (!mounted) return;
      final NavigatorState navigator = Navigator.of(context);
      if (_CourseEditPageState.isEditingCourseOpen(targetCourse)) {
        navigator.popUntil(
          (Route<dynamic> route) =>
              identical(route.settings.arguments, targetCourse),
        );
        return;
      }

      // 在当前编辑页之上弹出目标课程的编辑页
      final Object? editResult = await navigator.push(
        MaterialPageRoute(
          settings: RouteSettings(arguments: targetCourse),
          builder: (_) => CourseEditPage(
            course: targetCourse,
            existingCourses: _existingCourses,
            maxWeek: widget.maxWeek,
            scheduleConfig: _scheduleConfig,
          ),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;

      if (editResult is CourseEditResult && editResult.isSave) {
        // 子编辑页保存成功后，立即同步本地课程快照，确保当前页重新检查冲突时使用新数据。
        setState(() {
          _syncExistingCourseSnapshot(targetCourse, editResult.course);
        });
        await _persistCurrentDraftIntoService();
      } else if (editResult is CourseEditResult && editResult.isDelete) {
        setState(() {
          _syncExistingCourseSnapshot(targetCourse, null);
        });
        await _persistCurrentDraftIntoService();
      }
    }
  }

  /// 为指定教室组的指定周次分组选择上课周数。
  Future<void> _pickWeeksForWeekGroup(
    int groupIndex,
    int weekGroupIndex,
  ) async {
    final group = _classroomGroups[groupIndex];
    final weekGroup = group.weekGroups[weekGroupIndex];
    final disabledWeeks = _getOtherGroupsWeeks(groupIndex);

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _WeekRangePicker(
        initialStart: weekGroup.startWeek,
        initialEnd: weekGroup.endWeek,
        initialType: weekGroup.weekType,
        initialCustomWeeks: weekGroup.customWeeks,
        maxWeek: widget.maxWeek,
        disabledWeeks: disabledWeeks,
      ),
    );

    if (result != null) {
      setState(() {
        weekGroup.startWeek = result['start'] as int;
        weekGroup.endWeek = result['end'] as int;
        weekGroup.weekType = result['type'] as CourseWeekType;
        weekGroup.customWeeks = result['customWeeks'] as List<int>;
        // 同步更新当前分组下各时段的周次信息，确保后续逻辑读取一致。
        weekGroup.sessions = weekGroup.sessions
            .map(
              (CourseSession s) => CourseSession(
                weekday: s.weekday,
                startSection: s.startSection,
                sectionCount: s.sectionCount,
                location: s.location,
                startWeek: weekGroup.startWeek,
                endWeek: weekGroup.endWeek,
                weekType: weekGroup.weekType,
                customWeeks: List<int>.of(weekGroup.customWeeks),
              ),
            )
            .toList();
        // 选择周次后按周排序教室
        _sortClassroomGroups();
      });
    }
  }

  /// 为指定教室组的周次分组选择上课周数（旧版兼容，默认选最后一个周次分组）。
  Future<void> _pickWeeksForGroup(int groupIndex) async {
    final group = _classroomGroups[groupIndex];
    // 确保有至少一个周次分组
    if (group.weekGroups.isEmpty) {
      group.weekGroups.add(
        _WeekGroup(startWeek: 0, endWeek: 0, weekType: CourseWeekType.all),
      );
    }
    await _pickWeeksForWeekGroup(groupIndex, group.weekGroups.length - 1);
  }

  /// 将已保存的课程同步回本地快照，供后续冲突检查使用。
  void _syncExistingCourseSnapshot(Course oldCourse, Course? newCourse) {
    final int index = _existingCourses.indexOf(oldCourse);
    if (index == -1) {
      return;
    }
    if (newCourse == null) {
      _existingCourses.removeAt(index);
      return;
    }
    _existingCourses[index] = newCourse;
  }

  /// 生成当前页面正在编辑的课程草稿。
  Course _buildCurrentDraftCourse() {
    return Course(
      name: _nameController.text,
      teacher: _teacherController.text,
      color: _selectedColor,
      sessions: _buildResultSessions(),
    );
  }

  /// 基于当前页面状态生成待保存的课程时段列表。
  List<CourseSession> _buildResultSessions() {
    final List<CourseSession> allSessions = <CourseSession>[];
    final int defaultStartWeek = 1;
    final int defaultEndWeek = widget.maxWeek;

    for (final group in _classroomGroups) {
      for (final wg in group.weekGroups) {
        for (final s in wg.sessions) {
          final bool isUnconfigured =
              wg.startWeek == 0 && wg.endWeek == 0 && wg.customWeeks.isEmpty;
          final int startWeek = (widget.course == null && isUnconfigured)
              ? defaultStartWeek
              : wg.startWeek;
          final int endWeek = (widget.course == null && isUnconfigured)
              ? defaultEndWeek
              : wg.endWeek;
          allSessions.add(
            CourseSession(
              weekday: s.weekday,
              startSection: s.startSection,
              sectionCount: s.sectionCount,
              location: group.name,
              startWeek: startWeek,
              endWeek: endWeek,
              weekType: wg.weekType,
              customWeeks: List<int>.of(wg.customWeeks),
            ),
          );
        }
      }
    }

    return allSessions;
  }

  /// 将当前草稿与本地课程快照合并并立即写回服务层。
  Future<void> _persistCurrentDraftIntoService() async {
    final Course currentDraft = _buildCurrentDraftCourse();
    final List<Course> mergedCourses = List<Course>.of(_existingCourses);

    if (widget.course != null) {
      final int currentIndex = mergedCourses.indexOf(widget.course!);
      if (currentIndex != -1) {
        mergedCourses[currentIndex] = currentDraft;
      } else {
        mergedCourses.add(currentDraft);
      }
    } else {
      mergedCourses.add(currentDraft);
    }

    await CourseService.instance.saveCourses(mergedCourses);
  }

  // 颜色选择弹窗

  Future<void> _pickColor() async {
    final result = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ColorPickerSheet(
        selectedColor: _selectedColor,
        colors: _presetColors,
        customColors: _customColors,
        existingCourses: _existingCourses,
        onAddCustomColor: _addCustomColor,
        onDeleteCustomColor: _removeCustomColor,
      ),
    );

    if (result != null) {
      setState(() {
        _selectedColor = result;
        _initialSmartColor = result;
      });
    }
  }

  // UI 构建

  @override
  Widget build(BuildContext context) {
    // 计算总上课周数预览文本
    final totalWeeks = _totalEffectiveWeeks;
    final String totalWeeksText = _formatWeeksSet(totalWeeks);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.course == null ? '新建课程' : '编辑课程',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 17,
          ),
        ),
        leading: TextButton(
          onPressed: () {
            // 键盘弹起时先收起键盘，再次点击才返回
            final hasKeyboard = MediaQuery.of(context).viewInsets.bottom > 0;
            if (hasKeyboard) {
              FocusScope.of(context).unfocus();
            } else {
              Navigator.of(context).pop();
            }
          },
          child: Text(
            '取消',
            style: TextStyle(
              fontSize: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        leadingWidth: 70,
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              '完成',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // 课程名
          _buildCourseNameBlock(),
          const SizedBox(height: 12),
          // 备注（如老师）
          _buildTeacherBlock(),
          const SizedBox(height: 12),
          // 课程背景色（置于备注下方）
          _buildColorItem(),
          const SizedBox(height: 24),
          // 教室管理块 + 总上课周数预览
          _buildClassroomManagementBlock(totalWeeksText),
          const SizedBox(height: 12),
          // 每个教室组块（带过渡动画）
          _buildAnimatedClassroomList(),
          const SizedBox(height: 100),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: widget.course != null
          ? SizedBox(
              width: MediaQuery.of(context).size.width - 96,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildDeleteButton(),
              ),
            )
          : null,
    );
  }

  // 课程名块

  Widget _buildCourseNameBlock() {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    '课程名',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    textAlign: TextAlign.left,
                    decoration: const InputDecoration(
                      filled: false,
                      hintText: '必填',
                      hintStyle: TextStyle(color: Color(0xFFC4C4C6)),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            child: Column(
              children: [
                if (_suggestions.isNotEmpty) ...[
                  Divider(
                    height: 1,
                    indent: 16,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                  ..._suggestions.map(_buildSuggestionItem),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 备注块（备注在第一行，(如老师) 在第二行）

  Widget _buildTeacherBlock() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '备注',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  '(如老师)',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TextField(
              controller: _teacherController,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                filled: false,
                hintText: '非必填',
                hintStyle: const TextStyle(color: Color(0xFFC4C4C6)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 教室管理块（第一行：教室 -/+，第二行：总上课周数预览）

  Widget _buildClassroomManagementBlock(String totalWeeksText) {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // 第一行：教室 -/+
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '教室',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCounterButton(
                        icon: FontAwesomeIcons.minus,
                        onTap: _removeClassroomGroup,
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${_classroomGroups.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      _buildCounterButton(
                        icon: FontAwesomeIcons.plus,
                        onTap: _addClassroomGroup,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // 第二行：上课周数 预览（渐变背景，无横线分隔）
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: LinearGradient(
                begin: Alignment.centerRight,
                end: Alignment.centerLeft,
                stops: const <double>[0.0, 1.0],
                colors: <Color>[
                  Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF7C818A)
                      : const Color(0xFFE2E4E8),
                  Theme.of(context).cardTheme.color ??
                      Theme.of(context).colorScheme.surface,
                ],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '上课周数',
                    style: TextStyle(
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Expanded(
                    child: _buildAutoWeekLabel(
                      totalWeeksText,
                      color: Theme.of(context).colorScheme.outline,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 教室组块动画列表

  /// 构建带过渡动画的教室组列表。
  Widget _buildAnimatedClassroomList() {
    return AnimatedList(
      key: _classroomListKey,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: _classroomGroups.length,
      itemBuilder: (context, index, animation) {
        return _buildAnimatedClassroomBlock(index, animation);
      },
    );
  }

  /// 构建带动画的单个教室组块（用于正常显示）。
  Widget _buildAnimatedClassroomBlock(int index, Animation<double> animation) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: _buildClassroomGroupBlock(index),
      ),
    );
  }

  /// 构建正在被删除的教室组块（退出动画，使用快照数据保证内容与显示一致）。
  Widget _buildRemovingClassroomBlock(
    _ClassroomGroup group,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: _buildClassroomGroupSnapshot(group),
      ),
    );
  }

  /// 构建教室组静态快照（外观与 _buildClassroomGroupBlock 一致，但无交互元素）。
  Widget _buildClassroomGroupSnapshot(_ClassroomGroup group) {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 教室名（纯文本，非输入框）
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              group.name.isEmpty ? '教室名' : group.name,
              style: TextStyle(
                fontSize: 16,
                color: group.name.isEmpty
                    ? const Color(0xFFC4C4C6)
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          // 周次分组概览
          if (group.weekGroups.isNotEmpty)
            ...group.weekGroups.map((wg) => _buildWeekGroupSnapshot(wg)),
          // 无周次分组时显示"未配置"
          if (group.weekGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Flexible(child: _buildAutoWeekLabel('未配置')),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 构建单个教室组块（按周次分组组织时段显示，带动画过渡）。
  Widget _buildClassroomGroupBlock(int groupIndex) {
    final group = _classroomGroups[groupIndex];

    return Padding(
      padding: EdgeInsets.only(bottom: _classroomGroups.length > 1 ? 12 : 0),
      child: Container(
        decoration: BoxDecoration(
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            // 第一行：教室名输入
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: TextEditingController(text: group.name),
                onChanged: (value) {
                  group.name = value;
                },
                textAlign: TextAlign.left,
                decoration: const InputDecoration(
                  filled: false,
                  hintText: '教室名',
                  hintStyle: TextStyle(color: Color(0xFFC4C4C6)),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: TextStyle(
                  fontSize: 16,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            // 周次分组动画列表
            _buildAnimatedWeekGroupList(groupIndex),
            // 无周次分组时显示"未配置"占位行
            if (group.weekGroups.isEmpty) _buildEmptyWeekGroupRow(groupIndex),
          ],
        ),
      ),
    );
  }

  /// 构建周次分组动画列表。
  Widget _buildAnimatedWeekGroupList(int groupIndex) {
    final group = _classroomGroups[groupIndex];
    return AnimatedList(
      key: _getWeekGroupListKey(groupIndex),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      initialItemCount: group.weekGroups.length,
      itemBuilder: (context, index, animation) {
        return _buildAnimatedWeekGroupBlock(groupIndex, index, animation);
      },
    );
  }

  /// 构建带动画的单个周次分组块。
  Widget _buildAnimatedWeekGroupBlock(
    int groupIndex,
    int weekGroupIndex,
    Animation<double> animation,
  ) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: _buildWeekGroupBlock(groupIndex, weekGroupIndex),
      ),
    );
  }

  /// 构建正在被删除的周次分组块（退出动画，使用快照数据保证内容与显示一致）。
  Widget _buildRemovingWeekGroupBlock(
    _WeekGroup weekGroup,
    bool isOnly,
    bool isLast,
    Animation<double> animation,
  ) {
    // 按钮显示规则（与 _buildWeekGroupCounterButtons 一致）：
    // - 仅一个周次分组：只显示 +（但此处不会发生，因为至少保留一个的检查会阻止）
    // - 非最后一个：只显示 -   - 最后一个（且非唯一）：同时显示 - 和 +
    final showMinus = !isOnly;
    final showPlus = isLast;
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: _buildWeekGroupSnapshot(
          weekGroup,
          showMinus: showMinus,
          showPlus: showPlus,
        ),
      ),
    );
  }

  /// 构建周次分组静态快照（外观与 _buildWeekGroupBlock 一致，含按钮占位但无交互）。
  Widget _buildWeekGroupSnapshot(
    _WeekGroup weekGroup, {
    bool showMinus = true,
    bool showPlus = true,
  }) {
    final String weekText = _formatWeeksSet(weekGroup.effectiveWeeks);
    final bool hasNoSessions = !weekGroup.hasAnySession;
    final String displayText = weekText.isEmpty ? '未配置' : weekText;
    final iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 周数标签行（含按钮占位，与正常显示布局一致）
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 16, 4),
          child: Row(
            children: [
              // 与正常显示一致：Expanded 包裹 chevron + 间距 + 标签整个左侧区域
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: hasNoSessions
                          ? Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.4)
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: _buildAutoWeekLabel(
                        displayText,
                        color: hasNoSessions
                            ? Theme.of(context).colorScheme.outlineVariant
                                  .withValues(alpha: 0.4)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // 按钮占位容器（与 _buildWeekGroupCounterButtons 外观和显示规则一致）
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showMinus)
                      _buildButtonPlaceholder(
                        FontAwesomeIcons.minus,
                        iconColor,
                      ),
                    if (showPlus)
                      _buildButtonPlaceholder(FontAwesomeIcons.plus, iconColor),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 时段摘要行（含按钮占位，与正常显示布局一致）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '时段',
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildButtonPlaceholder(FontAwesomeIcons.minus, iconColor),
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${weekGroup.sessions.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    _buildButtonPlaceholder(FontAwesomeIcons.plus, iconColor),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 时段列表（只读标签）
        if (weekGroup.sessions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < weekGroup.sessions.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  Text(
                    '课程时间 ${i + 1}：周${_weekdayToString(weekGroup.sessions[i].weekday)} '
                    '${weekGroup.sessions[i].sectionCount == 1 ? '第 ${weekGroup.sessions[i].startSection} 节' : '第 ${weekGroup.sessions[i].startSection}-${weekGroup.sessions[i].startSection + weekGroup.sessions[i].sectionCount - 1} 节'}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  /// 构建按钮占位图标（外观与 _buildCounterButton 一致，无交互）。
  Widget _buildButtonPlaceholder(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      color: Colors.transparent,
      child: Icon(icon, size: 14, color: color),
    );
  }

  /// 构建课程时段项（由父级 AnimatedSize 提供尺寸过渡动画）。
  Widget _buildSessionItem(
    int groupIndex,
    int weekGroupIndex,
    int sessionIndex,
  ) {
    final sessions =
        _classroomGroups[groupIndex].weekGroups[weekGroupIndex].sessions;
    // 安全检查：防止列表数据与渲染索引不同步时的越界访问
    if (sessionIndex >= sessions.length) return const SizedBox.shrink();
    final session = sessions[sessionIndex];
    final isExpanded =
        _expandedClassroomIndex == groupIndex &&
        _expandedWeekGroupIndex == weekGroupIndex &&
        _expandedSessionIndex == sessionIndex;

    String timeText = '周${_weekdayToString(session.weekday)} ';
    if (session.sectionCount == 1) {
      timeText += '第 ${session.startSection} 节';
    } else {
      timeText +=
          '第 ${session.startSection}-${session.startSection + session.sectionCount - 1} 节';
    }

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: ExpandableItem(
        title: '课程时间 ${sessionIndex + 1}',
        value: Text(
          timeText,
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        isExpanded: isExpanded,
        onTap: () {
          setState(() {
            if (_expandedClassroomIndex == groupIndex &&
                _expandedWeekGroupIndex == weekGroupIndex &&
                _expandedSessionIndex == sessionIndex) {
              _expandedClassroomIndex = null;
              _expandedWeekGroupIndex = null;
              _expandedSessionIndex = null;
            } else {
              _expandedClassroomIndex = groupIndex;
              _expandedWeekGroupIndex = weekGroupIndex;
              _expandedSessionIndex = sessionIndex;
            }
          });
        },
        content: _buildInlineTimePicker(
          groupIndex,
          weekGroupIndex,
          sessionIndex,
        ),
        showDivider: false,
      ),
    );
  }

  /// 构建无周次分组时的"未配置"占位行（含 + 按钮以添加首个周次分组）。
  Widget _buildEmptyWeekGroupRow(int groupIndex) {
    final group = _classroomGroups[groupIndex];
    final hasNoSessions = !group.hasAnySession;
    final weekText = _formatWeeksSet(group.effectiveWeeks);
    // 当没有任何课程时段时，周数文字变灰
    final bool isGrayedOut = hasNoSessions;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: isGrayedOut
                  ? () {
                      // 未配置时段时点击提示需要先设置课程时间
                      AppToast.show(
                        context,
                        '需要先配置「 时段 」',
                        variant: AppToastVariant.info,
                      );
                    }
                  : () => _pickWeeksForGroup(groupIndex),
              child: Row(
                children: [
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: isGrayedOut
                        ? Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.4)
                        : Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: _buildAutoWeekLabel(
                      weekText.isEmpty ? '未配置' : weekText,
                      color: isGrayedOut
                          ? Theme.of(
                              context,
                            ).colorScheme.outlineVariant.withValues(alpha: 0.4)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // + 按钮：添加首个周次分组
          _buildCounterButton(
            icon: FontAwesomeIcons.plus,
            onTap: () => _addWeekGroupToClassroom(groupIndex),
          ),
        ],
      ),
    );
  }

  /// 构建周次分组的加减按钮，根据周次分组在列表中的位置动态显示。
  ///
  /// - 仅有一个周次分组时：只显示 + 按钮（新增上课周数）。
  /// - 非最后一个周次分组：只显示 - 按钮（删除该上课周数）。
  /// - 最后一个（且非唯一）周次分组：同时显示 - 和 + 按钮。
  Widget _buildWeekGroupCounterButtons(int groupIndex, int weekGroupIndex) {
    final group = _classroomGroups[groupIndex];
    final isOnly = group.weekGroups.length == 1;
    final isLast = weekGroupIndex == group.weekGroups.length - 1;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 仅有一个周次分组时不显示 - 按钮，其余情况均显示
          if (!isOnly)
            _buildCounterButton(
              icon: FontAwesomeIcons.minus,
              onTap: () =>
                  _removeWeekGroupFromClassroom(groupIndex, weekGroupIndex),
            ),
          // 非最后一个周次分组不显示 + 按钮，仅最后一个显示
          if (isLast)
            _buildCounterButton(
              icon: FontAwesomeIcons.plus,
              onTap: () => _addWeekGroupToClassroom(groupIndex),
            ),
        ],
      ),
    );
  }

  /// 构建单个周次分组块的内容。
  Widget _buildWeekGroupBlock(int groupIndex, int weekGroupIndex) {
    // 防御性检查：确保索引有效，防止 AnimatedList 与底层数据不同步时崩溃
    if (groupIndex < 0 || groupIndex >= _classroomGroups.length) {
      return const SizedBox.shrink();
    }
    final group = _classroomGroups[groupIndex];
    if (weekGroupIndex < 0 || weekGroupIndex >= group.weekGroups.length) {
      return const SizedBox.shrink();
    }
    final weekGroup = group.weekGroups[weekGroupIndex];
    String weekText = _formatWeeksSet(weekGroup.effectiveWeeks);
    final bool hasNoSessions = !weekGroup.hasAnySession;
    // 当该周次分组没有任何课程时段时，周数文字变灰
    bool isGrayedOut = hasNoSessions && weekGroup.effectiveWeeks.isEmpty;

    // 若为新建课程，且该周次分组为自动默认的 1..max 周且无时段，则视为未配置
    if (widget.course == null &&
        hasNoSessions &&
        weekGroup.startWeek == 1 &&
        weekGroup.endWeek == widget.maxWeek &&
        weekGroup.weekType == CourseWeekType.all &&
        weekGroup.customWeeks.isEmpty) {
      weekText = '未配置';
      isGrayedOut = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 上课周数行：周数标签 + > + -/+
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 3, 16, 4),
          child: Row(
            children: [
              // 周数标签（可点击选择周次，灰显时点击提示）
              Expanded(
                child: GestureDetector(
                  onTap: isGrayedOut
                      ? () {
                          AppToast.show(
                            context,
                            '需要先设置「 课程时间 」',
                            variant: AppToastVariant.info,
                          );
                        }
                      : () =>
                            _pickWeeksForWeekGroup(groupIndex, weekGroupIndex),
                  child: Row(
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: isGrayedOut
                            ? Theme.of(context).colorScheme.outlineVariant
                                  .withValues(alpha: 0.4)
                            : Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: _buildAutoWeekLabel(
                          weekText.isEmpty ? '未配置' : weekText,
                          color: isGrayedOut
                              ? Theme.of(context).colorScheme.outlineVariant
                                    .withValues(alpha: 0.4)
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // -/+ 按钮（控制周次分组的增减）：
              // - 仅一个周次分组时：只显示 + 按钮（新增上课周数）
              // - 非最后一个周次分组：只显示 - 按钮（删除该上课周数）
              // - 最后一个（且非唯一）周次分组：同时显示 - 和 + 按钮
              _buildWeekGroupCounterButtons(groupIndex, weekGroupIndex),
            ],
          ),
        ),
        // 时段行：标签 + -/+
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '时段',
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildCounterButton(
                      icon: FontAwesomeIcons.minus,
                      onTap: () => _removeSessionFromWeekGroup(
                        groupIndex,
                        weekGroupIndex,
                      ),
                    ),
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${weekGroup.sessions.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                    _buildCounterButton(
                      icon: FontAwesomeIcons.plus,
                      onTap: () =>
                          _addSessionToWeekGroup(groupIndex, weekGroupIndex),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 分割线：仅在存在时段时显示
        if (weekGroup.sessions.isNotEmpty)
          Divider(
            height: 1,
            indent: 16,
            endIndent: 16,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        // 该周次分组下的课程时间列表（AnimatedSize 包裹实现平滑过渡）
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int si = 0; si < weekGroup.sessions.length; si++) ...[
                if (si > 0)
                  Divider(
                    height: 1,
                    indent: 24,
                    endIndent: 16,
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                _buildSessionItem(groupIndex, weekGroupIndex, si),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // 内联时段选择器

  Widget _buildInlineTimePicker(
    int groupIndex,
    int weekGroupIndex,
    int sessionIndex,
  ) {
    final weekGroup = _classroomGroups[groupIndex].weekGroups[weekGroupIndex];
    final session = weekGroup.sessions[sessionIndex];
    final endSection = session.startSection + session.sectionCount - 1;

    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double baseFont =
              Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0;
          final double pickerFont = baseFont * kPickerFontScale;
          final double gap = 1.0;
          final double symbolWidth = 28.0;
          final double minPickerWidth = max(
            40.0,
            pickerFont * kPickerWidthScaleSmall,
          );
          final double maxPickerWidth = max(
            56.0,
            pickerFont * kPickerWidthScaleLarge,
          );
          final double available =
              constraints.maxWidth - symbolWidth * 2 - gap * 2;
          final double pickerWidth = (available / 3).clamp(
            minPickerWidth,
            maxPickerWidth,
          );

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 星期选择器
              SizedBox(
                width: pickerWidth,
                child: CupertinoPicker(
                  selectionOverlay: Container(),
                  itemExtent: kPickerItemExtent,
                  scrollController: FixedExtentScrollController(
                    initialItem: session.weekday - 1,
                  ),
                  onSelectedItemChanged: (newIndex) {
                    setState(() {
                      weekGroup.sessions[sessionIndex] = CourseSession(
                        weekday: newIndex + 1,
                        startSection: session.startSection,
                        sectionCount: session.sectionCount,
                        location: session.location,
                        startWeek: session.startWeek,
                        endWeek: session.endWeek,
                        weekType: session.weekType,
                        customWeeks: session.customWeeks,
                      );
                    });
                  },
                  children: List.generate(
                    7,
                    (i) => Center(
                      child: Text(
                        '周${_weekdayToString(i + 1)}',
                        style: TextStyle(fontSize: pickerFont),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(width: gap),
              // 起始节次选择器
              SizedBox(
                width: pickerWidth,
                child: CupertinoPicker(
                  key: ValueKey(
                    'start_picker_${groupIndex}_${weekGroupIndex}_${sessionIndex}_$_pickerResetVersion',
                  ),
                  selectionOverlay: Container(),
                  itemExtent: kPickerItemExtent,
                  scrollController: FixedExtentScrollController(
                    initialItem: session.startSection - 1,
                  ),
                  onSelectedItemChanged: (newIndex) {
                    final newStart = min(max(newIndex + 1, 1), _totalSections);
                    final currentEnd =
                        session.startSection + session.sectionCount - 1;

                    int validatedStart;
                    int newCount;

                    if (newStart > currentEnd) {
                      validatedStart = currentEnd;
                      newCount = newStart - currentEnd + 1;
                    } else {
                      validatedStart = newStart;
                      newCount = currentEnd - validatedStart + 1;
                    }

                    final newSession = CourseSession(
                      weekday: session.weekday,
                      startSection: validatedStart,
                      sectionCount: newCount,
                      location: session.location,
                      startWeek: session.startWeek,
                      endWeek: session.endWeek,
                      weekType: session.weekType,
                      customWeeks: session.customWeeks,
                    );
                    _updateSession(
                      groupIndex,
                      weekGroupIndex,
                      sessionIndex,
                      newSession,
                    );
                  },
                  children: List.generate(
                    _totalSections,
                    (i) => Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: pickerFont),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text('到'),
              const SizedBox(width: 4),
              // 结束节次选择器
              SizedBox(
                width: pickerWidth,
                child: CupertinoPicker(
                  key: ValueKey(
                    'end_picker_${groupIndex}_${weekGroupIndex}_${sessionIndex}_$_pickerResetVersion',
                  ),
                  selectionOverlay: Container(),
                  itemExtent: kPickerItemExtent,
                  scrollController: FixedExtentScrollController(
                    initialItem: endSection - 1,
                  ),
                  onSelectedItemChanged: (newIndex) {
                    final newEnd = min(max(newIndex + 1, 1), _totalSections);
                    final int oldStart = session.startSection;
                    final int oldEnd =
                        session.startSection + session.sectionCount - 1;

                    if (newEnd < oldStart) {
                      final int validatedNewStart = newEnd;
                      final int newCount = oldEnd - validatedNewStart + 1;
                      final newSession = CourseSession(
                        weekday: session.weekday,
                        startSection: validatedNewStart,
                        sectionCount: newCount,
                        location: session.location,
                        startWeek: session.startWeek,
                        endWeek: session.endWeek,
                        weekType: session.weekType,
                        customWeeks: session.customWeeks,
                      );
                      _updateSession(
                        groupIndex,
                        weekGroupIndex,
                        sessionIndex,
                        newSession,
                      );
                      return;
                    }

                    int validatedEnd = newEnd;
                    if (validatedEnd < oldStart) validatedEnd = oldStart;

                    final newCount = validatedEnd - oldStart + 1;
                    final newSession = CourseSession(
                      weekday: session.weekday,
                      startSection: oldStart,
                      sectionCount: newCount,
                      location: session.location,
                      startWeek: session.startWeek,
                      endWeek: session.endWeek,
                      weekType: session.weekType,
                      customWeeks: session.customWeeks,
                    );
                    _updateSession(
                      groupIndex,
                      weekGroupIndex,
                      sessionIndex,
                      newSession,
                    );
                  },
                  children: List.generate(
                    _totalSections,
                    (i) => Center(
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(fontSize: pickerFont),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Text('节'),
            ],
          );
        },
      ),
    );
  }

  // 通用组件

  /// 周数文本：单行固定字号，两行自动缩小 2 号字体。
  Widget _buildAutoWeekLabel(
    String text, {
    Color? color,
    TextAlign? textAlign,
  }) {
    const double baseSize = 14;
    final textColor = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        double fontSize = baseSize;
        if (maxWidth.isFinite && maxWidth > 0) {
          // 测量单行宽度判断是否换行
          final tp = TextPainter(
            text: TextSpan(
              text: text,
              style: TextStyle(fontSize: baseSize),
            ),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout();
          if (tp.width > maxWidth) {
            fontSize = baseSize - 2; // 两行时缩小 2 号
          }
        }
        return Text(
          text,
          maxLines: 2,
          textAlign: textAlign,
          style: TextStyle(fontSize: fontSize, color: textColor),
        );
      },
    );
  }

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        color: Colors.transparent,
        child: Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildColorItem() {
    return GestureDetector(
      onTap: _pickColor,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '课程背景色',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? dimColorForDark(_selectedColor)
                        : _selectedColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 建议项

  Widget _buildSuggestionItem(Course course) {
    return InkWell(
      onTap: () {
        _nameController.text = course.name;
        _teacherController.text = course.teacher;
        setState(() {
          _selectedColor = course.color;
          _suggestions = [];
          // 用选中课程的教室分组替换当前分组，实现"长出"完整课程信息
          final newGroups = _groupSessionsByLocation(course.sessions);
          if (newGroups.isNotEmpty) {
            _classroomGroups = newGroups;
            _sortClassroomGroups();
            // 重建 AnimatedList 以丝滑刷新教室列表
            _classroomListKey = GlobalKey<AnimatedListState>();
            _pickerResetVersion++;
          }
          // 重置展开状态
          _expandedClassroomIndex = null;
          _expandedSessionIndex = null;
        });
        FocusScope.of(context).unfocus();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? dimColorForDark(course.color)
                    : course.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                course.name,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 删除按钮

  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: _deleteCourse,
      child: Container(
        width: double.infinity,
        height: 72,
        decoration: BoxDecoration(
          color:
              Theme.of(context).cardTheme.color ??
              Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.08),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.onSurface,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              '删除课程',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCourse() async {
    final bool? confirm = await BottomSheetConfirm.show(
      context,
      title: '确定删除此课程及日程？',
    );

    if (confirm == true && mounted) {
      Navigator.pop(context, CourseEditResult.delete(course: widget.course!));
    }
  }

  String _weekdayToString(int weekday) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    if (weekday >= 1 && weekday <= 7) return weekdays[weekday - 1];
    return '';
  }
}

// 重叠检测数据模型

/// 可合并的同名教室组信息。
class _MergeableGroupInfo {
  final String name;
  final int count;
  final List<String> descriptions;
  final List<int> groupIndices;
  const _MergeableGroupInfo({
    required this.name,
    required this.count,
    required this.descriptions,
    required this.groupIndices,
  });
}

class _CourseOverlapGroup {
  final Course existingCourse;
  final String newCourseName;
  final Color newCourseColor;
  final List<_OverlapEntry> entries;
  _CourseOverlapGroup({
    required this.existingCourse,
    required this.newCourseName,
    required this.newCourseColor,
    required this.entries,
  });
}

/// 单条重叠记录。
class _OverlapEntry {
  final String timeLabel;
  final List<int> overlapWeeks;
  _OverlapEntry({required this.timeLabel, required this.overlapWeeks});
}

// 周数选择器（支持禁用周次）

class _WeekRangePicker extends StatefulWidget {
  final int initialStart;
  final int initialEnd;
  final CourseWeekType initialType;
  final List<int> initialCustomWeeks;
  final int maxWeek;

  /// 不可选（已占用）的周次集合，这些周次将灰显且无法选择。
  final Set<int> disabledWeeks;

  const _WeekRangePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.initialType,
    this.initialCustomWeeks = const [],
    required this.maxWeek,
    this.disabledWeeks = const {},
  });

  @override
  State<_WeekRangePicker> createState() => _WeekRangePickerState();
}

class _WeekRangePickerState extends State<_WeekRangePicker> {
  late Set<int> _selectedWeeks;
  CourseWeekType? _currentType;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _selectedWeeks = {};

    if (widget.initialCustomWeeks.isNotEmpty) {
      _selectedWeeks.addAll(widget.initialCustomWeeks);
      _currentType = null;
    } else {
      _currentType = widget.initialType;
      for (int i = widget.initialStart; i <= widget.initialEnd; i++) {
        // 周次从 1 开始，忽略无效的 0 值（未配置状态）
        if (i <= 0) continue;
        if (widget.initialType == CourseWeekType.all) {
          _selectedWeeks.add(i);
        } else if (widget.initialType == CourseWeekType.single) {
          if (i % 2 != 0) _selectedWeeks.add(i);
        } else if (widget.initialType == CourseWeekType.double) {
          if (i % 2 == 0) _selectedWeeks.add(i);
        }
      }
      // 若未选中任何周次（如初始范围 0..0），则清除类型勾选状态
      if (_selectedWeeks.isEmpty) {
        _currentType = null;
      }
    }
  }

  void _updateSelectionByType(CourseWeekType type) {
    setState(() {
      if (_currentType == type) {
        _currentType = null;
        _selectedWeeks.clear();
      } else {
        _currentType = type;
        _selectedWeeks.clear();
        for (int i = 1; i <= widget.maxWeek; i++) {
          // 跳过禁用的周次
          if (widget.disabledWeeks.contains(i)) continue;
          if (type == CourseWeekType.all) {
            _selectedWeeks.add(i);
          } else if (type == CourseWeekType.single) {
            if (i % 2 != 0) _selectedWeeks.add(i);
          } else if (type == CourseWeekType.double) {
            if (i % 2 == 0) _selectedWeeks.add(i);
          }
        }
      }
    });
  }

  void _toggleWeek(int week) {
    // 无效周次或禁用的周次不可切换
    if (week <= 0 || widget.disabledWeeks.contains(week)) return;
    setState(() {
      if (_selectedWeeks.contains(week)) {
        _selectedWeeks.remove(week);
      } else {
        _selectedWeeks.add(week);
      }
      _updateCurrentTypeFromSelection();
    });
  }

  Set<int> _buildExpectedWeeksByType(CourseWeekType type) {
    final Set<int> weeks = <int>{};
    for (int i = 1; i <= widget.maxWeek; i++) {
      if (widget.disabledWeeks.contains(i)) continue;
      if (type == CourseWeekType.all) {
        weeks.add(i);
      } else if (type == CourseWeekType.single) {
        if (i.isOdd) weeks.add(i);
      } else if (type == CourseWeekType.double) {
        if (i.isEven) weeks.add(i);
      }
    }
    return weeks;
  }

  bool _isExactlySelectedType(CourseWeekType type) {
    final Set<int> expected = _buildExpectedWeeksByType(type);
    if (expected.length != _selectedWeeks.length) return false;
    return _selectedWeeks.containsAll(expected);
  }

  void _updateCurrentTypeFromSelection() {
    if (_selectedWeeks.isEmpty) {
      _currentType = null;
      return;
    }

    if (_isExactlySelectedType(CourseWeekType.all)) {
      _currentType = CourseWeekType.all;
      return;
    }
    if (_isExactlySelectedType(CourseWeekType.single)) {
      _currentType = CourseWeekType.single;
      return;
    }
    if (_isExactlySelectedType(CourseWeekType.double)) {
      _currentType = CourseWeekType.double;
      return;
    }
    _currentType = null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context),
            _buildTypeSelector(),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.2,
                ),
                itemCount: widget.maxWeek,
                itemBuilder: (context, index) {
                  final week = index + 1;
                  final isSelected = _selectedWeeks.contains(week);
                  final isDisabled = widget.disabledWeeks.contains(week);
                  return GestureDetector(
                    onTap: () => _toggleWeek(week),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCheckbox(isSelected, isDisabled: isDisabled),
                        const SizedBox(width: 6),
                        Text(
                          '$week',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDisabled
                                ? Theme.of(context).colorScheme.outlineVariant
                                : Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 30, top: 10),
              child: GestureDetector(
                onTap: _confirm,
                child: Text(
                  '确定',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: CompositedTransformTarget(
        link: _layerLink,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Align(
              alignment: Alignment.center,
              child: Text(
                '上课周数',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: Icon(
                  Icons.close,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          _buildTypeOption('全部', CourseWeekType.all),
          const SizedBox(width: 24),
          _buildTypeOption('单周', CourseWeekType.single),
          const SizedBox(width: 24),
          _buildTypeOption('双周', CourseWeekType.double),
        ],
      ),
    );
  }

  Widget _buildTypeOption(String label, CourseWeekType type) {
    final isSelected = _currentType == type;
    // 检查该类型是否还有可选周次
    final bool hasAvailable = _buildExpectedWeeksByType(type).isNotEmpty;
    final bool isDisabled = !hasAvailable && !isSelected;
    return GestureDetector(
      onTap: isDisabled ? null : () => _updateSelectionByType(type),
      child: Opacity(
        opacity: isDisabled ? 0.4 : 1.0,
        child: Row(
          children: [
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox(bool isSelected, {bool isDisabled = false}) {
    final Color activeColor = ThemeService.instance.isWhiteMode
        ? Colors.grey.shade700
        : Theme.of(context).colorScheme.primary;
    final Color checkColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.black
        : Colors.white;
    const Color uncheckedBorder = Color(0xFFC4C4C6);

    // 禁用态使用更淡的颜色
    final Color borderColor = isDisabled
        ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3)
        : (isSelected ? activeColor : uncheckedBorder);
    final Color fillColor = isDisabled
        ? Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.15)
        : (isSelected ? activeColor : Colors.transparent);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: isSelected
          ? AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeInOut,
              opacity: isSelected ? 1.0 : 0.0,
              child: Icon(
                Icons.check,
                size: 14,
                color: isDisabled
                    ? Theme.of(context).colorScheme.outlineVariant
                    : checkColor,
              ),
            )
          : null,
    );
  }

  void _confirm() {
    if (_selectedWeeks.isEmpty) {
      AppToast.show(
        context,
        '上课周数不能为空',
        variant: AppToastVariant.warning,
        anchorLink: _layerLink,
        anchorOffset: const Offset(0, -24),
        targetAnchor: Alignment.topCenter,
        followerAnchor: Alignment.bottomCenter,
      );
      return;
    }

    // 过滤掉无效周次（安全兜底），然后排序
    final sortedWeeks = _selectedWeeks.where((w) => w > 0).toList()..sort();
    final start = sortedWeeks.first;
    final end = sortedWeeks.last;

    CourseWeekType type = CourseWeekType.all;
    List<int> customWeeks = <int>[];
    if (_isExactlySelectedType(CourseWeekType.single)) {
      type = CourseWeekType.single;
    } else if (_isExactlySelectedType(CourseWeekType.double)) {
      type = CourseWeekType.double;
    } else if (_isExactlySelectedType(CourseWeekType.all)) {
      type = CourseWeekType.all;
    } else {
      type = CourseWeekType.all;
      customWeeks = sortedWeeks;
    }

    Navigator.pop(context, {
      'start': start,
      'end': end,
      'type': type,
      'customWeeks': customWeeks,
    });
  }
}

// 颜色选择器

class _ColorPickerSheet extends StatefulWidget {
  final Color selectedColor;
  final List<Color> colors;
  final List<Color> customColors;
  final List<Course> existingCourses;
  final ValueChanged<Color> onAddCustomColor;
  final ValueChanged<Color> onDeleteCustomColor;

  const _ColorPickerSheet({
    required this.selectedColor,
    required this.colors,
    required this.customColors,
    required this.existingCourses,
    required this.onAddCustomColor,
    required this.onDeleteCustomColor,
  });

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late List<Color> _localCustomColors;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _localCustomColors = List.from(widget.customColors);
  }

  @override
  void dispose() {
    AppToast.dismiss();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allColors = [...widget.colors, ..._localCustomColors];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CompositedTransformTarget(
            link: _layerLink,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Align(
                  alignment: Alignment.center,
                  child: Text(
                    '课程背景色',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allColors.length + 1,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1,
              ),
              itemBuilder: (context, index) {
                if (index == allColors.length) {
                  return GestureDetector(
                    onTap: () async {
                      final Color?
                      customColor = await Navigator.of(context).push<Color>(
                        PageRouteBuilder<Color>(
                          opaque: false,
                          barrierDismissible: true,
                          barrierColor: Colors.black.withValues(alpha: 0.55),
                          pageBuilder:
                              (context, animation, secondaryAnimation) {
                                return _CustomColorPickerDialog(
                                  initialColor: widget.selectedColor,
                                );
                              },
                          transitionsBuilder:
                              (context, animation, secondaryAnimation, child) {
                                return FadeTransition(
                                  opacity: animation,
                                  child: child,
                                );
                              },
                        ),
                      );
                      if (customColor != null && context.mounted) {
                        widget.onAddCustomColor(customColor);
                        setState(() {
                          _localCustomColors.add(customColor);
                        });
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                        border: Theme.of(context).brightness == Brightness.dark
                            ? Border.all(
                                color: Colors.white.withValues(alpha: 0.24),
                                width: 1,
                              )
                            : null,
                      ),
                      child: Icon(
                        Icons.add,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  );
                }

                final color = allColors[index];
                final isCustom = index >= widget.colors.length;

                return GestureDetector(
                  onTap: () => Navigator.pop(context, color),
                  onLongPress: isCustom
                      ? () {
                          final usedBy = widget.existingCourses
                              .where(
                                (c) => c.color.toARGB32() == color.toARGB32(),
                              )
                              .toList();

                          if (usedBy.isNotEmpty) {
                            final courseName = usedBy.first.name;
                            AppToast.show(
                              context,
                              '当前颜色正被"$courseName"使用',
                              variant: AppToastVariant.info,
                              anchorLink: _layerLink,
                              anchorOffset: const Offset(0, -24),
                              targetAnchor: Alignment.topCenter,
                              followerAnchor: Alignment.bottomCenter,
                            );
                            return;
                          }

                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('删除颜色'),
                              content: const Text('确定要删除这个自定义颜色吗？'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    widget.onDeleteCustomColor(color);
                                    setState(() {
                                      _localCustomColors.remove(color);
                                    });
                                    Navigator.pop(ctx);
                                  },
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                        }
                      : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? dimColorForDark(color)
                          : color,
                      shape: BoxShape.circle,
                      border: isCustom
                          ? Border.all(color: Colors.grey.shade400, width: 2)
                          : null,
                    ),
                    child: widget.selectedColor == color
                        ? Icon(
                            Icons.check,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white70
                                : Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                            size: 24,
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// 自定义颜色选择对话框

class _CustomColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _CustomColorPickerDialog({required this.initialColor});

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  late double _hue;
  late double _saturation;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation.clamp(0.25, 0.5);
    _brightness = hsv.value.clamp(0.85, 0.96);
  }

  Color get _currentColor =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _brightness).toColor();

  String? _getInvalidColorReason(Color color) {
    final hsv = HSVColor.fromColor(color);

    if (hsv.value < 0.2) return '不能添加黑色';

    if (hsv.saturation < 0.05) {
      if (hsv.value > 0.85) return '不能添加白色';
      return '不能添加灰色';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final currentColor = _currentColor;
    final r = (currentColor.r * 255).round();
    final g = (currentColor.g * 255).round();
    final b = (currentColor.b * 255).round();
    final hexStr =
        r.toRadixString(16).padLeft(2, '0') +
        g.toRadixString(16).padLeft(2, '0') +
        b.toRadixString(16).padLeft(2, '0');

    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '添加自定义颜色',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildCoursePreview(currentColor),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 180,
                        child: _CourseColorSVPicker(
                          hue: _hue,
                          saturation: _saturation,
                          brightness: _brightness,
                          onChanged: (s, v) => setState(() {
                            _saturation = s;
                            _brightness = v;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 22,
                      child: _CourseColorHueSlider(
                        hue: _hue,
                        onChanged: (h) => setState(() => _hue = h),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _CourseColorCompactField(
                            label: 'Hex',
                            value: hexStr.toUpperCase(),
                            onSubmitted: (v) {
                              final parsed = int.tryParse(v, radix: 16);
                              if (parsed != null && v.length == 6) {
                                final c = Color(0xFF000000 | parsed);
                                final hsv = HSVColor.fromColor(c);
                                setState(() {
                                  _hue = hsv.hue;
                                  _saturation = hsv.saturation;
                                  _brightness = hsv.value;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CourseColorCompactField(
                            label: 'R',
                            value: '$r',
                            onSubmitted: (v) => _setFromRGB(r: int.tryParse(v)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CourseColorCompactField(
                            label: 'G',
                            value: '$g',
                            onSubmitted: (v) => _setFromRGB(g: int.tryParse(v)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CourseColorCompactField(
                            label: 'B',
                            value: '$b',
                            onSubmitted: (v) => _setFromRGB(b: int.tryParse(v)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () {
                            final reason = _getInvalidColorReason(currentColor);
                            if (reason != null) {
                              AppToast.show(
                                context,
                                '$reason，请调整颜色',
                                variant: AppToastVariant.warning,
                              );
                              return;
                            }
                            Navigator.pop(context, currentColor);
                          },
                          child: const Text('应用'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 通过 RGB 值更新 HSB 状态
  void _setFromRGB({int? r, int? g, int? b}) {
    final c = _currentColor;
    final nr = (r ?? (c.r * 255).round()).clamp(0, 255);
    final ng = (g ?? (c.g * 255).round()).clamp(0, 255);
    final nb = (b ?? (c.b * 255).round()).clamp(0, 255);
    final newColor = Color.fromARGB(255, nr, ng, nb);
    final hsv = HSVColor.fromColor(newColor);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
    });
  }

  Widget _buildCoursePreview(Color currentColor) {
    final Color previewColor = currentColor;
    final Color textColor =
        ThemeData.estimateBrightnessForColor(previewColor) == Brightness.dark
        ? Colors.white
        : const Color(0xFF1F2C33);
    final Color subtitleColor = textColor.withValues(alpha: 0.82);
    final bool needsBorder =
        ThemeData.estimateBrightnessForColor(previewColor) == Brightness.light;

    return Row(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: previewColor,
            shape: BoxShape.circle,
            border: needsBorder
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.85),
                    width: 1,
                  )
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 86,
            decoration: BoxDecoration(
              color: previewColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '课程预览',
                    style: TextStyle(
                      color: textColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@演示室',
                    style: TextStyle(color: subtitleColor, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// 课程色域选择器组件

class _CourseColorSVPicker extends StatelessWidget {
  final double hue;
  final double saturation;
  final double brightness;
  final void Function(double saturation, double brightness) onChanged;

  const _CourseColorSVPicker({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.onChanged,
  });

  void _handleInteraction(Offset localPosition, Size size) {
    final s = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final v = 1.0 - (localPosition.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (d) =>
              _handleInteraction(d.localPosition, constraints.biggest),
          onPanUpdate: (d) =>
              _handleInteraction(d.localPosition, constraints.biggest),
          child: CustomPaint(
            painter: _CourseColorSVPainter(hue: hue),
            child: Stack(
              children: [
                Positioned(
                  left: saturation * constraints.maxWidth - 8,
                  top: (1.0 - brightness) * constraints.maxHeight - 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// SV 平面的 CustomPainter
///
/// 水平：白色 → 纯色相（表示饱和度从 0 到 1）
/// 垂直：透明 → 黑色（表示明度从 1 到 0）
class _CourseColorSVPainter extends CustomPainter {
  final double hue;

  _CourseColorSVPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.clipRRect(rrect);

    // 基础纯色（由色相决定）
    final pureColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();

    // 层 1：水平渐变（白色 → 纯色）
    final horizontalGradient = LinearGradient(
      colors: [Colors.white, pureColor],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = horizontalGradient);

    // 层 2：垂直渐变（透明 → 黑色）
    final verticalGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = verticalGradient);
  }

  @override
  bool shouldRepaint(covariant _CourseColorSVPainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

/// 色相条——彩虹色带横条
///
/// 从红色(0°)到红色(360°)的全色相渐变，拖动选取目标色相。
class _CourseColorHueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _CourseColorHueSlider({required this.hue, required this.onChanged});

  void _handleInteraction(Offset localPosition, double width) {
    final h = (localPosition.dx / width).clamp(0.0, 1.0) * 360;
    onChanged(h);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanStart: (d) => _handleInteraction(d.localPosition, width),
          onPanUpdate: (d) => _handleInteraction(d.localPosition, width),
          child: CustomPaint(
            painter: _CourseColorHuePainter(),
            child: Stack(
              children: [
                Positioned(
                  left: (hue / 360.0) * width - 6,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 色相条的 CustomPainter
///
/// 绘制 7 个关键色相节点（红→黄→绿→青→蓝→紫→红）的彩虹渐变。
class _CourseColorHuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.clipRRect(rrect);

    final colors = List.generate(
      7,
      (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
    );
    final gradient = LinearGradient(colors: colors).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = gradient);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Hex / R / G / B 紧凑型输入框
///
/// 支持 Hex 模式（仅允许 0-9 a-f，最多 6 位）
/// 和数值模式（仅允许数字，最多 3 位）。
class _CourseColorCompactField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  const _CourseColorCompactField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  @override
  State<_CourseColorCompactField> createState() =>
      _CourseColorCompactFieldState();
}

class _CourseColorCompactFieldState extends State<_CourseColorCompactField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _CourseColorCompactField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化时同步更新（避免用户正在编辑时被覆盖）
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            inputFormatters: [
              if (widget.label == 'Hex')
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))
              else
                FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.label == 'Hex' ? 6 : 3),
            ],
            onSubmitted: widget.onSubmitted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
