import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';

import '../../../../models/course_schedule_config.dart';
import '../../../../models/schedule_metadata.dart';
import '../../../../services/course_service.dart';
import '../../widgets/bottom_sheet_confirm.dart';
import 'widgets/schedule_settings_sheet.dart';
import 'create_schedule_settings_page.dart';

class AllSchedulesPage extends StatefulWidget {
  final CourseScheduleConfig scheduleConfig;
  final DateTime semesterStart;
  final int currentWeek;
  final int maxWeek;
  final String tableName;
  final bool showWeekend;
  final bool showNonCurrentWeek;
  final bool isScheduleLocked;
  final ValueChanged<CourseScheduleConfig> onConfigChanged;
  final ValueChanged<DateTime> onSemesterStartChanged;
  final ValueChanged<int> onCurrentWeekChanged;
  final ValueChanged<int> onMaxWeekChanged;
  final ValueChanged<String> onTableNameChanged;
  final ValueChanged<bool> onShowWeekendChanged;
  final ValueChanged<bool> onShowNonCurrentWeekChanged;
  final ValueChanged<bool> onScheduleLockedChanged;
  final VoidCallback onOpenSectionSettings;

  const AllSchedulesPage({
    super.key,
    required this.scheduleConfig,
    required this.semesterStart,
    required this.currentWeek,
    required this.maxWeek,
    required this.tableName,
    required this.showWeekend,
    required this.showNonCurrentWeek,
    required this.isScheduleLocked,
    required this.onConfigChanged,
    required this.onSemesterStartChanged,
    required this.onCurrentWeekChanged,
    required this.onMaxWeekChanged,
    required this.onTableNameChanged,
    required this.onShowWeekendChanged,
    required this.onShowNonCurrentWeekChanged,
    required this.onScheduleLockedChanged,
    required this.onOpenSectionSettings,
  });

  @override
  State<AllSchedulesPage> createState() => _AllSchedulesPageState();
}

class _AllSchedulesPageState extends State<AllSchedulesPage> {
  late String _tableName;
  late CourseScheduleConfig _scheduleConfig;
  late DateTime _semesterStart;
  late int _currentWeek;
  late int _maxWeek;
  late bool _showWeekend;
  late bool _showNonCurrentWeek;
  late bool _isScheduleLocked;

  // _isAddMenuOpen 和 _addBtnKey 用于旧的气泡菜单，现在不再需要
  final GlobalKey _addBtnKey = GlobalKey();

  List<ScheduleMetadata> _schedules = [];
  String _currentScheduleId = '';
  bool _isLoading = true;

  // 选择模式开关
  bool _isSelectionMode = false;
  final Set<String> _selectedIds = {};
  final Set<String> _deletingIds = {};

  // 动画状态标记
  String? _newlyAddedId;
  bool _shouldFlashNewlyAdded = true;

  String? _initialScheduleId;

  @override
  void initState() {
    super.initState();
    _tableName = widget.tableName;
    _scheduleConfig = widget.scheduleConfig;
    _semesterStart = widget.semesterStart;
    _currentWeek = widget.currentWeek;
    _maxWeek = widget.maxWeek;
    _showWeekend = widget.showWeekend;
    _showNonCurrentWeek = widget.showNonCurrentWeek;
    _isScheduleLocked = widget.isScheduleLocked;
    _loadSchedules();
  }

