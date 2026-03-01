import 'package:dormdevise/services/theme/theme_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 个性主题设置页，提供主题模式（浅色/跟随系统/深色）切换、
/// 预设色板、HSB 自定义取色、效果预览以及主页导航顺序自定义。
class ThemeSettingsPage extends StatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  State<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage> {
  /// 开关预览的状态（可交互切换，仅做展示用）
  bool _previewSwitchValue = true;

  /// 预设主色列表（差异化色系，每排五个）
  static const List<_PresetColor> _presets = [
    _PresetColor(color: Colors.white, label: '洁白'),
    _PresetColor(color: Colors.blueAccent, label: '蔚蓝'),
    _PresetColor(color: Colors.teal, label: '青碧'),
    _PresetColor(color: Colors.green, label: '翠绿'),
    _PresetColor(color: Colors.orange, label: '暖橙'),
    _PresetColor(color: Colors.redAccent, label: '活力红'),
    _PresetColor(color: Colors.purple, label: '优雅紫'),
    _PresetColor(color: Colors.indigo, label: '深靛青'),
    _PresetColor(color: Color(0xFFFF6699), label: '少女粉'),
  ];

  /// 弹出 HSB 色轮取色对话框（与编辑课程的自定义颜色弹窗风格统一）。
  ///
  /// 取色成功后自动应用为当前主色。
  Future<void> _showCustomColorDialog() async {
    if (!mounted) return;
    final Color? result = await Navigator.of(context).push<Color>(
      PageRouteBuilder<Color>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.55),
        pageBuilder: (context, animation, secondaryAnimation) {
          return const _ThemeCustomColorDialog();
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
    if (result != null && mounted) {
      await ThemeService.instance.setPrimaryColor(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentColor = ThemeService.instance.primaryColor;
    final currentMode = ThemeService.instance.themeModeSetting;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('个性主题')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // —— 主题模式切换 ——
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isDark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '主题模式',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildAppearanceToggle(context, currentMode),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // —— 选择主题颜色 ——
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.color_lens_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '主题颜色',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          // 正方形色块 + 底部标签
                          childAspectRatio: 0.68,
                        ),
                    // +1 为末尾的"自定义"入口
                    itemCount: _presets.length + 1,
                    itemBuilder: (context, index) {
                      final bool isPresetSelected = _presets.any(
                        (p) => p.color.toARGB32() == currentColor.toARGB32(),
                      );
                      if (index == _presets.length) {
                        return _CustomColorTile(
                          rainbowColors: _presets.map((p) => p.color).toList(),
                          selectedColor: currentColor,
                          isSelected: !isPresetSelected,
                          onTap: () {
                            _showCustomColorDialog();
                          },
                        );
                      }
                      final preset = _presets[index];
                      // ignore: deprecated_member_use
                      final isSelected =
                          currentColor.value == preset.color.value;
                      return _ColorTile(
                        preset: preset,
                        isSelected: isSelected,
                        selectedBorderColor: colorScheme.primary,
                        onTap: () async {
                          await ThemeService.instance.setPrimaryColor(
                            preset.color,
                          );
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await ThemeService.instance.setPrimaryColor(
                          ThemeService.defaultPrimaryColor,
                        );
                      },
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('恢复默认'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // —— 主题预览区 ——
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 20,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '效果预览',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          child: const Text('主按钮'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          child: const Text('次按钮'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 不使用 const 以确保主题切换时输入框跟随渐变重建
                  TextField(
                    decoration: InputDecoration(
                      labelText: '输入框预览',
                      hintText: '请输入内容...',
                      // 显式引用当前主题的填充色，确保与主题渐变同步
                      fillColor: Theme.of(
                        context,
                      ).inputDecorationTheme.fillColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('开关预览'),
                      Switch(
                        value: _previewSwitchValue,
                        onChanged: (v) =>
                            setState(() => _previewSwitchValue = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // —— 主页导航顺序自定义 ——
          _buildNavOrderCard(context),
          const SizedBox(height: 12),

          // —— 主页设置（默认启动页） ——
          _buildHomePageCard(context),
        ],
      ),
    );
  }

  // ─────────────── 三段式主题模式切换 ───────────────

  /// 构建主题模式（浅色/跟随系统/深色）三段分段切换控件。
  ///
  /// 不使用 AnimatedContainer 包裹轨道颜色，而是让 MaterialApp 的主题渐变
  /// 动画直接驱动 colorScheme 的颜色过渡，确保与整体渐变完全同步。
  /// 即：轨道底色、滑块颜色均取自 Theme.of(context).colorScheme，
  /// 由 MaterialApp.themeAnimationDuration（500ms）统一插值。
  Widget _buildAppearanceToggle(
    BuildContext context,
    ThemeModeSetting currentMode,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 40,
      decoration: BoxDecoration(
        // 与课程颜色分配策略滑块保持一致：
        // 浅色使用 surfaceContainerLowest，深色使用 surfaceContainer
        color: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          // 三段式：每段宽度 = (轨道总宽 - 两侧边距) / 3
          final double indicatorWidth = (totalWidth - 4) / 3;

          // 滑块对齐位置：-1=左(浅色), 0=中(跟随系统), 1=右(深色)
          final Alignment alignment;
          switch (currentMode) {
            case ThemeModeSetting.light:
              alignment = Alignment.centerLeft;
            case ThemeModeSetting.system:
              alignment = Alignment.center;
            case ThemeModeSetting.dark:
              alignment = Alignment.centerRight;
          }

          return Stack(
            children: [
              // 滑块动画（500ms 匹配 app.dart 的 themeAnimationDuration）
              AnimatedAlign(
                alignment: alignment,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                child: Container(
                  width: indicatorWidth,
                  height: 36,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    // 与课程颜色分配策略滑块保持一致：
                    // 浅色白色，深色使用 surfaceContainerHigh
                    color: isDark
                        ? colorScheme.surfaceContainerHigh
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              // 三个选项
              Row(
                children: [
                  _buildAppearanceOption(
                    icon: Icons.light_mode_rounded,
                    label: '浅色模式',
                    isSelected: currentMode == ThemeModeSetting.light,
                    onTap: () async {
                      await ThemeService.instance.setThemeModeSetting(
                        ThemeModeSetting.light,
                      );
                    },
                  ),
                  _buildAppearanceOption(
                    icon: Icons.brightness_auto_rounded,
                    label: '跟随系统',
                    isSelected: currentMode == ThemeModeSetting.system,
                    onTap: () async {
                      await ThemeService.instance.setThemeModeSetting(
                        ThemeModeSetting.system,
                      );
                    },
                  ),
                  _buildAppearanceOption(
                    icon: Icons.dark_mode_rounded,
                    label: '深色模式',
                    isSelected: currentMode == ThemeModeSetting.dark,
                    onTap: () async {
                      await ThemeService.instance.setThemeModeSetting(
                        ThemeModeSetting.dark,
                      );
                    },
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// 主题模式切换的单个选项
  Widget _buildAppearanceOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: Container(
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: isSelected ? 1.0 : 0.6,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────── HSB 取色器 ───────────────

  /// 构建 HSB 取色器卡片（展开在主题模式和颜色选择之间）。
  // ─────────────── 主页导航顺序自定义 ───────────────

  /// 导航目的地定义（图标、选中图标、标签），索引对应原始页面：
  /// 0=课表, 1=开门, 2=我的
  static const List<_NavDestination> _allDestinations = [
    _NavDestination(
      icon: Icons.calendar_today_outlined,
      selectedIcon: Icons.calendar_today,
      label: '课表',
    ),
    _NavDestination(
      icon: Icons.door_front_door_outlined,
      selectedIcon: Icons.door_front_door,
      label: '开门',
    ),
    _NavDestination(
      icon: Icons.person_outline,
      selectedIcon: Icons.person,
      label: '我的',
    ),
  ];

  /// 构建主页导航顺序自定义卡片（水平排列，左右拖拽）。
  ///
  /// 用户可通过长按拖拽重新排列底部导航栏的页面顺序，
  /// 修改后实时生效并持久化到 SharedPreferences。
  Widget _buildNavOrderCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final navOrder = ThemeService.instance.navOrder;
    final Color navBlockColor = Theme.of(context).scaffoldBackgroundColor;
    final Color navBlockFg = colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.swap_horiz_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '主页导航顺序',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
                // 恢复默认按钮
                if (!_isDefaultOrder(navOrder))
                  GestureDetector(
                    onTap: () async {
                      await ThemeService.instance.setNavOrder(
                        ThemeService.defaultNavOrder,
                      );
                      setState(() {});
                    },
                    child: Text(
                      '重置',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '长按拖拽可调整底部导航栏顺序',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // 水平可拖拽重排的导航项列表
            LayoutBuilder(
              builder: (context, constraints) {
                final itemWidth = constraints.maxWidth / 3;
                return SizedBox(
                  height: 64,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          final double elevation = Tween<double>(
                            begin: 0,
                            end: 6,
                          ).evaluate(animation);
                          return Material(
                            elevation: elevation,
                            borderRadius: BorderRadius.circular(12),
                            child: child,
                          );
                        },
                        child: child,
                      );
                    },
                    itemCount: navOrder.length,
                    onReorder: (oldIndex, newIndex) async {
                      if (newIndex > oldIndex) newIndex--;
                      final newOrder = List<int>.from(navOrder);
                      final item = newOrder.removeAt(oldIndex);
                      newOrder.insert(newIndex, item);
                      await ThemeService.instance.setNavOrder(newOrder);
                      setState(() {});
                    },
                    itemBuilder: (context, index) {
                      final destIndex = navOrder[index];
                      final dest = _allDestinations[destIndex];
                      return ReorderableDragStartListener(
                        key: ValueKey(destIndex),
                        index: index,
                        child: SizedBox(
                          width: itemWidth,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: navBlockColor,
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.45,
                                ),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(dest.icon, size: 22, color: navBlockFg),
                                const SizedBox(height: 4),
                                Text(
                                  dest.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: navBlockFg,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────── 主页设置（默认启动页） ───────────────

  /// 构建主页设置卡片（选择 App 打开时默认显示的页面）。
  Widget _buildHomePageCard(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final navOrder = ThemeService.instance.navOrder;
    final currentHomePage = ThemeService.instance.defaultHomePage;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.home_outlined, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                const Text(
                  '主页设置',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildHomePageToggle(context, navOrder, currentHomePage),
          ],
        ),
      ),
    );
  }

  /// 构建主页选择三段滑块（与主题模式切换风格一致）。
  ///
  /// 选项按当前导航顺序排列，选中项对应默认启动页。
  Widget _buildHomePageToggle(
    BuildContext context,
    List<int> navOrder,
    int currentHomePage,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // 在导航顺序中查找当前默认主页的显示位置
    final displayPos = navOrder.indexOf(currentHomePage).clamp(0, 2);

    final Alignment alignment;
    switch (displayPos) {
      case 0:
        alignment = Alignment.centerLeft;
      case 1:
        alignment = Alignment.center;
      default:
        alignment = Alignment.centerRight;
    }

    return Container(
      height: 40,
      decoration: BoxDecoration(
        // 与课程颜色分配策略滑块保持一致
        color: isDark
            ? colorScheme.surfaceContainer
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double totalWidth = constraints.maxWidth;
          final double indicatorWidth = (totalWidth - 4) / 3;

          return Stack(
            children: [
              AnimatedAlign(
                alignment: alignment,
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                child: Container(
                  width: indicatorWidth,
                  height: 36,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    // 与课程颜色分配策略滑块保持一致
                    color: isDark
                        ? colorScheme.surfaceContainerHigh
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 1,
                        offset: const Offset(0, 1),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: List.generate(3, (displayIndex) {
                  final originalIndex = navOrder[displayIndex];
                  final dest = _allDestinations[originalIndex];
                  final isSelected = displayIndex == displayPos;
                  return _buildHomePageOption(
                    icon: dest.icon,
                    label: dest.label,
                    isSelected: isSelected,
                    onTap: () async {
                      await ThemeService.instance.setDefaultHomePage(
                        originalIndex,
                      );
                      setState(() {});
                    },
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 主页选择的单个选项（图标 + 文字）
  Widget _buildHomePageOption({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.translucent,
        child: Container(
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: isSelected ? 1.0 : 0.6,
                ),
              ),
              const SizedBox(width: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 判断当前导航顺序是否为默认值
  bool _isDefaultOrder(List<int> order) {
    if (order.length != ThemeService.defaultNavOrder.length) return false;
    for (int i = 0; i < order.length; i++) {
      if (order[i] != ThemeService.defaultNavOrder[i]) return false;
    }
    return true;
  }
}

// ─────────────── HSB 自定义颜色对话框 ───────────────

/// HSB 色轮自定义颜色伪弹窗页面（透明路由 + 背景变暗）。
///
/// 页面包含「效果预览 + 色轮取色」同屏内容，
/// 通过 Navigator.pop 返回选中的 Color。
class _ThemeCustomColorDialog extends StatefulWidget {
  const _ThemeCustomColorDialog();

  @override
  State<_ThemeCustomColorDialog> createState() =>
      _ThemeCustomColorDialogState();
}

class _ThemeCustomColorDialogState extends State<_ThemeCustomColorDialog> {
  late double _hue;
  late double _saturation;
  late double _brightness;
  bool _previewSwitchValue = true;

  @override
  void initState() {
    super.initState();
    // 初始化为当前主色的 HSB 值；白色无色相，用少女粉作默认
    final color = ThemeService.instance.primaryColor;
    final hsv = HSVColor.fromColor(
      color == Colors.white ? const Color(0xFFFF6699) : color,
    );
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _brightness = hsv.value;
  }

  Color get _pickerColor =>
      HSVColor.fromAHSV(1.0, _hue, _saturation, _brightness).toColor();

  @override
  Widget build(BuildContext context) {
    final color = _pickerColor;
    final colorScheme = Theme.of(context).colorScheme;
    final textOnColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final hexStr =
        r.toRadixString(16).padLeft(2, '0') +
        g.toRadixString(16).padLeft(2, '0') +
        b.toRadixString(16).padLeft(2, '0');

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color ?? colorScheme.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '自定义主题颜色',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                          tooltip: '关闭',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.45,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.visibility_outlined,
                                size: 18,
                                color: color,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '效果预览',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: color,
                                    foregroundColor: textOnColor,
                                  ),
                                  child: const Text('主按钮'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {},
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: color,
                                    side: BorderSide(color: color),
                                  ),
                                  child: const Text('次按钮'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: '输入框预览',
                              hintText: '示例文本',
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: color.withValues(alpha: 0.35),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: color,
                                  width: 1.6,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '开关预览',
                                style: TextStyle(color: colorScheme.onSurface),
                              ),
                              Switch(
                                value: _previewSwitchValue,
                                onChanged: (v) {
                                  setState(() {
                                    _previewSwitchValue = v;
                                  });
                                },
                                activeTrackColor: color,
                                activeThumbColor: textOnColor,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // SV 矩形拾色区（全宽，固定高度）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: 200,
                        child: _SVPicker(
                          hue: _hue,
                          saturation: _saturation,
                          brightness: _brightness,
                          onChanged: (s, v) => setState(() {
                            _saturation = s;
                            _brightness = v;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 色相条 + 右侧颜色预览
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 24,
                            child: _HueSlider(
                              hue: _hue,
                              onChanged: (h) => setState(() => _hue = h),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 36,
                          height: 24,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.outlineVariant,
                              width: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Hex / RGB 输入
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: _CompactTextField(
                            label: 'Hex',
                            value: hexStr.toUpperCase(),
                            onSubmitted: (text) {
                              final hex = text.replaceAll('#', '').trim();
                              if (hex.length == 6) {
                                final parsed = int.tryParse(hex, radix: 16);
                                if (parsed != null) {
                                  final c = Color(0xFF000000 | parsed);
                                  final hsv = HSVColor.fromColor(c);
                                  setState(() {
                                    _hue = hsv.hue;
                                    _saturation = hsv.saturation;
                                    _brightness = hsv.value;
                                  });
                                }
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CompactTextField(
                            label: 'R',
                            value: '$r',
                            onSubmitted: (v) => _setFromRGB(r: int.tryParse(v)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CompactTextField(
                            label: 'G',
                            value: '$g',
                            onSubmitted: (v) => _setFromRGB(g: int.tryParse(v)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _CompactTextField(
                            label: 'B',
                            value: '$b',
                            onSubmitted: (v) => _setFromRGB(b: int.tryParse(v)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // 快捷预设色点
                    _buildQuickPresets(),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, color),
                          child: const Text('应用'),
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

  /// 通过 RGB 值更新 HSB 状态
  void _setFromRGB({int? r, int? g, int? b}) {
    final c = _pickerColor;
    final nr = (r ?? (c.r * 255).round()).clamp(0, 255);
    final ng = (g ?? (c.g * 255).round()).clamp(0, 255);
    final nb = (b ?? (c.b * 255).round()).clamp(0, 255);
    final newColor = Color.fromARGB(255, nr, ng, nb);
    final hsv = HSVColor.fromColor(newColor);
    setState(() {
      _hue = hsv.hue;
      _saturation = hsv.saturation;
      _brightness = hsv.value;
    });
  }

  /// 快捷预设色点
  Widget _buildQuickPresets() {
    const presets = [
      Color(0xFFCC0033),
      Color(0xFFE86826),
      Color(0xFFDBC824),
      Color(0xFF8B6914),
      Color(0xFF5D8C2A),
      Color(0xFF356B3F),
      Color(0xFF8844AA),
      Color(0xFF5533CC),
      Color(0xFF4477DD),
      Color(0xFF33AAAA),
      Color(0xFFAADD44),
      Color(0xFF222222),
      Color(0xFF555555),
      Color(0xFF999999),
      Color(0xFFCCCCCC),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: presets.map((color) {
        return GestureDetector(
          onTap: () {
            final hsv = HSVColor.fromColor(color);
            setState(() {
              _hue = hsv.hue;
              _saturation = hsv.saturation;
              _brightness = hsv.value;
            });
          },
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────── HSB 子组件 ───────────────

/// SV 矩形拾色区（Photoshop 风格）。
///
/// 横轴表示饱和度（左=0 右=1），纵轴表示明度（上=1 下=0）。
/// 背景由当前色相决定：左上角为白色，右上角为纯色，
/// 左下角为黑色，右下角为纯色变暗。
class _SVPicker extends StatelessWidget {
  final double hue;
  final double saturation;
  final double brightness;
  final void Function(double saturation, double brightness) onChanged;

  const _SVPicker({
    required this.hue,
    required this.saturation,
    required this.brightness,
    required this.onChanged,
  });

  void _handleInteraction(Offset localPosition, Size size) {
    final s = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final v = 1.0 - (localPosition.dy / size.height).clamp(0.0, 1.0);
    onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onPanStart: (d) =>
              _handleInteraction(d.localPosition, constraints.biggest),
          onPanUpdate: (d) =>
              _handleInteraction(d.localPosition, constraints.biggest),
          child: CustomPaint(
            painter: _SVPainter(hue: hue),
            child: Stack(
              children: [
                // 圆形选择指示器
                Positioned(
                  left: saturation * constraints.maxWidth - 8,
                  top: (1.0 - brightness) * constraints.maxHeight - 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// SV 矩形的 CustomPainter，绘制饱和度-明度渐变。
///
/// 叠加两层渐变：
/// 1. 水平渐变：白色 → 纯色（色相色）
/// 2. 垂直渐变：透明 → 黑色
class _SVPainter extends CustomPainter {
  final double hue;

  _SVPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.clipRRect(rrect);

    // 基础纯色（由色相决定）
    final pureColor = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();

    // 层 1：水平渐变（白色 → 纯色）
    final horizontalGradient = LinearGradient(
      colors: [Colors.white, pureColor],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = horizontalGradient);

    // 层 2：垂直渐变（透明 → 黑色）
    final verticalGradient = const LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Colors.transparent, Colors.black],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = verticalGradient);
  }

  @override
  bool shouldRepaint(covariant _SVPainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

/// 水平色相滑块，渲染 0°~360° 的彩虹渐变。
class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;

  const _HueSlider({required this.hue, required this.onChanged});

  void _handleInteraction(Offset localPosition, double width) {
    final h = (localPosition.dx / width).clamp(0.0, 1.0) * 360;
    onChanged(h);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          onPanStart: (d) => _handleInteraction(d.localPosition, width),
          onPanUpdate: (d) => _handleInteraction(d.localPosition, width),
          child: CustomPaint(
            painter: _HuePainter(),
            child: Stack(
              children: [
                Positioned(
                  left: (hue / 360.0) * width - 6,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 色相条的 CustomPainter，绘制 0°~360° 彩虹渐变。
class _HuePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(6));
    canvas.clipRRect(rrect);

    // 7 个关键色相点的颜色停靠（红→黄→绿→青→蓝→紫→红）
    final colors = List.generate(
      7,
      (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
    );
    final gradient = LinearGradient(colors: colors).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = gradient);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 紧凑型文本输入框（用于 Hex/RGB 值显示与编辑）
class _CompactTextField extends StatefulWidget {
  final String label;
  final String value;
  final ValueChanged<String> onSubmitted;

  const _CompactTextField({
    required this.label,
    required this.value,
    required this.onSubmitted,
  });

  @override
  State<_CompactTextField> createState() => _CompactTextFieldState();
}

class _CompactTextFieldState extends State<_CompactTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(covariant _CompactTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部值变化时同步更新（避免用户正在编辑时被覆盖）
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 36,
          child: TextField(
            controller: _controller,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            inputFormatters: [
              if (widget.label == 'Hex')
                FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]'))
              else
                FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(widget.label == 'Hex' ? 6 : 3),
            ],
            onSubmitted: widget.onSubmitted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

// ─────────────── 预设色与自定义入口磁贴 ───────────────

/// 预设色磁贴（正方形色块 + 底部标签），选中时勾选图标带 AnimatedSwitcher 过渡。
class _ColorTile extends StatelessWidget {
  final _PresetColor preset;
  final bool isSelected;
  final Color selectedBorderColor;
  final VoidCallback onTap;

  const _ColorTile({
    required this.preset,
    required this.isSelected,
    required this.selectedBorderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 深色模式下白色预设展示为"乌黑"
    final bool isWhitePreset = preset.color == Colors.white;
    final Color displayColor = (isDark && isWhitePreset)
        ? Colors.black
        : preset.color;
    final String displayLabel = (isDark && isWhitePreset) ? '乌黑' : preset.label;

    final brightness = ThemeData.estimateBrightnessForColor(displayColor);
    final foreground = brightness == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final needsBorder = displayColor == Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: displayColor,
                border: isSelected
                    ? Border.all(color: selectedBorderColor, width: 2.5)
                    : needsBorder
                    ? Border.all(color: Colors.grey.shade300, width: 0.5)
                    : null,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: displayColor.withValues(alpha: 0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return ScaleTransition(
                    scale: animation,
                    child: FadeTransition(opacity: animation, child: child),
                  );
                },
                child: isSelected
                    ? Icon(
                        Icons.check,
                        key: const ValueKey('check'),
                        color: foreground,
                        size: 22,
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: Text(
              displayLabel,
              key: ValueKey(displayLabel),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// 彩虹渐变色的"自定义"颜色入口磁贴（点击弹出 HSB 色轮对话框）。
class _CustomColorTile extends StatelessWidget {
  final List<Color> rainbowColors;
  final Color selectedColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _CustomColorTile({
    required this.rainbowColors,
    required this.selectedColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        ThemeData.estimateBrightnessForColor(selectedColor) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: isSelected ? 1 : 0),
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              builder: (context, t, child) {
                return Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: isSelected
                        ? Border.all(color: selectedColor, width: 2.5)
                        : null,
                    gradient: LinearGradient(
                      // 彩虹基于9个预设主色按顺序组成
                      colors: rainbowColors
                          .map((c) => c.withValues(alpha: 0.68 - 0.2 * t))
                          .toList(),
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      color: selectedColor.withValues(alpha: t),
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: isSelected
                          ? Icon(
                              Icons.check,
                              key: const ValueKey('custom-check'),
                              color: foreground,
                              size: 22,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('custom-empty'),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '自定义',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 导航目的地模型
class _NavDestination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// 预设颜色模型
class _PresetColor {
  final Color color;
  final String label;

  const _PresetColor({required this.color, required this.label});
}
