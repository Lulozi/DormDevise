import 'dart:io';

import 'package:dormdevise/models/local_door_lock_config.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

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

  /// 扫描附近可见的 WiFi 列表。
  ///
  /// 注意：该能力依赖 Android 的定位权限与定位服务开关，iOS 默认返回空列表。
  Future<List<WifiSnapshot>> scanNearbyWifis({
    bool requestPermission = false,
  }) async {
    if (!Platform.isAndroid) {
      return const <WifiSnapshot>[];
    }

    try {
      if (requestPermission) {
        final status = await Permission.locationWhenInUse.request();
        if (!status.isGranted) {
          return const <WifiSnapshot>[];
        }
      }

      final canStart = await WiFiScan.instance.canStartScan(
        askPermissions: requestPermission,
      );
      if (canStart != CanStartScan.yes) {
        return const <WifiSnapshot>[];
      }

      await WiFiScan.instance.startScan();
      final canGet = await WiFiScan.instance.canGetScannedResults(
        askPermissions: requestPermission,
      );
      if (canGet != CanGetScannedResults.yes) {
        return const <WifiSnapshot>[];
      }

      final points = await WiFiScan.instance.getScannedResults();
      final seen = <String>{};
      final snapshots = <WifiSnapshot>[];

      for (final point in points) {
        final ssid = LocalDoorLockConfig.normalizeWifiValue(point.ssid);
        final bssid = LocalDoorLockConfig.normalizeWifiValue(point.bssid);
        final identity = bssid.isNotEmpty ? bssid : ssid;
        if (identity.isEmpty || seen.contains(identity)) {
          continue;
        }
        seen.add(identity);
        snapshots.add(WifiSnapshot(ssid: ssid, bssid: bssid));
      }

      return snapshots;
    } catch (_) {
      return const <WifiSnapshot>[];
    }
  }

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
