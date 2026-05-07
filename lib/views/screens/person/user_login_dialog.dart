import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/utils/person_identity.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 本地模拟登录弹窗：仅做本地状态保存，不请求远端服务。
class UserLoginDialog extends StatefulWidget {
  const UserLoginDialog({super.key});

  /// 显示登录弹窗，返回是否登录成功。
  static Future<bool> show(BuildContext context) async {
    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const UserLoginDialog(),
    );
    return result ?? false;
  }

  @override
  State<UserLoginDialog> createState() => _UserLoginDialogState();
}

class _UserLoginDialogState extends State<UserLoginDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _credentialErrorText;
  bool _showAccountError = false;
  bool _showPasswordError = false;
  late final AnimationController _errorShakeController;
  late final Animation<double> _errorShakeOffset;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
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
    _accountController.dispose();
    _passwordController.dispose();
    _errorShakeController.dispose();
    super.dispose();
  }

  void _clearCredentialValidation() {
    if (_credentialErrorText == null &&
        !_showAccountError &&
        !_showPasswordError) {
      return;
    }
    setState(() {
      _credentialErrorText = null;
      _showAccountError = false;
      _showPasswordError = false;
    });
  }

  Future<void> _playCredentialErrorFeedback() async {
    await HapticFeedback.mediumImpact();
    if (!mounted) {
      return;
    }
    _errorShakeController.forward(from: 0);
  }

  Widget? _buildAnimatedCredentialError(BuildContext context) {
    final String? errorText = _credentialErrorText;
    if (errorText == null) {
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
          errorText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: errorColor),
        ),
      ),
    );
  }

  /// 提交登录：校验输入并写入本地登录态。
  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final String account = _accountController.text.trim();
    final String password = _passwordController.text.trim();
    final bool isAccountEmpty = account.isEmpty;
    final bool isPasswordEmpty = password.isEmpty;

    if (isAccountEmpty || isPasswordEmpty) {
      // 账号/密码校验统一在密码输入框下方展示，并触发震动反馈。
      String errorText;
      if (isAccountEmpty && isPasswordEmpty) {
        errorText = '请输入账号和密码';
      } else if (isAccountEmpty) {
        errorText = '请输入账号';
      } else {
        errorText = '请输入密码';
      }
      setState(() {
        _credentialErrorText = errorText;
        // 账号/密码分别按空值单独高亮，避免账号错误时误高亮密码。
        _showAccountError = isAccountEmpty;
        _showPasswordError = isPasswordEmpty;
      });
      await _playCredentialErrorFeedback();
      return;
    }

    _clearCredentialValidation();

    setState(() => _submitting = true);
    try {
      await PersonIdentityService.instance.login(
        account: account,
        password: password,
      );
      if (!mounted) {
        return;
      }
      AppToast.show(context, '登录成功', variant: AppToastVariant.success);
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      AppToast.show(context, '登录失败：$error', variant: AppToastVariant.error);
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget? animatedCredentialError = _buildAnimatedCredentialError(
      context,
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Form(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '登录',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '当前为离线模式，账号信息仅保存在本地设备。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _accountController,
                textInputAction: TextInputAction.next,
                onChanged: (_) {
                  _clearCredentialValidation();
                },
                decoration: InputDecoration(
                  labelText: '账号',
                  hintText: '请输入账号',
                  errorText: _showAccountError ? '' : null,
                  errorStyle: const TextStyle(fontSize: 0, height: 0),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                onChanged: (_) {
                  _clearCredentialValidation();
                },
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '密码',
                  hintText: '请输入密码',
                  errorText: _showPasswordError ? '' : null,
                  errorStyle: const TextStyle(fontSize: 0, height: 0),
                ),
              ),
              if (animatedCredentialError != null) animatedCredentialError,
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('登录'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
