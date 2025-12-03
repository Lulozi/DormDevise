import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:dormdevise/utils/app_toast.dart';

import '../../../../models/course_schedule_config.dart';
import '../../../../models/schedule_metadata.dart';
import '../../../../services/course_service.dart';
import '../../widgets/bottom_sheet_confirm.dart';
import '../../widgets/bubble_popup.dart';
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
  final ValueChanged<CourseScheduleConfig> onConfigChanged;
  final ValueChanged<DateTime> onSemesterStartChanged;
  final ValueChanged<int> onCurrentWeekChanged;
  final ValueChanged<int> onMaxWeekChanged;
  final ValueChanged<String> onTableNameChanged;
  final ValueChanged<bool> onShowWeekendChanged;
  final ValueChanged<bool> onShowNonCurrentWeekChanged;
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
    required this.onConfigChanged,
    required this.onSemesterStartChanged,
    required this.onCurrentWeekChanged,
    required this.onMaxWeekChanged,
    required this.onTableNameChanged,
    required this.onShowWeekendChanged,
    required this.onShowNonCurrentWeekChanged,
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

  bool _isAddMenuOpen = false;
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

      if (mounted) {
        setState(() {
          _deletingIds.clear();
          _schedules = schedules;
          _currentScheduleId = currentId;
          _isLoading = false;

          // 若删除了全部课程表，则自动创建的默认课表视为新建并播放入场动画
          if (deletingAll && schedules.isNotEmpty) {
            _newlyAddedId = schedules.first.id;
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
  }

  Future<void> _showAddMenu(BuildContext context) async {
    await showBubblePopup(
      context: context,
      anchorKey: _addBtnKey,
      content: SizedBox(
        width: 180,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCustomMenuItem(context, 'web', '网页导入课程表', Icons.language),
            const Divider(height: 1, thickness: 0.5),
            _buildCustomMenuItem(
              context,
              'camera',
              '拍照导入课程表',
              Icons.camera_alt_outlined,
            ),
            const Divider(height: 1, thickness: 0.5),
            _buildCustomMenuItem(context, 'file', '文件导入课程表', Icons.folder_open),
            const Divider(height: 1, thickness: 0.5),
            _buildCustomMenuItem(
              context,
              'manual',
              '手动创建课程表',
              Icons.edit_outlined,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomMenuItem(
    BuildContext context,
    String value,
    String text,
    IconData icon,
  ) {
    return InkWell(
      onTap: () async {
        Navigator.of(context).pop();
        if (value == 'manual') {
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
              });
            }
          }
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(title: const Text('功能开发中')),
                body: const Center(child: Text('暂未开放')),
              ),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.black87),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC), // 浅灰背景色
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7F8FC),
        elevation: 0,
        leading: _isSelectionMode
            ? TextButton(
                onPressed: _selectAll,
                child: Text(
                  _selectedIds.length == _schedules.length ? '全不选' : '全选',
                  style: const TextStyle(
                    color: Colors.blue,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.black),
                onPressed: () => Navigator.of(context).pop(),
              ),
        leadingWidth: _isSelectionMode ? 80 : null,
        title: Text(
          _isSelectionMode ? '已选择${_selectedIds.length}项' : '全部课程表',
          style: const TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: [
          if (_isSelectionMode)
            TextButton(
              onPressed: _toggleSelectionMode,
              child: const Text(
                '取消',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            )
          else ...[
            IconButton(
              icon: const FaIcon(
                FontAwesomeIcons.squareCheck,
                color: Colors.black87,
                size: 22,
              ),
              onPressed: _toggleSelectionMode,
            ),
            IconButton(
              key: _addBtnKey,
              icon: Icon(
                Icons.add,
                color: _isAddMenuOpen ? Colors.grey : Colors.black87,
                size: 28,
              ),
              onPressed: () async {
                setState(() {
                  _isAddMenuOpen = true;
                });
                await _showAddMenu(context);
                if (mounted) {
                  setState(() {
                    _isAddMenuOpen = false;
                  });
                }
              },
            ),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            header: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _isSelectionMode ? '删除全部课程表将自动生成默认课程表' : '点击课程表卡片可切换当前并查看课程',
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
                    final double slideInput = (value / 0.666).clamp(0.0, 1.0);
                    final double slideValue = Curves.easeOutQuart.transform(
                      slideInput,
                    );

                    // 2. 闪烁动画 (400ms - 1200ms)
                    // 闪烁阶段：value 0.333 -> 1.0
                    // 在滑动动画进行到一半时开始触发（时间上）
                    final double flashInput = ((value - 0.333) / 0.666).clamp(
                      0.0,
                      1.0,
                    );

                    Color? flashColor;
                    if (flashInput > 0) {
                      // 使用抛物线形曲线实现单次平滑闪烁：0 -> 1 -> 0
                      // 模拟一次呼吸/闪烁效果
                      final double flashIntensity =
                          4 * flashInput * (1 - flashInput);
                      flashColor = Color.lerp(
                        Colors.white,
                        Theme.of(context).primaryColor.withOpacity(0.3),
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
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.white.withOpacity(0.6),
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
                      color: Colors.white,
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
                              : const Color(0xFF333333),
                          size: 26,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '删除',
                          style: TextStyle(
                            color: _selectedIds.isEmpty
                                ? Colors.grey
                                : const Color(0xFF333333),
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: backgroundColor ?? Colors.white,
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
                          padding: const EdgeInsets.only(right: 16),
                          child: _buildAnimatedCheckbox(isSelected),
                        )
                      : const SizedBox.shrink(),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
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
                      color: Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '当前',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.blue,
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
                    color: const Color(0xFFF2F2F2),
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        _openSettings(context, id);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Text(
                          '设置',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? Colors.blue : Colors.grey.shade300,
          width: 2,
        ),
      ),
      child: isSelected
          ? const Icon(Icons.check, size: 16, color: Colors.white)
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

    if (scheduleId == _currentScheduleId) {
      config = _scheduleConfig;
      semesterStart = _semesterStart;
      currentWeek = _currentWeek;
      maxWeek = _maxWeek;
      tableName = _tableName;
      showWeekend = _showWeekend;
      showNonCurrentWeek = _showNonCurrentWeek;
    } else {
      final service = CourseService.instance;
      config = await service.loadConfig(scheduleId);
      semesterStart =
          await service.loadSemesterStart(scheduleId) ?? DateTime(2025, 9, 1);
      maxWeek = await service.loadMaxWeek(scheduleId);
      tableName = await service.loadTableName(scheduleId);
      showWeekend = await service.loadShowWeekend(scheduleId);
      showNonCurrentWeek = await service.loadShowNonCurrentWeek(scheduleId);

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
            scheduleConfig: config,
            semesterStart: semesterStart,
            currentWeek: currentWeek,
            maxWeek: maxWeek,
            tableName: tableName,
            showWeekend: showWeekend,
            showNonCurrentWeek: showNonCurrentWeek,
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
