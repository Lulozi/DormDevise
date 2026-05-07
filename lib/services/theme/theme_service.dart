import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式选项枚举，对应用户在设置页面的三种选择。
///
/// - [light]：固定浅色模式
/// - [system]：跟随系统亮度自动切换浅色/深色
/// - [dark]：固定深色模式
enum ThemeModeSetting {
  /// 浅色模式（固定亮色主题）
  light,

  /// 跟随系统（根据设备系统亮度自动切换浅色/深色）
  system,

  /// 深色模式（固定暗色主题）
  dark,
}

/// 全局主题管理服务（单例），负责根据用户选择的主色调构建统一的 ThemeData，
/// 并通过 SharedPreferences 持久化用户偏好。
///
/// 三大维度：
/// - 主色调（白色、彩色等）：决定色系风格
/// - 外观模式（浅色 / 跟随系统 / 深色）：决定亮色或暗色主题
/// - 系统亮度（仅在"跟随系统"时生效）：设备当前的系统亮度
class ThemeService extends ChangeNotifier {
  ThemeService._();

  static final ThemeService instance = ThemeService._();

  static const String _prefKey = 'theme_primary_color';
  static const String _prefKeyDarkMode = 'theme_dark_mode';

  /// SharedPreferences 键名：主题模式设置（0=浅色, 1=跟随系统, 2=深色）
  static const String _prefKeyThemeMode = 'theme_mode_setting';

  /// SharedPreferences 键名：底部导航栏页面顺序
  static const String _prefKeyNavOrder = 'nav_order';

  /// SharedPreferences 键名：默认主页
  static const String _prefKeyDefaultHomePage = 'default_home_page';

  /// SharedPreferences 键名：是否启用自定义主题预览效果
  static const String _prefKeyCustomPreviewEnabled =
      'theme_custom_preview_enabled';

  /// SharedPreferences 键名：自定义主题下开关圆点颜色
  static const String _prefKeyCustomSwitchThumbColor =
      'theme_custom_switch_thumb_color';

  /// 默认主色
  static const Color defaultPrimaryColor = Colors.white;

  /// 默认导航顺序：课表(0)、开门(1)、我的(2)
  static const List<int> defaultNavOrder = [0, 1, 2];

  Color _primaryColor = defaultPrimaryColor;

  /// 是否启用了“自定义主题颜色弹窗”的预览效果到全局。
  bool _isCustomPreviewEnabled = false;

  /// 自定义主题下开关圆点颜色（白-黑灰阶中的任意值）。
  Color? _customSwitchThumbColor;

  /// 用户选择的主题模式：浅色 / 跟随系统 / 深色
  ThemeModeSetting _themeModeSetting = ThemeModeSetting.light;

  /// 底部导航栏页面排列顺序（索引对应原始页面：0=课表, 1=开门, 2=我的）
  List<int> _navOrder = List.from(defaultNavOrder);

  /// 默认启动的主页索引（原始页面索引：0=课表, 1=开门, 2=我的）
  int _defaultHomePage = 1;

  /// 当前用户选择的主色调
  Color get primaryColor => _primaryColor;

  /// 通知等系统着色场景使用的预览强调色。
  ///
  /// 白色/乌黑模式下避免直接返回纯白，改用与开关轨道一致的深灰。
  Color get notificationPreviewColor {
    if (isWhiteMode) {
      return Colors.grey.shade700;
    }
    return _primaryColor;
  }

  /// 当前是否启用了自定义主题颜色预览
  bool get isCustomPreviewEnabled => _isCustomPreviewEnabled;

  /// 当前用户选择的主题模式设置
  ThemeModeSetting get themeModeSetting => _themeModeSetting;

