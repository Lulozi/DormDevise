# 设舍

DormDevise 是一个为宿舍管理和服务而开发的 Flutter 应用，支持多平台（Android、iOS、Web、Windows、Linux、macOS）。

## 功能简介

- 基于MTQQ的门锁开关
- 个人信息页面
- ~~课程表~~
- ~~以及他们的桌面组件~~

## 主要依赖

- [flutter](https://flutter.dev/)
- [mqtt_client](https://pub.dev/packages/mqtt_client)
- [shared_preferences](https://pub.dev/packages/shared_preferences)
- [cached_network_image](https://pub.dev/packages/cached_network_image)
- [file_picker](https://pub.dev/packages/file_picker)
- [uuid](https://pub.dev/packages/uuid)
- [package_info_plus](https://pub.dev/packages/package_info_plus)

## 快速开始

1. 克隆项目：

   ```bash
   git clone <your-repo-url>
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

## 目录结构

- `lib/` 主要源码目录
  - `main.dart` 应用入口
  - `manage_screen.dart` 管理主界面
  - `screen/` 各功能页面
   - `personPage/` 个人信息相关页面
   - `openDoorPage/` 开门相关页面
   - `tablePage/` 课程表相关页面
- `android/`、`ios/`、`web/`、`windows/`、`linux/`、`macos/` 各平台工程目录
- `test/` 单元测试

## 更新日志

<details>
<summary>📜 版本更迭史</summary>

### ~~v0.0.1~~

- 构建门锁开关页面，个人页面，课表页面
- 初始化门锁开关动画
- 添加mqtt配置页面
- 完善门锁开关功能

### v0.1.0

- 重绘门锁动画
- 初始构建个人页面
- mqtt配置页面迁移



## License

© 2025 DormDevise. All rights reserved.
