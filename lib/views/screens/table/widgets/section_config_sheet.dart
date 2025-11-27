import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import '../../../../models/course_schedule_config.dart';
import '../../../../utils/animated_expand.dart';
import 'package:dormdevise/utils/index.dart';

/// 表示课间休息时长的使用模式。
enum _BreakDurationMode {
  /// 使用统一的全局课间休息时长。
  global,

  /// 为每个时段单独设置课间休息时长。
  segmented,
}

/// 课程时间设置弹窗，集中调整所有节次配置。
class SectionConfigSheet extends StatefulWidget {
  /// 当前生效的课表配置。
  final CourseScheduleConfig scheduleConfig;

  /// 保存结果时的回调函数。
  final ValueChanged<CourseScheduleConfig> onSubmit;

  /// 初始化时需要滚动到的节次序号。
  final int? initialSectionIndex;

  const SectionConfigSheet({
    super.key,
    required this.scheduleConfig,
    required this.onSubmit,
    this.initialSectionIndex,
  });

  @override
  State<SectionConfigSheet> createState() => _SectionConfigSheetState();
}

/// 维护课程时间设置弹窗的内部状态。
class _SectionConfigSheetState extends State<SectionConfigSheet> {
  late Duration _defaultClassDuration;
  late Duration _defaultBreakDuration;
  late _BreakDurationMode _breakMode;
  late List<_MutableSegment> _segments;
  late final List<GlobalKey> _segmentKeys;
  late final ScrollController _scrollController;
  OverlayEntry? _currentToast;