  /// 当前是否处于暗色模式（综合考虑用户设置和系统亮度）。
  ///
  /// - 浅色模式：始终返回 false
  /// - 深色模式：始终返回 true
  /// - 跟随系统：根据设备当前系统亮度返回结果
  bool get isDarkMode {
    switch (_themeModeSetting) {
      case ThemeModeSetting.light:
        return false;
      case ThemeModeSetting.dark:
        return true;
      case ThemeModeSetting.system:
        // 跟随系统模式下，通过平台调度器获取当前系统亮度
        return SchedulerBinding
                .instance
                .platformDispatcher
                .platformBrightness ==
            Brightness.dark;
    }
  }

  /// 当前底部导航栏页面排列顺序
  List<int> get navOrder => List.unmodifiable(_navOrder);

  /// 当前默认启动的主页（原始页面索引）
  int get defaultHomePage => _defaultHomePage;

  /// 当前是否为简洁白模式
  bool get isWhiteMode {
    if (_isCustomPreviewEnabled) return false;
    // ignore: deprecated_member_use
    return _primaryColor.value == Colors.white.value;
  }

  /// 从 SharedPreferences 恢复用户上次保存的主色和外观模式。
  ///
  /// 兼容旧版数据：
  /// 1. 如果存在新格式的 `_prefKeyThemeMode`（int），直接读取
  /// 2. 如果仅存在旧格式的 `_prefKeyDarkMode`（bool），自动迁移为新格式
  /// 3. 如果旧版存储了黑色作为主色，迁移为深色模式 + 默认白色
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(_prefKey);
    if (stored != null) {
      _primaryColor = Color(stored);
    }
    _isCustomPreviewEnabled =
        prefs.getBool(_prefKeyCustomPreviewEnabled) ?? false;
    final customThumbStored = prefs.getInt(_prefKeyCustomSwitchThumbColor);
    if (customThumbStored != null) {
      _customSwitchThumbColor = Color(customThumbStored);
    }

    // 尝试读取新格式的主题模式设置（优先）
    final storedMode = prefs.getInt(_prefKeyThemeMode);
    if (storedMode != null) {
      // 新格式：0=浅色, 1=跟随系统, 2=深色
      _themeModeSetting = ThemeModeSetting
          .values[storedMode.clamp(0, ThemeModeSetting.values.length - 1)];
    } else {
      // 兼容旧版：从 bool 类型的 isDarkMode 迁移到新的三态设置
      final oldDarkMode = prefs.getBool(_prefKeyDarkMode) ?? false;
      _themeModeSetting = oldDarkMode
          ? ThemeModeSetting.dark
          : ThemeModeSetting.light;
      // 将旧格式迁移到新格式并持久化
      await prefs.setInt(_prefKeyThemeMode, _themeModeSetting.index);
    }

    // 兼容旧版：如果旧版存储了黑色作为主色，自动迁移为深色模式 + 默认色
    // ignore: deprecated_member_use
    if (!_isCustomPreviewEnabled && _primaryColor.value == Colors.black.value) {
      _themeModeSetting = ThemeModeSetting.dark;
      _primaryColor = defaultPrimaryColor;
      // ignore: deprecated_member_use
      await prefs.setInt(_prefKey, defaultPrimaryColor.value);
      await prefs.setInt(_prefKeyThemeMode, ThemeModeSetting.dark.index);
    }

    if (_isCustomPreviewEnabled && _customSwitchThumbColor == null) {
      _customSwitchThumbColor = _resolveAutoCustomSwitchThumbColor(
        _primaryColor,
      );
      // ignore: deprecated_member_use
      await prefs.setInt(
        _prefKeyCustomSwitchThumbColor,
        _customSwitchThumbColor!.toARGB32(),
      );
    }

    // 恢复用户自定义的底部导航栏排列顺序
    final storedNav = prefs.getStringList(_prefKeyNavOrder);
    if (storedNav != null && storedNav.length == 3) {
      final parsed = storedNav.map((s) => int.tryParse(s)).toList();
      // 校验：必须恰好包含 0, 1, 2 三个值
      if (!parsed.contains(null) &&
          parsed.toSet().length == 3 &&
          parsed.every((v) => v! >= 0 && v < 3)) {
        _navOrder = parsed.cast<int>();
      }
    }

