import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/utils/constants.dart';
import 'package:dormdevise/utils/person_identity.dart';
import 'package:dormdevise/utils/person_signature_layout.dart';
import 'package:dormdevise/utils/qr_image_export_service.dart';
import 'package:dormdevise/utils/text_length_counter.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// 用户设置页：支持本地编辑头像、昵称、性别、生日和签名。
class UserProfileSettingsPage extends StatefulWidget {
  const UserProfileSettingsPage({super.key});

  @override
  State<UserProfileSettingsPage> createState() =>
      _UserProfileSettingsPageState();
}

class _UserProfileSettingsPageState extends State<UserProfileSettingsPage> {
  final PersonIdentityService _service = PersonIdentityService.instance;
  final ImagePicker _imagePicker = ImagePicker();
  static const int _signatureMaxLengthUnits = 50;
  // 昵称按半角单位计数：英文 1，中文 2；上限 20。
  static const int _nicknameMaxLengthUnits = 20;
  PersonIdentityProfile _profile = PersonIdentityProfile.defaults();
  bool _loading = true;
  bool _isGenderExpanded = false;
  bool _isBirthDateExpanded = false;

  /// 出生年月选择器当前暂存日期，展开时初始化，收起时持久化
  DateTime? _pendingPickerDate;

  /// 滚动停止后延迟保存的定时器
  Timer? _birthDateSaveTimer;

  /// 出生年月选择器的重建 Key：每次展开自增，确保全新 State
  int _birthDatePickerKey = 0;

