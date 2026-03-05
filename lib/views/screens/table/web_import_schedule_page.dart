import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../models/web_school.dart';
import '../../../services/web_school_service.dart';
import '../../../utils/app_toast.dart';
import 'web_import_login_page.dart';

/// 网页导入课表页面。
///
/// 展示学校列表卡片，支持新增学校、左滑编辑/删除、修改网址与导入校徽。
class WebImportSchedulePage extends StatefulWidget {
  const WebImportSchedulePage({super.key});

  @override
  State<WebImportSchedulePage> createState() => _WebImportSchedulePageState();
}

class _WebImportSchedulePageState extends State<WebImportSchedulePage> {
  static const String _fitBadgeAsset = 'assets/images/schoolBadge/FIT.jpg';

  List<WebSchool> _schools = <WebSchool>[];
  bool _isLoading = true;

  /// 正在编辑网址的学校索引，-1 表示未展开编辑面板。
  int _editingIndex = -1;

  /// 编辑网址输入控制器。
  final TextEditingController _editUrlController = TextEditingController();

  /// 删除动画追踪。
  final Set<int> _deletingIndices = <int>{};

  /// 新增动画追踪。
  int? _newlyAddedIndex;

  /// 记录每张卡片左滑位移（负数）。
  final Map<int, double> _swipeOffsets = <int, double>{};

  @override
  void initState() {
    super.initState();
    _loadSchools();
  }