    // 恢复用户选择的默认主页
    _defaultHomePage = (prefs.getInt(_prefKeyDefaultHomePage) ?? 1).clamp(0, 2);

    // 监听系统亮度变化，跟随系统模式时自动刷新 UI
    _setupBrightnessListener();
  }

  /// 监听系统平台亮度变化，当处于"跟随系统"模式时通知所有监听者刷新 UI。
  ///
  /// 原理：替换 PlatformDispatcher 的亮度变更回调，先执行 Flutter 框架
  /// 原有的变更处理（确保 MediaQuery 等基础设施正常更新），再在跟随系统
  /// 模式下调用 notifyListeners 触发依赖 isDarkMode 的组件重建。
  void _setupBrightnessListener() {
    final binding = WidgetsBinding.instance;
    final previousCallback =
        binding.platformDispatcher.onPlatformBrightnessChanged;
    binding.platformDispatcher.onPlatformBrightnessChanged = () {
      // 先执行 Flutter 框架原有的亮度变更处理
      previousCallback?.call();
      // 跟随系统模式下，系统亮度变化需要通知所有监听者
      if (_themeModeSetting == ThemeModeSetting.system) {
        notifyListeners();
      }
    };
  }

  /// 切换主色调并持久化，同时通知所有监听者刷新 UI。
  Future<void> setPrimaryColor(Color color) async {
    final bool unchanged =
        _primaryColor == color &&
        !_isCustomPreviewEnabled &&
        _customSwitchThumbColor == null;
    if (unchanged) return;

    _primaryColor = color;
    _isCustomPreviewEnabled = false;
    _customSwitchThumbColor = null;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    // ignore: deprecated_member_use
    await prefs.setInt(_prefKey, color.value);
    await prefs.setBool(_prefKeyCustomPreviewEnabled, false);
    await prefs.remove(_prefKeyCustomSwitchThumbColor);
  }

  /// 应用自定义主题颜色，并将弹窗预览效果同步到全局主题。
  Future<void> setCustomThemeColor({
    required Color color,
    required Color switchThumbColor,
  }) async {
    final bool unchanged =
        _primaryColor == color &&
        _isCustomPreviewEnabled &&
        _customSwitchThumbColor == switchThumbColor;
    if (unchanged) return;

    _primaryColor = color;
    _isCustomPreviewEnabled = true;
    _customSwitchThumbColor = switchThumbColor;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    // ignore: deprecated_member_use
    await prefs.setInt(_prefKey, color.value);
    await prefs.setBool(_prefKeyCustomPreviewEnabled, true);
    // ignore: deprecated_member_use
    await prefs.setInt(_prefKeyCustomSwitchThumbColor, switchThumbColor.value);
  }

  /// 根据主色自动推导“白-黑灰阶”中的开关圆点颜色。
  Color _resolveAutoCustomSwitchThumbColor(Color color) {
    final t = color.computeLuminance().clamp(0.0, 1.0);
    return Color.lerp(Colors.white, Colors.black, t)!;
  }

  /// 根据背景色自动推导前景文字颜色（与自定义预览按钮逻辑一致）。
  Color _resolveOnColor(Color backgroundColor) {
    return ThemeData.estimateBrightnessForColor(backgroundColor) ==
            Brightness.dark
        ? Colors.white
        : Colors.black87;
  }

  /// 构建“自定义主题预览效果”对应的输入框样式。
  InputDecorationTheme _buildCustomPreviewInputDecorationTheme({
    required ColorScheme colorScheme,
    required Color fillColor,
  }) {
    return InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryColor.withValues(alpha: 0.35)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryColor.withValues(alpha: 0.35)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _primaryColor, width: 1.6),
      ),
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
    );
  }

  /// 设置主题模式并持久化，通知所有监听者刷新 UI。
  ///
  /// [mode] 可选值：
  /// - [ThemeModeSetting.light]：浅色模式（固定亮色）
  /// - [ThemeModeSetting.system]：跟随系统（自动切换）
  /// - [ThemeModeSetting.dark]：深色模式（固定暗色）
  Future<void> setThemeModeSetting(ThemeModeSetting mode) async {
    if (_themeModeSetting == mode) return;
    _themeModeSetting = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyThemeMode, mode.index);
  }

  /// 设置底部导航栏页面排列顺序并持久化。
  ///
  /// [order] 必须是 [0, 1, 2] 的排列组合，分别对应：
  /// - 0: 课表页面
  /// - 1: 开门页面
  /// - 2: 我的页面
  Future<void> setNavOrder(List<int> order) async {
    if (order.length != 3 || order.toSet().length != 3) return;
    _navOrder = List.from(order);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _prefKeyNavOrder,
      order.map((i) => i.toString()).toList(),
    );
  }

  /// 设置默认启动的主页（原始页面索引：0=课表, 1=开门, 2=我的）。
  Future<void> setDefaultHomePage(int page) async {
    if (page < 0 || page > 2 || page == _defaultHomePage) return;
    _defaultHomePage = page;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefKeyDefaultHomePage, page);
  }

  /// 切换深色模式（兼容旧代码，建议使用 [setThemeModeSetting] 代替）。
  @Deprecated('请使用 setThemeModeSetting 代替')
  Future<void> setDarkMode(bool enabled) async {
    await setThemeModeSetting(
      enabled ? ThemeModeSetting.dark : ThemeModeSetting.light,
    );
  }

  /// 获取当前亮色主题（浅色模式）
  ThemeData get lightTheme {
    if (isWhiteMode) return _buildWhiteTheme();
    return _buildColorTheme(_primaryColor);
  }

  /// 获取当前暗色主题（深色模式）
  ThemeData get darkTheme {
    return _buildDarkTheme();
  }

  /// 获取当前的主题模式枚举，供 MaterialApp.themeMode 使用。
  ///
  /// - [ThemeMode.light]：浅色模式
  /// - [ThemeMode.system]：跟随系统亮度
  /// - [ThemeMode.dark]：深色模式
  ThemeMode get themeMode {
    switch (_themeModeSetting) {
      case ThemeModeSetting.light:
        return ThemeMode.light;
      case ThemeModeSetting.system:
        return ThemeMode.system;
      case ThemeModeSetting.dark:
        return ThemeMode.dark;
    }
  }

  /// 兼容旧代码，根据当前主色和外观模式生成完整的 ThemeData。
  @Deprecated('请优先使用 lightTheme、darkTheme 与 themeMode 组合')
  ThemeData get currentTheme {
    if (isDarkMode) return _buildDarkTheme();
    if (isWhiteMode) return _buildWhiteTheme();
    return _buildColorTheme(_primaryColor);
  }

  // ─────────── 简洁白主题 ───────────
  /// 白色主题：保持 blueGrey 种子色生成 ColorScheme，
  /// icon 用 black87、按钮白底黑字，整体极简。
  ThemeData _buildWhiteTheme() {
    final base = ColorScheme.fromSeed(
      seedColor: Colors.blueGrey,
      brightness: Brightness.light,
    );
    // 简洁白的 primary 仍设为 black87，使 icon/链接等强调色为黑色
    final colorScheme = base.copyWith(
      primary: Colors.black87,
      onPrimary: Colors.white,
      secondary: Colors.grey.shade700,
      onSecondary: Colors.white,
    );

    return _applyCommonLightTheme(
      colorScheme: colorScheme,
      // 简洁白：主按钮白底黑字，带浅灰边框
      elevatedButtonStyle: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        side: BorderSide(color: Colors.grey.shade300),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      // 简洁白 FAB 也为白底黑字
      fabBg: Colors.white,
      fabFg: Colors.black87,
      // Switch 开启时使用较深灰色轨道
      switchActiveTrack: Colors.grey.shade700,
      switchActiveThumb: Colors.white,
    );
  }

  // ─────────── 彩色主题 ───────────
  /// 以用户选定的颜色为种子色的标准 Material 3 亮色主题。
  ThemeData _buildColorTheme(Color seedColor) {
    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
    );
    final bool useCustomPreview = _isCustomPreviewEnabled;
    final Color previewOnPrimary = _resolveOnColor(_primaryColor);
    final colorScheme = useCustomPreview
        ? baseColorScheme.copyWith(
            primary: _primaryColor,
            onPrimary: previewOnPrimary,
            secondary: _primaryColor,
            onSecondary: previewOnPrimary,
          )
        : baseColorScheme;

    final Color resolvedSwitchThumbColor = useCustomPreview
        ? (_customSwitchThumbColor ??
              _resolveAutoCustomSwitchThumbColor(seedColor))
        : colorScheme.onPrimary;

    final ButtonStyle elevatedButtonStyle = useCustomPreview
        ? ElevatedButton.styleFrom(
            backgroundColor: _primaryColor,
            foregroundColor: previewOnPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          );

    ThemeData theme = _applyCommonLightTheme(
      colorScheme: colorScheme,
      elevatedButtonStyle: elevatedButtonStyle,
      fabBg: useCustomPreview ? _primaryColor : colorScheme.primary,
      fabFg: useCustomPreview ? previewOnPrimary : colorScheme.onPrimary,
      switchActiveTrack: useCustomPreview ? _primaryColor : colorScheme.primary,
      switchActiveThumb: resolvedSwitchThumbColor,
    );

    if (!useCustomPreview) {
      return theme;
    }

    return theme.copyWith(
      filledButtonTheme: FilledButtonThemeData(style: elevatedButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _primaryColor,
          side: BorderSide(color: _primaryColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: _buildCustomPreviewInputDecorationTheme(
        colorScheme: colorScheme,
        fillColor: Colors.white,
      ),
    );
  }

  // ─────────── 亮色公共构建器 ───────────
  /// 亮色主题公共部分——卡片、AppBar、输入框、按钮、开关、分割线等统一在此定义，
  /// 保证简洁白与彩色模式共享同一套组件规范。
  ThemeData _applyCommonLightTheme({
    required ColorScheme colorScheme,
    required ButtonStyle elevatedButtonStyle,
    required Color fabBg,
    required Color fabFg,
    required Color switchActiveTrack,
    required Color switchActiveThumb,
  }) {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFF7F8FC),

      // 卡片统一白底圆角
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFFF7F8FC),
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      // 输入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),

      // ElevatedButton（简洁白与彩色共享入口，但 style 不同）
      elevatedButtonTheme: ElevatedButtonThemeData(style: elevatedButtonStyle),

      // FilledButton 与 ElevatedButton 保持一致的视觉风格
      filledButtonTheme: FilledButtonThemeData(style: elevatedButtonStyle),

      // TextButton 主色前景
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),

      // OutlinedButton
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.primary,
          side: const BorderSide(color: Colors.grey),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // Switch
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return switchActiveThumb;
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return switchActiveTrack;
          return colorScheme.surfaceContainerHighest;
        }),
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: fabBg,
        foregroundColor: fabFg,
      ),

      // 分割线
      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),

      // BottomSheet
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      // PopupMenu
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: colorScheme.onSurfaceVariant,
      ),

      // Icon 全局默认色
      iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
    );
  }

  // ─────────── 暗色主题 ───────────
  /// 深色模式——surface 系列固定为 blueGrey 种子生成的暗色底色，
  /// 仅将 primary/secondary/tertiary 强调色替换为用户选定的颜色，
  /// 确保切换颜色时底色保持不变，与浅色模式的行为一致。
  ThemeData _buildDarkTheme() {
    final bool useCustomPreview = _isCustomPreviewEnabled;
    final Color previewOnPrimary = _resolveOnColor(_primaryColor);
    // 固定 blueGrey 作为 surface 底色基础，保证暗色模式底色稳定
    final base = ColorScheme.fromSeed(
      seedColor: Colors.blueGrey,
      brightness: Brightness.dark,
    );
    final ColorScheme colorScheme;
    if (isWhiteMode) {
      colorScheme = base.copyWith(
        primary: Colors.white,
        onPrimary: Colors.black,
        secondary: Colors.grey.shade300,
        onSecondary: Colors.black,
      );
    } else {
      // 用用户选定颜色生成 primary/secondary/tertiary 系列，
      // 但保留 blueGrey 的 surface 底色，避免选色时整体底色变化
      final accent = ColorScheme.fromSeed(
        seedColor: _primaryColor,
        brightness: Brightness.dark,
      );
      colorScheme = base.copyWith(
        primary: useCustomPreview ? _primaryColor : accent.primary,
        onPrimary: useCustomPreview ? previewOnPrimary : accent.onPrimary,
        primaryContainer: accent.primaryContainer,
        onPrimaryContainer: accent.onPrimaryContainer,
        secondary: useCustomPreview ? _primaryColor : accent.secondary,
        onSecondary: useCustomPreview ? previewOnPrimary : accent.onSecondary,
        secondaryContainer: accent.secondaryContainer,
        onSecondaryContainer: accent.onSecondaryContainer,
        tertiary: accent.tertiary,
        onTertiary: accent.onTertiary,
        tertiaryContainer: accent.tertiaryContainer,
        onTertiaryContainer: accent.onTertiaryContainer,
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colorScheme.surface,

      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: useCustomPreview
                ? _primaryColor.withValues(alpha: 0.35)
                : colorScheme.outlineVariant,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: useCustomPreview
                ? _primaryColor.withValues(alpha: 0.35)
                : colorScheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: useCustomPreview ? _primaryColor : colorScheme.primary,
            width: useCustomPreview ? 1.6 : 2,
          ),
        ),
        hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // 乌黑模式：黑底白字，与白天洁白模式的白底黑字形成对称
          backgroundColor: isWhiteMode
              ? Colors.black
              : (useCustomPreview ? _primaryColor : colorScheme.primary),
          foregroundColor: isWhiteMode
              ? Colors.white
              : (useCustomPreview ? previewOnPrimary : colorScheme.onPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      // FilledButton 与 ElevatedButton 保持一致的视觉风格
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isWhiteMode
              ? Colors.black
              : (useCustomPreview ? _primaryColor : colorScheme.primary),
          foregroundColor: isWhiteMode
              ? Colors.white
              : (useCustomPreview ? previewOnPrimary : colorScheme.onPrimary),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: useCustomPreview
              ? _primaryColor
              : colorScheme.primary,
          side: useCustomPreview
              ? BorderSide(color: _primaryColor)
              : const BorderSide(color: Colors.grey),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            // 乌黑模式与白天洁白模式使用相同的开关颜色
            if (isWhiteMode) return Colors.white;
            return _isCustomPreviewEnabled
                ? (_customSwitchThumbColor ??
                      _resolveAutoCustomSwitchThumbColor(_primaryColor))
                : colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            // 乌黑模式与白天洁白模式开关轨道色保持一致
            if (isWhiteMode) return Colors.grey.shade700;
            return useCustomPreview ? _primaryColor : colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: useCustomPreview ? _primaryColor : colorScheme.primary,
        foregroundColor: useCustomPreview
            ? previewOnPrimary
            : colorScheme.onPrimary,
      ),

      dividerTheme: DividerThemeData(color: colorScheme.outlineVariant),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),

      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),

      listTileTheme: ListTileThemeData(
        textColor: colorScheme.onSurface,
        iconColor: isWhiteMode ? Colors.white : colorScheme.onSurfaceVariant,
      ),

      iconTheme: IconThemeData(
        color: isWhiteMode ? Colors.white : colorScheme.onSurfaceVariant,
      ),
    );
  }
}
