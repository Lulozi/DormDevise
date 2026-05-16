import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dormdevise/utils/text_length_counter.dart';
import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/course_service.dart';
import 'widgets/schedule_settings_sheet.dart';
import 'widgets/section_config_sheet.dart';
import 'create_schedule_courses_page.dart';

class CreateScheduleSettingsPage extends StatefulWidget {
  /// 预填充的课程表名称（如从网页爬取导入）。
  final String? initialScheduleName;

  /// 预填充的课表节次配置。
  final CourseScheduleConfig? initialConfig;

  /// 预填充的学期开始日期。
  final DateTime? initialSemesterStart;

  /// 预填充的最大周数。
  final int? initialMaxWeek;

  /// 预填充是否显示周末。
  final bool? initialShowWeekend;

  /// 预填充是否显示非本周课程。
  final bool? initialShowNonCurrentWeek;

  /// 预填充课程表是否锁定。
  final bool initialLockSchedule;

  /// 从外部导入的课程列表（透传给下一步的课程页面）。
  final List<Course> initialCourses;

  const CreateScheduleSettingsPage({
    super.key,
    this.initialScheduleName,
    this.initialConfig,
    this.initialSemesterStart,
    this.initialMaxWeek,
    this.initialShowWeekend,
    this.initialShowNonCurrentWeek,
    this.initialLockSchedule = false,
    this.initialCourses = const <Course>[],
  });

  @override
  State<CreateScheduleSettingsPage> createState() =>
      _CreateScheduleSettingsPageState();
}

