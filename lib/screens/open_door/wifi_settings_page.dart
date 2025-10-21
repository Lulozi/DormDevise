import 'dart:async';
import 'dart:io';

import 'package:dormdevise/utils/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:plugin_wifi_connect/plugin_wifi_connect.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wifi_scan/wifi_scan.dart';

const _ssidPrefKey = 'preferred_wifi_ssid';
const _passwordPrefKey = 'preferred_wifi_password';

/// WiFi 网络配置页面，支持扫描、保存与连接。
class WifiSettingsPage extends StatefulWidget {
  const WifiSettingsPage({super.key});

  /// 创建页面状态以处理交互逻辑。
  @override
  State<WifiSettingsPage> createState() => _WifiSettingsPageState();
}

class _WifiSettingsPageState extends State<WifiSettingsPage> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  String? _savedSsid;
  String? _savedPassword;
  bool _loading = false;
  bool _connecting = false;
  bool _disconnecting = false;
  bool _obscurePassword = true;
  List<WiFiAccessPoint> _aps = [];
  bool _pluginRegistered = false;
  Future<void>? _registeringFuture;
  bool _warnedMissingPlugin = false;
  String? _connectStatusMessage;
  bool _connectStatusIsError = false;
  String? _connectStatusActionLabel;
  VoidCallback? _connectStatusAction;

  /// 初始化监听器并恢复历史保存的网络信息。
  @override
  void initState() {
    super.initState();
    _ssidController.addListener(_refreshState);
    _passwordController.addListener(_refreshState);
    _loadSaved();
  }

  /// 刷新状态以更新界面按钮可用性。
  void _refreshState() => setState(() {});

  /// 从本地存储恢复历史的 WiFi 凭据。
  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final ssid = prefs.getString(_ssidPrefKey);
    final password = prefs.getString(_passwordPrefKey);
    if (!mounted) return;
    _ssidController.text = ssid ?? '';
    _passwordController.text = password ?? '';
    setState(() {
      _savedSsid = ssid;
      _savedPassword = password;
    });
  }

  /// 判断当前是否填写了合法的 SSID。
  bool get _isSsidFilled => _ssidController.text.trim().isNotEmpty;

  /// 保存与连接操作是否可执行。
  bool get _canSubmit => _isSsidFilled;

  /// 执行 WiFi 扫描并展示结果列表。
  Future<void> _scan() async {
    if (!await _ensureWifiScanPermissions()) {
      if (!mounted) return;
      AppToast.show(
        context,
        '请先授予 Wi-Fi 扫描所需的权限',
        variant: AppToastVariant.warning,
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final can = await WiFiScan.instance.canGetScannedResults();
      if (can != CanGetScannedResults.yes) {
        throw Exception('当前设备或系统设置不允许获取WiFi扫描结果(状态: $can)，请检查是否已开启WiFi');
      }
      final canScan = await WiFiScan.instance.canStartScan();
      if (canScan == CanStartScan.yes) {
        await WiFiScan.instance.startScan();
        await Future.delayed(const Duration(seconds: 1));
      } else {
        throw Exception('无法开始扫描WiFi(状态: $canScan)，请确认已开启WiFi并授予所需权限');
      }
      final results = await WiFiScan.instance.getScannedResults();
      results.sort((a, b) => b.level.compareTo(a.level));
      if (!mounted) return;
      setState(() => _aps = results);
      await _showPickSheet();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, '扫描失败: $e', variant: AppToastVariant.error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 展示 WiFi 列表供用户选择。
  Future<void> _showPickSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<WiFiAccessPoint>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        if (_aps.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('未发现可用WiFi')),
          );
        }
        final cs = Theme.of(ctx).colorScheme;
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: _aps.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final ap = _aps[i];
            final ssid = ap.ssid.isNotEmpty ? ap.ssid : '(隐藏网络)';
            final isSelected =
                (_savedSsid != null && _savedSsid == ap.ssid) ||
                _ssidController.text.trim() == ap.ssid;
            return ListTile(
              leading: const Icon(Icons.wifi),
              title: Text(ssid),
              subtitle: Text('强度: ${ap.level}  •  频率: ${ap.frequency}MHz'),
              trailing: isSelected
                  ? Icon(Icons.check, color: cs.primary)
                  : null,
              onTap: () {
                Navigator.of(ctx).pop(ap);
                _ssidController.text = ap.ssid;
                _passwordController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _passwordController.text.length),
                );
              },
            );
          },
        );
      },
    );
  }

  /// 将当前输入的网络信息持久化到本地。
  Future<void> _save({bool showStatus = true}) async {
    final value = _ssidController.text.trim();
    final password = _passwordController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ssidPrefKey, value);
    if (password.isEmpty) {
      await prefs.remove(_passwordPrefKey);
    } else {
      await prefs.setString(_passwordPrefKey, password);
    }
    if (!mounted) return;
    setState(() {
      _savedSsid = value;
      _savedPassword = password.isEmpty ? null : password;
    });
    if (showStatus) {
      _showConnectStatus('已保存WiFi: $value');
    }
  }

  /// 校验所需的定位与邻近 WiFi 权限是否就绪。
  Future<bool> _ensureWifiScanPermissions() async {
    if (!Platform.isAndroid) {
      return true;
    }

    /// 助手方法：请求指定权限并返回最终状态。
    Future<bool> requestPermission(Permission permission) async {
      var status = await permission.status;
      if (status.isGranted) {
        return true;
      }
      if (status.isDenied || status.isLimited) {
        status = await permission.request();
        if (status.isGranted) {
          return true;
        }
      }
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
      return false;
    }

    final locationGranted = await requestPermission(
      Permission.locationWhenInUse,
    );
    if (!locationGranted) {
      return false;
    }

    final nearbyPermission = Permission.nearbyWifiDevices;
    final nearbyGranted = await requestPermission(nearbyPermission);
    return nearbyGranted;
  }

  /// 确保插件已完成注册，避免调用异常。
  Future<bool> _ensurePluginRegistered() async {
    if (_pluginRegistered) {
      return true;
    }
    if (_registeringFuture != null) {
      try {
        await _registeringFuture;
      } catch (_) {
        return false;
      }
      return _pluginRegistered;
    }
    final completer = Completer<void>();
    _registeringFuture = completer.future;
    try {
      try {
        await PluginWifiConnect.unregister();
      } catch (_) {}
      await PluginWifiConnect.register();
      _pluginRegistered = true;
      completer.complete();
      return true;
    } on MissingPluginException catch (_) {
      _handleMissingPlugin('注册 WiFi 回调');
      return false;
    } catch (e) {
      completer.completeError(e);
      _showConnectStatus('注册WiFi回调失败: $e', isError: true);
      return false;
    } finally {
      _registeringFuture = null;
    }
  }

  /// 使用保存的凭据尝试连接目标网络。
  Future<void> _connectToSavedNetwork(String target) async {
    if (!await _ensurePluginRegistered()) {
      if (!_warnedMissingPlugin) {
        _showConnectStatus('无法连接到WiFi，请稍后重试', isError: true);
      }
      return;
    }
    final password = _savedPassword?.trim() ?? '';
    var retried = false;
    while (true) {
      try {
        final bool? success = password.isEmpty
            ? await PluginWifiConnect.connect(target, saveNetwork: true)
            : await PluginWifiConnect.connectToSecureNetwork(
                target,
                password,
                saveNetwork: true,
              );
        final message = success == true
            ? '已尝试连接: $target'
            : '连接 $target 失败，请重试';
        _showConnectStatus(message, isError: success != true);
        return;
      } on MissingPluginException catch (_) {
        _handleMissingPlugin('连接 WiFi');
        _showConnectStatus(
          '当前构建缺少 plugin_wifi_connect 的原生实现，无法自动连接到WiFi',
          isError: true,
        );
        return;
      } on PlatformException catch (e) {
        final msg = e.message ?? '';
        final needRetry = msg.contains('NetworkCallback was not registered');
        final needsWriteSettings = msg.contains('WRITE_SETTINGS');
        if (!retried && needRetry) {
          await _teardownPlugin();
          retried = true;
          if (await _ensurePluginRegistered()) {
            continue;
          }
        }
        if (needsWriteSettings) {
          _showConnectStatus(
            '需要授予“修改系统设置”权限后才能连接到WiFi',
            isError: true,
            actionLabel: '去设置',
            action: () {
              openAppSettings();
            },
          );
        } else {
          _showConnectStatus('连接失败: $msg', isError: true);
        }
        return;
      } catch (e) {
        _showConnectStatus('连接失败: $e', isError: true);
        return;
      }
    }
  }

  /// 请求插件断开当前 WiFi 连接。
  Future<void> _disconnectFromCurrentNetwork() async {
    try {
      final bool? success = await PluginWifiConnect.disconnect();
      if (success == false) {
        _showConnectStatus('断开失败，请在系统设置中重试', isError: true);
      } else {
        _showConnectStatus('已请求断开当前WiFi');
      }
    } on MissingPluginException catch (_) {
      _handleMissingPlugin('断开 WiFi');
      _showConnectStatus(
        '当前构建缺少 plugin_wifi_connect 的原生实现，无法自动断开WiFi',
        isError: true,
      );
    } on PlatformException catch (e) {
      final msg = e.message ?? '未知错误';
      _showConnectStatus('断开失败: $msg', isError: true);
    } catch (e) {
      _showConnectStatus('断开失败: $e', isError: true);
    }
  }

  /// 注销插件回调并重置标记。
  Future<void> _teardownPlugin() async {
    if (!_pluginRegistered) return;
    try {
      await PluginWifiConnect.unregister();
    } catch (_) {
    } finally {
      _pluginRegistered = false;
    }
  }

  /// 更新连接结果提示文案与可选操作。
  void _showConnectStatus(
    String message, {
    bool isError = false,
    String? actionLabel,
    VoidCallback? action,
  }) {
    if (!mounted) {
      return;
    }
    setState(() {
      _connectStatusMessage = message;
      _connectStatusIsError = isError;
      _connectStatusActionLabel = actionLabel;
      _connectStatusAction = action;
    });
  }

  /// 记录缺失插件实现的情况并提示用户。
  void _handleMissingPlugin(String action) {
    if (!mounted) {
      return;
    }
    if (!_warnedMissingPlugin) {
      _warnedMissingPlugin = true;
      _showConnectStatus(
        '当前构建缺少 plugin_wifi_connect 的原生实现，无法自动$action',
        isError: true,
      );
    }
  }

  /// 清理控制器监听并注销插件。
  @override
  void dispose() {
    _ssidController.removeListener(_refreshState);
    _passwordController.removeListener(_refreshState);
    _ssidController.dispose();
    _passwordController.dispose();
    unawaited(_teardownPlugin());
    super.dispose();
  }

  /// 绘制 WiFi 管理表单与操作按钮。
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.outlineVariant),
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('WiFi设置')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_savedSsid?.isNotEmpty == true)
              Card(
                color: colorScheme.secondaryContainer,
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text('已保存的WiFi: ${_savedSsid!}'),
                  subtitle: Text(
                    _savedPassword?.isNotEmpty == true ? '密码已保存' : '未设置密码',
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _ssidController,
              decoration: InputDecoration(
                labelText: 'WiFi名称',
                border: inputBorder,
                prefixIcon: const Icon(Icons.wifi),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (_ssidController.text.trim().isNotEmpty) {
                  _save();
                }
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'WiFi密码',
                border: inputBorder,
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: _obscurePassword ? '显示密码' : '隐藏密码',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _scan,
                    icon: const Icon(Icons.wifi_find),
                    label: Text(_loading ? '正在扫描...' : '选择扫描到的WiFi'),
                    style: FilledButton.styleFrom(
                      shape: buttonShape,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canSubmit ? _save : null,
                    icon: const Icon(Icons.save_outlined),
                    label: const Text('保存WiFi'),
                    style: OutlinedButton.styleFrom(
                      shape: buttonShape,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _canSubmit && !_connecting
                        ? () async {
                            await _save(showStatus: false);
                            final target = _savedSsid?.trim();
                            if (target == null || target.isEmpty) {
                              return;
                            }
                            if (mounted) {
                              setState(() {
                                _connecting = true;
                                _connectStatusMessage = '正在尝试连接...';
                                _connectStatusIsError = false;
                                _connectStatusActionLabel = null;
                                _connectStatusAction = null;
                              });
                            }
                            try {
                              await _connectToSavedNetwork(target);
                            } finally {
                              if (mounted) {
                                setState(() => _connecting = false);
                              }
                            }
                          }
                        : null,
                    icon: Icon(
                      _connecting ? Icons.hourglass_top : Icons.wifi_lock,
                    ),
                    label: Text(_connecting ? '正在连接...' : '连接当前WiFi'),
                    style: FilledButton.styleFrom(
                      shape: buttonShape,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: !_canSubmit || _disconnecting
                        ? null
                        : () async {
                            if (mounted) {
                              setState(() {
                                _disconnecting = true;
                                _connectStatusMessage = '正在断开当前WiFi...';
                                _connectStatusIsError = false;
                                _connectStatusActionLabel = null;
                                _connectStatusAction = null;
                              });
                            }
                            try {
                              await _disconnectFromCurrentNetwork();
                            } finally {
                              if (mounted) {
                                setState(() => _disconnecting = false);
                              }
                            }
                          },
                    icon: Icon(
                      _disconnecting ? Icons.hourglass_bottom : Icons.wifi_off,
                    ),
                    label: Text(_disconnecting ? '正在断开...' : '断开当前WiFi'),
                    style: OutlinedButton.styleFrom(
                      shape: buttonShape,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _connectStatusMessage == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey(
                        '${_connectStatusMessage}_${_connectStatusIsError}_${_connectStatusActionLabel ?? ''}',
                      ),
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _connectStatusIsError
                              ? colorScheme.errorContainer
                              : colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _connectStatusIsError
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                              color: _connectStatusIsError
                                  ? colorScheme.onErrorContainer
                                  : colorScheme.onSecondaryContainer,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _connectStatusMessage!,
                                style: TextStyle(
                                  color: _connectStatusIsError
                                      ? colorScheme.onErrorContainer
                                      : colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                            if (_connectStatusActionLabel != null &&
                                _connectStatusAction != null)
                              TextButton(
                                onPressed: _connectStatusAction,
                                style: TextButton.styleFrom(
                                  foregroundColor: _connectStatusIsError
                                      ? colorScheme.onErrorContainer
                                      : colorScheme.onSecondaryContainer,
                                ),
                                child: Text(_connectStatusActionLabel!),
                              ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
