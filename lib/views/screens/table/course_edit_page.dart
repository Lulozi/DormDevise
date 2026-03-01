import 'dart:async';
import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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

class CourseEditPage extends StatefulWidget {
  final Course? course; // 如果为 null，则表示正在添加新课程
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

class _CourseEditPageState extends State<CourseEditPage> {
  late TextEditingController _nameController;
  late TextEditingController _teacherController;
  late TextEditingController _classroomController;
  late Color _selectedColor;
  late Color _initialSmartColor;
  late List<CourseSession> _sessions;
  List<Color> _customColors = [];
  Color? _temporaryAutoColor;
  CourseScheduleConfig? _scheduleConfig;
  final Map<int, Timer> _debounceTimers = {};
  int _pickerResetVersion = 0;
  List<Course> _suggestions = [];

  // 全局周次设置
  int _startWeek = 1;
  late int _endWeek;
  CourseWeekType _weekType = CourseWeekType.all;
  List<int> _customWeeks = [];

  int? _expandedSessionIndex;

  int get _totalSections {
    if (_scheduleConfig == null) return 12;
    return _scheduleConfig!.segments.fold(
      0,
      (sum, seg) => sum + seg.classCount,
    );
  }

  final List<Color> _presetColors = [
    const Color(0xFFFFCDD2),
    const Color(0xFFF8BBD0),
    const Color(0xFFE1BEE7),
    const Color(0xFFD1C4E9),
    const Color(0xFFC5CAE9),
    const Color(0xFFBBDEFB),
    const Color(0xFFB3E5FC),
    const Color(0xFFB2EBF2),
    const Color(0xFFB2DFDB),
    const Color(0xFFC8E6C9),
    const Color(0xFFDCEDC8),
    const Color(0xFFF0F4C3),
    const Color(0xFFFFF9C4),
    const Color(0xFFFFECB3),
    const Color(0xFFFFE0B2),
    const Color(0xFFFFCCBC),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.scheduleConfig != null) {
      _scheduleConfig = widget.scheduleConfig;
    }
    _loadConfig();
    _loadCustomColors();
    _endWeek = widget.maxWeek;
    _nameController = TextEditingController(text: widget.course?.name ?? '');
    _nameController.addListener(_onNameChanged);
    _teacherController = TextEditingController(
      text: widget.course?.teacher ?? '',
    );

    // 如果有第一个课节，则从第一个课节初始化教室，否则为空
    String initialLocation = '';
    if (widget.course != null && widget.course!.sessions.isNotEmpty) {
      initialLocation = widget.course!.sessions.first.location;
      _startWeek = widget.course!.sessions.first.startWeek;
      _endWeek = widget.course!.sessions.first.endWeek;
      _weekType = widget.course!.sessions.first.weekType;
      _customWeeks = widget.course!.sessions.first.customWeeks;
    }
    _classroomController = TextEditingController(text: initialLocation);

    if (widget.course != null) {
      _initialSmartColor = widget.course!.color;
      _selectedColor = _initialSmartColor;
    } else {
      // 优先选择未使用的颜色
      final Set<int> usedColorValues = widget.existingCourses
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
    }

    _sessions = widget.course?.sessions.toList() ?? [];

