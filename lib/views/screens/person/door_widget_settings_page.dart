import 'dart:io';

import 'package:dormdevise/models/door_widget_state.dart';
import 'package:dormdevise/utils/app_toast.dart';
import 'package:dormdevise/widgets/door_desktop_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _NativePinRequestResult {
  const _NativePinRequestResult({
    required this.requestAccepted,
    required this.pinSupported,
    required this.fallbackOpened,
    required this.fallbackType,
  });

  final bool requestAccepted;
  final bool pinSupported;
  final bool fallbackOpened;
  final String fallbackType;

  factory _NativePinRequestResult.fromNative(dynamic value) {
    if (value is bool) {
      return _NativePinRequestResult(
        requestAccepted: value,
        pinSupported: value,
        fallbackOpened: false,
        fallbackType: 'none',
      );
    }

    if (value is Map) {
      return _NativePinRequestResult(
        requestAccepted: value['requestAccepted'] == true,
        pinSupported: value['pinSupported'] == true,
        fallbackOpened: value['fallbackOpened'] == true,
        fallbackType: (value['fallbackType'] as String?) ?? 'none',
      );
    }

    return const _NativePinRequestResult(
      requestAccepted: false,
      pinSupported: false,
      fallbackOpened: false,
      fallbackType: 'none',
    );
  }
}

/// 桌面微件配置页，包含开门组件和课表组件两个Tab。
class DoorWidgetSettingsPage extends StatefulWidget {
  const DoorWidgetSettingsPage({super.key});

  @override
  State<DoorWidgetSettingsPage> createState() => _DoorWidgetSettingsPageState();
}

class _DoorWidgetSettingsPageState extends State<DoorWidgetSettingsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('桌面组件配置'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '开门组件', icon: Icon(Icons.lock_outline_rounded)),
            Tab(text: '课表组件', icon: Icon(Icons.calendar_today_rounded)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [_DoorWidgetTab(), _ScheduleWidgetTab()],
      ),
    );
  }
}

/// 开门组件配置Tab
class _DoorWidgetTab extends StatefulWidget {
  const _DoorWidgetTab();

  @override
  State<_DoorWidgetTab> createState() => _DoorWidgetTabState();
}

class _DoorWidgetTabState extends State<_DoorWidgetTab> {
  static const MethodChannel _homeChannel = MethodChannel(
    'dormdevise/home_widget',
  );
  static const DoorWidgetState _previewState = DoorWidgetState(
    busy: false,
    lastResultSuccess: null,
    lastResultMessage: '待开门',
    lastUpdatedAt: null,
    doorLockStatus: DoorLockStatus.pending,
    deviceStatus: DeviceStatus.online,
    wifiStatus: WifiStatus.unconfigured,
    mqttConnectionStatus: MqttConnectionStatus.failed,
    mqttSubscriptionStatus: MqttSubscriptionStatus.unsubscribed,
  );

  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _requestPinWidget(
    BuildContext context, {
    bool simple = false,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    try {
      final String methodName = simple
          ? 'requestPinDoorSimpleWidget'
          : 'requestPinDoorWidget';
      final dynamic nativeResponse = await _homeChannel.invokeMethod<dynamic>(
        methodName,
      );
      final pinResult = _NativePinRequestResult.fromNative(nativeResponse);
      if (!context.mounted) {
        return;
      }

      if (pinResult.requestAccepted) {
        AppToast.show(
          context,
          '系统添加请求已发起，请在系统弹窗中确认添加。',
          variant: AppToastVariant.success,
        );
        return;
      }

      final (message, variant) = switch (pinResult.fallbackType) {
        'permission' => (
          '已打开系统权限页，请允许桌面快捷方式或桌面组件相关权限后重试。',
          AppToastVariant.warning,
        ),
        'app_details' => (
          '已打开应用信息页，请检查桌面组件相关权限或系统限制后重试。',
          AppToastVariant.warning,
        ),
        'home_screen' => (
          '当前桌面未弹出系统添加窗口，已返回桌面，请长按空白处手动添加组件。',
          AppToastVariant.info,
        ),
        _ when !pinResult.pinSupported || !pinResult.fallbackOpened => (
          '当前桌面暂不支持应用内自动添加，请长按桌面空白处手动添加组件。',
          AppToastVariant.warning,
        ),
        _ => ('当前桌面未响应系统添加请求，请长按桌面空白处手动添加组件。', AppToastVariant.warning),
      };
      AppToast.show(context, message, variant: variant);
    } on PlatformException {
      if (!context.mounted) {
        return;
      }
      AppToast.show(context, '组件添加请求失败，请稍后重试。', variant: AppToastVariant.error);
    }
  }

  Widget _buildPageIndicator(int index, ColorScheme colorScheme) {
    final bool isSelected = _currentPage == index;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: isSelected ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.outline.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 组件预览标题
        Text(
          '组件预览',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '预览为固定示例状态：待开门、设备在线、WiFi非配置、MQTT连接失败',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),

        // 组件预览卡片 - 支持左右滑动
        Card(
          child: Column(
            children: [
              SizedBox(
                height: 256,
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: [
                    // 2x2 完整组件预览
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '完整版',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onPrimaryContainer,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.62,
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                        width: 1,
                                      ),
                                    ),
                                    child: DoorLockWidget(
                                      state: _previewState,
                                      busy: false,
                                      onDoubleTap: null,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 1x1 简洁组件预览
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              '简洁版',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSecondaryContainer,
                              ),
                              textScaler: TextScaler.noScaling,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Expanded(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: 0.24,
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: colorScheme.surfaceContainerLow,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: colorScheme.outlineVariant,
                                        width: 1,
                                      ),
                                    ),
                                    child: _SimpleDoorWidgetPreview(
                                      colorScheme: colorScheme,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 页面指示器
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPageIndicator(0, colorScheme),
                    const SizedBox(width: 8),
                    _buildPageIndicator(1, colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // 添加到桌面按钮
        if (Platform.isAndroid)
          FilledButton.icon(
            onPressed: () =>
                _requestPinWidget(context, simple: _currentPage == 1),
            icon: const Icon(Icons.add_to_home_screen_rounded),
            label: Text(_currentPage == 0 ? '添加完整版到桌面' : '添加简洁版到桌面'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
        if (Platform.isAndroid) const SizedBox(height: 12),
        const SizedBox(height: 24),

        // 使用说明卡片
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '使用小贴士',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 8),
                Text('1. 点击上方按钮或长按桌面空白处添加组件。'),
                Text('2. 双击门锁图标即可静默发送开门指令。'),
                Text('3. 组件每秒自动检测状态变化并更新。'),
                Text('4. 完整版显示 WiFi、MQTT 和设备状态，缩到 1x1 会自动切换紧凑样式。'),
                Text('5. 简洁版只显示门锁图标。'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SimpleDoorWidgetPreview extends StatelessWidget {
  const _SimpleDoorWidgetPreview({required this.colorScheme});

  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surface,
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 19,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 课表组件配置Tab - 暂不实现功能
class _ScheduleWidgetTab extends StatelessWidget {
  const _ScheduleWidgetTab();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ScheduleWidget(),
            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.construction_rounded,
                    size: 32,
                    color: colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '功能开发中',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '课表桌面组件正在开发中，敬请期待！\n该组件将支持在桌面直接查看今日课程安排。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
