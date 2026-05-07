import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../models/course.dart';
import '../../../models/course_schedule_config.dart';
import '../../../services/web_login/fit/fit_china_ocr_service.dart';
import '../../../services/web_login/fit/fit_login_web_automation.dart';
import '../../../services/web_login/fit/fit_schedule_scraper.dart';
import '../../../services/web_school_service.dart';
import '../../../utils/android_soft_input_mode.dart';
import '../../../utils/app_toast.dart';
import '../../../utils/course_utils.dart';
import 'create_schedule_settings_page.dart';

/// 网页自动登录 + 课表爬取页面。
///
/// 页面会在加载完成后尝试自动执行：
/// 1. 填入账号密码；
/// 2. 读取验证码图片并 OCR 识别；
/// 3. 自动填入验证码并提交登录。
///
/// 登录成功后，用户在课表页面点击「确认」按钮即可触发爬取，
/// 爬取到的课程数据将自动带入新建课程表页面。
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
    extends State<WebImportAutoLoginWebViewPage>
    with WidgetsBindingObserver {
  static const String _fitSchoolName = '福州理工学院';

  final FitChinaOcrService _fitChinaOcrService = FitChinaOcrService();

  InAppWebViewController? _webViewController;
  String _statusText = '正在加载页面...';
  bool _isLoading = true;
  bool _isPreparingWebView = true;
  bool _isAutoLoginRunning = false;
  bool _isScraping = false;
  bool _didRestoreAccountWebData = false;

  /// 记录上一次尝试自动登录的 URL，避免同一页面重复执行，
  /// 但允许在重定向到新 URL 后重新触发。
  String? _lastAttemptedUrl;

  bool get _isFitSchool => widget.schoolName.trim() == _fitSchoolName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AndroidSoftInputModeController.setModeSilently(
      AndroidSoftInputMode.adjustPan,
    );
    _prepareWebLoginEnvironment();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AndroidSoftInputModeController.setModeSilently(
      AndroidSoftInputMode.adjustResize,
    );
    unawaited(_persistAccountWebData());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AndroidSoftInputModeController.setModeSilently(
        AndroidSoftInputMode.adjustPan,
      );
    }
  }

  /// 进入登录页前准备账号级网页数据：
  /// 1. 清理当前 Cookie；
  /// 2. 按学校+账号恢复此前保存的 Cookie。
  Future<void> _prepareWebLoginEnvironment() async {
    try {
      _updateStatus('正在准备账号登录数据...');
      _didRestoreAccountWebData = await WebSchoolService.instance
          .restoreAccountWebData(
            schoolName: widget.schoolName,
            username: widget.username,
            loginUrl: widget.loginUrl,
          );
    } catch (error) {
      debugPrint('[自动登录] 准备账号数据失败: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingWebView = false;
          _isLoading = true;
          _statusText = _didRestoreAccountWebData
              ? '已恢复该账号登录状态，正在加载页面...'
              : '正在加载页面...';
        });
      }
    }
  }

  Future<void> _persistAccountWebData({WebUri? currentUrl}) async {
    final InAppWebViewController? controller = _webViewController;
    if (controller == null) {
      return;
    }

    final Set<String> candidateUrls = <String>{widget.loginUrl};
    final String? currentUrlString =
        currentUrl?.toString() ?? (await controller.getUrl())?.toString();
    if (currentUrlString != null && currentUrlString.trim().isNotEmpty) {
      candidateUrls.add(currentUrlString.trim());
    }

    final CookieManager cookieManager = CookieManager.instance();
    final List<Cookie> mergedCookies = <Cookie>[];
    final Set<String> cookieKeys = <String>{};

    for (final String url in candidateUrls) {
      final Uri? parsed = Uri.tryParse(url);
      if (parsed == null ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        continue;
      }

      try {
        final List<Cookie> cookies = await cookieManager.getCookies(
          url: WebUri(url),
        );
        for (final Cookie cookie in cookies) {
          final String key =
              '${cookie.name}|${cookie.domain ?? ''}|${cookie.path ?? '/'}';
          if (cookieKeys.add(key)) {
            mergedCookies.add(cookie);
          }
        }
      } catch (error) {
        debugPrint('[自动登录] 读取 Cookie 失败: $error');
      }
    }

    if (mergedCookies.isEmpty) {
      return;
    }

    await WebSchoolService.instance.saveAccountWebData(
      schoolName: widget.schoolName,
      username: widget.username,
      loginUrl: widget.loginUrl,
      cookies: mergedCookies,
    );
  }

  PageRouteBuilder<T> _buildNoAnimationRoute<T>({
    required WidgetBuilder builder,
  }) {
    return PageRouteBuilder<T>(
      pageBuilder:
          (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) {
            return builder(context);
          },
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  // ---------------------------------------------------------------------------
  // 状态辅助
  // ---------------------------------------------------------------------------

  void _updateStatus(String statusText) {
    if (!mounted) return;
    setState(() {
      _statusText = statusText;
    });
  }

  // ---------------------------------------------------------------------------
  // 自动登录
  // ---------------------------------------------------------------------------

  Future<void> _tryAutoLogin() async {
    if (_isAutoLoginRunning) return;

    final InAppWebViewController? controller = _webViewController;
    if (controller == null) return;

    final WebUri? currentUrl = await controller.getUrl();
    final String urlString = currentUrl?.toString() ?? '';
    debugPrint('[自动登录] onLoadStop 当前 URL: $urlString');

    if (!_isFitSchool) {
      _updateStatus('当前学校暂无定制自动登录模板，请手动登录');
      return;
    }

    // 仅在登录页面执行
    final bool isLoginPage = urlString.contains('login_slogin');
    if (!isLoginPage) {
      debugPrint('[自动登录] 非登录页面，跳过自动登录');
      _updateStatus('加载完成！浏览到课表页面后__CONFIRM_HINT__');
      return;
    }

    // 每次停留在登录页时，先检测页面内是否已显示账号/密码错误提示。
    final bool hasCredentialError = await _checkPageForCredentialError(
      controller,
    );
    if (hasCredentialError) {
      return;
    }

    if (_lastAttemptedUrl == urlString) {
      debugPrint('[自动登录] 已在该 URL 尝试过，跳过重复提交');
      return;
    }

    _isAutoLoginRunning = true;
    _lastAttemptedUrl = urlString;

    try {
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

  /// 手动重试自动登录。
  Future<void> _retryAutoLogin() async {
    _lastAttemptedUrl = null;
    await _tryAutoLogin();
  }

  /// 检测页面中是否包含密码错误提示，若检测到则返回登录页并提示。
  /// 返回 true 表示已处理（已提示并返回），调用方应终止后续自动登录。
  Future<bool> _checkPageForCredentialError(
    InAppWebViewController controller,
  ) async {
    try {
      final Object? bodyText = await controller.evaluateJavascript(
        source:
            '(function(){ return document.body ? document.body.innerText : ""; })()',
      );
      final String text = bodyText?.toString() ?? '';
      if (text.contains('用户名或密码不正确') ||
          text.contains('用户名或密码不正确，请重新输入') ||
          text.contains('密码不正确') ||
          text.contains('用户名或密码')) {
        _updateStatus('账号或密码错误');
        if (mounted) {
          AppToast.show(
            context,
            '账号或密码错误，请检查后重新输入',
            variant: AppToastVariant.error,
          );
          Navigator.of(context).pop();
        }
        return true;
      }
    } catch (e) {
      debugPrint('[自动登录] 检测页面错误信息异常: $e');
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // 课表爬取 + 跳转
  // ---------------------------------------------------------------------------

  /// 点击「确认」按钮后触发：爬取当前页面课表并跳转到新建课程表页面。
  Future<void> _onConfirmScrape() async {
    if (_isScraping) return;

    final InAppWebViewController? controller = _webViewController;
    if (controller == null) {
      AppToast.show(context, '页面未就绪', variant: AppToastVariant.warning);
      return;
    }
    final NavigatorState navigator = Navigator.of(context);

    setState(() {
      _isScraping = true;
    });
    _updateStatus('正在爬取课表数据...');

    try {
      // 1. 爬取原始数据（含学年学期信息）
      final FitScrapeResult scrapeResult =
          await FitScheduleScraper.scrapeScheduleRaw(controller);

      if (scrapeResult.isEmpty) {
        _updateStatus('未在当前页面找到课表数据，请先导航到课表页面');
        if (mounted) {
          AppToast.show(
            context,
            '未找到课表数据，请确认当前页面是否显示课程表',
            variant: AppToastVariant.warning,
          );
        }
        return;
      }

      // 2. 解析为 Course 列表
      final List<Course> rawCourses = FitScheduleScraper.parseRawToCourses(
        scrapeResult.rawItems,
      );

      if (rawCourses.isEmpty) {
        _updateStatus('课表数据解析为空，请检查页面内容');
        if (mounted) {
          AppToast.show(
            context,
            '课表解析失败，请确认页面是否正确显示课表',
            variant: AppToastVariant.warning,
          );
        }
        return;
      }

      // 3. 按教学时段拆分跨时段课程（如 1-8 节 -> 上午 1-4 + 下午 5-8）
      final CourseScheduleConfig fitConfig = CourseScheduleConfig.fitDefaults();
      final List<Course> courses = splitCrossSegmentSessions(
        rawCourses,
        fitConfig,
      );
      final int maxWeek = _computeImportedMaxWeek(courses);

      _updateStatus('成功爬取 ${courses.length} 门课程，正在跳转...');
      debugPrint('[FIT 爬取] 准备跳转，共 ${courses.length} 门课程');

      if (!mounted) return;

      await _persistAccountWebData();

      // 4. 跳转到基本信息页面（预填 FIT 默认配置 + 课程数据）
      //    用户可在该页面修改配置后，再进入课程表页面。
      final String scheduleName = '${widget.schoolName}课表';

      final bool? result = await navigator.push<bool>(
        _buildNoAnimationRoute<bool>(
          builder: (BuildContext context) => CreateScheduleSettingsPage(
            initialScheduleName: scheduleName,
            initialConfig: fitConfig,
            initialSemesterStart: _guessSemesterStart(),
            initialMaxWeek: maxWeek,
            initialShowWeekend: _hasWeekendCourses(courses),
            initialShowNonCurrentWeek: true,
            initialLockSchedule: true,
            initialCourses: courses,
          ),
        ),
      );

      // 用户在后续页面完成创建后一路返回
      if (result == true && mounted) {
        await _persistAccountWebData();
        navigator.pop(true);
      }
    } catch (error) {
      debugPrint('[FIT 爬取] 异常: $error');
      _updateStatus('爬取失败：$error');
      if (mounted) {
        AppToast.show(context, '爬取失败：$error', variant: AppToastVariant.warning);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScraping = false;
        });
      }
    }
  }

  /// 检查课程列表中是否有周末排课（weekday == 6 或 7）。
  bool _hasWeekendCourses(List<Course> courses) {
    return courses.any(
      (Course c) => c.sessions.any((CourseSession s) => s.weekday >= 6),
    );
  }

  /// 根据导入课程估算学期总周数：最后一节课周次 + 2。
  int _computeImportedMaxWeek(List<Course> courses) {
    int lastWeek = 1;
    for (final Course course in courses) {
      for (final CourseSession session in course.sessions) {
        if (session.customWeeks.isNotEmpty) {
          final int customMax = session.customWeeks.reduce(max);
          if (customMax > lastWeek) {
            lastWeek = customMax;
          }
          continue;
        }
        if (session.endWeek > lastWeek) {
          lastWeek = session.endWeek;
        }
      }
    }
    return lastWeek + 2;
  }

  /// 估算学期开始日期（春季 2 月下旬，秋季 9 月初）。
  DateTime _guessSemesterStart() {
    final DateTime now = DateTime.now();
    if (now.month >= 1 && now.month <= 7) {
      return DateTime(now.year, 3, 4);
    }
    return DateTime(now.year, 9, 1);
  }

  // ---------------------------------------------------------------------------
  // UI 构建
  // ---------------------------------------------------------------------------

  /// 构建状态栏文本内容。
  /// 当状态文本包含确认提示标记时，使用红色富文本显示打勾图标。
  Widget _buildStatusContent(ColorScheme colorScheme) {
    // 使用 __CONFIRM_HINT__ 标记来区分需要特殊展示的提示
    if (_statusText.contains('__CONFIRM_HINT__')) {
      final String prefix = _statusText.split('__CONFIRM_HINT__').first;
      return Text.rich(
        TextSpan(
          style: TextStyle(color: colorScheme.onSurface, fontSize: 12),
          children: <InlineSpan>[
            TextSpan(text: prefix),
            const TextSpan(
              text: '点击右上角 ',
              style: TextStyle(color: Colors.red),
            ),
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(
                Icons.check_rounded,
                size: 16,
                color: colorScheme.primary,
              ),
            ),
            const TextSpan(
              text: ' 导入',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    }
    return Text(
      _statusText,
      style: TextStyle(color: colorScheme.onSurface, fontSize: 12),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    final bool isBusy =
        _isPreparingWebView || _isAutoLoginRunning || _isLoading || _isScraping;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          widget.schoolName,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        actions: <Widget>[
          // 重试按钮
          IconButton(
            onPressed: _isAutoLoginRunning ? null : _retryAutoLogin,
            tooltip: '重试自动登录',
            icon: const Icon(Icons.refresh_rounded),
          ),
          // 确认爬取按钮（打勾图标，无圆圈）
          IconButton(
            onPressed: _isScraping ? null : _onConfirmScrape,
            tooltip: '确认导入课表',
            icon: _isScraping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.check_rounded, color: colorScheme.primary),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // 状态栏
          Material(
            color: colorScheme.surfaceContainerHighest.withAlpha(110),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: isBusy
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Icon(
                            Icons.check_circle_outline,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStatusContent(colorScheme)),
                ],
              ),
            ),
          ),
          // WebView 主体
          Expanded(
            child: _isPreparingWebView
                ? const Center(child: CircularProgressIndicator())
                : InAppWebView(
                    initialUrlRequest: URLRequest(url: WebUri(widget.loginUrl)),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      useShouldOverrideUrlLoading: true,
                      mixedContentMode:
                          MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
                      safeBrowsingEnabled: false,
                      clearCache: false,
                      clearSessionCache: false,
                      cacheEnabled: true,
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
                        _statusText = '加载完成！';
                      });
                      await _tryAutoLogin();
                      await _persistAccountWebData(currentUrl: url);
                    },
                    // 拦截 JS alert 弹窗，检测密码错误提示
                    onJsAlert:
                        (
                          InAppWebViewController controller,
                          JsAlertRequest jsAlertRequest,
                        ) async {
                          final String msg = jsAlertRequest.message ?? '';
                          debugPrint('[自动登录] 拦截 JS alert: $msg');
                          if (msg.contains('密码不正确') || msg.contains('用户名或密码')) {
                            _updateStatus('账号或密码错误');
                            if (mounted) {
                              AppToast.show(
                                context,
                                '账号或密码错误，请检查后重新输入',
                                variant: AppToastVariant.error,
                              );
                              Navigator.of(context).pop();
                            }
                            return JsAlertResponse(handledByClient: true);
                          }
                          // 其他 alert 正常弹出
                          return JsAlertResponse(handledByClient: false);
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