    if (widget.course == null) {
      if (widget.initialWeekday != null && widget.initialSection != null) {
        int initialCount = 2;
        final int nextSection = widget.initialSection! + 1;

        // 检查下一个节次是否被已有课程占用
        bool nextSectionOccupied = widget.existingCourses.any((course) {
          return course.sessions.any((session) {
            if (session.weekday != widget.initialWeekday!) return false;
            final int sessionEnd =
                session.startSection + session.sectionCount - 1;
            return session.startSection <= nextSection &&
                sessionEnd >= nextSection;
          });
        });

        // 检查默认的 2 节课程是否会跨越分段（例如上午 -> 下午）
        bool isCrossSegment = false;
        if (_scheduleConfig != null) {
          final tempSession = CourseSession(
            weekday: widget.initialWeekday!,
            startSection: widget.initialSection!,
            sectionCount: 2,
            location: '',
            startWeek: 1,
            endWeek: widget.maxWeek,
            weekType: CourseWeekType.all,
          );
          if (_isCrossSegment(tempSession)) {
            isCrossSegment = true;
          }
        }

        if (nextSectionOccupied || isCrossSegment) {
          initialCount = 1;
        }

        _sessions.add(
          CourseSession(
            weekday: widget.initialWeekday!,
            startSection: widget.initialSection!,
            sectionCount: initialCount,
            location: '',
            startWeek: 1,
            endWeek: widget.maxWeek,
            weekType: CourseWeekType.all,
          ),
        );
      } else if (_sessions.isEmpty) {
        // 如果不存在课节，则添加默认课节
        _sessions.add(
          CourseSession(
            weekday: 1,
            startSection: 1,
            sectionCount: 2,
            location: '',
            startWeek: 1,
            endWeek: widget.maxWeek,
            weekType: CourseWeekType.all,
          ),
        );
      }
    }
  }

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
    final exactMatches = widget.existingCourses.where((c) => c.name == name);
    if (exactMatches.isNotEmpty) {
      final exactMatch = exactMatches.first;
      final bool isTeacherSame = exactMatch.teacher == _teacherController.text;
      final bool isColorSame = exactMatch.color.value == _selectedColor.value;

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
    final matches = widget.existingCourses.where((c) {
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

  ({int start, int end})? _getSegmentRange(int section) {
    if (_scheduleConfig == null) return null;
    int segStart = 1;
    for (var segment in _scheduleConfig!.segments) {
      int segEnd = segStart + segment.classCount - 1;
      if (section >= segStart && section <= segEnd) {
        return (start: segStart, end: segEnd);
      }
      segStart += segment.classCount;
    }
    return null;
  }

  bool _isCrossSegment(CourseSession session) {
    if (_scheduleConfig == null) return false;

    bool contained = false;
    int segStart = 1;
    for (var segment in _scheduleConfig!.segments) {
      int segEnd = segStart + segment.classCount - 1;
      final uEnd = session.startSection + session.sectionCount - 1;

      // 检查是否完全包含在当前段内
      if (session.startSection >= segStart && uEnd <= segEnd) {
        contained = true;
        break;
      }
      segStart += segment.classCount;
    }
    // 如果没有被任何一个段完全包含，则是跨段
    return !contained;
  }

  Future<void> _loadConfig() async {
    final config =
        widget.scheduleConfig ?? await CourseService.instance.loadConfig();
    if (mounted) {
      setState(() {
        _scheduleConfig = config;

        // 检查初始课程是否跨段，如果是则调整
        if (widget.course == null &&
            widget.initialSection != null &&
            _sessions.isNotEmpty) {
          // 检查第一个会话（即初始添加的会话）
          final session = _sessions[0];
          if (_isCrossSegment(session)) {
            // 如果跨段，且节数大于1，则缩减为1
            if (session.sectionCount > 1) {
              _sessions[0] = CourseSession(
                weekday: session.weekday,
                startSection: session.startSection,
                sectionCount: 1,
                location: session.location,
                startWeek: session.startWeek,
                endWeek: session.endWeek,
                weekType: session.weekType,
                customWeeks: session.customWeeks,
              );
              _pickerResetVersion++;
            }
          }
        }
      });
    }
  }

  void _updateSession(int index, CourseSession newSession) {
    // 1. 立即更新当前会话，保证 UI 响应
    setState(() {
      _sessions[index] = newSession;
    });

    // 2. 防抖处理：延迟执行智能拆分与合并逻辑
    _debounceTimers[index]?.cancel();
    _debounceTimers[index] = Timer(const Duration(milliseconds: 800), () {
      _smartSplitAndMerge(index);
      _debounceTimers.remove(index);
    });
  }

  void _smartSplitAndMerge(int index) {
    if (!mounted || index >= _sessions.length) return;

    var updatedSession = _sessions[index];
    bool wasReverseOrder = false;

    // 0. 归一化处理：如果结束时间小于开始时间，自动交换
    final currentEnd =
        updatedSession.startSection + updatedSession.sectionCount - 1;
    if (currentEnd < updatedSession.startSection) {
      wasReverseOrder = true;
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
      );
    }

    setState(() {
      _pickerResetVersion++; // 强制刷新 Picker 状态，确保滚动位置同步

      // 1. 收集不需要移除的会话
      final List<CourseSession> keptSessions = [];

      // 判断是否跨段（Inter-segment）
      // 如果调整后的时间跨越了作息表定义的时段边界（例如从上午跨到下午），则视为“大调整”，清除当天其他所有课程
      // 如果调整仍在同一时段内（例如 1-4 调整为 1-2），则仅清除重叠课程，保留其他时段
      // 特殊情况：如果是反向选择（B < A），则强制视为大调整，清除当天其他课程
      bool isInterSegment = false;
      if (wasReverseOrder) {
        isInterSegment = true;
      } else if (_scheduleConfig != null) {
        bool contained = false;
        int segStart = 1;
        for (var segment in _scheduleConfig!.segments) {
          int segEnd = segStart + segment.classCount - 1;
          final uEnd =
              updatedSession.startSection + updatedSession.sectionCount - 1;

          // 检查是否完全包含在当前段内
          if (updatedSession.startSection >= segStart && uEnd <= segEnd) {
            contained = true;
            break;
          }
          segStart += segment.classCount;
        }
        // 如果没有被任何一个段完全包含，则是跨段
        if (!contained) {
          isInterSegment = true;
        }
      }

      for (int i = 0; i < _sessions.length; i++) {
        if (i == index) continue; // 跳过当前正在编辑的会话

        final s = _sessions[i];

        // 不同天的会话始终保留
        if (s.weekday != updatedSession.weekday) {
          keptSessions.add(s);
          continue;
        }

        // 同一天的会话处理
        if (isInterSegment) {
          // 跨段调整：清除当天所有其他课程
          continue;
        } else {
          // 段内调整：仅清除重叠的
          final sEnd = s.startSection + s.sectionCount - 1;
          final uEnd =
              updatedSession.startSection + updatedSession.sectionCount - 1;

          bool isOverlapping = false;
          if (s.startSection <= uEnd && sEnd >= updatedSession.startSection) {
            isOverlapping = true;
          }

          if (!isOverlapping) {
            keptSessions.add(s);
          }
        }
      }

      // 2. 计算拆分结果
      List<CourseSession> splits = _calculateSplits(updatedSession);

      // 3. 重建列表
      _sessions = [...keptSessions, ...splits];

      // 4. 重新排序：按周几、开始节次排序，确保列表顺序正确
      _sessions.sort((a, b) {
        if (a.weekday != b.weekday) {
          return a.weekday.compareTo(b.weekday);
        }
        return a.startSection.compareTo(b.startSection);
      });

      // 5. 保持展开状态
      // 找到包含原开始节次的那个会话的新索引，保持用户焦点
      final newIndex = _sessions.indexWhere(
        (s) =>
            s.weekday == updatedSession.weekday &&
            s.startSection == updatedSession.startSection,
      );

      if (newIndex != -1) {
        _expandedSessionIndex = newIndex;
      } else {
        _expandedSessionIndex = null;
      }
    });
  }

  List<CourseSession> _calculateSplits(CourseSession session) {
    if (_scheduleConfig == null) return [session];

    List<CourseSession> splits = [];
    int currentStart = session.startSection;
    int remainingCount = session.sectionCount;
    int sessionEnd = currentStart + remainingCount - 1;

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
      // 显示选择对话框
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
        // 询问用户是否要记住该选择
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
    // 尝试生成一个与现有颜色差异较大的颜色
    int attempts = 0;
    Color bestColor = Colors.white;
    double maxMinDistance = -1.0;

    // 获取所有已存在的颜色（预设 + 自定义）
    final allColors = [..._presetColors, ..._customColors];

    while (attempts < 20) {
      // 调整参数以获得“淡一些但有辨识度”的颜色
      // 饱和度 (Saturation): 0.3 - 0.5 (保持色彩但不过于艳丽，也不至于太灰)
      // 亮度 (Value): 0.85 - 0.95 (保持明亮但不过曝，不刺眼)
      final hsv = HSVColor.fromAHSV(
        1.0,
        random.nextDouble() * 360,
        0.3 + random.nextDouble() * 0.2,
        0.85 + random.nextDouble() * 0.1,
      );
      final candidate = hsv.toColor();

      if (allColors.isEmpty) return candidate;

      // 计算与现有颜色的最小距离
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

      // 如果距离足够大，直接返回 (RGB空间下 45 左右经验值)
      if (minDistance > 45) {
        return candidate;
      }

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
    for (var timer in _debounceTimers.values) {
      timer.cancel();
    }
    AppToast.dismiss();
    _nameController.dispose();
    _teacherController.dispose();
    _classroomController.dispose();
    super.dispose();
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
        .map((c) {
          return c.toARGB32().toString();
        })
        .toList();
    await prefs.setStringList('custom_course_colors', colors);
  }

  void _addCustomColor(Color color, {bool save = true}) {
    if (!_customColors.contains(color) && !_presetColors.contains(color)) {
      setState(() {
        _customColors.add(color);
      });
      if (save) {
        _saveCustomColors();
      }
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

  Future<void> _save() async {
    if (_nameController.text.isEmpty) {
      // 显示错误或直接返回
      AppToast.show(context, '请输入课程名称', variant: AppToastVariant.warning);
      return;
    }

    // 校验跨段
    if (_scheduleConfig != null) {
      for (var session in _sessions) {
        int segStart = 1;
        for (int i = 0; i < _scheduleConfig!.segments.length; i++) {
          final segment = _scheduleConfig!.segments[i];
          int segEnd = segStart + segment.classCount - 1;
          final uStart = session.startSection;
          final uEnd = session.startSection + session.sectionCount - 1;

          // 检查是否跨越了当前段的结束边界
          if (uStart >= segStart && uStart <= segEnd && uEnd > segEnd) {
            String errorMsg = '课程时间不能跨越时段';
            if (i == 0) {
              errorMsg = '课程时间不能跨越午休';
            } else if (i == 1) {
              errorMsg = '课程时间不能跨越晚修';
            }
            AppToast.show(context, errorMsg, variant: AppToastVariant.warning);
            return;
          }
          segStart += segment.classCount;
        }
      }
    }

    // 确认临时颜色为永久
    _temporaryAutoColor = null;
    // 保存自定义颜色
    await _saveCustomColors();

    if (!mounted) return;

    // 将全局设置应用到所有课节
    final updatedSessions = _sessions.map((s) {
      return CourseSession(
        weekday: s.weekday,
        startSection: s.startSection,
        sectionCount: s.sectionCount,
        location: _classroomController.text, // 应用全局教室
        startWeek: _startWeek, // 应用全局开始周
        endWeek: _endWeek, // 应用全局结束周
        weekType: _weekType, // 应用全局周类型
        customWeeks: _customWeeks, // 应用全局自定义周
      );
    }).toList();

    final newCourse = Course(
      name: _nameController.text,
      teacher: _teacherController.text,
      color: _selectedColor,
      sessions: updatedSessions,
    );
    Navigator.of(context).pop(newCourse);
  }

  void _incrementSessions() {
    setState(() {
      _sessions.add(
        CourseSession(
          weekday: 1,
          startSection: 1,
          sectionCount: 2,
          location: _classroomController.text,
          startWeek: _startWeek,
          endWeek: _endWeek,
          weekType: _weekType,
          customWeeks: _customWeeks,
        ),
      );
    });
  }

  void _decrementSessions() {
    if (_sessions.isNotEmpty) {
      setState(() {
        _sessions.removeLast();
      });
    }
  }

  Future<void> _pickWeeks() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _WeekRangePicker(
        initialStart: _startWeek,
        initialEnd: _endWeek,
        initialType: _weekType,
        initialCustomWeeks: _customWeeks,
        maxWeek: widget.maxWeek,
      ),
    );

    if (result != null) {
      setState(() {
        _startWeek = result['start'] as int;
        _endWeek = result['end'] as int;
        _weekType = result['type'] as CourseWeekType;
        _customWeeks = result['customWeeks'] as List<int>;
      });
    }
  }

  Future<void> _pickColor() async {
    final result = await showModalBottomSheet<Color>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _ColorPickerSheet(
        selectedColor: _selectedColor,
        colors: _presetColors,
        customColors: _customColors,
        existingCourses: widget.existingCourses,
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

  @override
  Widget build(BuildContext context) {
    // 构造一个临时的 CourseSession 来使用 formatWeeks
    final tempSession = CourseSession(
      weekday: 1, // 占位
      startSection: 1, // 占位
      sectionCount: 1, // 占位
      location: '',
      startWeek: _startWeek,
      endWeek: _endWeek,
      weekType: _weekType,
      customWeeks: _customWeeks,
    );
    String weekText = formatWeeks(tempSession);

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
          onPressed: () => Navigator.of(context).pop(),
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
          Container(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).cardTheme.color ??
                  Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
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
          ),
          const SizedBox(height: 12),
          _buildInputGroup(
            label: '教室',
            controller: _classroomController,
            placeholder: '非必填',
            isLast: false,
          ),
          const SizedBox(height: 12),
          _buildInputGroup(
            label: '备注（如老师）',
            controller: _teacherController,
            placeholder: '非必填',
            isLast: true,
          ),
          const SizedBox(height: 24),
          _buildTimeSlotsSection(),
          const SizedBox(height: 24),
          _buildSelectionItem(
            label: '上课周数',
            value: weekText,
            onTap: _pickWeeks,
          ),
          const SizedBox(height: 12),
          _buildColorItem(),
          const SizedBox(height: 100),
        ],
      ),
      bottomNavigationBar: widget.course != null
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: _buildDeleteButton(),
              ),
            )
          : null,
    );
  }

  Widget _buildDeleteButton() {
    return GestureDetector(
      onTap: _deleteCourse,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 48),
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
      Navigator.pop(context, 'delete'); // 返回删除信号
    }
  }

  Widget _buildSuggestionItem(Course course) {
    return InkWell(
      onTap: () {
        _nameController.text = course.name;
        _teacherController.text = course.teacher;
        setState(() {
          _selectedColor = course.color;
          _suggestions = [];
        });
        // 如果当前教室为空且选中课程有教室信息，则自动填充
        if (_classroomController.text.isEmpty && course.sessions.isNotEmpty) {
          _classroomController.text = course.sessions.first.location;
        }
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
                // 暗色模式下降低课程颜色亮度以匹配深色界面
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

  Widget _buildInputGroup({
    required String label,
    required TextEditingController controller,
    required String placeholder,
    required bool isLast,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color:
            Theme.of(context).cardTheme.color ??
            Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textAlign: TextAlign.left,
              decoration: InputDecoration(
                filled: false,
                hintText: placeholder,
                hintStyle: const TextStyle(color: Color(0xFFC4C4C6)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
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

  Widget _buildTimeSlotsSection() {
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '时段',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    // 时段计数器底色采用整体背景色
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCounterButton(
                        icon: Icons.remove,
                        onTap: _decrementSessions,
                      ),
                      SizedBox(
                        width: 30,
                        child: Text(
                          '${_sessions.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      _buildCounterButton(
                        icon: Icons.add,
                        onTap: _incrementSessions,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_sessions.isNotEmpty)
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ..._sessions.asMap().entries.map((entry) {
            final index = entry.key;
            final session = entry.value;
            final isLast = index == _sessions.length - 1;
            final isExpanded = _expandedSessionIndex == index;

            String timeText = '周${_weekdayToString(session.weekday)} ';
            if (session.sectionCount == 1) {
              timeText += '第 ${session.startSection} 节';
            } else {
              timeText +=
                  '第 ${session.startSection}-${session.startSection + session.sectionCount - 1} 节';
            }
            return ExpandableItem(
              title: '课程时间 ${index + 1}',
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
                  if (_expandedSessionIndex == index) {
                    _expandedSessionIndex = null;
                  } else {
                    _expandedSessionIndex = index;
                  }
                });
              },
              content: _buildInlineTimePicker(index),
              showDivider: !isLast,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInlineTimePicker(int index) {
    final session = _sessions[index];
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
          final double gap = 1.0; // 再缩小间距为 1px
          final double symbolWidth = 28.0; // '到' 和 '节' 文字宽度估算
          // 根据字体动态计算 picker 宽度范围，确保 2x 字体也能显示
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
                      _sessions[index] = CourseSession(
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
              SizedBox(
                width: pickerWidth,
                child: CupertinoPicker(
                  key: ValueKey('start_picker_${index}_$_pickerResetVersion'),
                  selectionOverlay: Container(),
                  itemExtent: kPickerItemExtent,
                  scrollController: FixedExtentScrollController(
                    initialItem: session.startSection - 1,
                  ),
                  onSelectedItemChanged: (newIndex) {
                    final newStart = newIndex + 1;
                    // 计算当前的结束时间
                    final currentEnd =
                        session.startSection + session.sectionCount - 1;

                    // 验证跨段
                    int validatedStart = newStart;

                    // 情况1: newStart > currentEnd (发生交换)
                    // 实际区间变为 [currentEnd, newStart]
                    if (newStart > currentEnd) {
                      final range = _getSegmentRange(currentEnd);
                      if (range != null && newStart > range.end) {
                        validatedStart = range.end;
                        // 强制刷新 UI
                        setState(() {
                          _pickerResetVersion++;
                        });
                      }
                    }
                    // 情况2: newStart <= currentEnd (正常)
                    // 实际区间变为 [newStart, currentEnd]
                    else {
                      final range = _getSegmentRange(currentEnd);
                      if (range != null && newStart < range.start) {
                        validatedStart = range.start;
                        // 强制刷新 UI
                        setState(() {
                          _pickerResetVersion++;
                        });
                      }
                    }

                    final newCount = currentEnd - validatedStart + 1;

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
                    _updateSession(index, newSession);
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
              SizedBox(
                width: pickerWidth,
                child: CupertinoPicker(
                  key: ValueKey('end_picker_${index}_$_pickerResetVersion'),
                  selectionOverlay: Container(),
                  itemExtent: kPickerItemExtent,
                  scrollController: FixedExtentScrollController(
                    initialItem: endSection - 1,
                  ),
                  onSelectedItemChanged: (newIndex) {
                    final newEnd = newIndex + 1;

                    // 验证跨段
                    int validatedEnd = newEnd;
                    final range = _getSegmentRange(session.startSection);

                    if (range != null) {
                      // 如果结束时间超过了当前段的结束时间
                      if (newEnd > range.end) {
                        validatedEnd = range.end;
                        setState(() {
                          _pickerResetVersion++;
                        });
                      }
                    }

                    // 限制结束节次不能小于开始节次
                    if (validatedEnd < session.startSection) {
                      // 采用修正策略：如果结束 < 开始，则结束 = 开始
                      validatedEnd = session.startSection;
                      setState(() {
                        _pickerResetVersion++;
                      });
                    }

                    final newCount = validatedEnd - session.startSection + 1;
                    final newSession = CourseSession(
                      weekday: session.weekday,
                      startSection: session.startSection,
                      sectionCount: newCount,
                      location: session.location,
                      startWeek: session.startWeek,
                      endWeek: session.endWeek,
                      weekType: session.weekType,
                      customWeeks: session.customWeeks,
                    );
                    _updateSession(index, newSession);
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

  Widget _buildCounterButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        color: Colors.transparent,
        child: Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSelectionItem({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
              label,
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    // 与课程背景色行的 > 箭头颜色保持一致
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ],
              ),
            ),
          ],
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
                    // 暗色模式下降低课程颜色亮度以匹配深色界面
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

  String _weekdayToString(int weekday) {
    const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    if (weekday >= 1 && weekday <= 7) return weekdays[weekday - 1];
    return '';
  }
}

class _WeekRangePicker extends StatefulWidget {
  final int initialStart;
  final int initialEnd;
  final CourseWeekType initialType;
  final List<int> initialCustomWeeks;
  final int maxWeek;

  const _WeekRangePicker({
    required this.initialStart,
    required this.initialEnd,
    required this.initialType,
    this.initialCustomWeeks = const [],
    required this.maxWeek,
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
      // 根据范围和类型初始化选择
      for (int i = widget.initialStart; i <= widget.initialEnd; i++) {
        if (widget.initialType == CourseWeekType.all) {
          _selectedWeeks.add(i);
        } else if (widget.initialType == CourseWeekType.single) {
          if (i % 2 != 0) _selectedWeeks.add(i);
        } else if (widget.initialType == CourseWeekType.double) {
          if (i % 2 == 0) _selectedWeeks.add(i);
        }
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
    setState(() {
      if (_selectedWeeks.contains(week)) {
        _selectedWeeks.remove(week);
      } else {
        _selectedWeeks.add(week);
      }
      _updateCurrentTypeFromSelection();
    });
  }

  void _updateCurrentTypeFromSelection() {
    if (_selectedWeeks.isEmpty) {
      _currentType = null;
      return;
    }

    final sortedWeeks = _selectedWeeks.toList()..sort();
    final start = sortedWeeks.first;
    final end = sortedWeeks.last;

    bool isAllOdd = true;
    bool isAllEven = true;

    for (final w in sortedWeeks) {
      if (w % 2 == 0) isAllOdd = false;
      if (w % 2 != 0) isAllEven = false;
    }

    CourseWeekType? candidateType;
    if (isAllOdd) {
      candidateType = CourseWeekType.single;
    } else if (isAllEven) {
      candidateType = CourseWeekType.double;
    } else {
      // 检查是否连续
      bool isContiguous = true;
      for (int i = 0; i < sortedWeeks.length - 1; i++) {
        if (sortedWeeks[i + 1] - sortedWeeks[i] != 1) {
          isContiguous = false;
          break;
        }
      }
      if (isContiguous) {
        candidateType = CourseWeekType.all;
      }
    }

    if (candidateType == null) {
      _currentType = null;
      return;
    }

    // 验证完整性：检查 start 到 end 之间是否包含了所有该类型应有的周次
    bool match = true;
    for (int i = start; i <= end; i++) {
      bool shouldHave = false;
      if (candidateType == CourseWeekType.all) {
        shouldHave = true;
      } else if (candidateType == CourseWeekType.single) {
        if (i % 2 != 0) shouldHave = true;
      } else if (candidateType == CourseWeekType.double) {
        if (i % 2 == 0) shouldHave = true;
      }

      if (shouldHave) {
        if (!_selectedWeeks.contains(i)) {
          match = false;
          break;
        }
      }
    }

    if (match) {
      _currentType = candidateType;
    } else {
      _currentType = null;
    }
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
                // 上课周数网格底色采用整体背景色
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
                  return GestureDetector(
                    onTap: () => _toggleWeek(week),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildCheckbox(isSelected),
                        const SizedBox(width: 6),
                        Text(
                          '$week',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
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
    return GestureDetector(
      onTap: () => _updateSelectionByType(type),
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
    );
  }

  Widget _buildCheckbox(bool isSelected) {
    // 选中颜色采用开关预览色：
    // 洁白/乌黑模式用 grey.shade700，彩色模式用 primary
    final Color activeColor = ThemeService.instance.isWhiteMode
        ? Colors.grey.shade700
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: isSelected ? activeColor : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: isSelected
            ? null
            : Border.all(color: const Color(0xFFC4C4C6), width: 1.5),
      ),
      child: isSelected
          ? Icon(
              Icons.check,
              size: 14,
              // 深色模式下打勾采用黑色以在亮色 primary 背景上清晰可见
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.black
                  : Colors.white,
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

    final sortedWeeks = _selectedWeeks.toList()..sort();
    final start = sortedWeeks.first;
    final end = sortedWeeks.last;

    // 根据选择确定类型
    CourseWeekType type = CourseWeekType.all;
    bool isAllOdd = true;
    bool isAllEven = true;

    for (final week in sortedWeeks) {
      if (week % 2 == 0) isAllOdd = false;
      if (week % 2 != 0) isAllEven = false;
    }

    if (isAllOdd) {
      type = CourseWeekType.single;
    } else if (isAllEven) {
      type = CourseWeekType.double;
    } else {
      type = CourseWeekType.all;
    }

    // 检查推断的类型是否完全匹配选中的周次
    Set<int> inferredWeeks = {};
    for (int i = start; i <= end; i++) {
      if (type == CourseWeekType.all) {
        inferredWeeks.add(i);
      } else if (type == CourseWeekType.single) {
        if (i % 2 != 0) inferredWeeks.add(i);
      } else if (type == CourseWeekType.double) {
        if (i % 2 == 0) inferredWeeks.add(i);
      }
    }

    List<int> customWeeks = [];
    bool match = true;
    if (inferredWeeks.length != sortedWeeks.length) {
      match = false;
    } else {
      for (int w in sortedWeeks) {
        if (!inferredWeeks.contains(w)) {
          match = false;
          break;
        }
      }
    }

    if (!match) {
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
                              '当前颜色正被“$courseName”使用',
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
                      // 暗色模式下应用 dim 效果，与课表中实际展示的颜色一致
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

class _CustomColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _CustomColorPickerDialog({required this.initialColor});

  @override
  State<_CustomColorPickerDialog> createState() =>
      _CustomColorPickerDialogState();
}

class _CustomColorPickerDialogState extends State<_CustomColorPickerDialog> {
  /// HSB 三通道（色相 0-360, 饱和度 0-1, 明度 0-1）
  late double _hue;
  late double _saturation;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    // 自定义添加颜色默认采用更柔和的课程色风格（贴近截图效果）
    _hue = hsv.hue;
    _saturation = hsv.saturation.clamp(0.25, 0.5);
    _brightness = hsv.value.clamp(0.85, 0.96);
  }

  /// 将当前 HSB 转换为 Color
  Color get _currentColor =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _brightness).toColor();

  /// 校验颜色是否可用——禁止添加纯黑/纯白/灰色
  String? _getInvalidColorReason(Color color) {
    final hsv = HSVColor.fromColor(color);

    // 判定黑色：亮度过低
    if (hsv.value < 0.2) {
      return '不能添加黑色';
    }

    // 判定低饱和度 (灰或白)
    if (hsv.saturation < 0.05) {
      if (hsv.value > 0.85) {
        return '不能添加白色';
      }
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
                    // ── 课程卡片预览 ──
                    _buildCoursePreview(currentColor),
                    const SizedBox(height: 16),
                    // ── SV 矩形色域（类似 Photoshop 的 SB 平面）──
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
                    // ── 色相条（彩虹渐变横条）──
                    SizedBox(
                      height: 22,
                      child: _CourseColorHueSlider(
                        hue: _hue,
                        onChanged: (h) => setState(() => _hue = h),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // ── Hex / R / G / B 输入 ──
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

  /// 课程卡片预览（左侧圆点 + 右侧课程卡片），视觉效果与截图保持一致
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

// ─── 课程色域选择器组件 ────────────────────────────────────────────

/// Photoshop 风格的 SV 矩形选色区
///
/// 横轴为饱和度（S），纵轴为明度（V/B）。
/// 通过手势拖拽选择颜色。
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
                // 圆形选择指示器
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
