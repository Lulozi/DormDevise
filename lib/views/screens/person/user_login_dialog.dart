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

  /// 统一展示“业务校验类”错误（如账号不存在、账号密码错误），
  /// 并复用震动+抖动反馈，保持与空值校验体验一致。
  Future<void> _showCredentialBusinessError(
    String message, {
    bool highlightAccount = false,
    bool highlightPassword = true,
  }) async {
    setState(() {
      _credentialErrorText = message;
      _showAccountError = highlightAccount;
      _showPasswordError = highlightPassword;
    });
    await _playCredentialErrorFeedback();
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
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      final String message = error.message.trim().isEmpty
          ? '登录失败，请稍后重试'
          : error.message.trim();
      // “账号不存在”更贴近账号输入错误，其它错误默认高亮密码输入框。
      final bool highlightAccount = message.contains('账号不存在');
      await _showCredentialBusinessError(
        message,
        highlightAccount: highlightAccount,
        highlightPassword: !highlightAccount,
      );
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

  /// 打开注册弹窗。
  ///
  /// 注册成功后会自动回填账号/密码到登录表单，降低二次输入成本。
  Future<void> _openRegisterDialog() async {
    if (_submitting) {
      return;
    }
    final _RegisterCredentialResult? result = await _UserRegisterDialog.show(
      context,
    );
    if (!mounted || result == null) {
      return;
    }

    _accountController.text = result.account;
    _accountController.selection = TextSelection.collapsed(
      offset: result.account.length,
    );
    _passwordController.text = result.password;
    _passwordController.selection = TextSelection.collapsed(
      offset: result.password.length,
    );
    _clearCredentialValidation();
    AppToast.show(context, '注册成功，请点击登录', variant: AppToastVariant.success);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final Widget? animatedCredentialError = _buildAnimatedCredentialError(
      context,
    );
    // 获取当前可视区域高度：Android adjustResize 模式下键盘弹出时自动缩减，
    // 无需再手动添加 keyboardInset 抬升，避免双重压缩导致弹窗仅剩输入框。
    final double availableHeight = MediaQuery.sizeOf(context).height;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        // 限制弹窗最大高度为可视区域的 85%，超出时通过 SingleChildScrollView 滚动。
        constraints: BoxConstraints(maxHeight: availableHeight * 0.85),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Form(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '登录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                    children: <Widget>[
                      TextButton(
                        onPressed: _submitting ? null : _openRegisterDialog,
                        style: ButtonStyle(
                          // 固定蓝色，不跟随主题变化
                          foregroundColor: WidgetStateProperty.all(Colors.blue),
                        ),
                        child: const Text('立即注册'),
                      ),
                      const Spacer(),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('登录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 注册成功后返回给登录弹窗的账号信息，用于自动回填输入框。
class _RegisterCredentialResult {
  const _RegisterCredentialResult({
    required this.account,
    required this.password,
  });

  final String account;
  final String password;
}

/// 注册弹窗：当前采用本地注册，并与登录弹窗保持一致的视觉与输入体验。
class _UserRegisterDialog extends StatefulWidget {
  const _UserRegisterDialog();

  static Future<_RegisterCredentialResult?> show(BuildContext context) async {
    return showDialog<_RegisterCredentialResult>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _UserRegisterDialog(),
    );
  }

  @override
  State<_UserRegisterDialog> createState() => _UserRegisterDialogState();
}

class _UserRegisterDialogState extends State<_UserRegisterDialog> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmController = TextEditingController();
  String? _errorText;
  bool _submitting = false;

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final String account = _accountController.text.trim();
    final String password = _passwordController.text.trim();
    final String confirmPassword = _confirmController.text.trim();
    if (account.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      setState(() {
        _errorText = '请完整填写账号与密码';
      });
      return;
    }
    if (password != confirmPassword) {
      setState(() {
        _errorText = '两次输入的密码不一致';
      });
      return;
    }

    setState(() {
      _errorText = null;
      _submitting = true;
    });
    try {
      await PersonIdentityService.instance.register(
        account: account,
        password: password,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(
        context,
      ).pop(_RegisterCredentialResult(account: account, password: password));
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = error.message.trim().isEmpty
            ? '注册失败，请稍后重试'
            : error.message.trim();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '注册失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    // 获取当前可视区域高度：Android adjustResize 模式下键盘弹出时自动缩减，
    // 无需再手动添加 keyboardInset 抬升，避免双重压缩。
    final double availableHeight = MediaQuery.sizeOf(context).height;
    final TextStyle? errorStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.error);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        // 限制弹窗最大高度为可视区域的 85%，超出时通过 SingleChildScrollView 滚动。
        constraints: BoxConstraints(maxHeight: availableHeight * 0.85),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '立即注册',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前为离线模式，注册信息仅保存在本地设备。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _accountController,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: '账号',
                    hintText: '请输入账号',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: '密码',
                    hintText: '请输入密码',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmController,
                  obscureText: true,
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(
                    labelText: '确认密码',
                    hintText: '请再次输入密码',
                  ),
                ),
                if (_errorText != null) ...<Widget>[
                  const SizedBox(height: 8),
                  Text(_errorText!, style: errorStyle),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => Navigator.of(context).pop(),
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
                          : const Text('注册'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
