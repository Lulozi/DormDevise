import 'dart:async';
import 'dart:convert';

import 'package:dormdevise/models/door_widget_settings.dart';
import 'package:dormdevise/models/door_widget_state.dart';
import 'package:dormdevise/services/door_trigger_service.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 管理桌面微件生命周期、数据持久化与交互回调的核心服务。
class DoorWidgetService {
  DoorWidgetService._();

  /// 提供全局单例，方便在应用内统一调度。
  static final DoorWidgetService instance = DoorWidgetService._();

  static const String _settingsPrefKey = 'door_widget_settings';
  static const String _statePrefKey = 'door_widget_state';
  static const String _hwBusyKey = 'door_widget_busy';
  static const String _hwMessageKey = 'door_widget_message';
  static const String _hwSuccessKey = 'door_widget_last_success';
  static const String _hwUpdatedKey = 'door_widget_updated_at';
  static const String _hwHintKey = 'door_widget_hint';
  static const String _androidProviderQualified =
      'com.lulo.dormdevise.DoorWidgetProvider';
  static const String _androidProviderName = 'DoorWidgetProvider';

  DoorWidgetSettings _settings = DoorWidgetSettings.defaults();
  DoorWidgetState _state = DoorWidgetState.initial();
  bool _initialized = false;
  bool _hasHydrated = false;
  Timer? _autoRefreshTimer;
  StreamSubscription<Uri?>? _widgetClickSubscription;
  final StreamController<Uri?> _launchEventsController =
      StreamController<Uri?>.broadcast();
  Uri? _latestLaunchUri;
  Timer? _successResetTimer;

  /// 对外暴露的可监听状态，便于设置页面实时刷新。
  final ValueNotifier<DoorWidgetState> stateNotifier =
      ValueNotifier<DoorWidgetState>(DoorWidgetState.initial());

  /// 提供桌面微件唤起应用时的 URI 事件流。
  Stream<Uri?> get launchEvents => _launchEventsController.stream;

  /// 读取最近一次微件唤起 URI，并在读取后清空缓存，防止重复触发。
  Uri? takeLatestLaunchUri() {
    final Uri? result = _latestLaunchUri;
    _latestLaunchUri = null;
    return result;
  }

  DoorWidgetSettings get settings => _settings;
  DoorWidgetState get state => _state;