  Future<void> _loadSchedules() async {
    final service = CourseService.instance;
    final schedules = await service.loadSchedules();
    final currentId = await service.getCurrentScheduleId();
    if (mounted) {
      setState(() {
        _schedules = schedules;
        _currentScheduleId = currentId;
        _initialScheduleId ??= currentId;
        _isLoading = false;
      });
    }
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _schedules.length) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_schedules.map((s) => s.id));
      }
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    String title;
    if (_selectedIds.length == 1) {
      final id = _selectedIds.first;
      final schedule = _schedules.firstWhere(
        (s) => s.id == id,
        orElse: () => ScheduleMetadata(id: '', name: ''),
      );
      title = '确定删除“${schedule.name}”课程表吗？';
    } else {
      title = '确定删除${_selectedIds.length}个课程表吗？';
    }

    final bool? confirm = await BottomSheetConfirm.show(context, title: title);

    if (confirm == true) {
      setState(() {
        _deletingIds.addAll(_selectedIds);
      });

      // 等待动画完成
      await Future.delayed(const Duration(milliseconds: 400));
      // 判断是否删除了全部课程表
      final bool deletingAll = _selectedIds.length == _schedules.length;

      await CourseService.instance.deleteSchedules(_selectedIds.toList());
      _toggleSelectionMode();

      // 重新加载列表
      final service = CourseService.instance;
      final schedules = await service.loadSchedules();
      final currentId = await service.getCurrentScheduleId();

      // 如果删除了全部课程表（导致自动创建了新表），或者当前课表ID发生了变化
      // 我们需要重新加载当前课表的配置，以确保 _openSettings 使用的是最新数据
      if (deletingAll || currentId != _currentScheduleId) {
        final newConfig = await service.loadConfig(currentId);
        final newSemesterStart =
            await service.loadSemesterStart(currentId) ??
            DateTime(DateTime.now().year, 9, 1);
        final newMaxWeek = await service.loadMaxWeek(currentId);
        final newTableName = await service.loadTableName(currentId);
        final newShowWeekend = await service.loadShowWeekend(currentId);
        final newShowNonCurrentWeek = await service.loadShowNonCurrentWeek(
          currentId,
        );
        final newIsScheduleLocked = await service.loadScheduleLocked(currentId);

        if (mounted) {
          setState(() {
            _scheduleConfig = newConfig;
            _semesterStart = newSemesterStart;
            _maxWeek = newMaxWeek;
            _tableName = newTableName;
            _showWeekend = newShowWeekend;
            _showNonCurrentWeek = newShowNonCurrentWeek;
            _isScheduleLocked = newIsScheduleLocked;
          });
        }
      }

      if (mounted) {
        setState(() {
          _deletingIds.clear();
          _schedules = schedules;
          _currentScheduleId = currentId;
          _isLoading = false;

          // 若删除了全部课程表，则自动创建的默认课表视为新建并播放入场动画
          if (deletingAll && schedules.isNotEmpty) {
            _newlyAddedId = schedules.first.id;
            _shouldFlashNewlyAdded = false;
          }
        });

        // 检查是否需要强制刷新上层
        // 由于 deleteSchedules 内部处理了 currentId 的重置，
        // 我们只需要确保 TablePage 知道发生了变化。
        // 目前 TablePage 在 pop(true) 时会刷新。
        // 但这里我们还在 AllSchedulesPage 内部。
        // 如果删除了当前课表，_currentScheduleId 会变。
        final newCurrentId = await CourseService.instance
            .getCurrentScheduleId();
        if (newCurrentId != _currentScheduleId) {
          // 如果当前课表变了，我们应该通知 TablePage
          // 但 AllSchedulesPage 是 push 进来的，我们不能直接通知
          // 只能在 pop 时返回 true
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant AllSchedulesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tableName != widget.tableName) {
      _tableName = widget.tableName;
    }
    if (oldWidget.scheduleConfig != widget.scheduleConfig) {
      _scheduleConfig = widget.scheduleConfig;
    }
    if (oldWidget.semesterStart != widget.semesterStart) {
      _semesterStart = widget.semesterStart;
    }
    if (oldWidget.currentWeek != widget.currentWeek) {
      _currentWeek = widget.currentWeek;
    }
    if (oldWidget.maxWeek != widget.maxWeek) {
      _maxWeek = widget.maxWeek;
    }
    if (oldWidget.showWeekend != widget.showWeekend) {
      _showWeekend = widget.showWeekend;
    }
    if (oldWidget.showNonCurrentWeek != widget.showNonCurrentWeek) {
      _showNonCurrentWeek = widget.showNonCurrentWeek;
    }
    if (oldWidget.isScheduleLocked != widget.isScheduleLocked) {
      _isScheduleLocked = widget.isScheduleLocked;
    }
  }

  // BubblePopupController? _bubbleController;  // 不再需要

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_isSelectionMode) {
          _toggleSelectionMode();
        } else {
          // 正常返回时，如果当前课表ID变了，也应该返回true
          if (_initialScheduleId != null &&
              _currentScheduleId != _initialScheduleId) {
            Navigator.of(context).pop(true);
          } else {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
          leading: _isSelectionMode
              ? TextButton(
                  onPressed: _selectAll,
                  child: Text(
                    _selectedIds.length == _schedules.length ? '全不选' : '全选',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              : IconButton(
                  icon: Icon(
                    Icons.arrow_back_ios_new,
                    color: colorScheme.onSurface,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          leadingWidth: _isSelectionMode ? 80 : null,
          title: Text(
            _isSelectionMode ? '已选择${_selectedIds.length}项' : '全部课程表',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            if (_isSelectionMode)
              TextButton(
                onPressed: _toggleSelectionMode,
                child: Text(
                  '取消',
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else ...[
              IconButton(
                icon: FaIcon(
                  FontAwesomeIcons.squareCheck,
                  color: colorScheme.primary,
                  size: 22,
                ),
                onPressed: _toggleSelectionMode,
              ),
              IconButton(
                key: _addBtnKey,
                icon: Icon(Icons.add, color: colorScheme.primary, size: 28),
                onPressed: () async {
                  // 直接跳转到手动创建页
                  final result = await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const CreateScheduleSettingsPage(),
                    ),
                  );
                  if (result == true && mounted) {
                    await _loadSchedules();
                    if (_schedules.isNotEmpty) {
                      setState(() {
                        _newlyAddedId = _schedules.first.id;
                        _shouldFlashNewlyAdded = true;
                      });
                    }
                  }
                },
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            // 使用自定义 Overlay 包裹列表，使拖拽代理在删除按钮的下层
            Positioned.fill(
              child: _ReorderableOverlay(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                  header: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _isSelectionMode
                          ? '删除全部课程表将自动生成默认课程表'
                          : '点击课程表卡片可切换当前并查看课程',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ),
                  itemCount: _schedules.length,
                  onReorder: (int oldIndex, int newIndex) {
                    setState(() {
                      if (oldIndex < newIndex) {
                        newIndex -= 1;
                      }
                      final item = _schedules.removeAt(oldIndex);
                      _schedules.insert(newIndex, item);
                    });
                    CourseService.instance.updateScheduleOrder(_schedules);
                  },
                  proxyDecorator: (child, index, animation) {
                    return Material(color: Colors.transparent, child: child);
                  },
                  buildDefaultDragHandles: false,
                  itemBuilder: (context, index) {
                    final schedule = _schedules[index];
                    final isNew = schedule.id == _newlyAddedId;
                    final isDeleting = _deletingIds.contains(schedule.id);

                    if (isDeleting) {
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(schedule.id),
                        tween: Tween(begin: 1.0, end: 0.0),
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeInQuart,
                        builder: (context, value, child) {
                          return ClipRect(
                            child: Align(
                              alignment: Alignment.topCenter,
                              heightFactor: value,
                              child: Opacity(
                                opacity: value.clamp(0.0, 1.0),
                                child: child,
                              ),
                            ),
                          );
                        },
                        child: _buildScheduleCard(
                          context,
                          isCurrent: schedule.id == _currentScheduleId,
                          name: schedule.name,
                          id: schedule.id,
                          index: index,
                        ),
                      );
                    }

                    if (isNew) {
                      return TweenAnimationBuilder<double>(
                        key: ValueKey(schedule.id),
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: const Duration(milliseconds: 1200),
                        curve: Curves.linear,
                        onEnd: () {
                          if (mounted) {
                            setState(() {
                              _newlyAddedId = null;
                            });
                          }
                        },
                        builder: (context, value, child) {
                          // 1. 滑动动画 (0ms - 800ms)
                          // 动画滑动阶段：value 0.0 -> 0.666
                          final double slideInput = (value / 0.666).clamp(
                            0.0,
                            1.0,
                          );
                          final double slideValue = Curves.easeOutQuart
                              .transform(slideInput);

                          // 2. 闪烁动画 (400ms - 1200ms)
                          // 闪烁阶段：value 0.333 -> 1.0
                          // 在滑动动画进行到一半时开始触发（时间上）
                          final double flashInput = ((value - 0.333) / 0.666)
                              .clamp(0.0, 1.0);

                          Color? flashColor;
                          if (_shouldFlashNewlyAdded && flashInput > 0) {
                            // 使用抛物线形曲线实现单次平滑闪烁：0 -> 1 -> 0
                            // 模拟一次呼吸/闪烁效果
                            final double flashIntensity =
                                4 * flashInput * (1 - flashInput);
                            flashColor = Color.lerp(
                              colorScheme.surface,
                              Theme.of(
                                context,
                              ).primaryColor.withValues(alpha: 0.3),
                              flashIntensity,
                            );
                          }

                          return Align(
                            alignment: Alignment.topCenter,
                            heightFactor: slideValue,
                            child: Transform.translate(
                              offset: Offset(0, 40 * (1 - slideValue)),
                              child: Opacity(
                                opacity: slideValue.clamp(0.0, 1.0),
                                child: _buildScheduleCard(
                                  context,
                                  isCurrent: schedule.id == _currentScheduleId,
                                  name: schedule.name,
                                  id: schedule.id,
                                  index: index,
                                  backgroundColor: flashColor,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }

                    return Container(
                      key: ValueKey(schedule.id),
                      child: _buildScheduleCard(
                        context,
                        isCurrent: schedule.id == _currentScheduleId,
                        name: schedule.name,
                        id: schedule.id,
                        index: index,
                      ),
                    );
                  },
                ),
              ),
            ),
            if (_isLoading)
              Positioned.fill(
                child: Container(
                  color: colorScheme.surface.withValues(alpha: 0.6),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            if (_isSelectionMode)
              Positioned(
                left: 48,
                right: 48,
                bottom: 32,
                child: SafeArea(
                  child: GestureDetector(
                    onTap: _selectedIds.isEmpty ? null : _deleteSelected,
                    child: Container(
                      height: 72,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color.fromRGBO(0, 0, 0, 0.08),
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
                            color: _selectedIds.isEmpty
                                ? Colors.grey
                                : colorScheme.primary,
                            size: 26,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '删除',
                            style: TextStyle(
                              color: _selectedIds.isEmpty
                                  ? Colors.grey
                                  : colorScheme.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(
    BuildContext context, {
    required bool isCurrent,
    required String name,
    required String id,
    required int index,
    Color? backgroundColor,
  }) {
    final bool isSelected = _selectedIds.contains(id);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (Theme.of(context).cardTheme.color ?? colorScheme.surface),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onLongPress: () {
            if (!_isSelectionMode) {
              _toggleSelectionMode();
              _toggleSelection(id);
            }
          },
          onTap: () async {
            if (_isSelectionMode) {
              _toggleSelection(id);
            } else {
              if (!isCurrent) {
                await CourseService.instance.switchSchedule(id);
                if (context.mounted) {
                  Navigator.of(context).pop(true);
                }
              } else {
                // 如果点击的是当前课表，且当前课表ID与进入页面时的ID不同（说明发生了切换或重建），则返回true刷新
                if (_initialScheduleId != null && id != _initialScheduleId) {
                  Navigator.of(context).pop(true);
                } else {
                  Navigator.of(context).pop();
                }
              }
            }
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Row(
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  child: _isSelectionMode
                      ? Padding(
                          // 缩小右侧间距，让选择框更紧凑，并垂直居中对齐文本
                          padding: const EdgeInsets.only(right: 8),
                          child: Center(
                            child: _buildAnimatedCheckbox(isSelected),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '当前',
                      style: TextStyle(
                        fontSize: 10,
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (_isSelectionMode)
                  ReorderableDragStartListener(
                    index: index,
                    child: Container(
                      padding: const EdgeInsets.only(left: 16),
                      color: Colors.transparent,
                      child: const Icon(Icons.drag_handle, color: Colors.grey),
                    ),
                  )
                else
                  Material(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        _openSettings(context, id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Text(
                          '设置',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCheckbox(bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      // 尺寸调整（与文字高度更接近，用于对齐）
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: isSelected ? colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
          width: 1.2,
        ),
      ),
      // 把勾选图标的大小缩成与文字更协同的尺寸
      child: isSelected
          ? const Icon(Icons.check, size: 12, color: Colors.white)
          : null,
    );
  }

  Future<void> _openSettings(BuildContext context, String scheduleId) async {
    CourseScheduleConfig config;
    DateTime semesterStart;
    int currentWeek;
    int maxWeek;
    String tableName;
    bool showWeekend;
    bool showNonCurrentWeek;
    bool isScheduleLocked;

    if (scheduleId == _currentScheduleId) {
      config = _scheduleConfig;
      semesterStart = _semesterStart;
      currentWeek = _currentWeek;
      maxWeek = _maxWeek;
      tableName = _tableName;
      showWeekend = _showWeekend;
      showNonCurrentWeek = _showNonCurrentWeek;
      isScheduleLocked = _isScheduleLocked;
    } else {
      final service = CourseService.instance;
      config = await service.loadConfig(scheduleId);
      semesterStart =
          await service.loadSemesterStart(scheduleId) ?? DateTime(2025, 9, 1);
      maxWeek = await service.loadMaxWeek(scheduleId);
      tableName = await service.loadTableName(scheduleId);
      showWeekend = await service.loadShowWeekend(scheduleId);
      showNonCurrentWeek = await service.loadShowNonCurrentWeek(scheduleId);
      isScheduleLocked = await service.loadScheduleLocked(scheduleId);

      final DateTime now = DateTime.now();
      final DateTime firstWeekStart = semesterStart.subtract(
        Duration(days: semesterStart.weekday - 1),
      );
      final int diffDays = now.difference(firstWeekStart).inDays;
      currentWeek = (diffDays / 7).floor() + 1;
      if (currentWeek < 1) currentWeek = 1;
      if (currentWeek > maxWeek) currentWeek = maxWeek;
    }

    if (!context.mounted) return;

    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (BuildContext context) {
          return ScheduleSettingsPage(
            saveNotificationImmediately: false,
            scheduleId: scheduleId,
            scheduleConfig: config,
            semesterStart: semesterStart,
            currentWeek: currentWeek,
            maxWeek: maxWeek,
            tableName: tableName,
            showWeekend: showWeekend,
            showNonCurrentWeek: showNonCurrentWeek,
            isScheduleLocked: isScheduleLocked,
            nameValidator: (name) async {
              final exists = _schedules.any(
                (s) => s.name == name && s.id != scheduleId,
              );
              if (exists) {
                return '课程表名称 "$name" 已存在';
              }
              return null;
            },
            onConfigChanged: (newConfig) async {
              if (scheduleId == _currentScheduleId) {
                widget.onConfigChanged(newConfig);
                setState(() => _scheduleConfig = newConfig);
              }
              await CourseService.instance.saveConfig(newConfig, scheduleId);
              config = newConfig; // 更新本地变量
            },
            onSemesterStartChanged: (date) async {
              if (scheduleId == _currentScheduleId) {
                widget.onSemesterStartChanged(date);
                setState(() => _semesterStart = date);
              }
              await CourseService.instance.saveSemesterStart(date, scheduleId);
              semesterStart = date; // 更新本地变量
            },
            onCurrentWeekChanged: (week) {
              if (scheduleId == _currentScheduleId) {
                widget.onCurrentWeekChanged(week);
                setState(() => _currentWeek = week);
              }
              currentWeek = week; // 更新本地变量
            },
            onMaxWeekChanged: (max) async {
              if (scheduleId == _currentScheduleId) {
                widget.onMaxWeekChanged(max);
                setState(() => _maxWeek = max);
              }
              await CourseService.instance.saveMaxWeek(max, scheduleId);
              maxWeek = max; // 更新本地变量
            },
            onTableNameChanged: (newName) async {
              if (scheduleId == _currentScheduleId) {
                widget.onTableNameChanged(newName);
                setState(() {
                  _tableName = newName;
                });
              }

              final index = _schedules.indexWhere((s) => s.id == scheduleId);
              if (index != -1) {
                setState(() {
                  _schedules[index] = ScheduleMetadata(
                    id: scheduleId,
                    name: newName,
                  );
                });
              }

              await CourseService.instance.saveTableName(newName, scheduleId);
              tableName = newName; // 更新本地变量
            },
            onShowWeekendChanged: (show) async {
              if (scheduleId == _currentScheduleId) {
                widget.onShowWeekendChanged(show);
                setState(() => _showWeekend = show);
              }
              await CourseService.instance.saveShowWeekend(show, scheduleId);
              showWeekend = show; // 更新本地变量
            },
            onShowNonCurrentWeekChanged: (show) async {
              if (scheduleId == _currentScheduleId) {
                widget.onShowNonCurrentWeekChanged(show);
                setState(() => _showNonCurrentWeek = show);
              }
              await CourseService.instance.saveShowNonCurrentWeek(
                show,
                scheduleId,
              );
              showNonCurrentWeek = show; // 更新本地变量
            },
            onScheduleLockedChanged: (locked) async {
              if (scheduleId == _currentScheduleId) {
                widget.onScheduleLockedChanged(locked);
                setState(() => _isScheduleLocked = locked);
              }
              await CourseService.instance.saveScheduleLocked(
                locked,
                scheduleId,
              );
              isScheduleLocked = locked;
            },
            onOpenSectionSettings: () {
              if (scheduleId == _currentScheduleId) {
                widget.onOpenSectionSettings();
              } else {
                AppToast.show(context, '请切换到该课程表后再设置课程时间');
              }
            },
          );
        },
      ),
    );

    // 重新加载课程表以反映名称变更
    _loadSchedules();
  }
}

/// 将子组件包裹在独立的 [Overlay] 中，
/// 使 [ReorderableListView] 的拖拽代理渲染在此 Overlay 内部，
/// 而非全局 Overlay，从而让 Stack 中后续子项（如删除按钮）位于拖拽卡片上方。
class _ReorderableOverlay extends StatefulWidget {
  final Widget child;
  const _ReorderableOverlay({required this.child});

  @override
  State<_ReorderableOverlay> createState() => _ReorderableOverlayState();
}

class _ReorderableOverlayState extends State<_ReorderableOverlay> {
  late final OverlayEntry _entry;

  @override
  void initState() {
    super.initState();
    _entry = OverlayEntry(builder: (_) => widget.child);
  }

  @override
  void didUpdateWidget(covariant _ReorderableOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 父组件重建时刷新 OverlayEntry 内容
    _entry.markNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entry]);
  }
}
