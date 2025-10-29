import 'dart:async';

import 'package:dormdevise/screens/open_door/open_door_page.dart';
import 'package:dormdevise/screens/open_door/open_door_settings_page.dart';
import 'package:dormdevise/screens/open_door/door_widget_prompt_page.dart';
import 'package:dormdevise/screens/open_door/widgets/door_widget_dialog.dart';
import 'package:dormdevise/screens/person/person_page.dart';
import 'package:dormdevise/screens/table/table_page.dart';
import 'package:dormdevise/services/door_widget_service.dart';
import 'package:flutter/material.dart';

/// 应用根组件，负责注入基础主题与导航框架。
class DormDeviseApp extends StatelessWidget {
  const DormDeviseApp({super.key});

  /// 构建顶层 MaterialApp 并指定首页及主题配置。
  @override
  Widget build(BuildContext context) {
    final String initialRoute =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
        useMaterial3: true,
      ),
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
              builder: (_) => const OpenDoorSettingsPage(initialTabIndex: 1),
            );
          default:
            return MaterialPageRoute<void>(
              builder: (_) => const ManagementScreen(),
            );
        }
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
  int selectedIndex = 1;
  late final PageController _pageController;
  double _page = 1.0;
  bool _navLocked = false;
  StreamSubscription<Uri?>? _widgetLaunchSubscription;
  bool _widgetDialogVisible = false;

  /// 根据索引构建对应的业务页面。
  Widget _buildPage(int index) {
    if (index == 2) {
      double progress = 0.0;
      if (_page >= 1.7 && _page <= 2.0) {
        progress = (1 - (_page - 1.7) / 0.3).clamp(0.0, 1.0);
      } else if (_page <= 1.7) {
        progress = 1.0;
      }
      return PersonPage(
        appBarProgress: progress,
        onInteractionLockChanged: _handleInteractionLockChanged,
      );
    }
    if (index == 1) {
      return const OpenDoorPage();
    }
    return const TablePage();
  }

  /// 为分页添加淡入与平移动画。
  Widget _buildAnimatedPage(BuildContext context, int index) {
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
            child: _buildPage(index),
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
    _pageController = PageController(initialPage: selectedIndex);
    _bindWidgetLaunchEvents();
  }

  /// 移除绑定并释放控制器资源。
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLaunchSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
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
        if (selectedIndex != 1) {
          setState(() {
            selectedIndex = 1;
          });
          if (_pageController.hasClients) {
            _pageController.jumpToPage(1);
          }
        } else if (_pageController.hasClients) {
          _pageController.jumpToPage(1);
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
            backgroundColor: colorScheme.surface,
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
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined),
                selectedIcon: Icon(Icons.calendar_today),
                label: '课表',
              ),
              NavigationDestination(
                icon: Icon(Icons.door_front_door_outlined),
                selectedIcon: Icon(Icons.door_front_door),
                label: '开门',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person),
                label: '我的',
              ),
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