  @override
  void initState() {
    super.initState();
    _service.addListener(_handleProfileChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _birthDateSaveTimer?.cancel();
    _service.removeListener(_handleProfileChanged);
    super.dispose();
  }

  /// 接收全局资料变化后刷新当前页面。
  void _handleProfileChanged() {
    _loadProfile();
  }

  /// 从本地服务读取最新用户资料。
  Future<void> _loadProfile() async {
    final PersonIdentityProfile profile = await _service.loadProfile();
    if (!mounted) {
      return;
    }
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  /// 统一封装资料更新并提示结果。
  Future<void> _applyUpdate(
    Future<void> Function() action, {
    bool showSuccessToast = true,
  }) async {
    try {
      await action();
      if (!mounted) {
        return;
      }
      if (showSuccessToast) {
        AppToast.show(context, '资料已更新', variant: AppToastVariant.success);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '更新失败：$error', variant: AppToastVariant.error);
    }
  }

  /// 编辑昵称。
  Future<void> _editNickname() async {
    // 打开弹窗时直接显示原昵称，便于在原文基础上编辑。
    final String? result = await _showTextEditorDialog(
      title: '修改昵称',
      initialValue: _profile.displayName,
      hintText: '昵称',
      maxLines: 1,
      maxLengthUnits: _nicknameMaxLengthUnits,
      duplicateValue: _profile.displayName,
      emptyErrorText: '昵称不能为空！',
      exceededErrorText: '昵称超出字数限制！',
    );
    if (result == null) {
      return;
    }
    await _applyUpdate(() => _service.updateProfile(displayName: result));
  }

  /// 编辑个性签名。
  Future<void> _editSignature() async {
    final String normalizedSignature = _resolveSignatureDisplayText(
      _profile.signature,
    );
    final bool useDefaultAsHint = normalizedSignature == kDefaultSignatureText;
    final String? result = await _showTextEditorDialog(
      title: '修改个性签名',
      // 默认文案作为提示语，不作为真实输入值。
      initialValue: useDefaultAsHint
          ? ''
          : normalizedSignature.replaceAll(RegExp(r'[\r\n]'), ''),
      hintText: kDefaultSignatureText,
      maxLines: 3,
      maxLengthUnits: _signatureMaxLengthUnits,
      helperText: '写点什么介绍自己吧！',
      exceededErrorText: '个性签名超出字数限制！',
      allowEmptySubmit: true,
      emptyValueOnSave: kDefaultSignatureText,
    );
    if (result == null) {
      return;
    }
    await _applyUpdate(() => _service.updateProfile(signature: result));
  }

  /// 点击性别行时展开或收起性别选项。
  void _toggleGenderExpanded() {
    setState(() {
      _isGenderExpanded = !_isGenderExpanded;
      if (_isGenderExpanded) {
        _isBirthDateExpanded = false;
      }
    });
  }

  /// 点击出生年月行时展开或收起日期滚轮。
  void _toggleBirthDateExpanded() {
    setState(() {
      _isBirthDateExpanded = !_isBirthDateExpanded;
      if (_isBirthDateExpanded) {
        _isGenderExpanded = false;
        // 展开时初始化暂存日期，并递增 Key 强制全新 picker 实例
        _pendingPickerDate = _resolveBirthDateForPicker();
        _birthDatePickerKey++;
      } else {
        // 收起时取消延迟定时器并立即持久化当前日期
        _birthDateSaveTimer?.cancel();
        _birthDateSaveTimer = null;
        if (_pendingPickerDate != null && _pendingPickerDate!.year >= 1950) {
          _updateBirthDate(_pendingPickerDate!);
          _pendingPickerDate = null;
        }
      }
    });
  }

  /// 选择性别，空字符串表示“未配置”。
  Future<void> _selectGender(String gender) async {
    await _applyUpdate(() => _service.updateProfile(gender: gender));
    if (!mounted) {
      return;
    }
    setState(() {
      _isGenderExpanded = false;
    });
  }

  /// 构建纵向性别选项，使用列表行样式更贴合设置页主题。
  Widget _buildGenderOptionTile({
    required String label,
    required String value,
    required bool isLast,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool selected = _profile.gender.trim() == value.trim();

    return Column(
      children: <Widget>[
        InkWell(
          onTap: () => _selectGender(value),
          // 去除长按/点击时的灰色状态底，保持设置页干净视觉。
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          overlayColor: WidgetStateProperty.all<Color>(Colors.transparent),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: <Widget>[
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: selected
                      ? Icon(
                          Icons.check_rounded,
                          key: ValueKey<String>('gender_$value'),
                          color: colorScheme.onSurface,
                          size: 20,
                        )
                      : Icon(
                          Icons.radio_button_unchecked_rounded,
                          key: ValueKey<String>('gender_unchecked_$value'),
                          color: colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 12,
            endIndent: 12,
            color: colorScheme.outlineVariant.withValues(alpha: 0.55),
          ),
      ],
    );
  }

  /// 屏蔽列表行的长按灰色态，避免头像等设置行出现灰底。
  Widget _buildNoPressOverlayTheme({required Widget child}) {
    final ThemeData theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: child,
    );
  }

  /// 出生年月滚轮变更时同步更新资料（静默更新，避免滚动时重复提示）。
  Future<void> _updateBirthDate(DateTime date) async {
    // 防御：拒绝早于 1950 年的异常值
    if (date.year < 1950) return;
    final DateTime? current = _profile.birthDate;
    if (current != null &&
        current.year == date.year &&
        current.month == date.month &&
        current.day == date.day) {
      return;
    }
    // 立即更新本地状态，确保 picker 每次重建时 daysInMonth 正确
    setState(() {
      _profile = _profile.copyWith(birthDate: date);
    });
    await _applyUpdate(
      () => _service.updateProfile(birthDate: date),
      showSuccessToast: false,
    );
  }

  /// 修改头像：最终都会保存为本地文件路径。
  Future<void> _editAvatar() async {
    final _AvatarEditAction?
    action = await showModalBottomSheet<_AvatarEditAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('从相册选择'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AvatarEditAction.pickAlbum),
              ),
              ListTile(
                leading: const Icon(Icons.link_outlined),
                title: const Text('链接获取'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AvatarEditAction.inputUrl),
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('拍照'),
                onTap: () =>
                    Navigator.of(sheetContext).pop(_AvatarEditAction.takePhoto),
              ),
              ListTile(
                enabled: false,
                leading: Icon(
                  Icons.shuffle_rounded,
                  color: Theme.of(
                    sheetContext,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                ),
                title: Text(
                  '随机',
                  style: TextStyle(
                    color: Theme.of(
                      sheetContext,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
                subtitle: Text(
                  '暂未开放，后续版本更新',
                  style: TextStyle(
                    color: Theme.of(
                      sheetContext,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    switch (action) {
      case _AvatarEditAction.pickAlbum:
        await _pickAndCropAvatar(ImageSource.gallery);
        break;
      case _AvatarEditAction.takePhoto:
        await _pickAndCropAvatar(ImageSource.camera);
        break;
      case _AvatarEditAction.inputUrl:
        final String? url = await _showTextEditorDialog(
          title: '输入头像链接',
          initialValue: '',
          hintText: 'https://example.com/avatar.jpg',
          maxLines: 1,
        );
        if (url == null) {
          return;
        }
        await _downloadAndCropAvatar(url);
        break;
      case _AvatarEditAction.random:
        break;
    }
  }

  /// 下载头像图片并使用圆形裁剪框进行精细调整。
  Future<void> _downloadAndCropAvatar(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      final http.Response response = await http.get(uri);
      if (response.statusCode != 200) {
        if (mounted) {
          AppToast.show(
            context,
            '图片下载失败 (${response.statusCode})',
            variant: AppToastVariant.error,
          );
        }
        return;
      }
      final Directory tempDir = await getTemporaryDirectory();
      final File tempFile = File(
        '${tempDir.path}/temp_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(response.bodyBytes);
      await _cropImage(tempFile.path);
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '图片处理失败：$e', variant: AppToastVariant.error);
      }
    }
  }

  /// 从相册或相机获取头像后，弹出圆形裁剪框进行精细调整。
  Future<void> _pickAndCropAvatar(ImageSource source) async {
    try {
      // 相册入口统一走系统图片选择器，支持按“全部图片”范围挑选。
      if (source == ImageSource.gallery) {
        await _pickAndCropAvatarFromSystemImagePicker();
        return;
      }

      final XFile? pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 100,
      );
      if (pickedFile == null || pickedFile.path.trim().isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      await _cropImage(pickedFile.path);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '头像选择失败：$error', variant: AppToastVariant.error);
    }
  }

  /// 使用系统图片选择器挑选头像（单张），并进入后续裁剪流程。
  Future<void> _pickAndCropAvatarFromSystemImagePicker() async {
    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
        dialogTitle: '选择照片',
      );
      if (result == null || result.files.isEmpty) {
        return;
      }

      final PlatformFile picked = result.files.single;
      String? selectedPath = picked.path?.trim();

      // 某些设备返回 content uri 时可能没有可用 path，回退为临时文件路径。
      if ((selectedPath == null || selectedPath.isEmpty) &&
          picked.bytes != null) {
        final Uint8List data = picked.bytes!;
        final Directory tempDir = await getTemporaryDirectory();
        final String ext = (picked.extension ?? 'jpg').trim().isEmpty
            ? 'jpg'
            : picked.extension!.trim();
        final File tempFile = File(
          '${tempDir.path}/picked_avatar_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
        await tempFile.writeAsBytes(data, flush: true);
        selectedPath = tempFile.path;
      }

      if (selectedPath == null || selectedPath.isEmpty) {
        if (!mounted) {
          return;
        }
        AppToast.show(context, '未获取到图片路径，请重试', variant: AppToastVariant.error);
        return;
      }

      if (!mounted) {
        return;
      }
      await _cropImage(selectedPath);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '头像选择失败：$error', variant: AppToastVariant.error);
    }
  }

  Future<void> _cropImage(String imagePath) async {
    try {
      final CroppedFile? croppedFile = await ImageCropper().cropImage(
        sourcePath: imagePath,
        compressFormat: ImageCompressFormat.png,
        uiSettings: <PlatformUiSettings>[
          AndroidUiSettings(
            toolbarTitle: '调整头像',
            toolbarColor: const Color(0xFF111111),
            toolbarWidgetColor: Colors.white,
            statusBarLight: false,
            backgroundColor: Colors.black,
            // 轮盘指针与度数字体使用黑灰色，贴合历史视觉风格。
            activeControlsWidgetColor: const Color(0xFF2E333A),
            cropFrameColor: Colors.white,
            // 提高圆框描边宽度，让外圈高亮更明显。
            cropFrameStrokeWidth: 3,
            // 未拖动时，圆外区域更明显地渐灭到黑色背景。
            cropGridColor: Colors.transparent,
            // 灰色半透明改为黑色半透明
            dimmedLayerColor: const Color(0x99000000),
            showCropGrid: false,
            hideBottomControls: false,
            lockAspectRatio: true,
            // 仅保留 1:1 选项，确保头像裁剪框始终为正方形。
            aspectRatioPresets: const <CropAspectRatioPresetData>[
              CropAspectRatioPreset.square,
            ],
            initAspectRatio: CropAspectRatioPreset.square,
            cropStyle: CropStyle.circle,
          ),
          IOSUiSettings(
            title: '调整头像',
            aspectRatioLockEnabled: true,
            rotateButtonsHidden: true,
            rotateClockwiseButtonHidden: true,
            resetAspectRatioEnabled: false,
            cropStyle: CropStyle.circle,
          ),
        ],
      );
      if (croppedFile == null || croppedFile.path.trim().isEmpty) {
        return;
      }

      await _applyUpdate(
        () => _service.updateProfile(avatarPath: croppedFile.path),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '头像处理失败：$error', variant: AppToastVariant.error);
    }
  }

  /// 弹出文本编辑对话框。
  Future<String?> _showTextEditorDialog({
    required String title,
    required String initialValue,
    required String hintText,
    required int maxLines,
    int? maxLengthUnits,
    String? helperText,
    String? duplicateValue,
    bool allowEmptySubmit = false,
    String? emptyValueOnSave,
    String? emptyErrorText,
    String? exceededErrorText,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return _ProfileTextEditorDialog(
          title: title,
          initialValue: initialValue,
          hintText: hintText,
          maxLines: maxLines,
          maxLengthUnits: maxLengthUnits,
          helperText: helperText,
          duplicateValue: duplicateValue,
          allowEmptySubmit: allowEmptySubmit,
          emptyValueOnSave: emptyValueOnSave,
          emptyErrorText: emptyErrorText,
          exceededErrorText: exceededErrorText,
        );
      },
    );
  }

  /// 展开区域通用动画：展开/收起时同时做高度和透明度过渡。
  Widget _buildExpandAnimatedContent({
    required bool expanded,
    required Widget child,
  }) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeInOutCubic,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: expanded ? 1 : 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            opacity: expanded ? 1 : 0,
            child: IgnorePointer(ignoring: !expanded, child: child),
          ),
        ),
      ),
    );
  }