class _CreateScheduleSettingsPageState extends State<CreateScheduleSettingsPage>
    with TickerProviderStateMixin {
  // 新建课程表名称上限：30 个半角单位（中文按 2 计算）。
  static const int _tableNameMaxLengthUnits = 30;

  final TextEditingController _nameController = TextEditingController();
  late final AnimationController _nameErrorShakeController;
  late final Animation<double> _nameErrorShakeOffset;
  String? _nameErrorText;
  bool _isCheckingName = false;

  // 初始设置
  CourseScheduleConfig _scheduleConfig = CourseScheduleConfig.njuDefaults();
  late DateTime _semesterStart = (() {
    final now = DateTime.now();
    if (now.month >= 1 && now.month <= 7) {
      return DateTime(now.year, 2, 20);
    }
    return DateTime(now.year, 9, 1);
  })();
  int _currentWeek = 1;
  int _maxWeek = 20;
  String _tableName = '我的课表';
  bool _showWeekend = false;
  bool _showNonCurrentWeek = true;
  bool _isScheduleLocked = false;

  @override
  void initState() {
    super.initState();
    _nameErrorShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _nameErrorShakeOffset =
        TweenSequence<double>(<TweenSequenceItem<double>>[
          TweenSequenceItem<double>(
            tween: Tween<double>(begin: 0, end: -7),
            weight: 1,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(begin: -7, end: 7),
            weight: 1,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(begin: 7, end: -5),
            weight: 1,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(begin: -5, end: 5),
            weight: 1,
          ),
          TweenSequenceItem<double>(
            tween: Tween<double>(begin: 5, end: 0),
            weight: 1,
          ),
        ]).animate(
          CurvedAnimation(
            parent: _nameErrorShakeController,
            curve: Curves.easeOut,
          ),
        );

    // 使用外部传入的初始值预填充（如网页爬取导入场景）
    if (widget.initialScheduleName != null) {
      _nameController.text = widget.initialScheduleName!;
      _tableName = widget.initialScheduleName!;
    }
    if (widget.initialConfig != null) {
      _scheduleConfig = widget.initialConfig!;
    }
    if (widget.initialSemesterStart != null) {
      _semesterStart = widget.initialSemesterStart!;
    }
    if (widget.initialMaxWeek != null) {
      _maxWeek = widget.initialMaxWeek!;
    }
    if (widget.initialShowWeekend != null) {
      _showWeekend = widget.initialShowWeekend!;
    }
    if (widget.initialShowNonCurrentWeek != null) {
      _showNonCurrentWeek = widget.initialShowNonCurrentWeek!;
    }
    _isScheduleLocked = widget.initialLockSchedule;
  }

  @override
  void dispose() {
    _nameErrorShakeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  int _currentNameUnits() {
    return TextLengthCounter.computeHalfWidthUnits(_nameController.text);
  }

  bool _isNameLengthExceeded() {
    return _currentNameUnits() > _tableNameMaxLengthUnits;
  }

  Future<void> _showNameValidationError(String message) async {
    setState(() {
      _nameErrorText = message;
    });
    await HapticFeedback.mediumImpact();
    if (!mounted) {
      return;
    }
    // 通过抖动红色错误文本强调失败原因，和昵称弹窗反馈保持一致。
    _nameErrorShakeController.forward(from: 0);
  }

  void _onNext() async {
    if (_isCheckingName) {
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      await _showNameValidationError('课程表名称不能为空！');
      return;
    }
    if (_isNameLengthExceeded()) {
      await _showNameValidationError('课程表名称超出字数限制！');
      return;
    }

    setState(() {
      _isCheckingName = true;
    });

    // 校验是否名称重复
    try {
      final schedules = await CourseService.instance.loadSchedules();
      if (schedules.any((s) => s.name == name)) {
        if (!mounted) {
          return;
        }
        await _showNameValidationError('课程表名称已存在！');
        return;
      }
    } catch (e) {
      // 忽略错误（或在需要时处理），不阻塞流程
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingName = false;
        });
      }
    }

    if (!mounted) {
      return;
    }

    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateScheduleCoursesPage(
          scheduleName: name,
          scheduleConfig: _scheduleConfig,
          semesterStart: _semesterStart,
          currentWeek: _currentWeek,
          maxWeek: _maxWeek,
          tableName: name,
          showWeekend: _showWeekend,
          showNonCurrentWeek: _showNonCurrentWeek,
          isScheduleLocked: _isScheduleLocked,
          initialCourses: widget.initialCourses,
        ),
      ),
    );

    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openSectionSettings() async {
    final CourseScheduleConfig? result =
        await showModalBottomSheet<CourseScheduleConfig>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return SectionConfigSheet(
              scheduleConfig: _scheduleConfig,
              onSubmit: (CourseScheduleConfig updated) {
                Navigator.of(context).pop(updated);
              },
            );
          },
        );
    if (result != null) {
      setState(() {
        _scheduleConfig = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final int currentNameUnits = _currentNameUnits();
    final bool isNameLengthExceeded = _isNameLengthExceeded();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontSize: 16,
            ),
          ),
        ),
        leadingWidth: 80,
        title: Text(
          '确认课程表基本信息',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            // 名称空时也允许点击，由 _onNext 统一触发震动+抖动验证反馈
            onPressed: !_isCheckingName ? _onNext : null,
            child: Text(
              _isCheckingName ? '校验中' : '下一步',
              style: TextStyle(
                color: _nameController.text.isNotEmpty && !_isCheckingName
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: ScheduleSettingsPage(
        isEmbedded: true,
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: Text(
                  '以下信息对计算周数、课表展示很重要，请认真填写。',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: '课程表名称 (必填)',
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  counterText: '',
                  counter: Text(
                    '$currentNameUnits/$_tableNameMaxLengthUnits',
                    style: TextStyle(
                      color: isNameLengthExceeded
                          ? colorScheme.error
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                onChanged: (value) => setState(() {
                  _tableName = value;
                  _nameErrorText = null;
                }),
              ),
            ),
            if (_nameErrorText != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                child: AnimatedBuilder(
                  animation: _nameErrorShakeController,
                  builder: (_, Widget? child) {
                    return Transform.translate(
                      offset: Offset(_nameErrorShakeOffset.value, 0),
                      child: child,
                    );
                  },
                  child: Text(
                    _nameErrorText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colorScheme.error,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        scheduleConfig: _scheduleConfig,
        semesterStart: _semesterStart,
        currentWeek: _currentWeek,
        maxWeek: _maxWeek,
        tableName: _tableName,
        showWeekend: _showWeekend,
        showNonCurrentWeek: _showNonCurrentWeek,
        isScheduleLocked: _isScheduleLocked,
        onConfigChanged: (v) => setState(() => _scheduleConfig = v),
        onSemesterStartChanged: (v) => setState(() => _semesterStart = v),
        onCurrentWeekChanged: (v) => setState(() => _currentWeek = v),
        onMaxWeekChanged: (v) => setState(() => _maxWeek = v),
        onTableNameChanged: (v) => setState(() => _tableName = v),
        onShowWeekendChanged: (v) => setState(() => _showWeekend = v),
        onShowNonCurrentWeekChanged: (v) =>
            setState(() => _showNonCurrentWeek = v),
        onScheduleLockedChanged: (v) => setState(() => _isScheduleLocked = v),
        onOpenSectionSettings: _openSectionSettings,
      ),
    );
  }
}
