import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../services/web_login/fit/fit_china_ocr_service.dart';
import '../../../services/web_login/fit/fit_login_web_automation.dart';
import '../../../utils/app_toast.dart';

/// 网页自动登录页面。
///
/// 页面会在加载完成后尝试自动执行：
/// 1. 填入账号密码；
/// 2. 读取验证码图片并 OCR 识别；
/// 3. 自动填入验证码并提交登录。
class WebImportAutoLoginWebViewPage extends StatefulWidget {
  final String schoolName;
  final String loginUrl;
  final String username;
  final String password;

  const WebImportAutoLoginWebViewPage({
    super.key,
    required this.schoolName,
    required this.loginUrl,
    required this.username,
    required this.password,
  });

  @override
  State<WebImportAutoLoginWebViewPage> createState() =>
      _WebImportAutoLoginWebViewPageState();
}

class _WebImportAutoLoginWebViewPageState
    extends State<WebImportAutoLoginWebViewPage> {
  static const String _fitSchoolName = '福州理工学院';

  final FitChinaOcrService _fitChinaOcrService = FitChinaOcrService();

  InAppWebViewController? _webViewController;
  String _statusText = '正在加载登录页面...';
  bool _isLoading = true;
  bool _isAutoLoginRunning = false;

  /// 记录上一次尝试自动登录的 URL，避免同一页面重复执行，
  /// 但允许在重定向到新 URL 后重新触发。
  String? _lastAttemptedUrl;

  bool get _isFitSchool => widget.schoolName.trim() == _fitSchoolName;

  /// 统一更新状态文案，避免重复判空与 mounted 判断。
  void _updateStatus(String statusText) {
    if (!mounted) return;
    setState(() {
      _statusText = statusText;
    });
  }

  /// 页面加载完成后触发自动登录流程。
  ///
  /// 仅在检测到当前 URL 为登录页（含 `login_slogin`）时执行，
  /// 避免在非登录页面（如课表页重定向前）误触发。
  Future<void> _tryAutoLogin() async {
    if (_isAutoLoginRunning) return;

    final InAppWebViewController? controller = _webViewController;
    if (controller == null) return;

    // 获取当前实际 URL（可能经过了重定向）
    final WebUri? currentUrl = await controller.getUrl();
    final String urlString = currentUrl?.toString() ?? '';
    debugPrint('[自动登录] onLoadStop 当前 URL: $urlString');

    if (!_isFitSchool) {
      _updateStatus('当前学校暂无定制自动登录模板，请手动登录');
      return;
    }

    // 仅在登录页面执行（避免在课表页等非登录页触发）
    final bool isLoginPage = urlString.contains('login_slogin');
    if (!isLoginPage) {
      debugPrint('[自动登录] 非登录页面，跳过自动登录');
      return;
    }

    // 同一 URL 只尝试一次，重定向到新页面后可重新触发
    if (_lastAttemptedUrl == urlString) {
      debugPrint('[自动登录] 已在该 URL 尝试过，跳过');
      return;
    }

    _isAutoLoginRunning = true;
    _lastAttemptedUrl = urlString;

    try {
      // 等待页面 DOM 完全渲染（避免 onLoadStop 时元素还未就绪）
      debugPrint('[自动登录] 等待 1.5 秒确保 DOM 就绪...');
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      _updateStatus('正在自动填充账号与密码...');
      final Map<String, dynamic> fillResult =
          await FitLoginWebAutomation.fillCredentials(
            controller: controller,
            username: widget.username,
            password: widget.password,
          );

      final bool credentialsFilled =
          fillResult['yhmFilled'] == true && fillResult['mmFilled'] == true;
      if (!credentialsFilled) {
        debugPrint('[自动登录] 账号密码填充失败: $fillResult');
        _updateStatus('账号密码填充失败，请手动登录');
        return;
      }

      _updateStatus('正在读取验证码图片...');
      final String? captchaDataUrl =
          await FitLoginWebAutomation.extractCaptchaDataUrl(controller);
      if (captchaDataUrl == null || captchaDataUrl.isEmpty) {
        _updateStatus('未读取到验证码图片，账号密码已填好，请手动输入验证码后登录');
        return;
      }

      _updateStatus('正在识别验证码...');
      final String? captchaCode = await _fitChinaOcrService
          .recognizeCaptchaFromDataUrl(captchaDataUrl);
      if (captchaCode == null || captchaCode.isEmpty) {
        _updateStatus('验证码识别失败，账号密码已填好，请手动输入验证码后登录');
        return;
      }

      _updateStatus('正在填入验证码并提交...');
      final bool submitted = await FitLoginWebAutomation.fillCaptchaAndSubmit(
        controller: controller,
        captchaCode: captchaCode,
      );

      if (submitted) {
        _updateStatus('已自动提交登录请求，请稍候...');
      } else {
        _updateStatus('已填入验证码（$captchaCode），但未找到登录按钮，请手动点击登录');
      }
    } catch (error) {
      debugPrint('[自动登录] 异常: $error');
      _updateStatus('自动登录失败，请手动登录');
      if (mounted) {
        AppToast.show(
          context,
          '自动登录失败：$error',
          variant: AppToastVariant.warning,
        );
      }
    } finally {
      _isAutoLoginRunning = false;
    }
  }

  /// 手动重试自动登录（重置尝试记录，允许再次执行）。
  Future<void> _retryAutoLogin() async {
    _lastAttemptedUrl = null;
    await _tryAutoLogin();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          '${widget.schoolName} 登录',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: <Widget>[
          IconButton(
            onPressed: _isAutoLoginRunning ? null : _retryAutoLogin,
            tooltip: '重试自动登录',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Material(
            color: colorScheme.surfaceContainerHighest.withAlpha(110),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: _isAutoLoginRunning || _isLoading
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _statusText,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 12,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(url: WebUri(widget.loginUrl)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                safeBrowsingEnabled: false,
              ),
              onWebViewCreated: (InAppWebViewController controller) {
                _webViewController = controller;
              },
              onLoadStart: (_, __) {
                if (!mounted) return;
                setState(() {
                  _isLoading = true;
                });
              },
              onLoadStop: (_, url) async {
                debugPrint('[自动登录] onLoadStop 触发, url=$url');
                if (!mounted) return;
                setState(() {
                  _isLoading = false;
                });
                await _tryAutoLogin();
              },
              shouldOverrideUrlLoading: (_, navigationAction) async {
                final WebUri? requestUrl = navigationAction.request.url;
                if (requestUrl == null) {
                  return NavigationActionPolicy.ALLOW;
                }
                final String scheme = requestUrl.scheme.toLowerCase();
                if (scheme == 'http' || scheme == 'https') {
                  return NavigationActionPolicy.ALLOW;
                }
                return NavigationActionPolicy.CANCEL;
              },
              onReceivedServerTrustAuthRequest: (_, __) async {
                return ServerTrustAuthResponse(
                  action: ServerTrustAuthResponseAction.PROCEED,
                );
              },
              onReceivedError: (_, request, error) {
                if (!mounted) return;
                if (request.isForMainFrame == true) {
                  _updateStatus('页面加载失败：${error.description}');
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
