import 'dart:async';

import 'package:dormdevise/views/screens/open_door/open_door_page.dart';
import 'package:dormdevise/views/screens/open_door/door_lock_config_page.dart';
import 'package:dormdevise/views/screens/open_door/door_widget_prompt_page.dart';
import 'package:dormdevise/widgets/door_widget_dialog.dart';
import 'package:dormdevise/views/screens/person/person_page.dart';
import 'package:dormdevise/views/screens/table/table_page.dart';
import 'package:dormdevise/services/course_service.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:dormdevise/services/theme/theme_service.dart';
import 'package:dormdevise/services/update/update_check_service.dart';
import 'package:dormdevise/services/update/update_download_service.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// 应用根组件，负责注入基础主题与导航框架。
class DormDeviseApp extends StatelessWidget {
  const DormDeviseApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// 构建顶层 MaterialApp，通过 ListenableBuilder 监听主题变化实现动态换肤。
  @override
  Widget build(BuildContext context) {
    final String initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    return ListenableBuilder(
      listenable: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeService.instance.lightTheme,
          darkTheme: ThemeService.instance.darkTheme,
          themeMode: ThemeService.instance.themeMode,
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData mediaQuery = MediaQuery.of(context);
            final double rawScale = mediaQuery.textScaler.scale(14) / 14;
            final double clampedScale = rawScale.clamp(0.85, 1.15).toDouble();
            final TextScaler clampedTextScaler = TextScaler.linear(
              clampedScale,
            );
            return MediaQuery(
              data: mediaQuery.copyWith(textScaler: clampedTextScaler),
              child: child ?? const SizedBox.shrink(),
            );
          },
          themeAnimationDuration: const Duration(
            milliseconds: 500,
          ), // 延长渐变时间使其更平滑
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
          initialRoute: initialRoute,
          onGenerateRoute: (RouteSettings settings) {
            switch (settings.name) {
              case '/':
              case null:
                return MaterialPageRoute<void>(
                  builder: (_) => const ManagementScreen(),
                );
              case 'door_widget_prompt':
                return PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const DoorWidgetPromptPage(),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                  opaque: false,
                );
              case 'open_door_settings/mqtt':
                return MaterialPageRoute<void>(
                  builder: (_) =>
                      const OpenDoorSettingsPage(initialTabIndex: 1),
                );
              default:
                return MaterialPageRoute<void>(
                  builder: (_) => const ManagementScreen(),
                );
            }
          },
        );
      },
    );
  }
}

/// 主控制台页面，提供底部导航与多页切换。
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  /// 创建与主页面关联的状态对象。
  @override
  State<ManagementScreen> createState() => ManagementScreenState();
}

