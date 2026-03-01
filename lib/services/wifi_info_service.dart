import 'dart:io';

import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// 当前连接的 WiFi 快照。
class WifiSnapshot {
  /// 当前 WiFi 名称（SSID）。
  final String ssid;

  /// 当前 WiFi BSSID（路由器 MAC）。
  final String bssid;

  const WifiSnapshot({this.ssid = '', this.bssid = ''});

  /// 是否拿到了可用于匹配的有效信息。
  bool get hasValidValue => ssid.isNotEmpty || bssid.isNotEmpty;
}

/// WiFi 信息查询服务。
class WifiInfoService {
  WifiInfoService._();

  /// 全局单例。
  static final WifiInfoService instance = WifiInfoService._();

  final NetworkInfo _networkInfo = NetworkInfo();

  /// 读取当前连接 WiFi。
  ///
  /// [requestPermission] 为 true 时，会在 Android 上尝试申请定位权限。
  Future<WifiSnapshot> getCurrentWifi({bool requestPermission = false}) async {
    try {
      if (requestPermission && Platform.isAndroid) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          return const WifiSnapshot();
        }
      }

      final ssid = LocalDoorLockConfig.normalizeWifiValue(
        await _networkInfo.getWifiName(),
      );
      final bssid = LocalDoorLockConfig.normalizeWifiValue(
        await _networkInfo.getWifiBSSID(),
      );
      return WifiSnapshot(ssid: ssid, bssid: bssid);
    } catch (_) {
      return const WifiSnapshot();
    }
  }
}
