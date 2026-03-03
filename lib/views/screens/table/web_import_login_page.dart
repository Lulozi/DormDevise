import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../models/web_school.dart';
import '../../../services/web_school_service.dart';
import '../../../utils/app_toast.dart';
import 'web_import_auto_login_webview_page.dart';

/// 网页导入课表的账号密码登录页面。
///
/// 输入教务系统账号密码后加密保存到本地，
/// 后续用于自动登录教务系统抓取课表数据。
class WebImportLoginPage extends StatefulWidget {
  /// 目标学校信息（名称与教务系统地址）。
  final WebSchool school;

  const WebImportLoginPage({super.key, required this.school});

  @override
  State<WebImportLoginPage> createState() => _WebImportLoginPageState();
}

class _WebImportLoginPageState extends State<WebImportLoginPage> {
  static const String _fitBadgeAsset = 'assets/images/schoolBadge/FIT.jpg';

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final FocusNode _usernameFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();
  final FocusNode _idleFocusNode = FocusNode(skipTraversal: true);
  bool _obscurePassword = true;
  bool _isSaving = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _idleFocusNode.dispose();
    super.dispose();
  }

  /// 将账号/密码输入框重置到未选中状态，避免页面返回后输入法意外弹出。
  void _resetInputFocusState() {
    if (!mounted) return;
    FocusScope.of(context).requestFocus(_idleFocusNode);
    FocusManager.instance.primaryFocus?.unfocus();
    _usernameController.selection = TextSelection.collapsed(
      offset: _usernameController.text.length,
    );
    _passwordController.selection = TextSelection.collapsed(
      offset: _passwordController.text.length,
    );
  }

  /// 加载已保存的凭据（如果有）。
  Future<void> _loadSavedCredentials() async {
    final credentials = await WebSchoolService.instance.loadCredentials(
      widget.school.name,
    );
    if (mounted) {
      if (credentials != null) {
        _usernameController.text = credentials.username;
        _passwordController.text = credentials.password;
      }
      setState(() => _isLoading = false);
    }
  }

  /// 保存凭据并提示用户。
  Future<void> _saveCredentialsAndOpenWebLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final loginUrl = widget.school.url.trim();

    if (username.isEmpty) {
      AppToast.show(context, '请输入账号', variant: AppToastVariant.warning);
      return;
    }
    if (password.isEmpty) {
      AppToast.show(context, '请输入密码', variant: AppToastVariant.warning);
      return;
    }
    if (loginUrl.isEmpty) {
      AppToast.show(
        context,
        '请先在学校卡片中完善教务系统网址',
        variant: AppToastVariant.warning,
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      await WebSchoolService.instance.saveCredentials(
        schoolName: widget.school.name,
        username: username,
        password: password,
      );
      if (mounted) {
        AppToast.show(
          context,
          '账号密码已加密保存，正在打开登录页',
          variant: AppToastVariant.success,
        );
        final bool? result = await Navigator.of(context).push<bool>(
          MaterialPageRoute<bool>(
            builder: (context) => WebImportAutoLoginWebViewPage(
              schoolName: widget.school.name,
              loginUrl: loginUrl,
              username: username,
              password: password,
            ),
          ),
        );

        // 返回登录页后重置焦点，防止输入法误弹。
        _resetInputFocusState();

        // 课表创建成功后一路回退到课表主页
        if (result == true && mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, '保存失败: $e', variant: AppToastVariant.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// 构建学校校徽，优先使用导入校徽，其次使用预设 FIT 校徽，最后降级为图标。
  Widget _buildSchoolBadge() {
    final Uint8List? badgeBytes = _decodeBadgeBytes(widget.school.badgeBase64);
    if (badgeBytes != null) {
      return ClipOval(
        child: Image.memory(
          badgeBytes,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    if (widget.school.name == '福州理工学院') {
      return ClipOval(
        child: Image.asset(
          _fitBadgeAsset,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
        ),
      );
    }

    return Icon(
      Icons.school_rounded,
      size: 72,
      color: Theme.of(context).colorScheme.primary,
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

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
          widget.school.name,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 学校图标与提示
                  Center(
                    child: SizedBox(
                      width: 76,
                      height: 76,
                      child: _buildSchoolBadge(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '登录教务系统',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 表单卡片
                  Container(
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).cardTheme.color ??
                          colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 账号输入
                        Text(
                          '账号',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _usernameController,
                          focusNode: _usernameFocusNode,
                          style: TextStyle(
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: '请输入学号或用户名',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurface.withAlpha(102),
                              fontSize: 15,
                            ),
                            prefixIcon: Icon(
                              Icons.person_outline,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withAlpha(128),
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
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 20),

                        // 密码输入
                        Text(
                          '密码',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: _obscurePassword,
                          style: TextStyle(
                            fontSize: 15,
                            color: colorScheme.onSurface,
                          ),
                          decoration: InputDecoration(
                            hintText: '请输入密码',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurface.withAlpha(102),
                              fontSize: 15,
                            ),
                            prefixIcon: Icon(
                              Icons.lock_outline,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                            suffixIcon: IconButton(
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                color: colorScheme.onSurface.withAlpha(128),
                                size: 22,
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            filled: true,
                            fillColor: colorScheme.surfaceContainerHighest
                                .withAlpha(128),
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
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveCredentialsAndOpenWebLogin(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 安全提示
                  Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 14,
                        color: colorScheme.onSurface.withAlpha(102),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '您的账号密码经过加密后仅存储在本设备，不会上传至任何服务器',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurface.withAlpha(102),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // 保存按钮
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving
                          ? null
                          : _saveCredentialsAndOpenWebLogin,
                      child: _isSaving
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.onPrimary,
                              ),
                            )
                          : const Text(
                              '登录',
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