class ManagementScreenState extends State<ManagementScreen>
    with WidgetsBindingObserver {
  /// 所有导航项的固定定义（默认排列：0=课表, 1=开门, 2=我的）。
  static const _allDestinations = [
    NavigationDestination(
      icon: Icon(FontAwesomeIcons.calendar),
      selectedIcon: Icon(FontAwesomeIcons.solidCalendar),
      label: '课表',
    ),
    NavigationDestination(
      icon: Icon(Icons.door_front_door_outlined, size: 28),
      selectedIcon: Icon(Icons.door_front_door, size: 28),
      label: '开门',
    ),
    NavigationDestination(
      icon: Icon(FontAwesomeIcons.user),
      selectedIcon: Icon(FontAwesomeIcons.solidUser),
      label: '我的',
    ),
  ];

  int selectedIndex = 1;
  late final PageController _pageController;
  late double _page;
  bool _navLocked = false;
  StreamSubscription<Uri?>? _widgetLaunchSubscription;
  bool _widgetDialogVisible = false;
  bool _updatePromptVisible = false;
  bool _updateCheckInProgress = false;
  DateTime _lastReminderRefreshAt = DateTime.now();

  /// 根据原始页面索引构建对应的业务页面。
  ///
  /// [originalIndex] 是页面的固有标识（0=课表, 1=开门, 2=我的），
  /// 与导航顺序无关。
  Widget _buildPageByOriginalIndex(int originalIndex) {
    if (originalIndex == 2) {
      double progress = 0.0;
      // 在导航顺序中查找"我的"页面的实际显示位置
      final navOrder = ThemeService.instance.navOrder;
      final displayIndex = navOrder.indexOf(2);
      if (displayIndex >= 0) {
        final lower = displayIndex - 0.3;
        if (_page >= lower && _page <= displayIndex.toDouble()) {
          progress = (1 - (_page - lower) / 0.3).clamp(0.0, 1.0);
        } else if (_page <= lower) {
          progress = 1.0;
        }
      }
      return PersonPage(
        appBarProgress: progress,
        onInteractionLockChanged: _handleInteractionLockChanged,
      );
    }
    if (originalIndex == 1) {
      return const OpenDoorPage();
    }
    return const TablePage();
  }

  /// 为分页添加淡入与平移动画。
  ///
  /// [index] 是 PageView 中的显示顺序索引，
  /// 通过 navOrder 映射到原始页面索引。
  Widget _buildAnimatedPage(BuildContext context, int index) {
    final navOrder = ThemeService.instance.navOrder;
    final originalIndex = navOrder[index];
    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, child) {
        double page = 0.0;
        try {
          page = _pageController.hasClients && _pageController.page != null
              ? _pageController.page!
              : selectedIndex.toDouble();
        } catch (_) {
          page = selectedIndex.toDouble();
        }
        _page = page;
        final double delta = (index - page).clamp(-1.0, 1.0);
        final double opacity = 1.0 - delta.abs().clamp(0.0, 1.0);
        final double dx = delta > 0 ? 0.2 * delta : 0.0;
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(60.0 * dx, 0),
            child: _buildPageByOriginalIndex(originalIndex),
          ),
        );
      },
      child: const SizedBox.shrink(),
    );
  }

  /// 控制底部导航交互锁，防止动效未结束时切换页面。
  void _handleInteractionLockChanged(bool locked) {
    if (_navLocked == locked) {
      return;
    }
    setState(() {
      _navLocked = locked;
    });
  }

  /// 初始化页面控制器并处理短暂的加载动效。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 根据用户设置的默认主页，在导航顺序中查找其实际显示位置
    final navOrder = ThemeService.instance.navOrder;
    final homePage = ThemeService.instance.defaultHomePage;
    selectedIndex = navOrder.indexOf(homePage).clamp(0, 2);
    _page = selectedIndex.toDouble();
    _pageController = PageController(initialPage: selectedIndex);
    _bindWidgetLaunchEvents();
    // 提前请求通知权限
    UpdateDownloadService.instance.initializeNotifications();
    UpdateDownloadService.instance.setAppInForeground(true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) {
          return;
        }
        unawaited(
          UpdateDownloadService.instance.resumePendingInstallIfNeeded(),
        );
        unawaited(_checkForUpdatesOnLaunch());
      });
    });
  }

  /// 移除绑定并释放控制器资源。
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bool isForeground = state == AppLifecycleState.resumed;
    UpdateDownloadService.instance.setAppInForeground(isForeground);
    if (state != AppLifecycleState.resumed) {
      return;
    }
    unawaited(UpdateDownloadService.instance.resumePendingInstallIfNeeded());
    final DateTime now = DateTime.now();
    final bool crossedDay = _dateOnly(now) != _dateOnly(_lastReminderRefreshAt);
    final bool exceededRefreshWindow =
        now.difference(_lastReminderRefreshAt) >= const Duration(hours: 6);
    if (crossedDay || exceededRefreshWindow) {
      _lastReminderRefreshAt = now;
      unawaited(CourseService.instance.initializeReminders(force: true));
    }
    unawaited(_checkForUpdatesOnLaunch());
  }

  /// 绑定桌面微件事件流，支持轻点微件后自动弹出滑动对话框。
  void _bindWidgetLaunchEvents() {
    _widgetLaunchSubscription?.cancel();
    _widgetLaunchSubscription = DoorWidgetService.instance.launchEvents.listen(
      _handleWidgetLaunchUri,
    );
    final Uri? initialUri = DoorWidgetService.instance.takeLatestLaunchUri();
    if (initialUri != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleWidgetLaunchUri(initialUri);
      });
    }
  }

  /// 处理桌面微件传入的 URI 请求，触发弹窗或其他操作。
  void _handleWidgetLaunchUri(Uri? uri) {
    if (!mounted || uri == null || uri.host != 'door_widget') {
      return;
    }
    if (uri.pathSegments.isEmpty) {
      return;
    }
    final String action = uri.pathSegments.first;
    switch (action) {
      case 'prompt':
        // 使用导航顺序查找"开门"页面的实际显示位置
        final doorDisplayIndex = ThemeService.instance.navOrder
            .indexOf(1)
            .clamp(0, 2);
        if (selectedIndex != doorDisplayIndex) {
          setState(() {
            selectedIndex = doorDisplayIndex;
          });
          if (_pageController.hasClients) {
            _pageController.jumpToPage(doorDisplayIndex);
          }
        } else if (_pageController.hasClients) {
          _pageController.jumpToPage(doorDisplayIndex);
        }
        _showDoorWidgetDialog();
        break;
      case 'open':
      case 'refresh':
        // 若应用前台接收到后台操作请求，直接交由微件服务处理。
        unawaited(DoorWidgetService.instance.handleWidgetInteraction(uri));
        break;
      default:
        break;
    }
  }

  Future<void> _checkForUpdatesOnLaunch() async {
    if (_updateCheckInProgress ||
        _widgetDialogVisible ||
        _updatePromptVisible) {
      return;
    }
    if (UpdateDownloadService.instance.coordinator.isDownloading) {
      return;
    }
    _updateCheckInProgress = true;
    if (await UpdateDownloadService.instance.hasPendingInstall()) {
      _updateCheckInProgress = false;
      return;
    }
    try {
      final HomePageUpdatePromptPlan? promptPlan = await UpdateCheckService
          .instance
          .fetchHomePageUpdatePrompt(forceRefresh: true);
      final UpdateCheckResult? result = promptPlan?.result;
      if (!mounted ||
          promptPlan == null ||
          result == null ||
          !result.hasCompatibleAsset ||
          _widgetDialogVisible) {
        return;
      }

      _updatePromptVisible = true;
      final UpdateDialogAction action = await UpdateCheckService.instance
          .showUpdateAvailableDialog(
            context,
            result,
            confirmLabel: '立即更新',
            secondaryLabel: promptPlan.secondaryLabel,
          );
      if (!mounted) {
        return;
      }
      if (action == UpdateDialogAction.secondary) {
        if (promptPlan.secondaryAction ==
            HomePageUpdatePromptSecondaryAction.cancel) {
          await UpdateCheckService.instance.cancelHomePageUpdatePrompt(
            result.latestVersion,
          );
        } else {
          await UpdateCheckService.instance.deferHomePageUpdatePrompt(
            result.latestVersion,
          );
        }
        if (mounted) {
          AppToast.show(context, promptPlan.feedbackMessage);
        }
        return;
      }
      if (action != UpdateDialogAction.confirm) {
        return;
      }

      await UpdateCheckService.instance.clearHomePageUpdatePromptState();
      await UpdateCheckService.instance.startBackgroundUpdate(
        asset: result.asset,
        releaseVersion: result.latestVersion,
      );
    } catch (error, stackTrace) {
      debugPrint('启动更新检查失败: $error\n$stackTrace');
    } finally {
      _updatePromptVisible = false;
      _updateCheckInProgress = false;
    }
  }

  /// 展示滑动开门弹窗，防止重复打开。
  Future<void> _showDoorWidgetDialog() async {
    if (!mounted || _widgetDialogVisible) {
      return;
    }
    setState(() {
      _widgetDialogVisible = true;
    });
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const DoorWidgetDialog(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _widgetDialogVisible = false;
    });
  }

  /// 构建包含底部导航与分页内容的界面结构。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: IgnorePointer(
          ignoring: _navLocked,
          child: NavigationBar(
            height: 72,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            indicatorColor: colorScheme.secondaryContainer,
            selectedIndex: selectedIndex,
            onDestinationSelected: (value) {
              if (_navLocked || selectedIndex == value) {
                return;
              }
              _pageController.animateToPage(
                value,
                duration: const Duration(milliseconds: 600),
                curve: Curves.ease,
              );
            },
            destinations: [
              // 根据导航顺序动态构建底部导航项
              for (final oi in ThemeService.instance.navOrder)
                _allDestinations[oi],
            ],
            labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
            elevation: 0,
            shadowColor: Colors.transparent,
          ),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 3,
        itemBuilder: (context, index) => _buildAnimatedPage(context, index),
        onPageChanged: (index) {
          setState(() {
            selectedIndex = index;
          });
        },
      ),
    );
  }
}
