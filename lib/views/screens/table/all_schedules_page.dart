import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../../models/course_schedule_config.dart';
import '../../../../models/schedule_metadata.dart';
import '../../../../services/course_service.dart';
import '../../widgets/bottom_sheet_confirm.dart';
import 'widgets/section_config_sheet.dart';
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
  bool _shouldJumpToCurrentWeekOnExit = false;
  bool _shouldRefreshOnExit = false;

  String? _initialScheduleId;

  String _formatScheduleNameForDisplay(String name) {
    final String normalized = name.trim();
    if (normalized.isEmpty) {
      return '未命名课程表';
    }
    // 为连续英文/数字注入零宽断行点，避免长串导致右侧按钮被挤出。
    return normalized.replaceAllMapped(RegExp(r'[A-Za-z0-9_]{8,}'), (Match m) {
      final String token = m.group(0)!;
      return token.split('').join('\u200B');
    });
  }

  /// 根据可用宽度和名称长度自适应字号，优先完整显示课程表名。
  double _resolveScheduleNameFontSize({
    required int charCount,
    required double maxWidth,
  }) {
    double size = 16;
    if (maxWidth < 220 || charCount > 12) {
      size = 15;
    }
    if (maxWidth < 180 || charCount > 18) {
      size = 14;
    }
    if (maxWidth < 150 || charCount > 24) {
      size = 13;
    }
    return size;
  }

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

  void _markCurrentScheduleNeedsRefresh({bool jumpToCurrentWeek = false}) {
    _shouldRefreshOnExit = true;
    if (jumpToCurrentWeek) {
      _shouldJumpToCurrentWeekOnExit = true;
    }
  }

  Future<CourseScheduleConfig?> _openSectionSettingsSheet(
    BuildContext context,
    CourseScheduleConfig scheduleConfig,
  ) {
    return showModalBottomSheet<CourseScheduleConfig>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return SectionConfigSheet(
          scheduleConfig: scheduleConfig,
          onSubmit: (CourseScheduleConfig updated) {
            Navigator.of(context).pop(updated);
          },
        );
      },
    );
  }

  void _popWithRefreshResult() {
    final bool didSwitchCurrentSchedule =
        _initialScheduleId != null && _currentScheduleId != _initialScheduleId;
    if (_shouldJumpToCurrentWeekOnExit) {
      Navigator.of(context).pop('jump_to_current_week');
      return;
    }
    if (_shouldRefreshOnExit || didSwitchCurrentSchedule) {
      Navigator.of(context).pop('refresh_only');
      return;
    }
    Navigator.of(context).pop();
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
      final bool currentScheduleChanged = currentId != _currentScheduleId;

      // 如果删除了全部课程表（导致自动创建了新表），或者当前课表ID发生了变化
      // 我们需要重新加载当前课表的配置，以确保 _openSettings 使用的是最新数据
      if (deletingAll || currentId != _currentScheduleId) {
        final snapshot = await service.loadScheduleSnapshot(
          scheduleId: currentId,
        );
        final newConfig = CourseScheduleConfig.fromJson(
          snapshot.config.toJson(),
        );
        final newSemesterStart =
            snapshot.semesterStart ?? DateTime(DateTime.now().year, 9, 1);
        final newMaxWeek = snapshot.maxWeek;
        final newTableName = snapshot.tableName;
        final newShowWeekend = snapshot.showWeekend;
        final newShowNonCurrentWeek = snapshot.showNonCurrentWeek;
        final newIsScheduleLocked = snapshot.isScheduleLocked;

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

        if (currentScheduleChanged) {
          _markCurrentScheduleNeedsRefresh(jumpToCurrentWeek: true);
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
          // 避免在导航器锁定期间重入 pop。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _popWithRefreshResult();
          });
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
                  onPressed: _popWithRefreshResult,
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
                        _shouldJumpToCurrentWeekOnExit = true;
                        _shouldRefreshOnExit = true;
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
                  Navigator.of(context).pop('jump_to_current_week');
                }
              } else {
                // 如果点击的是当前课表，且当前课表ID与进入页面时的ID不同（说明发生了切换或重建），则返回true刷新
                if (_initialScheduleId != null && id != _initialScheduleId) {
                  _popWithRefreshResult();
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
                Expanded(
                  child: Row(
                    children: [
                      // 课程表名称在窄屏下自动缩小字号并换行，避免被“当前/设置”区域截断。
                      Expanded(
                        child: LayoutBuilder(
                          builder:
                              (
                                BuildContext context,
                                BoxConstraints constraints,
                              ) {
                                final String normalizedName = name.trim();
                                final int nameChars = normalizedName.isEmpty
                                    ? 5
                                    : normalizedName.runes.length;
                                final double fontSize =
                                    _resolveScheduleNameFontSize(
                                      charCount: nameChars,
                                      maxWidth: constraints.maxWidth,
                                    );
                                return Text(
                                  _formatScheduleNameForDisplay(name),
                                  softWrap: true,
                                  overflow: TextOverflow.visible,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    height: 1.25,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSurface,
                                  ),
                                );
                              },
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
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
    CourseScheduleConfig draftConfig;
    DateTime draftSemesterStart;
    int draftCurrentWeek;
    int draftMaxWeek;
    String draftTableName;
    bool draftShowWeekend;
    bool draftShowNonCurrentWeek;
    bool draftIsScheduleLocked;

    if (scheduleId == _currentScheduleId) {
      draftConfig = CourseScheduleConfig.fromJson(_scheduleConfig.toJson());
      draftSemesterStart = _semesterStart;
      draftCurrentWeek = _currentWeek;
      draftMaxWeek = _maxWeek;
      draftTableName = _tableName;
      draftShowWeekend = _showWeekend;
      draftShowNonCurrentWeek = _showNonCurrentWeek;
      draftIsScheduleLocked = _isScheduleLocked;
    } else {
      final service = CourseService.instance;
      final snapshot = await service.loadScheduleSnapshot(
        scheduleId: scheduleId,
      );
      draftConfig = CourseScheduleConfig.fromJson(snapshot.config.toJson());
      draftSemesterStart = snapshot.semesterStart ?? DateTime(2025, 9, 1);
      draftMaxWeek = snapshot.maxWeek;
      draftTableName = snapshot.tableName;
      draftShowWeekend = snapshot.showWeekend;
      draftShowNonCurrentWeek = snapshot.showNonCurrentWeek;
      draftIsScheduleLocked = snapshot.isScheduleLocked;

      final DateTime now = DateTime.now();
      final DateTime firstWeekStart = draftSemesterStart.subtract(
        Duration(days: draftSemesterStart.weekday - 1),
      );
      final int diffDays = now.difference(firstWeekStart).inDays;
      draftCurrentWeek = (diffDays / 7).floor() + 1;
      if (draftCurrentWeek < 1) draftCurrentWeek = 1;
      if (draftCurrentWeek > draftMaxWeek) draftCurrentWeek = draftMaxWeek;
    }

    final CourseScheduleConfig originalConfig = CourseScheduleConfig.fromJson(
      draftConfig.toJson(),
    );
    final DateTime originalSemesterStart = draftSemesterStart;
    final int originalCurrentWeek = draftCurrentWeek;
    final int originalMaxWeek = draftMaxWeek;
    final String originalTableName = draftTableName;
    final bool originalShowWeekend = draftShowWeekend;
    final bool originalShowNonCurrentWeek = draftShowNonCurrentWeek;
    final bool originalIsScheduleLocked = draftIsScheduleLocked;

    if (!context.mounted) return;

    final Object? result = await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (BuildContext context) {
          return ScheduleSettingsPage(
            saveNotificationImmediately: false,
            scheduleId: scheduleId,
            scheduleConfig: draftConfig,
            semesterStart: draftSemesterStart,
            currentWeek: draftCurrentWeek,
            maxWeek: draftMaxWeek,
            tableName: draftTableName,
            showWeekend: draftShowWeekend,
            showNonCurrentWeek: draftShowNonCurrentWeek,
            isScheduleLocked: draftIsScheduleLocked,
            nameValidator: (name) async {
              final exists = _schedules.any(
                (s) => s.name == name && s.id != scheduleId,
              );
              if (exists) {
                return '课程表名称 "$name" 已存在';
              }
              return null;
            },
            onConfigChanged: (newConfig) {
              draftConfig = newConfig;
            },
            onSemesterStartChanged: (date) {
              draftSemesterStart = date;
            },
            onCurrentWeekChanged: (week) {
              draftCurrentWeek = week;
            },
            onMaxWeekChanged: (max) {
              draftMaxWeek = max;
            },
            onTableNameChanged: (newName) {
              draftTableName = newName;
            },
            onShowWeekendChanged: (show) {
              draftShowWeekend = show;
            },
            onShowNonCurrentWeekChanged: (show) {
              draftShowNonCurrentWeek = show;
            },
            onScheduleLockedChanged: (locked) {
              draftIsScheduleLocked = locked;
            },
            onOpenSectionSettings: () async {
              final CourseScheduleConfig? updated =
                  await _openSectionSettingsSheet(context, draftConfig);
              if (updated == null) {
                return;
              }

              draftConfig = updated;
            },
          );
        },
      ),
    );

    // 仅在点击“完成”后提交设置；返回/取消不落库。
    if (result != true) {
      return;
    }

    final CourseService service = CourseService.instance;
    await service.saveConfig(draftConfig, scheduleId);
    await service.saveSemesterStart(draftSemesterStart, scheduleId);
    await service.saveMaxWeek(draftMaxWeek, scheduleId);
    await service.saveTableName(draftTableName, scheduleId);
    await service.saveShowWeekend(draftShowWeekend, scheduleId);
    await service.saveShowNonCurrentWeek(draftShowNonCurrentWeek, scheduleId);
    await service.saveScheduleLocked(draftIsScheduleLocked, scheduleId);

    if (!mounted) {
      return;
    }

    final int scheduleIndex = _schedules.indexWhere((s) => s.id == scheduleId);
    final int clampedCurrentWeek = draftCurrentWeek.clamp(1, draftMaxWeek);
    final bool isCurrentSchedule = scheduleId == _currentScheduleId;
    final bool currentSettingsChanged =
        draftConfig.toJson().toString() != originalConfig.toJson().toString() ||
        draftSemesterStart != originalSemesterStart ||
        clampedCurrentWeek != originalCurrentWeek ||
        draftMaxWeek != originalMaxWeek ||
        draftTableName != originalTableName ||
        draftShowWeekend != originalShowWeekend ||
        draftShowNonCurrentWeek != originalShowNonCurrentWeek ||
        draftIsScheduleLocked != originalIsScheduleLocked;

    setState(() {
      if (scheduleIndex != -1) {
        _schedules[scheduleIndex] = ScheduleMetadata(
          id: scheduleId,
          name: draftTableName,
        );
      }
      if (isCurrentSchedule) {
        _scheduleConfig = draftConfig;
        _semesterStart = draftSemesterStart;
        _currentWeek = clampedCurrentWeek;
        _maxWeek = draftMaxWeek;
        _tableName = draftTableName;
        _showWeekend = draftShowWeekend;
        _showNonCurrentWeek = draftShowNonCurrentWeek;
        _isScheduleLocked = draftIsScheduleLocked;
      }
    });

    if (isCurrentSchedule && currentSettingsChanged) {
      _markCurrentScheduleNeedsRefresh();
    }
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