  /// 初始化桌面微件运行所需的资源与监听。
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    WidgetsFlutterBinding.ensureInitialized();
    await _ensureLoaded();
    stateNotifier.value = _state;
    await HomeWidget.registerInteractivityCallback(
      doorWidgetBackgroundCallback,
    );
    _listenWidgetLaunches();
    await _persistSettingsToWidget();
    await _persistStateToWidget();
    await syncWidget();
    _scheduleAutoRefresh();
    _initialized = true;
  }

  /// 释放桌面微件相关资源，供应用退出时调用。
  Future<void> dispose() async {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
    _successResetTimer?.cancel();
    _successResetTimer = null;
    _hasHydrated = false;
    await _widgetClickSubscription?.cancel();
    await _launchEventsController.close();
    _latestLaunchUri = null;
  }

  /// 更新桌面微件设置项并持久化。
  Future<void> updateSettings(DoorWidgetSettings newSettings) async {
    await _ensureLoaded();
    _settings = newSettings;
    await _saveSettings();
    await _persistSettingsToWidget();
    _scheduleAutoRefresh();
    await syncWidget();
  }

  /// 通知桌面微件进入忙碌态，后续将触发 UI 切换。
  Future<void> markManualTriggerStart() async {
    await _ensureLoaded();
    _successResetTimer?.cancel();
    _state = _state.copyWith(
      busy: true,
      lastResultMessage: '正在开门，请稍候…',
      lastResultSuccess: null,
    );
    stateNotifier.value = _state;
    await _saveState();
    await _persistStateToWidget();
    await syncWidget();
  }

  /// 将开门结果同步到桌面微件，用于展示开门反馈。
  Future<void> recordManualTriggerResult(DoorTriggerResult result) async {
    await _ensureLoaded();
    _successResetTimer?.cancel();
    final String displayMessage = result.success
        ? '开门成功'
        : (result.message.isNotEmpty ? result.message : '开门失败');
    _state = _state.copyWith(
      busy: false,
      lastResultSuccess: result.success,
      lastResultMessage: displayMessage,
      lastUpdatedAt: DateTime.now(),
    );
    stateNotifier.value = _state;
    await _saveState();
    await _persistStateToWidget();
    await syncWidget();
    if (result.success) {
      _scheduleSuccessReset();
    }
  }

  /// 主动刷新桌面微件展示的数据。
  Future<void> syncWidget() async {
    try {
      await HomeWidget.updateWidget(
        name: _androidProviderName,
        qualifiedAndroidName: _androidProviderQualified,
      );
    } catch (err, stackTrace) {
      debugPrint('刷新桌面微件失败: $err\n$stackTrace');
    }
  }

  /// 处理桌面微件发起的交互请求，例如滑动开门或手动刷新。
  Future<void> handleWidgetInteraction(Uri? uri) async {
    if (uri == null || uri.host != 'door_widget' || uri.pathSegments.isEmpty) {
      return;
    }
    await _ensureLoaded();
    final String action = uri.pathSegments.first;
    switch (action) {
      case 'open':
        if (_state.busy) {
          return;
        }
        await markManualTriggerStart();
        final DoorTriggerResult result = await DoorTriggerService.instance
            .triggerDoor();
        await recordManualTriggerResult(result);
        break;
      case 'refresh':
        await _persistSettingsToWidget();
        await _persistStateToWidget();
        await syncWidget();
        break;
      default:
        break;
    }
  }

  Future<void> _ensureLoaded() async {
    if (_hasHydrated) {
      return;
    }
    _settings = await _loadSettings();
    _state = await _loadState();
    _hasHydrated = true;
  }

  void _listenWidgetLaunches() {
    HomeWidget.initiallyLaunchedFromHomeWidget().then(_handleLaunchUri);
    _widgetClickSubscription = HomeWidget.widgetClicked.listen(
      _handleLaunchUri,
    );
  }

  void _handleLaunchUri(Uri? uri) {
    if (uri == null || uri.host != 'door_widget') {
      return;
    }
    _latestLaunchUri = uri;
    _launchEventsController.add(uri);
  }

  Future<DoorWidgetSettings> _loadSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_settingsPrefKey);
    if (raw == null || raw.isEmpty) {
      return DoorWidgetSettings.defaults();
    }
    try {
      final Map<String, dynamic> map =
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>();
      return DoorWidgetSettings.fromMap(map);
    } catch (_) {
      return DoorWidgetSettings.defaults();
    }
  }

  Future<void> _saveSettings() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsPrefKey, jsonEncode(_settings.toMap()));
  }

  Future<DoorWidgetState> _loadState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? raw = prefs.getString(_statePrefKey);
    if (raw == null || raw.isEmpty) {
      return DoorWidgetState.initial();
    }
    try {
      final Map<String, dynamic> map =
          (jsonDecode(raw) as Map<dynamic, dynamic>).cast<String, dynamic>();
      return DoorWidgetState.fromMap(map);
    } catch (_) {
      return DoorWidgetState.initial();
    }
  }

  Future<void> _saveState() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_statePrefKey, jsonEncode(_state.toMap()));
  }

  Future<void> _persistSettingsToWidget() async {
    final List<Future<bool?>> futures = [
      HomeWidget.saveWidgetData<bool>(
        'door_widget_setting_show_result',
        _settings.showLastResult,
      ),
      HomeWidget.saveWidgetData<bool>(
        'door_widget_setting_haptics',
        _settings.enableHaptics,
      ),
      HomeWidget.saveWidgetData<bool>(
        'door_widget_setting_auto_refresh',
        _settings.autoRefreshEnabled,
      ),
      HomeWidget.saveWidgetData<int>(
        'door_widget_setting_auto_refresh_minutes',
        _settings.autoRefreshMinutes,
      ),
    ];
    await Future.wait(futures);
  }

  Future<void> _persistStateToWidget() async {
    final List<Future<bool?>> futures = [
      HomeWidget.saveWidgetData<bool>(_hwBusyKey, _state.busy),
      HomeWidget.saveWidgetData<String>(_hwMessageKey, _composeWidgetMessage()),
      HomeWidget.saveWidgetData<bool?>(_hwSuccessKey, _state.lastResultSuccess),
      HomeWidget.saveWidgetData<String?>(
        _hwUpdatedKey,
        _state.lastUpdatedAt?.toIso8601String(),
      ),
      HomeWidget.saveWidgetData<String>(
        _hwHintKey,
        _state.busy ? '正在处理，请稍候' : '轻点以打开滑动弹窗',
      ),
    ];
    await Future.wait(futures);
  }

  String _composeWidgetMessage() {
    if (_state.busy) {
      return '正在开门…';
    }
    if (!_settings.showLastResult ||
        _state.lastResultMessage == null ||
        _state.lastResultMessage!.isEmpty) {
      return '未开门';
    }
    if (_state.lastResultSuccess == true) {
      return _state.lastResultMessage!;
    }
    final String timestamp = _state.lastUpdatedAt != null
        ? _formatTimestamp(_state.lastUpdatedAt!)
        : '';
    final String suffix = timestamp.isEmpty ? '' : ' · $timestamp';
    return _state.lastResultMessage! + suffix;
  }

  String _formatTimestamp(DateTime value) {
    final List<String> parts = <String>[
      value.month.toString().padLeft(2, '0'),
      value.day.toString().padLeft(2, '0'),
    ];
    final List<String> time = <String>[
      value.hour.toString().padLeft(2, '0'),
      value.minute.toString().padLeft(2, '0'),
    ];
    return '${parts.join('-')} ${time.join(':')}';
  }

  void _scheduleAutoRefresh() {
    _autoRefreshTimer?.cancel();
    if (!_settings.autoRefreshEnabled || _settings.autoRefreshMinutes <= 0) {
      return;
    }
    _autoRefreshTimer = Timer.periodic(
      Duration(minutes: _settings.autoRefreshMinutes),
      (_) async {
        await _persistStateToWidget();
        await syncWidget();
      },
    );
  }

  /// 成功开门后延时恢复默认提示，保持微件状态清爽。
  void _scheduleSuccessReset() {
    _successResetTimer?.cancel();
    _successResetTimer = Timer(const Duration(seconds: 3), () async {
      await _ensureLoaded();
      if (_state.busy) {
        return;
      }
      _state = _state.copyWith(
        lastResultSuccess: null,
        lastResultMessage: null,
      );
      stateNotifier.value = _state;
      await _saveState();
      await _persistStateToWidget();
      await syncWidget();
    });
  }
}

/// 桌面微件交互回调入口，需保持顶层函数以便原生侧正确定位。
@pragma('vm:entry-point')
Future<void> doorWidgetBackgroundCallback(Uri? data) async {
  WidgetsFlutterBinding.ensureInitialized();
  await DoorWidgetService.instance.handleWidgetInteraction(data);
}
