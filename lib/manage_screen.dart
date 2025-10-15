import 'package:dormdevise/screen/openDoorPage/open_door.dart';
import 'package:dormdevise/screen/personPage/person.dart';
import 'package:dormdevise/screen/tablePage/table.dart';
import 'package:flutter/material.dart';

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => ManagementScreenState();
}

class ManagementScreenState extends State<ManagementScreen>
    with WidgetsBindingObserver {
  int selectedIndex = 1;
  late final PageController _pageController;
  double _page = 1.0;
  bool _isLoading = true;

  Widget _buildPage(int index) {
    if (index == 2) {
      // 修正渐变方向：滑动到person页面时，progress=1为完全显示，progress=0为完全透明
      double progress = 0.0;
      if (_page >= 1.7 && _page <= 2.0) {
        progress = (1 - (_page - 1.7) / 0.3).clamp(0.0, 1.0);
      } else if (_page <= 1.7) {
        progress = 1.0;
      }
      return PersonPage(appBarProgress: progress);
    }
    if (index == 1) {
      return const OpenDoorPage();
    }
    return const TablePage();
  }

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
        double delta = (index - page).clamp(-1.0, 1.0);
        // 右进左出滑动+淡入
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

  // FIXME 流畅度需要优化
  // MAYBE 更好看的页面切换效果
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: selectedIndex);
    // 模拟初始化耗时操作，实际可替换为真实初始化逻辑
    Future.microtask(() async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  // 监听App生命周期（已移除回到前台时的 setState，避免白屏）

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: NavigationBar(
          height: 72,
          backgroundColor: colorScheme.surface,
          indicatorColor: colorScheme.secondaryContainer,
          selectedIndex: selectedIndex,
          onDestinationSelected: (value) {
            if (selectedIndex == value) return;
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
      body: PageView.builder(
        controller: _pageController,
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