  @override
  void initState() {
    super.initState();
    _defaultClassDuration = widget.scheduleConfig.defaultClassDuration;
    _defaultBreakDuration = widget.scheduleConfig.defaultBreakDuration;
    _breakMode = widget.scheduleConfig.useSegmentBreakDurations
        ? _BreakDurationMode.segmented
        : _BreakDurationMode.global;
    _segments = widget.scheduleConfig.segments
        .map(
          (ScheduleSegmentConfig segment) =>
              _MutableSegment.fromConfig(segment, widget.scheduleConfig),
        )
        .toList();
    _segmentKeys = List<GlobalKey>.generate(
      _segments.length,
      (_) => GlobalKey(),
    );
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();
    });
  }

  @override
  void dispose() {
    _currentToast?.remove();
    _scrollController.dispose();
    super.dispose();
  }

  /// 显示自定义样式的提示信息
  void _showToast(String message) {
    if (!mounted) return;

    _currentToast?.remove();
    _currentToast = null;

    final OverlayState overlay = Overlay.of(context);

    final OverlayEntry entry = OverlayEntry(
      builder: (BuildContext context) {
        return Positioned(
          top: MediaQuery.of(context).padding.top + 12,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFEBF2FF),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Color.fromRGBO(30, 105, 255, 0.15)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Color.fromRGBO(30, 105, 255, 0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: Color(0xFF1E69FF),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      message,
                      style: const TextStyle(
                        color: Color(0xFF2D3A52),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    _currentToast = entry;
    overlay.insert(entry);

    Future.delayed(const Duration(seconds: 2), () {
      if (_currentToast == entry) {
        entry.remove();
        _currentToast = null;
      }
    });
  }

  /// 构建底部弹窗整体布局。
  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    // 计算目标高度：屏幕高度 - 状态栏 - 导航栏
    final double targetHeight =
        media.size.height - media.padding.top - kToolbarHeight;
    final EdgeInsets inset = media.viewInsets;

    return AnimatedPadding(
      padding: EdgeInsets.only(bottom: inset.bottom),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: Container(
        height: targetHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: Column(
            children: <Widget>[
              _buildHeader(context),
              const Divider(height: 1, color: Color(0xFFE7EDF8)),
              Expanded(
                child: ListView(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                  children: <Widget>[
                    _buildGlobalSettingsCard(context),
                    const SizedBox(height: 14),
                    for (int i = 0; i < _segments.length; i++) ...<Widget>[
                      _buildSegmentCard(context, i),
                      if (i != _segments.length - 1) const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 滚动到用户指定的初始节次位置。
  void _scrollToInitialSection() {
    final int? target = widget.initialSectionIndex;
    if (target == null || _segments.isEmpty) {
      return;
    }
    int cursor = 1;
    for (int i = 0; i < _segments.length; i++) {
      final _MutableSegment segment = _segments[i];
      final int end = cursor + segment.classCount - 1;
      if (target >= cursor && target <= end) {
        final BuildContext? ctx = _segmentKeys[i].currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: 0.08,
          );
        }
        break;
      }
      cursor = end + 1;
    }
  }

  /// 构建顶部标题栏。
  Widget _buildHeader(BuildContext context) {
    final TextStyle title = Theme.of(
      context,
    ).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700);
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      child: Row(
        children: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('取消'),
          ),
          Expanded(
            child: Center(child: Text('课程时间设置', style: title)),
          ),
          TextButton(onPressed: _handleSubmit, child: const Text('完成')),
        ],
      ),
    );
  }

  /// 构建全局时长与模式切换卡片。
  Widget _buildGlobalSettingsCard(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E9F5)),
      ),
      child: Column(
        children: <Widget>[
          _SettingRow(
            label: '每节课上课时长',
            value: _formatDurationLabel(_defaultClassDuration),
            onTap: () => _editDefaultDuration(isClassDuration: true),
          ),
          AnimatedExpand(
            expand: _breakMode == _BreakDurationMode.global,
            child: Column(
              key: const ValueKey<String>('globalBreakDuration'),
              children: <Widget>[
                Divider(height: 1, color: Colors.black.withValues(alpha: 0.05)),
                _SettingRow(
                  label: '课间休息时长',
                  value: _formatDurationLabel(_defaultBreakDuration),
                  onTap: () => _editDefaultDuration(isClassDuration: false),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.black.withValues(alpha: 0.05)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: <Widget>[
                Text(
                  '时长模式',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _BreakModeToggle(
                  mode: _breakMode,
                  onChanged: (_BreakDurationMode value) {
                    if (_breakMode == value) {
                      return;
                    }
                    setState(() {
                      _breakMode = value;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建单个时段的配置卡片。
  Widget _buildSegmentCard(BuildContext context, int index) {
    final ThemeData theme = Theme.of(context);
    final _MutableSegment segment = _segments[index];
    final int baseNumber = _segments
        .take(index)
        .fold<int>(0, (int acc, _MutableSegment item) => acc + item.classCount);
    final List<_SectionPreview> previews = _buildSectionPreviews(
      segment,
      baseNumber,
    );

    return DecoratedBox(
      key: _segmentKeys[index],
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  segment.name,
                  style: theme.textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                _CircleIconButton(
                  icon: Icons.remove,
                  tooltip: '减少节次',
                  onTap: segment.classCount > 0
                      ? () => _updateClassCount(index, -1)
                      : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    segment.classCount == 0 ? '无课' : '${segment.classCount} 节',
                    style: theme.textTheme.titleSmall!.copyWith(
                      fontWeight: FontWeight.w600,
                      color: segment.classCount == 0 ? Colors.black45 : null,
                    ),
                  ),
                ),
                _CircleIconButton(
                  icon: Icons.add,
                  tooltip: '增加节次',
                  onTap: () => _updateClassCount(index, 1),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedExpand(
              expand:
                  _breakMode == _BreakDurationMode.segmented &&
                  segment.classCount > 1,
              child: Column(
                key: ValueKey<String>('segmentBreak_$index'),
                children: <Widget>[
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _editSegmentBreakDuration(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: <Widget>[
                          Text(
                            '课间休息时长',
                            style: theme.textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _formatSegmentBreakSummary(segment),
                            style: theme.textTheme.bodySmall!.copyWith(
                              color: Colors.black45,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: Colors.black26,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE8EDF5)),
                  const SizedBox(height: 2),
                ],
              ),
            ),
            for (int i = 0; i < previews.length; i++) ...<Widget>[
              _buildSectionTile(
                context: context,
                segmentIndex: index,
                sectionIndex: i,
                preview: previews[i],
                isLast: i == previews.length - 1,
                classDuration: segment.classDurations[i],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 渲染单节课程的预览行。
  Widget _buildSectionTile({
    required BuildContext context,
    required int segmentIndex,
    required int sectionIndex,
    required _SectionPreview preview,
    required bool isLast,
    required Duration classDuration,
  }) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _editSectionTimeRange(
            segmentIndex: segmentIndex,
            sectionIndex: sectionIndex,
            preview: preview,
            canEditStart: true,
            classDuration: classDuration,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: <Widget>[
                Text(
                  '第 ${preview.number} 节（${classDuration.inMinutes} 分钟）',
                  style: theme.textTheme.bodyMedium,
                ),
                const Spacer(),
                Text(
                  '${_formatTime(preview.start)} - ${_formatTime(preview.end)}',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: Colors.black26,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: Colors.black.withValues(alpha: 0.05)),
      ],
    );
  }

  /// 生成指定时段内的节次预览列表。
  List<_SectionPreview> _buildSectionPreviews(
    _MutableSegment segment,
    int baseIndex,
  ) {
    final List<_SectionPreview> items = <_SectionPreview>[];
    TimeOfDay cursor = segment.startTime;
    for (int i = 0; i < segment.classCount; i++) {
      final Duration classDuration = segment.classDurations[i];
      final TimeOfDay end = _addDuration(cursor, classDuration);
      items.add(
        _SectionPreview(number: baseIndex + i + 1, start: cursor, end: end),
      );
      if (i < segment.classCount - 1) {
        final Duration breakDuration = _resolveBreakDuration(
          segment: segment,
          breakIndex: i,
        );
        cursor = _addDuration(end, breakDuration);
      }
    }
    return items;
  }

  /// 解析指定索引的课间休息时长，优先使用逐段自定义值。
  Duration _resolveBreakDuration({
    required _MutableSegment segment,
    required int breakIndex,
  }) {
    if (breakIndex >= 0 && breakIndex < segment.breakDurations.length) {
      return segment.breakDurations[breakIndex];
    }
    return _resolveBaseBreakDuration(segment);
  }

  /// 计算当前模式下应使用的基准课间休息时长。
  Duration _resolveBaseBreakDuration(_MutableSegment segment) {
    if (_breakMode == _BreakDurationMode.segmented) {
      return segment.breakDuration ?? _defaultBreakDuration;
    }
    return _defaultBreakDuration;
  }

  /// 确保课间列表长度与节次数一致，新增项将按基准时长填充。
  void _ensureBreakSlots(_MutableSegment segment) {
    final int expected = segment.classCount > 1 ? segment.classCount - 1 : 0;
    final Duration base = _resolveBaseBreakDuration(segment);
    if (segment.breakDurations.length > expected) {
      segment.breakDurations.removeRange(
        expected,
        segment.breakDurations.length,
      );
    } else if (segment.breakDurations.length < expected) {
      segment.breakDurations.addAll(
        List<Duration>.filled(
          expected - segment.breakDurations.length,
          base,
          growable: false,
        ),
      );
    }
  }

  /// 生成课间休息设置的摘要文本，便于在列表中展示。
  String _formatSegmentBreakSummary(_MutableSegment segment) {
    if (segment.classCount <= 1) {
      return '无课间';
    }
    final Duration base = _resolveBaseBreakDuration(segment);
    final bool allEqualBase = segment.breakDurations.every(
      (Duration duration) => duration == base,
    );
    if (allEqualBase) {
      if (_breakMode == _BreakDurationMode.segmented &&
          segment.breakDuration != null) {
        return '整段 ${segment.breakDuration!.inMinutes} 分钟';
      }
      return '默认 ${base.inMinutes} 分钟';
    }
    final String detail = segment.breakDurations
        .map((Duration duration) => duration.inMinutes.toString())
        .join(' / ');
    return '自定义 $detail 分钟';
  }

  /// 根据操作调整节次数量。
  void _updateClassCount(int segmentIndex, int delta) {
    final _MutableSegment segment = _segments[segmentIndex];
    final int newCount = segment.classCount + delta;
    if (newCount < 0) {
      return;
    }

    if (delta > 0) {
      TimeOfDay cursor = segment.startTime;
      for (int i = 0; i < newCount; i++) {
        final Duration d = i < segment.classDurations.length
            ? segment.classDurations[i]
            : _defaultClassDuration;
        final TimeOfDay nextCursor = _addDuration(cursor, d);

        // 检查是否跨天
        if (_compareTimeOfDay(nextCursor, cursor) < 0) {
          _showToast('不能超过当天时间');
          return;
        }
        cursor = nextCursor;

        if (i < newCount - 1) {
          Duration b;
          if (i < segment.breakDurations.length) {
            b = segment.breakDurations[i];
          } else {
            b = _resolveBaseBreakDuration(segment);
          }
          final TimeOfDay nextCursorAfterBreak = _addDuration(cursor, b);

          // 检查课间是否跨天
          if (_compareTimeOfDay(nextCursorAfterBreak, cursor) < 0) {
            _showToast('不能超过当天时间');
            return;
          }
          cursor = nextCursorAfterBreak;
        }
      }

      if (segmentIndex < _segments.length - 1) {
        if (_compareTimeOfDay(cursor, _segments[segmentIndex + 1].startTime) >
            0) {
          _showToast('增加节次后将超过下个时段的开始时间');
          return;
        }
      }
    }

    setState(() {
      final int previousCount = segment.classCount;
      if (newCount > segment.classCount) {
        final int diff = newCount - segment.classCount;
        for (int i = 0; i < diff; i++) {
          segment.classDurations.add(_defaultClassDuration);
        }
      } else if (newCount < segment.classCount) {
        segment.classDurations.removeRange(
          newCount,
          segment.classDurations.length,
        );
      }
      segment.classCount = newCount;
      if (previousCount != newCount) {
        _ensureBreakSlots(segment);
      }
    });
  }

  /// 弹出底部弹窗以调整节次的起止时间。
  Future<void> _editSectionTimeRange({
    required int segmentIndex,
    required int sectionIndex,
    required _SectionPreview preview,
    required bool canEditStart,
    required Duration classDuration,
  }) async {
    final _MutableSegment segment = _segments[segmentIndex];
    // 获取当前状态下的所有节次预览，用于验证
    final List<_SectionPreview> currentPreviews = _buildSectionPreviews(
      segment,
      0,
    );

    final _SectionTimeResult? result = await _showSectionTimePicker(
      segmentName: segment.name,
      sectionNumber: preview.number,
      initialStart: preview.start,
      initialEnd: preview.end,
      canEditStart: canEditStart,
      initialDurationOverride: classDuration,
    );

    if (result == null) {
      return;
    }

    final TimeOfDay newStart = result.updatedStart ?? preview.start;
    final Duration newDuration = result.classDuration;

    // 1. 验证开始时间是否合法
    if (sectionIndex == 0) {
      // 如果是该时段的第一节课
      if (segmentIndex > 0) {
        // 必须晚于上一时段的结束时间
        final _MutableSegment prevSegment = _segments[segmentIndex - 1];
        final TimeOfDay prevSegmentEnd = _buildSectionPreviews(
          prevSegment,
          0,
        ).last.end;

        if (_compareTimeOfDay(newStart, prevSegmentEnd) < 0) {
          _showToast('开始时间不能早于上一时段结束时间');
          return;
        }
      }
    } else {
      // 如果是中间的节次，必须晚于上一节课的结束时间
      final TimeOfDay prevSectionEnd = currentPreviews[sectionIndex - 1].end;
      if (_compareTimeOfDay(newStart, prevSectionEnd) < 0) {
        _showToast('开始时间不能早于上一节课结束时间');
        return;
      }
    }

    // 2. 模拟计算后续时间链，验证是否跨天或超过下一时段
    TimeOfDay cursor = newStart;

    for (int i = sectionIndex; i < segment.classCount; i++) {
      // 当前节次时长（如果是正在编辑的节次，使用新时长）
      final Duration d = (i == sectionIndex)
          ? newDuration
          : segment.classDurations[i];

      // 计算结束时间
      final TimeOfDay end = _addDuration(cursor, d);

      // 检查单节课是否跨天
      if (_compareTimeOfDay(end, cursor) < 0) {
        _showToast('时间不能跨越午夜');
        return;
      }

      cursor = end; // 游标移动到下课时间

      // 如果不是最后一节，加上课间
      if (i < segment.classCount - 1) {
        Duration b;
        // 课间时长保持不变，只随课程平移
        b = _resolveBreakDuration(segment: segment, breakIndex: i);

        final TimeOfDay nextStart = _addDuration(cursor, b);
        // 检查课间是否跨天
        if (_compareTimeOfDay(nextStart, cursor) < 0) {
          _showToast('时间不能跨越午夜');
          return;
        }
        cursor = nextStart; // 游标移动到下一节上课时间
      }
    }

    // 3. 验证是否超过下一时段开始时间
    if (segmentIndex < _segments.length - 1) {
      final TimeOfDay nextSegmentStart = _segments[segmentIndex + 1].startTime;
      // cursor 此时是当前时段最后一节课的结束时间
      if (_compareTimeOfDay(cursor, nextSegmentStart) > 0) {
        _showToast('调整后时间将超过下一时段开始时间');
        return;
      }
    }

    // 4. 应用更改
    setState(() {
      segment.classDurations[sectionIndex] = newDuration;

      if (sectionIndex == 0) {
        segment.startTime = newStart;
      } else {
        // 更新当前节次与上一节次之间的课间
        final TimeOfDay prevEnd = currentPreviews[sectionIndex - 1].end;
        final int newBreakMin = _differenceInMinutes(prevEnd, newStart);

        _ensureBreakSlots(segment);
        segment.breakDurations[sectionIndex - 1] = Duration(
          minutes: newBreakMin,
        );

        // 如果课间变化且当前不是分段模式，自动切换为分段模式
        if (_breakMode != _BreakDurationMode.segmented &&
            newBreakMin != _defaultBreakDuration.inMinutes) {
          _breakMode = _BreakDurationMode.segmented;
        }
      }
    });
  }

  /// 调整当前时段的课间休息时长。
  Future<void> _editSegmentBreakDuration(int index) async {
    final _MutableSegment segment = _segments[index];
    final Duration seed = segment.breakDuration ?? _defaultBreakDuration;
    final Duration? picked = await _showDurationWheelPicker(
      title: '${segment.name}课间休息时长',
      initial: seed,
      minMinutes: 5,
      maxMinutes: 60,
      step: 5,
      subtitle: _breakMode == _BreakDurationMode.global
          ? '全局模式下将使用统一课间时长'
          : '仅影响本时段的课间休息时长',
    );
    if (picked == null) {
      return;
    }
    setState(() {
      segment.breakDuration = picked;
      final int breakCount = segment.classCount > 1
          ? segment.classCount - 1
          : 0;
      segment.breakDurations = List<Duration>.filled(
        breakCount,
        picked,
        growable: true,
      );
    });
  }

  /// 编辑默认的上课或课间时长。
  Future<void> _editDefaultDuration({required bool isClassDuration}) async {
    final Duration initial = isClassDuration
        ? _defaultClassDuration
        : _defaultBreakDuration;
    final Duration? result = await _showDurationWheelPicker(
      title: isClassDuration ? '每节课上课时长' : '课间休息时长',
      initial: initial,
      minMinutes: isClassDuration ? 10 : 5,
      maxMinutes: isClassDuration ? 180 : 60,
      step: 5,
      subtitle: isClassDuration ? '将同步替换保持默认值的节次上课时长' : '全局模式下将同步替换课间休息时长',
    );
    if (result == null) {
      return;
    }
    setState(() {
      final int previousMinutes = initial.inMinutes;
      if (isClassDuration) {
        _defaultClassDuration = result;
      } else {
        _defaultBreakDuration = result;
      }
      _syncDurationsWithDefault(
        previousMinutes: previousMinutes,
        newDuration: result,
        isClassDuration: isClassDuration,
      );
    });
  }

  /// 同步保持默认值的时长配置。
  void _syncDurationsWithDefault({
    required int previousMinutes,
    required Duration newDuration,
    required bool isClassDuration,
  }) {
    for (final _MutableSegment segment in _segments) {
      if (isClassDuration) {
        for (int i = 0; i < segment.classDurations.length; i++) {
          if (segment.classDurations[i].inMinutes == previousMinutes) {
            segment.classDurations[i] = newDuration;
          }
        }
      } else {
        if (segment.breakDuration != null &&
            segment.breakDuration!.inMinutes == previousMinutes) {
          segment.breakDuration = newDuration;
        }
        for (int i = 0; i < segment.breakDurations.length; i++) {
          if (segment.breakDurations[i].inMinutes == previousMinutes) {
            segment.breakDurations[i] = newDuration;
          }
        }
      }
    }
  }

  /// 展示通用的时长滚轮选择器。
  Future<Duration?> _showDurationWheelPicker({
    required String title,
    required Duration initial,
    required int minMinutes,
    required int maxMinutes,
    required int step,
    String? subtitle,
  }) async {
    final List<int> options = _buildMinuteOptions(
      minMinutes: minMinutes,
      maxMinutes: maxMinutes,
      step: step,
      ensure: initial.inMinutes,
    );
    final FixedExtentScrollController controller = FixedExtentScrollController(
      initialItem: options.indexOf(initial.inMinutes),
    );
    int current = initial.inMinutes;

    final Duration? result = await _showWheelBottomSheet<Duration>(
      titleBuilder: () => title,
      subtitleBuilder: subtitle == null ? null : () => subtitle,
      contentBuilder: (StateSetter setModalState) {
        return SizedBox(
          height: 220,
          child: CupertinoPicker(
            selectionOverlay: const CupertinoPickerDefaultSelectionOverlay(
              background: Colors.transparent,
            ),
            scrollController: controller,
            itemExtent: kPickerItemExtent,
            magnification: 1.08,
            useMagnifier: true,
            looping: true,
            onSelectedItemChanged: (int index) {
              setModalState(() {
                current = options[index];
              });
            },
            children: options
                .map(
                  (int minutes) => Center(
                    child: Text(
                      '$minutes 分钟',
                      style: const TextStyle(
                        fontSize: 44,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        );
      },
      onConfirm: () => Duration(minutes: current),
    );

    controller.dispose();
    return result;
  }

  /// 展示节次时间编辑滚轮弹窗。
  Future<_SectionTimeResult?> _showSectionTimePicker({
    required String segmentName,
    required int sectionNumber,
    required TimeOfDay initialStart,
    required TimeOfDay initialEnd,
    required bool canEditStart,
    Duration? initialDurationOverride,
  }) async {
    final int difference = _differenceInMinutes(initialStart, initialEnd);
    int currentDuration = initialDurationOverride?.inMinutes ?? difference;
    if (currentDuration < 1) {
      currentDuration = 1;
    }
    TimeOfDay currentStart = initialStart;
    TimeOfDay currentEnd = difference <= 0 && initialDurationOverride != null
        ? _addDuration(initialStart, Duration(minutes: currentDuration))
        : initialEnd;

    // 使用静态的 0-23 小时和 0-59 分钟列表，避免滚动时列表变化导致的不稳定
    final List<int> staticHours = List<int>.generate(24, (int index) => index);
    final List<int> staticMinutes = List<int>.generate(
      60,
      (int index) => index,
    );

    final FixedExtentScrollController startHourController =
        FixedExtentScrollController(initialItem: currentStart.hour);
    final FixedExtentScrollController startMinuteController =
        FixedExtentScrollController(initialItem: currentStart.minute);

    final FixedExtentScrollController endHourController =
        FixedExtentScrollController(initialItem: currentEnd.hour);
    final FixedExtentScrollController endMinuteController =
        FixedExtentScrollController(initialItem: currentEnd.minute);

    // 智能滚动到目标值（处理循环列表的最短路径）
    void jumpToItem(
      FixedExtentScrollController controller,
      int targetValue,
      int max,
    ) {
      if (!controller.hasClients) {
        return;
      }
      final int current = controller.selectedItem;
      final int currentMod = current % max;
      if (currentMod == targetValue) {
        return;
      }

      int diff = targetValue - currentMod;
      if (diff > max / 2) diff -= max;
      if (diff < -max / 2) diff += max;

      controller.jumpToItem(current + diff);
    }

    void syncEndControllers() {
      jumpToItem(endHourController, currentEnd.hour, 24);
      jumpToItem(endMinuteController, currentEnd.minute, 60);
    }

    final _SectionTimeResult?
    result = await _showWheelBottomSheet<_SectionTimeResult>(
      titleBuilder: () => '第 $sectionNumber 节（$currentDuration 分钟）',
      subtitleBuilder: () => '$segmentName时段',
      contentBuilder: (StateSetter setModalState) {
        void updateStart({int? hour, int? minute}) {
          final TimeOfDay updated = TimeOfDay(
            hour: hour ?? currentStart.hour,
            minute: minute ?? currentStart.minute,
          );
          // 保持时长不变，计算新的结束时间
          final TimeOfDay newEnd = _addDuration(
            updated,
            Duration(minutes: currentDuration),
          );
          setModalState(() {
            currentStart = updated;
            currentEnd = newEnd;
          });
          syncEndControllers();
        }

        void updateEnd({int? hour, int? minute}) {
          final TimeOfDay candidate = TimeOfDay(
            hour: hour ?? currentEnd.hour,
            minute: minute ?? currentEnd.minute,
          );

          // 如果时间没有变化（例如由 syncEndControllers 触发的回调），则忽略
          if (candidate.hour == currentEnd.hour &&
              candidate.minute == currentEnd.minute) {
            return;
          }

          // 计算新的时长（支持跨天）
          final int diff = _differenceInMinutes(currentStart, candidate);

          // 确保最少 1 分钟时长
          if (diff < 1) {
            // 如果时间相同，不做处理或者设为 1 分钟？
            // 这里简单处理：如果用户选了相同时间，暂不更新时长，或者强制 +1 分钟
            // 为了体验流畅，如果 diff < 1 (即相同时间)，我们强制结束时间为开始时间 + 1 分钟
            final TimeOfDay minEnd = _addDuration(
              currentStart,
              const Duration(minutes: 1),
            );
            setModalState(() {
              currentEnd = minEnd;
              currentDuration = 1;
            });
            syncEndControllers();
            return;
          }

          setModalState(() {
            currentEnd = candidate;
            currentDuration = diff;
          });
          // 不需要 syncEndControllers，因为是用户手动滚动的
        }

        Widget buildTimeColumn({
          required bool enabled,
          required FixedExtentScrollController hourController,
          required FixedExtentScrollController minuteController,
          required void Function(int index) onHourChanged,
          required void Function(int index) onMinuteChanged,
        }) {
          final Widget picker = LayoutBuilder(
            builder: (context, constraints) {
              final double gap = 1.5; // 再缩小间距为 1.5px
              final double baseFont =
                  Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14.0;
              final double pickerFont =
                  baseFont *
                  kPickerFontScale; // 使用常量 kPickerFontScale，以便统一调整（原为 2x）
              final double maxPickerWidth = max(
                48.0,
                pickerFont * kPickerWidthScaleMedium,
              );
              final double pickerWidth = min(
                (constraints.maxWidth - gap) / 2,
                maxPickerWidth,
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: pickerWidth,
                    child: CupertinoPicker(
                      selectionOverlay:
                          const CupertinoPickerDefaultSelectionOverlay(
                            background: Colors.transparent,
                          ),
                      scrollController: hourController,
                      itemExtent: kPickerItemExtent,
                      magnification: 1.05,
                      useMagnifier: true,
                      looping: true,
                      onSelectedItemChanged: onHourChanged,
                      children: staticHours
                          .map(
                            (int hour) => Center(
                              child: Text(
                                '${hour.toString().padLeft(2, '0')}时',
                                style: const TextStyle(
                                  fontSize: kTimePickerFontSize,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  SizedBox(width: gap),
                  SizedBox(
                    width: pickerWidth,
                    child: CupertinoPicker(
                      selectionOverlay:
                          const CupertinoPickerDefaultSelectionOverlay(
                            background: Colors.transparent,
                          ),
                      scrollController: minuteController,
                      itemExtent: kPickerItemExtent,
                      magnification: 1.05,
                      useMagnifier: true,
                      looping: true,
                      onSelectedItemChanged: onMinuteChanged,
                      children: staticMinutes
                          .map(
                            (int minute) => Center(
                              child: Text(
                                '${minute.toString().padLeft(2, '0')}分',
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              );
            },
          );

          if (!enabled) {
            return IgnorePointer(
              ignoring: true,
              child: Opacity(opacity: 0.55, child: picker),
            );
          }
          return picker;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '开始时间',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: buildTimeColumn(
                          enabled: canEditStart,
                          hourController: startHourController,
                          minuteController: startMinuteController,
                          onHourChanged: (int index) {
                            if (!canEditStart) {
                              return;
                            }
                            updateStart(hour: staticHours[index % 24]);
                          },
                          onMinuteChanged: (int index) {
                            if (!canEditStart) {
                              return;
                            }
                            updateStart(minute: staticMinutes[index % 60]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '—',
                    style: Theme.of(context).textTheme.titleLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.black54,
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '结束时间',
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 180,
                        child: buildTimeColumn(
                          enabled: true,
                          hourController: endHourController,
                          minuteController: endMinuteController,
                          onHourChanged: (int index) {
                            updateEnd(hour: staticHours[index % 24]);
                          },
                          onMinuteChanged: (int index) {
                            updateEnd(minute: staticMinutes[index % 60]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
      onConfirm: () {
        final bool startChanged =
            canEditStart && !_isSameTimeOfDay(currentStart, initialStart);
        return _SectionTimeResult(
          classDuration: Duration(minutes: currentDuration),
          updatedStart: startChanged ? currentStart : null,
        );
      },
    );

    startHourController.dispose();
    startMinuteController.dispose();
    endHourController.dispose();
    endMinuteController.dispose();
    return result;
  }

  /// 展示通用滚轮弹窗容器。
  Future<T?> _showWheelBottomSheet<T>({
    required String Function() titleBuilder,
    String? Function()? subtitleBuilder,
    required Widget Function(StateSetter setModalState) contentBuilder,
    required T Function() onConfirm,
    String confirmLabel = '确定',
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return _WheelSheet(
              titleBuilder: titleBuilder,
              subtitleBuilder: subtitleBuilder,
              onCancel: () => Navigator.of(context).pop(),
              onConfirm: () => Navigator.of(context).pop(onConfirm()),
              confirmLabel: confirmLabel,
              child: contentBuilder(setModalState),
            );
          },
        );
      },
    );
  }

  /// 组合分钟选项，确保包含初始值。
  List<int> _buildMinuteOptions({
    required int minMinutes,
    required int maxMinutes,
    required int step,
    required int ensure,
  }) {
    final List<int> items = <int>[];
    for (int value = minMinutes; value <= maxMinutes; value += step) {
      items.add(value);
    }
    if (!items.contains(ensure)) {
      items.add(ensure);
      items.sort();
    }
    return items;
  }

  /// 组装最终的课表配置对象。
  CourseScheduleConfig _buildResultConfig() {
    final List<ScheduleSegmentConfig> segments = <ScheduleSegmentConfig>[];
    final bool useSegmented = _breakMode == _BreakDurationMode.segmented;

    for (final _MutableSegment segment in _segments) {
      _ensureBreakSlots(segment);

      final Duration? breakDuration = useSegmented
          ? segment.breakDuration
          : null;

      // 在全局模式下，不保存分段的课间配置，以免下次加载时误判
      final List<Duration> perBreakDurations =
          (useSegmented && segment.classCount > 1)
          ? List<Duration>.from(segment.breakDurations)
          : <Duration>[];

      segments.add(
        ScheduleSegmentConfig(
          name: segment.name,
          startTime: segment.startTime,
          classCount: segment.classCount,
          perClassDurations: List<Duration>.from(segment.classDurations),
          breakDuration: breakDuration,
          perBreakDurations: perBreakDurations.isEmpty
              ? null
              : perBreakDurations,
        ),
      );
    }

    return CourseScheduleConfig(
      defaultClassDuration: _defaultClassDuration,
      defaultBreakDuration: _defaultBreakDuration,
      segments: segments,
      useSegmentBreakDurations: useSegmented,
    );
  }

  /// 提交更改并关闭弹窗。
  void _handleSubmit() {
    widget.onSubmit(_buildResultConfig());
  }

  /// 将时长转为分钟展示文本。
  String _formatDurationLabel(Duration duration) {
    return '${duration.inMinutes} 分钟';
  }

  /// 将时间格式化为 HH:mm。
  String _formatTime(TimeOfDay time) {
    final String hour = time.hour.toString().padLeft(2, '0');
    final String minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// 在指定时间上叠加持续时长。
  TimeOfDay _addDuration(TimeOfDay time, Duration duration) {
    final int minutes = time.hour * 60 + time.minute + duration.inMinutes;
    final int hour = (minutes ~/ 60) % 24;
    final int minute = minutes % 60;
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// 计算两个时间的分钟差值。
  int _differenceInMinutes(TimeOfDay start, TimeOfDay end) {
    final int from = start.hour * 60 + start.minute;
    final int to = end.hour * 60 + end.minute;
    final int diff = to - from;
    return diff < 0 ? diff + 1440 : diff;
  }

  /// 判断两个时间是否完全相同。
  bool _isSameTimeOfDay(TimeOfDay a, TimeOfDay b) {
    return a.hour == b.hour && a.minute == b.minute;
  }

  /// 比较两个时间的先后，返回负数表示 a 早于 b。
  int _compareTimeOfDay(TimeOfDay a, TimeOfDay b) {
    if (a.hour == b.hour) {
      return a.minute.compareTo(b.minute);
    }
    return a.hour.compareTo(b.hour);
  }
}

/// 单节课程的时间预览信息。
class _SectionPreview {
  final int number;
  final TimeOfDay start;
  final TimeOfDay end;

  const _SectionPreview({
    required this.number,
    required this.start,
    required this.end,
  });
}

/// 课程时间选择结果的模型。
class _SectionTimeResult {
  final Duration classDuration;
  final TimeOfDay? updatedStart;

  const _SectionTimeResult({
    required this.classDuration,
    required this.updatedStart,
  });
}

/// 可变的时段配置实体。
class _MutableSegment {
  String name;
  TimeOfDay startTime;
  int classCount;
  List<Duration> classDurations;
  List<Duration> breakDurations;
  Duration? breakDuration;

  _MutableSegment({
    required this.name,
    required this.startTime,
    required this.classCount,
    required List<Duration> classDurations,
    required List<Duration> breakDurations,
    this.breakDuration,
  }) : classDurations = List<Duration>.from(classDurations),
       breakDurations = List<Duration>.from(breakDurations);

  factory _MutableSegment.fromConfig(
    ScheduleSegmentConfig config,
    CourseScheduleConfig schedule,
  ) {
    Duration? resolvedBreak;
    if (config.breakDuration != null) {
      resolvedBreak = config.breakDuration;
    } else if (config.perBreakDurations != null &&
        config.perBreakDurations!.isNotEmpty) {
      resolvedBreak = config.perBreakDurations!.first;
    }
    return _MutableSegment(
      name: config.name,
      startTime: config.startTime,
      classCount: config.classCount,
      classDurations:
          config.perClassDurations ?? schedule.getClassDurations(config),
      breakDurations: schedule.getBreakDurations(config),
      breakDuration: resolvedBreak,
    );
  }
}

/// 全局/分段模式切换控件。
class _BreakModeToggle extends StatelessWidget {
  final _BreakDurationMode mode;
  final ValueChanged<_BreakDurationMode> onChanged;

  const _BreakModeToggle({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const Color activeColor = Color(0xFF1E69FF);
    const double itemWidth = 56.0;
    const double height = 32.0;
    const double padding = 2.0;

    return Container(
      height: height,
      width: itemWidth * 2 + padding * 2,
      decoration: BoxDecoration(
        color: const Color(0xFFE9EDF6),
        borderRadius: BorderRadius.circular(height / 2),
      ),
      padding: const EdgeInsets.all(padding),
      child: Stack(
        children: <Widget>[
          AnimatedAlign(
            alignment: mode == _BreakDurationMode.segmented
                ? Alignment.centerLeft
                : Alignment.centerRight,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: Container(
              width: itemWidth,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular((height - padding * 2) / 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: activeColor.withValues(alpha: 0.15),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: <Widget>[
              _buildOption(
                label: '分段',
                isSelected: mode == _BreakDurationMode.segmented,
                onTap: () => onChanged(_BreakDurationMode.segmented),
                width: itemWidth,
                activeColor: activeColor,
              ),
              _buildOption(
                label: '全局',
                isSelected: mode == _BreakDurationMode.global,
                onTap: () => onChanged(_BreakDurationMode.global),
                width: itemWidth,
                activeColor: activeColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required double width,
    required Color activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSelected ? activeColor : const Color(0xFF8E9AB0),
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// 通用设置行组件。
class _SettingRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _SettingRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.bodyMedium!.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: theme.textTheme.bodyMedium!.copyWith(
                color: Colors.black54,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

/// 圆形图标按钮组件。
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _CircleIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: enabled ? const Color(0xFFE9EDF6) : const Color(0xFFF0F2F7),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: enabled ? Colors.black87 : Colors.black26,
          ),
        ),
      ),
    );
  }
}

/// 滚轮弹窗的通用外壳。
class _WheelSheet extends StatelessWidget {
  final String Function() titleBuilder;
  final String? Function()? subtitleBuilder;
  final Widget child;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;

  const _WheelSheet({
    required this.titleBuilder,
    this.subtitleBuilder,
    required this.child,
    required this.onCancel,
    required this.onConfirm,
    required this.confirmLabel,
  });

  @override
  Widget build(BuildContext context) {
    final String title = titleBuilder();
    final String? subtitle = subtitleBuilder?.call();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const SizedBox(width: 32),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 19,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (subtitle != null) ...<Widget>[
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close_rounded, size: 22),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFE8EDF8)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: child,
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: TextButton(
                    onPressed: onConfirm,
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Color(0xFF1E69FF),
                        fontWeight: FontWeight.w600,
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
}