  /// 根据当前资料计算滚轮的初始日期。
  DateTime _resolveBirthDateForPicker() {
    final DateTime now = DateTime.now();
    // 未配置时默认定位到今天日期，减少二次滚动操作。
    final DateTime fallback = DateTime(now.year, now.month, now.day);
    final DateTime raw = _profile.birthDate ?? fallback;
    final DateTime minDate = DateTime(1950, 1, 1);
    final DateTime maxDate = DateTime(now.year, 12, 31);
    if (raw.isBefore(minDate)) {
      return minDate;
    }
    if (raw.isAfter(maxDate)) {
      return maxDate;
    }
    return raw;
  }

  /// 动画弹窗显示二维码名片详情。
  Future<void> _showNameCardDialog() async {
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '二维码名片',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, _, __) {
        return _NameCardDetailDialog(
          profile: _profile,
          nameCardPayload: _buildNameCardPayload(),
        );
      },
      transitionBuilder: (dialogContext, animation, _, child) {
        final Animation<double> curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  /// 退出登录并返回上一页。
  Future<void> _logout() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确认退出当前账号吗？'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) {
      return;
    }

    try {
      await _service.logout();
      if (!mounted) {
        return;
      }
      AppToast.show(context, '已退出登录', variant: AppToastVariant.success);
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '退出失败：$error', variant: AppToastVariant.error);
    }
  }

  /// 构建本地二维码名片负载。
  String _buildNameCardPayload() {
    final Map<String, Object?> payload = <String, Object?>{
      'uid': _profile.uid,
      'nickname': _profile.displayName,
      'account': _profile.account,
      'gender': _profile.genderText,
      'birthDate': _profile.birthDateText,
      'signature': _profile.signature,
    };
    return jsonEncode(payload);
  }

  /// 长按 UID 时复制到剪贴板，并给出轻量反馈。
  Future<void> _copyUidToClipboard() async {
    await Clipboard.setData(ClipboardData(text: '${_profile.uid}'));
    if (!mounted) {
      return;
    }
    await HapticFeedback.selectionClick();
    if (!mounted) {
      return;
    }
    AppToast.show(context, 'UID 已复制', variant: AppToastVariant.success);
  }

  /// 签名为空时统一展示默认文案。
  String _resolveSignatureDisplayText(String signature) {
    final String normalized = signature.trim();
    if (normalized.isEmpty) {
      return kDefaultSignatureText;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isDarkMode = theme.brightness == Brightness.dark;
    // 资料区字号与 UID/二维码名片条目保持一致。
    final TextStyle settingsLabelTextStyle =
        theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16);
    final double settingsLabelFontSize = settingsLabelTextStyle.fontSize ?? 16;
    final double settingsValueFontSize = settingsLabelFontSize > 2
        ? settingsLabelFontSize - 2
        : settingsLabelFontSize;
    // 统一值文本灰色，保证 UID 和签名右侧在深浅模式都稳定可读。
    final Color mutedValueColor = isDarkMode
        ? const Color(0xFFB3BECE)
        : const Color(0xFF8A8E99);
    final TextStyle settingsValueTextStyle = settingsLabelTextStyle.copyWith(
      fontSize: settingsValueFontSize,
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final double signatureValueFontSize = settingsValueFontSize > 2
        ? settingsValueFontSize - 2
        : settingsValueFontSize;
    final TextStyle signatureValueTextStyle = settingsValueTextStyle.copyWith(
      fontSize: signatureValueFontSize,
      color: mutedValueColor,
    );
    // UID 与二维码名片左侧标题与头像左侧标题保持完全一致。
    final TextStyle uidCardTitleTextStyle = settingsLabelTextStyle;
    // 资料区左右留白按二维码名片条目间距对齐。
    const EdgeInsets settingsTilePadding = EdgeInsets.symmetric(horizontal: 16);

    // 设置卡片统一底色，避免深色模式下内层选项块出现偏蓝偏黑色差。
    final Color settingsCardColor =
        theme.cardTheme.color ?? theme.colorScheme.surfaceContainerHighest;
    final Color nameCardBackground = isDarkMode
        ? colorScheme.surfaceContainerHigh
        : Colors.white;
    final Color uidSolidGray = isDarkMode
        ? const Color(0xFF7C818A)
        : const Color(0xFFE2E4E8);
    final Color uidGradientEnd = isDarkMode ? nameCardBackground : Colors.white;
    // 签名优先一行显示，空间不足时再自动换到两行。
    final double signatureValueMaxWidth = min(
      220.0,
      max(150.0, MediaQuery.sizeOf(context).width * 0.52),
    );
    // 设置页签名按13中文字符自动换行，并完整展示内容。
    final String settingsSignatureText = formatSignatureForSettingsDisplay(
      _profile.signature,
      maxCharsPerLine: 13,
    );
    final TextScaler settingsSignatureTextScaler = MediaQuery.textScalerOf(
      context,
    );
    final List<String> settingsSignatureLines = settingsSignatureText.split(
      '\n',
    );
    final bool isSettingsSignatureTwoLines = settingsSignatureLines.length > 1;
    final String settingsSignatureFirstLine = settingsSignatureLines.isNotEmpty
        ? settingsSignatureLines.first
        : settingsSignatureText;
    final String settingsSignatureSecondLine = settingsSignatureLines.length > 1
        ? settingsSignatureLines[1]
        : '';
    final double settingsSignatureFirstLineWidth = () {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: settingsSignatureFirstLine,
          style: signatureValueTextStyle,
        ),
        textDirection: Directionality.of(context),
        textScaler: settingsSignatureTextScaler,
        maxLines: 1,
      )..layout(maxWidth: signatureValueMaxWidth);
      return painter.size.width;
    }();
    final double settingsSignatureSecondLineWidth = () {
      final TextPainter painter = TextPainter(
        text: TextSpan(
          text: settingsSignatureSecondLine,
          style: signatureValueTextStyle,
        ),
        textDirection: Directionality.of(context),
        textScaler: settingsSignatureTextScaler,
        maxLines: 1,
      )..layout(maxWidth: signatureValueMaxWidth);
      return painter.size.width;
    }();
    final double settingsSignatureTwoLineBlockWidth = max(
      settingsSignatureFirstLineWidth,
      settingsSignatureSecondLineWidth,
    ).clamp(0.0, signatureValueMaxWidth).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('用户设置')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: <Widget>[
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _buildNoPressOverlayTheme(
                    child: Column(
                      children: <Widget>[
                        ListTile(
                          // 使用标题位文本，字号与 UID/二维码名片条目保持一致。
                          contentPadding: settingsTilePadding,
                          title: Text('头像', style: settingsLabelTextStyle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _ProfileAvatarPreview(path: _profile.avatarPath),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: _editAvatar,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          // 使用标题位文本，字号与 UID/二维码名片条目保持一致。
                          contentPadding: settingsTilePadding,
                          title: Text('昵称', style: settingsLabelTextStyle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 180,
                                ),
                                child: Text(
                                  _profile.displayName,
                                  overflow: TextOverflow.ellipsis,
                                  style: settingsValueTextStyle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: _editNickname,
                        ),
                        const Divider(height: 1),
                        ListTile(
                          // 使用标题位文本，字号与 UID/二维码名片条目保持一致。
                          contentPadding: settingsTilePadding,
                          title: Text('性别', style: settingsLabelTextStyle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _profile.genderText,
                                style: settingsValueTextStyle,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _isGenderExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                              ),
                            ],
                          ),
                          onTap: _toggleGenderExpanded,
                        ),
                        _buildExpandAnimatedContent(
                          expanded: _isGenderExpanded,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: settingsCardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.transparent),
                              ),
                              child: Column(
                                children: <Widget>[
                                  _buildGenderOptionTile(
                                    label: '男',
                                    value: '男',
                                    isLast: false,
                                  ),
                                  _buildGenderOptionTile(
                                    label: '女',
                                    value: '女',
                                    isLast: false,
                                  ),
                                  _buildGenderOptionTile(
                                    label: '保密',
                                    value: '保密',
                                    isLast: true,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          // 使用标题位文本，字号与 UID/二维码名片条目保持一致。
                          contentPadding: settingsTilePadding,
                          title: Text('出生年月', style: settingsLabelTextStyle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                _profile.birthDateText,
                                style: settingsValueTextStyle,
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                _isBirthDateExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                              ),
                            ],
                          ),
                          onTap: _toggleBirthDateExpanded,
                        ),
                        _buildExpandAnimatedContent(
                          expanded: _isBirthDateExpanded,
                          child: _BirthDateWheelPicker(
                            key: ValueKey<int>(_birthDatePickerKey),
                            initialDate:
                                _pendingPickerDate ??
                                _resolveBirthDateForPicker(),
                            onChanged: (DateTime date) {
                              // 防御：拒绝早于 1950 年的异常值
                              if (date.year < 1950) return;
                              // 滚动期间暂存并启动延迟保存定时器
                              _pendingPickerDate = date;
                              _birthDateSaveTimer?.cancel();
                              _birthDateSaveTimer = Timer(
                                const Duration(milliseconds: 500),
                                () {
                                  if (_pendingPickerDate != null) {
                                    _updateBirthDate(_pendingPickerDate!);
                                  }
                                },
                              );
                            },
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          // 使用标题位文本，字号与 UID/二维码名片条目保持一致。
                          contentPadding: settingsTilePadding,
                          minVerticalPadding: 10,
                          title: Text('个性签名', style: settingsLabelTextStyle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                width: signatureValueMaxWidth,
                                child: !isSettingsSignatureTwoLines
                                    ? Text(
                                        settingsSignatureText,
                                        softWrap: true,
                                        // 单行保持右对齐，与其他设置值列对齐。
                                        textAlign: TextAlign.right,
                                        style: signatureValueTextStyle,
                                      )
                                    : Align(
                                        alignment: Alignment.centerRight,
                                        child: SizedBox(
                                          width:
                                              settingsSignatureTwoLineBlockWidth <=
                                                  0
                                              ? signatureValueMaxWidth
                                              : settingsSignatureTwoLineBlockWidth,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                settingsSignatureFirstLine,
                                                maxLines: 1,
                                                softWrap: false,
                                                style: signatureValueTextStyle,
                                              ),
                                              // 双行时第二行左边对齐到第一行13字块起点。
                                              Text(
                                                settingsSignatureSecondLine,
                                                maxLines: 1,
                                                softWrap: false,
                                                style: signatureValueTextStyle,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: _editSignature,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: _buildNoPressOverlayTheme(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                      child: Column(
                        children: <Widget>[
                          // UID 放在二维码名片上方，并从右侧灰色平滑渐变到左侧背景色。
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              gradient: LinearGradient(
                                begin: Alignment.centerRight,
                                end: Alignment.centerLeft,
                                stops: const <double>[0.0, 1.0],
                                colors: <Color>[uidSolidGray, uidGradientEnd],
                              ),
                            ),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: const Icon(Icons.perm_identity_rounded),
                              title: Text('UID', style: uidCardTitleTextStyle),
                              trailing: Text(
                                '${_profile.uid}',
                                style: TextStyle(
                                  color: mutedValueColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onLongPress: _copyUidToClipboard,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(
                              color: nameCardBackground,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: ListTile(
                              onTap: _showNameCardDialog,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              leading: const Icon(Icons.badge_outlined),
                              title: Text(
                                '二维码名片',
                                style: uidCardTitleTextStyle,
                              ),
                              trailing: const Icon(Icons.chevron_right_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _logout,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('退出登录'),
                ),
              ],
            ),
    );
  }
}

/// 出生年月滚轮选择器：内部管理年/月/日状态与滚动控制器，
/// 确保月份变化时日期列表动态更新，杜绝越界日期（如 2 月 31 日）。
class _BirthDateWheelPicker extends StatefulWidget {
  const _BirthDateWheelPicker({
    super.key,
    required this.initialDate,
    required this.onChanged,
  });

  /// 初始选中日期
  final DateTime initialDate;

  /// 选中日期变化回调
  final ValueChanged<DateTime> onChanged;

  @override
  State<_BirthDateWheelPicker> createState() => _BirthDateWheelPickerState();
}

class _BirthDateWheelPickerState extends State<_BirthDateWheelPicker> {
  late int _year;
  late int _month;
  late int _day;

  late final List<int> _years;
  final List<int> _months = List<int>.generate(12, (int i) => i + 1);
  List<int> _days = <int>[];

  late FixedExtentScrollController _yearController;
  late FixedExtentScrollController _monthController;
  late FixedExtentScrollController _dayController;

  /// 初始化就位标记：阻止首次布局滚动期间的中间值被保存
  bool _initialized = false;
  Timer? _initTimer;

  /// 当前选中月份的实际天数（考虑闰年）
  int get _daysInSelectedMonth => DateTime(_year, _month + 1, 0).day;

  @override
  void initState() {
    super.initState();
    _year = widget.initialDate.year;
    _month = widget.initialDate.month;
    _day = widget.initialDate.day;

    final int nowYear = DateTime.now().year;
    // 年份下限与 _resolveBirthDateForPicker 的 minDate 保持一致
    const int minYear = 1950;
    _years = List<int>.generate(nowYear - minYear + 1, (int i) => minYear + i);
    _rebuildDayList();

    _yearController = FixedExtentScrollController(
      initialItem: _years.indexOf(_year).clamp(0, _years.length - 1),
    );
    _monthController = FixedExtentScrollController(initialItem: _month - 1);
    _dayController = FixedExtentScrollController(initialItem: _day - 1);

    // 延迟标记初始化完成，避免 CupertinoPicker 初始布局滚动期间的中间值被保存
    _initTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _initialized = true;
        });
        // 发射最终稳定值让父级知晓当前日期
        _emit();
      }
    });
  }

  /// 根据当前选中的年月重建日列表并确保 day 不越界
  void _rebuildDayList() {
    final int maxDay = _daysInSelectedMonth;
    _days = List<int>.generate(maxDay, (int i) => i + 1);
    if (_day > maxDay) {
      _day = maxDay;
    }
  }

  /// 统一发射选中日期变更事件（初始化就位前静默，防止中间值被持久化）
  void _emit() {
    if (_initialized) {
      widget.onChanged(DateTime(_year, _month, _day));
    }
  }

  /// 年份变更：夹紧日期并重建日列表
  void _onYearChanged(int index) {
    final int newYear = _years[index % _years.length];
    final int oldMaxDay = _daysInSelectedMonth;
    setState(() {
      _year = newYear;
      _rebuildDayList();
    });
    // 闰年/平年切换导致天数不同时，重建日滚轮
    if (_daysInSelectedMonth != oldMaxDay) {
      final FixedExtentScrollController old = _dayController;
      _dayController = FixedExtentScrollController(initialItem: _day - 1);
      // 下一帧释放旧控制器，避免与当前 widget 树冲突
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
      });
    }
    _emit();
  }

  /// 月份变更：夹紧日期并重建日列表
  void _onMonthChanged(int index) {
    final int newMonth = (index % 12) + 1;
    final int oldMaxDay = _daysInSelectedMonth;
    setState(() {
      _month = newMonth;
      _rebuildDayList();
    });
    if (_daysInSelectedMonth != oldMaxDay) {
      final FixedExtentScrollController old = _dayController;
      _dayController = FixedExtentScrollController(initialItem: _day - 1);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
      });
    }
    _emit();
  }

  /// 日期变更：直接更新并发射
  void _onDayChanged(int index) {
    final int newDay = (index % _days.length) + 1;
    setState(() {
      _day = newDay;
    });
    _emit();
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    _yearController.dispose();
    _monthController.dispose();
    _dayController.dispose();
    super.dispose();
  }

  /// 获取月份中文显示
  static String _monthLabel(int month) {
    const List<String> months = <String>[
      '1月',
      '2月',
      '3月',
      '4月',
      '5月',
      '6月',
      '7月',
      '8月',
      '9月',
      '10月',
      '11月',
      '12月',
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      color:
          Theme.of(context).cardTheme.color ??
          Theme.of(context).colorScheme.surface,
      child: LayoutBuilder(
        builder: (BuildContext ctx, BoxConstraints constraints) {
          const double gap = 0.0;

          double yearWidth = kMinYearWidth;
          double monthWidth = kMinMonthWidth;
          double dayWidth = kMinDayWidth;
          final double totalMin = kMinYearWidth + kMinMonthWidth + kMinDayWidth;
          if (constraints.maxWidth < totalMin) {
            final double scale = constraints.maxWidth / totalMin;
            yearWidth = max(24.0, kMinYearWidth * scale);
            monthWidth = max(24.0, kMinMonthWidth * scale);
            dayWidth = max(24.0, kMinDayWidth * scale);
          }

          double leftPadding =
              (constraints.maxWidth / 2) - yearWidth - gap - (monthWidth / 2);
          if (leftPadding < 0) {
            leftPadding = 0;
          }

          final double innerGap = gap / 2;

          return Row(
            children: <Widget>[
              SizedBox(width: leftPadding),
              // 年份滚轮：looping 允许循环
              SizedBox(
                width: yearWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerGap),
                  child: CupertinoPicker(
                    selectionOverlay: Container(),
                    itemExtent: kPickerItemExtent,
                    looping: true,
                    scrollController: _yearController,
                    onSelectedItemChanged: _onYearChanged,
                    children: _years
                        .map(
                          (int y) => Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                '$y年',
                                style: const TextStyle(
                                  fontSize: kPickerFontSizeDefault,
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(width: gap),
              // 月份滚轮：looping 允许循环
              SizedBox(
                width: monthWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerGap),
                  child: CupertinoPicker(
                    selectionOverlay: Container(),
                    itemExtent: kPickerItemExtent,
                    looping: true,
                    scrollController: _monthController,
                    onSelectedItemChanged: _onMonthChanged,
                    children: _months
                        .map(
                          (int m) => SizedBox(
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  _BirthDateWheelPickerState._monthLabel(m),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: kPickerFontSizeDefault,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              SizedBox(width: gap),
              // 日期滚轮：使用 Key 强制在日列表变化时重建
              SizedBox(
                width: dayWidth,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: innerGap),
                  child: CupertinoPicker(
                    key: ValueKey<int>(_days.length),
                    selectionOverlay: Container(),
                    itemExtent: kPickerItemExtent,
                    looping: true,
                    scrollController: _dayController,
                    onSelectedItemChanged: _onDayChanged,
                    children: _days
                        .map(
                          (int d) => SizedBox(
                            width: double.infinity,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  '$d日',
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(
                                    fontSize: kPickerFontSizeDefault,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 文本编辑对话框：由内部状态管理控制器生命周期，避免释放过早导致异常。
class _ProfileTextEditorDialog extends StatefulWidget {
  const _ProfileTextEditorDialog({
    required this.title,
    required this.initialValue,
    required this.hintText,
    required this.maxLines,
    this.maxLengthUnits,
    this.helperText,
    this.duplicateValue,
    this.allowEmptySubmit = false,
    this.emptyValueOnSave,
    this.emptyErrorText,
    this.exceededErrorText,
  });

  final String title;
  final String initialValue;
  final String hintText;
  final int maxLines;
  final int? maxLengthUnits;
  final String? helperText;
  final String? duplicateValue;
  final bool allowEmptySubmit;
  final String? emptyValueOnSave;
  final String? emptyErrorText;
  final String? exceededErrorText;

  @override
  State<_ProfileTextEditorDialog> createState() =>
      _ProfileTextEditorDialogState();
}

class _ProfileTextEditorDialogState extends State<_ProfileTextEditorDialog>
    with TickerProviderStateMixin {
  late final TextEditingController _controller;
  late final AnimationController _errorShakeController;
  late final Animation<double> _errorShakeOffset;

  int _currentLengthUnits() {
    return TextLengthCounter.computeHalfWidthUnits(_controller.text);
  }

  bool _isLengthExceeded() {
    final int? maxLengthUnits = widget.maxLengthUnits;
    if (maxLengthUnits == null) {
      return false;
    }
    return _currentLengthUnits() > maxLengthUnits;
  }

  String? _errorText;

  String? _buildCounterText() {
    final int? maxLengthUnits = widget.maxLengthUnits;
    if (maxLengthUnits == null) {
      return null;
    }
    return '${_currentLengthUnits()}/$maxLengthUnits';
  }

  Widget? _buildCounter(BuildContext context) {
    final String? counterText = _buildCounterText();
    if (counterText == null) {
      return null;
    }
    final ThemeData theme = Theme.of(context);
    final bool isLengthExceeded = _isLengthExceeded();
    final Color counterColor = isLengthExceeded
        ? theme.colorScheme.error
        : theme.colorScheme.onSurfaceVariant;

    return Text(
      counterText,
      style: theme.textTheme.bodySmall?.copyWith(color: counterColor),
    );
  }

  Widget? _buildAnimatedErrorText(BuildContext context) {
    if (_errorText == null) {
      return null;
    }
    final Color errorColor = Theme.of(context).colorScheme.error;
    return AnimatedBuilder(
      animation: _errorShakeController,
      builder: (_, Widget? child) {
        return Transform.translate(
          offset: Offset(_errorShakeOffset.value, 0),
          child: child,
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          _errorText!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: errorColor),
        ),
      ),
    );
  }

  Future<void> _playValidationErrorFeedback() async {
    // 空值/重名校验失败时，仅抖动错误文字，不抖动右侧计数器。
    await HapticFeedback.mediumImpact();
    if (!mounted) {
      return;
    }
    _errorShakeController.forward(from: 0);
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _errorShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _errorShakeOffset =
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
          CurvedAnimation(parent: _errorShakeController, curve: Curves.easeOut),
        );
  }

  @override
  void dispose() {
    _errorShakeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int? maxLengthUnits = widget.maxLengthUnits;
    // 放宽输入框宽度，避免签名文本在弹窗内过早换行。
    final double dialogInputWidth = min(
      MediaQuery.sizeOf(context).width * 0.82,
      380,
    );
    final Widget? animatedErrorText = _buildAnimatedErrorText(context);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: dialogInputWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _controller,
              maxLines: widget.maxLines,
              minLines: widget.maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.done,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
              ],
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() {
                    _errorText = null;
                  });
                } else if (maxLengthUnits != null) {
                  setState(() {});
                }
              },
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintMaxLines: 1,
                // 昵称和签名弹窗的 hint 文案固定为灰色。
                hintStyle: const TextStyle(color: Color(0xFF8A8E99)),
                helperText: widget.helperText,
                helperMaxLines: 1,
                counterText: '',
                counter: _buildCounter(context),
              ),
            ),
            if (animatedErrorText != null) animatedErrorText,
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final String value = _controller.text.trim();
            if (value.isEmpty) {
              if (widget.allowEmptySubmit) {
                Navigator.of(
                  context,
                ).pop(widget.emptyValueOnSave ?? kDefaultSignatureText);
                return;
              }
              if (widget.emptyErrorText != null) {
                setState(() {
                  _errorText = widget.emptyErrorText;
                });
                _playValidationErrorFeedback();
              }
              return;
            }
            if (widget.duplicateValue != null &&
                value.toLowerCase() ==
                    widget.duplicateValue!.trim().toLowerCase()) {
              setState(() {
                _errorText = '与原昵称相同！';
              });
              _playValidationErrorFeedback();
              return;
            }
            if (_isLengthExceeded()) {
              setState(() {
                _errorText = widget.exceededErrorText ?? '输入内容超出字数限制！';
              });
              // 超限错误与重名错误一致：错误文案抖动 + 手机震动。
              _playValidationErrorFeedback();
              return;
            }
            Navigator.of(context).pop(value);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 二维码名片详情弹窗：点击“二维码名片”后以动画弹出。
class _NameCardDetailDialog extends StatelessWidget {
  const _NameCardDetailDialog({
    required this.profile,
    required this.nameCardPayload,
  });

  final PersonIdentityProfile profile;
  final String nameCardPayload;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;
    final bool isDarkMode = theme.brightness == Brightness.dark;
    final TextStyle baseNicknameTextStyle =
        theme.textTheme.titleMedium ?? const TextStyle(fontSize: 16);
    final double nicknameFontSize = (baseNicknameTextStyle.fontSize ?? 16) + 2;
    final TextStyle nicknameTextStyle = baseNicknameTextStyle.copyWith(
      fontSize: nicknameFontSize,
      fontWeight: FontWeight.w700,
      color: colorScheme.onSurface,
    );
    // 使用设置页“个性签名”同源字号基准：标题字号减 4。
    final double settingsLabelFontSizeReference =
        theme.textTheme.titleMedium?.fontSize ?? 16;
    final double settingsValueFontSizeReference =
        settingsLabelFontSizeReference > 2
        ? settingsLabelFontSizeReference - 2
        : settingsLabelFontSizeReference;
    final double settingsSignatureFontSizeReference =
        settingsValueFontSizeReference > 2
        ? settingsValueFontSizeReference - 2
        : settingsValueFontSizeReference;
    final Color mutedValueColor = isDarkMode
        ? const Color(0xFFB3BECE)
        : const Color(0xFF8A8E99);
    // 名片头像缩小 8px：直径 64 -> 56。
    const double avatarRadius = 28;
    const double avatarSize = avatarRadius * 2;
    final double signatureValueMaxWidth = min(
      220.0,
      max(150.0, MediaQuery.sizeOf(context).width * 0.52),
    );
    final (String signatureText, bool isSignatureTwoLines) =
        formatSignatureForAvatarInfo(profile.signature, maxCharsPerLine: 13);
    // 个性签名字号与设置页保持一致，双行时再缩小一号。
    final double preferredSignatureFontSize = isSignatureTwoLines
        ? settingsSignatureFontSizeReference - 1
        : settingsSignatureFontSizeReference;
    // 按设计值直接使用签名字号，不再应用保底上限规则。
    final double signatureFontSize = preferredSignatureFontSize;
    final TextStyle signatureValueTextStyle = nicknameTextStyle.copyWith(
      fontSize: signatureFontSize,
      color: mutedValueColor,
      fontWeight: FontWeight.w500,
      height: 1.1,
    );
    final double signatureTopGap = computeAvatarInfoSignatureTopGap(
      avatarSize: avatarSize,
      nicknameStyle: nicknameTextStyle,
      signatureStyle: signatureValueTextStyle,
      twoLines: isSignatureTwoLines,
    );
    final GlobalKey previewBoundaryKey = GlobalKey();

    // 捕获名片预览区域截图，导出/分享时优先使用预览图而非纯二维码。
    Future<Uint8List?> capturePreviewImageBytes() async {
      try {
        final RenderObject? renderObject = previewBoundaryKey.currentContext
            ?.findRenderObject();
        if (renderObject is! RenderRepaintBoundary) {
          return null;
        }

        // 为导出图补一圈外边距，和二维码导出图视觉留白保持一致。
        const double pixelRatio = 3.0;
        const double exportMarginDp = 12.0;
        final ui.Image image = await renderObject.toImage(
          pixelRatio: pixelRatio,
        );
        final int marginPx = (exportMarginDp * pixelRatio).round();
        final int outputWidth = image.width + marginPx * 2;
        final int outputHeight = image.height + marginPx * 2;

        final ui.PictureRecorder recorder = ui.PictureRecorder();
        final Canvas canvas = Canvas(recorder);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, outputWidth.toDouble(), outputHeight.toDouble()),
          Paint()..color = colorScheme.surface,
        );
        canvas.drawImage(
          image,
          Offset(marginPx.toDouble(), marginPx.toDouble()),
          Paint()..filterQuality = FilterQuality.medium,
        );

        final ui.Image paddedImage = await recorder.endRecording().toImage(
          outputWidth,
          outputHeight,
        );
        final ByteData? byteData = await paddedImage.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      } catch (_) {
        return null;
      }
    }

    // 导出文件名和分享文案基于当前用户信息动态生成。
    final String fileNamePrefix =
        'name_card_${profile.uid}_${profile.displayName}';
    final String shareText = '${profile.displayName} 的 DormDevise 二维码名片';

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Material(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    RepaintBoundary(
                      key: previewBoundaryKey,
                      child: ColoredBox(
                        color: colorScheme.surface,
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                const Icon(Icons.badge_outlined),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '二维码名片',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _ProfileAvatarPreview(
                                  path: profile.avatarPath,
                                  radius: avatarRadius,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Padding(
                                    // 昵称起始位置与头像顶部对齐，并在下方展示签名。
                                    padding: const EdgeInsets.only(top: 0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text(
                                          profile.displayName,
                                          style: nicknameTextStyle,
                                        ),
                                        SizedBox(height: signatureTopGap),
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxWidth: signatureValueMaxWidth,
                                          ),
                                          child: Text(
                                            signatureText,
                                            maxLines: 2,
                                            softWrap: true,
                                            overflow: TextOverflow.ellipsis,
                                            style: signatureValueTextStyle,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: avatarSize,
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      'UID: ${profile.uid}',
                                      style: TextStyle(
                                        color: mutedValueColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerHigh,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Container(
                                width: 240,
                                height: 240,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: QrImageView(
                                  data: nameCardPayload,
                                  size: 224,
                                  padding: EdgeInsets.zero,
                                  version: QrVersions.auto,
                                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                                  eyeStyle: const QrEyeStyle(
                                    eyeShape: QrEyeShape.square,
                                    color: Color(0xFF000000),
                                  ),
                                  dataModuleStyle: const QrDataModuleStyle(
                                    dataModuleShape: QrDataModuleShape.square,
                                    color: Color(0xFF000000),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        _NameCardExportActionButton(
                          icon: Icons.download_rounded,
                          iconBackground: const Color(0xFF5F72FF),
                          label: '保存至本地',
                          onTap: () async {
                            final Uint8List? previewBytes =
                                await capturePreviewImageBytes();
                            if (!context.mounted) {
                              return;
                            }
                            await QrImageExportService.saveQrImage(
                              context: context,
                              qrData: nameCardPayload,
                              fileNamePrefix: fileNamePrefix,
                              imageBytes: previewBytes,
                            );
                          },
                        ),
                        _NameCardExportActionButton(
                          icon: FontAwesomeIcons.weixin,
                          iconBackground: const Color(0xFF29C046),
                          label: '微信',
                          onTap: () async {
                            final Uint8List? previewBytes =
                                await capturePreviewImageBytes();
                            if (!context.mounted) {
                              return;
                            }
                            await QrImageExportService.shareQrImageToWechat(
                              context: context,
                              qrData: nameCardPayload,
                              fileNamePrefix: fileNamePrefix,
                              shareText: shareText,
                              imageBytes: previewBytes,
                            );
                          },
                        ),
                        _NameCardExportActionButton(
                          icon: FontAwesomeIcons.qq,
                          iconBackground: const Color(0xFF2FA8FF),
                          label: 'QQ',
                          onTap: () async {
                            final Uint8List? previewBytes =
                                await capturePreviewImageBytes();
                            if (!context.mounted) {
                              return;
                            }
                            await QrImageExportService.shareQrImageToQQ(
                              context: context,
                              qrData: nameCardPayload,
                              fileNamePrefix: fileNamePrefix,
                              shareText: shareText,
                              imageBytes: previewBytes,
                            );
                          },
                        ),
                        _NameCardExportActionButton(
                          icon: Icons.share_rounded,
                          iconBackground: const Color(0xFFFFC429),
                          label: '其他',
                          onTap: () async {
                            final Uint8List? previewBytes =
                                await capturePreviewImageBytes();
                            if (!context.mounted) {
                              return;
                            }
                            await QrImageExportService.shareQrImage(
                              context: context,
                              qrData: nameCardPayload,
                              fileNamePrefix: fileNamePrefix,
                              shareText: shareText,
                              imageBytes: previewBytes,
                            );
                          },
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
}

/// 名片弹窗底部导出动作按钮。
class _NameCardExportActionButton extends StatelessWidget {
  const _NameCardExportActionButton({
    required this.icon,
    required this.iconBackground,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color iconBackground;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircleAvatar(
                radius: 20,
                backgroundColor: iconBackground,
                foregroundColor: Colors.white,
                child: Icon(icon, size: 18),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 头像预览：优先本地文件，其次回退资源图。
class _ProfileAvatarPreview extends StatelessWidget {
  const _ProfileAvatarPreview({required this.path, this.radius = 18});

  final String path;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final String normalized = path.trim();

    Widget avatarImage;
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(normalized)) {
      avatarImage = Image.file(
        File(normalized),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Image.asset(kPersonAvatarAsset, fit: BoxFit.cover),
      );
    } else {
      avatarImage = Image.asset(
        normalized.isEmpty ? kPersonAvatarAsset : normalized,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Image.asset(kPersonAvatarAsset, fit: BoxFit.cover),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: avatarImage,
      ),
    );
  }
}

/// 头像选择动作。
enum _AvatarEditAction { pickAlbum, inputUrl, takePhoto, random }
