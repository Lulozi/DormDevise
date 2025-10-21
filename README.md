# 设舍

[中文](README.md)  |  [English](README_en.md)

DormDevise 是一款面向宿舍场景的 Flutter 跨平台应用，当前适配 Android（其他平台未进行打包及测试）。

## 功能特性

- 基于 MQTT 的智能门锁控制，支持动画反馈、长按进入高级设置与操作节流。
- Wi-Fi 网络配置向导，可扫描周边热点、保存常用凭据并快速连接。
- MQTT 连接管理中心，支持 TLS 证书配置、主题订阅调试与消息实时预览。
- 个人中心整合开门、网络、定位、关于等设置，并内置版本更新检测与下载流程。
- ~~课程表页面占位~~，预留后续接入课程数据与桌面组件的能力。

## 主要依赖

- [flutter](https://flutter.dev/)
- [mqtt_client](https://pub.dev/packages/mqtt_client)
- [shared_preferences](https://pub.dev/packages/shared_preferences)
- [cached_network_image](https://pub.dev/packages/cached_network_image)
- [file_picker](https://pub.dev/packages/file_picker)
- [uuid](https://pub.dev/packages/uuid)
- [package_info_plus](https://pub.dev/packages/package_info_plus)
- [wifi_scan](https://pub.dev/packages/wifi_scan)
- [permission_handler](https://pub.dev/packages/permission_handler)

## 快速开始

1. 克隆项目：

   ```bash
   git clone https://github.com/Lulozi/DormDevise.git
   cd dormdevise
   ```

2. 安装依赖：

   ```bash
   flutter pub get
   ```

3. 运行项目：

   ```bash
   flutter run
   ```

4. 首次启动后，在应用内完成 Wi-Fi 与 MQTT 配置，即可进行开门测试。

## 配置说明

- **Wi-Fi 设置**：支持扫描周边网络并保存 SSID/密码；如扫描失败，请确认设备已授予定位与附近设备权限。
- **MQTT 设置**：可配置主机、端口、主题、客户端 ID、用户名密码以及 TLS 证书；提供主题调试面板与状态订阅预览。
- **定位设置**：当前为占位页面，后续将扩展室内定位或地理围栏能力。
- **版本更新**：关于页内置版本检测、APK 下载与安装流程，下载任务状态由单例协调器统一管理。

## 目录结构

- `lib/`
  - `main.dart`：应用入口与全局 Provider 初始化。
  - `app.dart`：应用壳、底部导航与页面容器。
  - `screens/open_door/`：门锁控制主界面及 Wi-Fi、MQTT、定位等配置页。
  - `screens/person/`：个人中心、关于页面与配套动画组件。
  - `screens/table/`：课程表占位页面。
  - `services/mqtt_service.dart`：MQTT 封装服务，支持发布、订阅与请求-响应模式。
  - `utils/app_toast.dart`：全局 Toast 工具。
- `android/`、`ios/`、`web/`、`windows/`、`linux/`、`macos/`：各平台工程与构建脚本。
- `test/`：测试样例（默认 Flutter 示例，可按需扩展）。

## 注意事项

- Android 端 Wi-Fi 扫描需要定位权限与附近设备权限；若被永久拒绝，请在系统设置中手动开启。
- 使用 TLS 连接时，请确保证书文件路径正确且具备读权限，必要时可通过应用内的文件选择器导入。
- MQTT Topic 订阅调试默认会记录最近一次订阅主题，可在设置页清除。
- 若在桌面端或 Web 上运行，部分硬件特性（如 Wi-Fi 扫描、APK 下载）可能不可用。

## 更新日志

<details>

	<summary>📜 版本更迭史</summary>

   ### V0.5.0

   - 提炼展开动画为统一接口
   - 优化主页滑动动画逻辑
   - 重构文件结构，使得更符合规范

   ### v0.4.6
   - 全面补充中文注释并梳理文件结构，提升可维护性
   - 优化主页折叠动画与滑动体验，统一交互节奏

   ### v0.4.5
   - 全面补充中文注释并梳理文件结构，提升可维护性
   - 优化主页折叠动画与滑动体验，统一交互节奏

   ### v0.4.4
   - 新增设备 ABI 检测逻辑，自动匹配适配的安装包
   - 优化外部链接处理与权限提示，增强可用性

   ### v0.4.3
   - 修复后台下载返回页面后动画状态不同步的问题
   - 调整底部弹窗样式并更新依赖，统一 UI 视觉

   ### v0.4.2
   - 修复下载完成未自动跳转安装的问题
   - 新增允许安装未知来源应用的权限配置

   ### v0.4.1
   - 修复 WebView 弹窗无法滚动的问题
   - 统一开源许可页面弹窗呈现方式

   ### v0.4.0
   - 重构关于页面结构，加入开源许可与新图标
   - 引入许可证查看与文件相关插件，完善信息展示

   ### v0.3.4
   - 扩展关于页面内容并更新相关插件

   ### v0.3.3
   - 为状态主题添加展开动画及联想词体验
   - 调整多处展开效果以保持一致性

   ### v0.3.2
   - 统一多平台 UI，优化界面一致性

   ### v0.3.1
   - 引入状态主题订阅与重定向逻辑，支持断开 Wi-Fi
   - 持续完善综合设置页面入口

   ### v0.3.0
   - 新增 Wi-Fi 设置流程，补充权限配置与插件
   - 优化扫描保存与位置设置入口

   ### v0.2.6
   - 增加开门按钮动画与长按设置重定向

   ### v0.2.5
   - 修复重新打开应用偶现白屏问题
   - 优化启动阶段权限与动画体验

   ### v0.2.4
   - 新增联网权限，确保 MQTT 与网络请求可用

   ### v0.2.3
   - 继续优化开门按钮动画表现

   ### v0.2.2
   - 重构文件命名并统一图标资源

   ### v0.2.1
   - 修复应用首屏空白问题

   ### v0.2.0
   - 完成开门主页面动画与页面切换逻辑
   - 支持自动命名 APK，完善构建流程

   ### v0.1.0
   - 重绘门锁动画
   - 初始构建个人页面
   - MQTT 配置页面迁移

</details>


## License

© 2025 DormDevise. All rights reserved.
