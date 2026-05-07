# DormDevise —— 智慧宿舍管理

<div align="center">

[![Flutter](https://img.shields.io/badge/Flutter-3.31+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.9+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-lightgrey)]()

**一站式管理宿舍课表、智能门锁与桌面组件**

[English](README_en.md) | [中文](README.md)

</div>

---

## 📖 目录

- [功能概览](#-功能概览)
- [📸 界面展示](#-界面展示)
- [🏗️ 项目架构](#️-项目架构)
- [🚀 快速开始](#-快速开始)
- [📦 核心依赖](#-核心依赖)
- [⚙️ 配置说明](#️-配置说明)
- [🔐 权限说明](#-权限说明)
- [📄 开源协议](#-开源协议)

---

## ✨ 功能概览

### 📚 课表管理
- **多课表支持** — 创建和管理多套课程表，满足不同学期或不同班级的需求
- **二维码导入/导出** — 通过扫码或导入图片快速分享/迁移课表数据
- **网页导入** — 内置浏览器登录学校教务系统，一键抓取课程数据（目前仅内置「福州理工学院」适配，其他学校可自行测试，亦欢迎 [提交 Issue](https://github.com/Lulozi/DormDevise/issues) 反馈兼容情况）
- **课程提醒** — 上课前自动推送通知，支持自定义提醒时间
- **课节时间配置** — 灵活设置每节课的起止时间，适配不同学校的作息表
- **周次管理** — 支持单双周、自定义周次、学期起始周等复杂排课规则

### 🚪 智能开门
- **MQTT 远程开门** — 通过 MQTT 协议发送开门指令，支持 TLS 加密连接
- **HTTP POST 开门** — 支持通过 HTTP 请求触发开门，可与宿舍局域网设备联动
- **WiFi 智能匹配** — 自动检测当前连接的 WiFi，匹配后优先使用高效开门方式
- **长按快速开门** — 门锁页面长按门锁图标即可快速触发开门
- **桌面开门组件** — 在手机桌面放置开门小组件，无需打开 App 即可一键开门

### 🎨 个性主题
- **动态换肤** — 支持浅色/深色模式，自由选择主题色
- **导航栏自定义** — 支持拖拽排序底部导航栏顺序
- **平滑过渡** — 主题切换时带有流畅的渐变动画

### 🧩 桌面组件 (Android)
- **课表组件** — 在桌面查看今日/明日课程
- **开门组件（完整版）** — 显示门锁状态并支持一键开门
- **开门组件（简洁版）** — 最小化的开门按钮，节省桌面空间

---

## 📸 界面展示

### 课表页

| 默认课表 | 点击新增 |
|:---:|:---:|
| ![默认课表](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_默认课表.jpg) | ![课表页_点击](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_点击.jpg) |

| 新增课表 | 课表卡片 |
| :---: | :---: |
| ![课表页_新增课表](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_新增课表.jpg) | ![课表页_有课表卡片](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_有课表卡片.jpg) |

### 课表设置

| 课程时间设置 | 课程表设置 |
|:---:|:---:|
| ![课程时间](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程时间设置.jpg) | ![课程表设置](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程表设置.jpg) |

### 课表详细

|                          未锁定课表                          |                           锁定课表                           |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
| ![课表页_课程详细_未锁定](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程详细_未锁定.jpg) | ![课表页_课程详细_锁定](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程详细_锁定.jpg) |



### 课表导入/导出

| 扫码导入 | 导入码导入 | 二维码导出 |
|:---:|:---:|:---:|
| ![扫码导入](https://img.minio.xiaoheiwu.fun/new/DormDevise_扫码导入课表.jpg) | ![导入码导入](https://img.minio.xiaoheiwu.fun/new/DormDevise_导入码导入课表.jpg) | ![二维码导出](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表二维码导出.jpg) |

### 门锁页
| 门锁主页 | 长按开门 |
|:---:|:---:|
| ![门锁页](https://img.minio.xiaoheiwu.fun/new/DormDevise_门锁页.jpg) | ![长按门锁](https://img.minio.xiaoheiwu.fun/new/DormDevise_门锁页_长按门锁.jpg) |

### 桌面组件

| 开门组件完整版 | 开门组件简洁版 | 课表组件 |
|:---:|:---:|:---:|
| ![开门完整版](https://img.minio.xiaoheiwu.fun/new/DormDevise_桌面组件_开门组件完整版.jpg) | ![开门简洁版](https://img.minio.xiaoheiwu.fun/new/DormDevise_桌面组件_开门组件简洁版.jpg) | ![课表组件](https://img.minio.xiaoheiwu.fun/new/DormDevise_桌面组件_课表组件.jpg) |

### 个人页

| 个人主页 | 个性主题 |
|:---:|:---:|
| ![个人页](https://img.minio.xiaoheiwu.fun/new/DormDevise_个人页.jpg) | ![个性主题](https://img.minio.xiaoheiwu.fun/new/DormDevise_个人页_个性主题.jpg) |

---

## 🏗️ 项目架构

本项目遵循 Flutter 推荐的分层架构：

```
lib/
├── main.dart                 # 应用入口，初始化各类服务
├── app.dart                  # 根组件，主题注入与路由管理
├── models/                   # 数据模型层
│   ├── course.dart           # 课程模型
│   ├── course_schedule_config.dart  # 课表配置模型
│   ├── mqtt_config.dart      # MQTT 配置模型
│   ├── door_widget_settings.dart    # 门锁组件设置模型
│   └── ...
├── services/                 # 业务逻辑层
│   ├── course_service.dart   # 课表数据服务
│   ├── mqtt_service.dart     # MQTT 通信服务
│   ├── door_trigger_service.dart    # 开门触发服务
│   ├── door_widget_service.dart     # 桌面门锁组件服务
│   ├── course_widget_service.dart   # 桌面课表组件服务
│   ├── notification_service.dart    # 本地通知服务
│   ├── alarm_service.dart    # 闹钟提醒服务
│   ├── web_school_service.dart      # 教务系统导入服务
│   └── theme/                # 主题服务
├── views/                    # 视图层
│   ├── screens/
│   │   ├── table/            # 课表页面
│   │   ├── open_door/        # 开门页面
│   │   └── person/           # 个人页面
│   └── widgets/              # 视图级复用组件
├── widgets/                  # 全局复用组件
│   ├── door_desktop_widgets.dart    # 桌面门锁组件
│   └── door_widget_dialog.dart      # 门锁组件弹窗
└── utils/                    # 工具类
    ├── constants.dart        # 常量定义
    ├── course_utils.dart     # 课程工具函数
    ├── qr_transfer_codec.dart        # 二维码编解码
    └── ...
```

---

## 🚀 快速开始

### 环境要求

- **Flutter SDK** >= 3.31
- **Dart SDK** >= 3.9
- **Android Studio** 或 **VS Code** + Flutter 插件
- **Android SDK** (最低 API 26) / **Xcode** (iOS 14+)

### 克隆与运行

```bash
# 克隆仓库
git clone <your-repo-url>
cd dormdevise

# 安装依赖
flutter pub get

# 运行应用
flutter run
```

### 构建发布

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release
```

---

## 📦 核心依赖

| 依赖 | 用途 |
|:---|:---|
| [mqtt_client](https://pub.dev/packages/mqtt_client) | MQTT 协议通信，智能门锁控制 |
| [home_widget](https://pub.dev/packages/home_widget) | Android 桌面小组件 |
| [mobile_scanner](https://pub.dev/packages/mobile_scanner) | 二维码扫描导入课表 |
| [qr_flutter](https://pub.dev/packages/qr_flutter) | 生成课表分享二维码 |
| [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) | 教务系统网页登录抓取课表 |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | 本地键值对持久化 |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | 敏感数据加密存储 |
| [provider](https://pub.dev/packages/provider) | 状态管理 |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | 本地课程提醒通知 |
| [connectivity_plus](https://pub.dev/packages/connectivity_plus) / [wifi_scan](https://pub.dev/packages/wifi_scan) | WiFi 状态检测与匹配 |
| [animations](https://pub.dev/packages/animations) | 页面过渡动画 |
| [font_awesome_flutter](https://pub.dev/packages/font_awesome_flutter) | 图标库 |

---

## ⚙️ 配置说明

### MQTT 门锁配置

在「开门」页面的设置中，可配置：

- **MQTT Broker** — 服务器地址、端口、TLS 证书
- **开门主题** — MQTT 发布主题（支持 `{status}` 状态占位符）
- **HTTP POST** — 备用开门方式，配置请求 URL 及参数
- **WiFi 匹配** — 设置宿舍 WiFi 的 SSID/BSSID，自动切换开门策略

### 课表配置

- **学期起始日** — 设置学期第一天，用于自动计算当前教学周
- **课节时间** — 自定义每节课的起止时间
- **最大周数** — 学期总周数

---

## 🔐 权限说明

| 权限 | 用途 |
|:---|:---|
| `INTERNET` | MQTT/HTTP 通信 |
| `ACCESS_WIFI_STATE` / `ACCESS_NETWORK_STATE` | WiFi 匹配检测 |
| `CAMERA` | 扫描课表二维码 |
| `POST_NOTIFICATIONS` | 课程提醒通知 |
| `SCHEDULE_EXACT_ALARM` | 精确闹钟提醒 |
| `READ/WRITE_EXTERNAL_STORAGE` | 课表文件导入/导出 |
| `RECEIVE_BOOT_COMPLETED` | 桌面组件开机自启 |

---

## 📄 开源协议

本项目基于 [BSD 3-Clause License](LICENSE) 开源。

---

<div align="center">

**Made with ❤️ by [Lulo](https://github.com/Lulozi)**

*让宿舍生活更智能*

</div>