  @override
  void dispose() {
    _editUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadSchools() async {
    final List<WebSchool> schools = await WebSchoolService.instance
        .loadSchools();
    if (!mounted) return;
    setState(() {
      _schools = schools;
      _isLoading = false;
      _swipeOffsets.clear();
      if (_editingIndex >= schools.length) {
        _editingIndex = -1;
      }
    });
  }

  /// 判断是否为预设学校（预设学校禁止删除）。
  bool _isPresetSchool(WebSchool school) {
    return WebSchoolService.instance.isPresetSchool(school);
  }

  /// 根据学校类型返回动作区宽度。
  double _actionWidthForSchool(WebSchool school) {
    return _isPresetSchool(school) ? 72 : 144;
  }

  /// 收起所有左滑动作区。
  void _closeAllSwipeActions() {
    if (_swipeOffsets.isEmpty) return;
    setState(() {
      _swipeOffsets.clear();
    });
  }

  /// 更新单个卡片左滑位移，并关闭其他卡片动作区。
  void _setSwipeOffset(int index, double offset) {
    setState(() {
      _swipeOffsets.removeWhere((int key, double value) => key != index);
      if (offset == 0) {
        _swipeOffsets.remove(index);
      } else {
        _swipeOffsets[index] = offset;
      }
    });
  }

  /// 左滑拖动中：仅改变右侧露出宽度（左边固定）。
  void _onCardHorizontalDragUpdate(int index, DragUpdateDetails details) {
    if (_editingIndex != -1) return;
    final WebSchool school = _schools[index];
    final double maxActionWidth = _actionWidthForSchool(school);
    final double currentOffset = _swipeOffsets[index] ?? 0;
    final double nextOffset = (currentOffset + details.delta.dx)
        .clamp(-maxActionWidth, 0.0)
        .toDouble();
    _setSwipeOffset(index, nextOffset);
  }

  /// 左滑拖动结束后自动吸附（展开或收回）。
  void _onCardHorizontalDragEnd(int index) {
    if (_editingIndex != -1) return;
    final WebSchool school = _schools[index];
    final double maxActionWidth = _actionWidthForSchool(school);
    final double currentOffset = _swipeOffsets[index] ?? 0;
    final bool shouldOpen = currentOffset.abs() > maxActionWidth * 0.35;
    _setSwipeOffset(index, shouldOpen ? -maxActionWidth : 0);
  }

  /// 切换网址编辑面板：再次点击同一项自动收回。
  void _toggleEditUrlPanel(int index) {
    final String currentUrl = _schools[index].url;
    setState(() {
      if (_editingIndex == index) {
        _editingIndex = -1;
      } else {
        _editingIndex = index;
        _editUrlController.text = currentUrl;
      }
    });
  }

  /// 保存当前编辑中的网址。
  Future<void> _saveEditingUrl() async {
    if (_editingIndex < 0 || _editingIndex >= _schools.length) return;

    final String newUrl = _editUrlController.text.trim();
    if (newUrl.isEmpty) return;

    final WebSchool updatedSchool = _schools[_editingIndex].copyWith(
      url: newUrl,
    );
    await WebSchoolService.instance.updateSchool(_editingIndex, updatedSchool);

    if (!mounted) return;
    setState(() {
      _schools[_editingIndex] = updatedSchool;
      _editingIndex = -1;
    });
  }

  /// 删除学校（预设学校不允许删除）。
  Future<void> _deleteSchool(int index) async {
    if (index < 0 || index >= _schools.length) return;
    if (_isPresetSchool(_schools[index])) {
      AppToast.show(context, '预设学校不支持删除', variant: AppToastVariant.warning);
      return;
    }

    setState(() {
      _deletingIndices.add(index);
      _swipeOffsets.remove(index);
      if (_editingIndex == index) {
        _editingIndex = -1;
      }
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));
    await WebSchoolService.instance.deleteSchool(index);
    await _loadSchools();

    if (!mounted) return;
    setState(() {
      _deletingIndices.clear();
    });
  }

  /// 打开新增学校弹窗。
  void _openAddSchoolDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => _AddSchoolDialog(
        onAdd: (WebSchool school) async {
          await WebSchoolService.instance.addSchool(school);
          await _loadSchools();
          if (!mounted) return;
          setState(() {
            _newlyAddedIndex = _schools.length - 1;
          });
        },
      ),
    );
  }

  /// 点击学校卡片。
  Future<void> _onSchoolTap(int index) async {
    if ((_swipeOffsets[index] ?? 0) < 0) {
      _closeAllSwipeActions();
      return;
    }

    if (_editingIndex == index) {
      setState(() {
        _editingIndex = -1;
      });
      return;
    }

    final WebSchool school = _schools[index];
    final bool? result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (context) => WebImportLoginPage(school: school),
      ),
    );
    // 课表创建成功后一路回退到课表主页
    if (result == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '网页导入课表',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: <Widget>[
          _buildActionButtons(colorScheme),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _schools.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.school_outlined,
                    size: 56,
                    color: colorScheme.primary.withAlpha(128),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '暂无学校，点击右上角新增',
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurface.withAlpha(153),
                    ),
                  ),
                ],
              ),
            )
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                if (_editingIndex != -1 || _swipeOffsets.isNotEmpty) {
                  setState(() {
                    _editingIndex = -1;
                    _swipeOffsets.clear();
                  });
                }
              },
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                itemCount: _schools.length,
                itemBuilder: (context, index) {
                  return _buildSchoolItem(context, index);
                },
              ),
            ),
    );
  }

  /// 构建右上角按钮：新增（不加粗）。
  Widget _buildActionButtons(ColorScheme colorScheme) {
    return TextButton(
      onPressed: _openAddSchoolDialog,
      child: Text(
        '新增',
        style: TextStyle(
          color: colorScheme.primary,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 构建单个学校项（含新增/删除动画）。
  Widget _buildSchoolItem(BuildContext context, int index) {
    final bool isDeleting = _deletingIndices.contains(index);
    final bool isNew = index == _newlyAddedIndex;

    if (isDeleting) {
      return TweenAnimationBuilder<double>(
        key: ValueKey<String>('deleting_$index'),
        tween: Tween<double>(begin: 1.0, end: 0.0),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInQuart,
        builder: (context, value, child) {
          return ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: value,
              child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
            ),
          );
        },
        child: _buildSchoolCard(context, index),
      );
    }

    if (isNew) {
      return TweenAnimationBuilder<double>(
        key: ValueKey<String>('new_$index'),
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 800),
        curve: Curves.linear,
        onEnd: () {
          if (!mounted) return;
          setState(() {
            _newlyAddedIndex = null;
          });
        },
        builder: (context, value, child) {
          final double slideInput = (value / 0.666).clamp(0.0, 1.0);
          final double slideValue = Curves.easeOutQuart.transform(slideInput);

          return Align(
            alignment: Alignment.topCenter,
            heightFactor: slideValue,
            child: Transform.translate(
              offset: Offset(0, 40 * (1 - slideValue)),
              child: Opacity(opacity: slideValue.clamp(0.0, 1.0), child: child),
            ),
          );
        },
        child: _buildSchoolCard(context, index),
      );
    }

    return _buildSchoolCard(context, index);
  }

  /// 构建学校卡片。
  Widget _buildSchoolCard(BuildContext context, int index) {
    final WebSchool school = _schools[index];
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isEditing = _editingIndex == index;
    final bool isPreset = _isPresetSchool(school);
    final double actionWidth = _actionWidthForSchool(school);
    final double swipeOffset = _swipeOffsets[index] ?? 0;
    final double revealWidth = (-swipeOffset).clamp(0.0, actionWidth);
    final double actionGap = math.min(4.0, revealWidth);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double maxWidth = constraints.maxWidth;
          final double cardWidth = (maxWidth - revealWidth - actionGap).clamp(
            maxWidth - actionWidth - 4,
            maxWidth,
          );

          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: _buildSwipeActionPane(
                      colorScheme: colorScheme,
                      index: index,
                      isPreset: isPreset,
                    ),
                  ),
                  GestureDetector(
                    onHorizontalDragUpdate: _editingIndex == -1
                        ? (details) {
                            _onCardHorizontalDragUpdate(index, details);
                          }
                        : null,
                    onHorizontalDragEnd: _editingIndex == -1
                        ? (_) {
                            _onCardHorizontalDragEnd(index);
                          }
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      width: cardWidth,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).cardTheme.color ??
                              colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _onSchoolTap(index),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 20,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      SizedBox(
                                        width: 40,
                                        height: 40,
                                        child: _buildSchoolBadge(school),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Text(
                                          school.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: AnimatedOpacity(
                                          duration: const Duration(
                                            milliseconds: 120,
                                          ),
                                          opacity: revealWidth <= 0.1 ? 1 : 0,
                                          child: Icon(
                                            Icons.chevron_right,
                                            color: colorScheme.onSurface
                                                .withAlpha(102),
                                            size: 22,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOut,
                                    child: isEditing
                                        ? Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: _buildUrlEditField(
                                              colorScheme,
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建左滑后显示的动作区域（编辑/删除）。
  Widget _buildSwipeActionPane({
    required ColorScheme colorScheme,
    required int index,
    required bool isPreset,
  }) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildSwipeActionButton(
            icon: Icons.edit_outlined,
            label: '编辑',
            backgroundColor: colorScheme.primary.withAlpha(24),
            foregroundColor: colorScheme.primary,
            width: 72,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              bottomLeft: const Radius.circular(20),
              topRight: isPreset ? const Radius.circular(20) : Radius.zero,
              bottomRight: isPreset ? const Radius.circular(20) : Radius.zero,
            ),
            onTap: () {
              _closeAllSwipeActions();
              _toggleEditUrlPanel(index);
            },
          ),
          if (!isPreset)
            _buildSwipeActionButton(
              icon: Icons.delete_outline,
              label: '删除',
              backgroundColor: colorScheme.error.withAlpha(24),
              foregroundColor: colorScheme.error,
              width: 72,
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
              onTap: () {
                _closeAllSwipeActions();
                _deleteSchool(index);
              },
            ),
        ],
      ),
    );
  }

  /// 构建左滑动作按钮。
  Widget _buildSwipeActionButton({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color foregroundColor,
    required double width,
    required BorderRadius borderRadius,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: width,
      child: Material(
        color: backgroundColor,
        borderRadius: borderRadius,
        child: InkWell(
          borderRadius: borderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, color: foregroundColor, size: 20),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建学校校徽：优先显示自定义导入校徽，其次显示预设 FIT 校徽。
  Widget _buildSchoolBadge(WebSchool school) {
    final Uint8List? badgeBytes = _decodeBadgeBytes(school.badgeBase64);
    if (badgeBytes != null) {
      return ClipOval(
        child: Image.memory(
          badgeBytes,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    if (school.name == '福州理工学院') {
      return ClipOval(
        child: Image.asset(
          _fitBadgeAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(shape: BoxShape.circle),
      child: Icon(Icons.school_rounded, size: 40, color: Colors.grey.shade600),
    );
  }

  /// 解码 Base64 校徽数据，失败时返回 null。
  Uint8List? _decodeBadgeBytes(String? badgeBase64) {
    if (badgeBase64 == null || badgeBase64.isEmpty) {
      return null;
    }
    try {
      return base64Decode(badgeBase64);
    } catch (_) {
      return null;
    }
  }

  /// 构建网址编辑输入框。
  Widget _buildUrlEditField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '教务系统网址',
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurface.withAlpha(153),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _editUrlController,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: '输入教务系统网页地址',
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withAlpha(102),
              fontSize: 14,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            filled: true,
            fillColor: colorScheme.surfaceContainerHighest.withAlpha(128),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
            ),
          ),
          maxLines: 2,
          onSubmitted: (_) => _saveEditingUrl(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _saveEditingUrl,
            child: Text(
              '确认修改',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 新增学校弹窗。
///
/// 支持手动输入学校名称、网页地址与校徽图片。
class _AddSchoolDialog extends StatefulWidget {
  final Future<void> Function(WebSchool school) onAdd;

  const _AddSchoolDialog({required this.onAdd});

  @override
  State<_AddSchoolDialog> createState() => _AddSchoolDialogState();
}

class _AddSchoolDialogState extends State<_AddSchoolDialog> {
  static const String _fitBadgeAsset = 'assets/images/schoolBadge/FIT.jpg';

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  Uint8List? _badgePreviewBytes;
  bool _isAdding = false;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleAdd() async {
    final String name = _nameController.text.trim();
    final String url = _urlController.text.trim();

    if (name.isEmpty) {
      AppToast.show(context, '请输入学校名称', variant: AppToastVariant.warning);
      return;
    }
    if (url.isEmpty) {
      AppToast.show(context, '请输入网页地址', variant: AppToastVariant.warning);
      return;
    }

    final String? badgeBase64 = _badgePreviewBytes == null
        ? null
        : base64Encode(_badgePreviewBytes!);

    setState(() => _isAdding = true);
    await widget.onAdd(
      WebSchool(name: name, url: url, badgeBase64: badgeBase64),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// 导入校徽图片并更新预览。
  Future<void> _pickBadgeImage() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final Uint8List? bytes = result.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) {
        AppToast.show(context, '图片读取失败，请重试', variant: AppToastVariant.warning);
      }
      return;
    }

    setState(() {
      _badgePreviewBytes = bytes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '新增学校',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Text(
              '学校名称',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              onChanged: (_) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: '例如：福州理工学院',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withAlpha(102),
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(128),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text(
              '网页地址',
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
              decoration: InputDecoration(
                hintText: '输入教务系统网页地址',
                hintStyle: TextStyle(
                  color: colorScheme.onSurface.withAlpha(102),
                  fontSize: 14,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withAlpha(128),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),

            Row(
              children: <Widget>[
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withAlpha(128),
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: ClipOval(
                    child: _badgePreviewBytes != null
                        ? Image.memory(
                            _badgePreviewBytes!,
                            fit: BoxFit.cover,
                            filterQuality: FilterQuality.high,
                          )
                        : (_nameController.text.trim() == '福州理工学院'
                              ? Image.asset(
                                  _fitBadgeAsset,
                                  fit: BoxFit.cover,
                                  filterQuality: FilterQuality.high,
                                )
                              : Icon(
                                  Icons.school_rounded,
                                  color: colorScheme.primary,
                                  size: 38,
                                )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickBadgeImage,
                    icon: const Icon(Icons.upload_rounded, size: 18),
                    label: const Text('导入校徽'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _isAdding ? null : _handleAdd,
                child: _isAdding
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : const Text(
                        '添加',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
