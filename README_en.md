# DormDevise — Smart Dormitory Management

<div align="center">

[![Flutter](https://img.shields.io/badge/Flutter-3.31+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.9+-0175C2?logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-BSD%203--Clause-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-lightgrey)]()

**One-stop management for dormitory course schedules, smart door locks & desktop widgets**

[中文](README.md) | [English](README_en.md)

</div>

---

## 📖 Table of Contents

- [Features](#-features)
- [📸 Screenshots](#-screenshots)
- [🏗️ Architecture](#️-architecture)
- [🚀 Getting Started](#-getting-started)
- [📦 Core Dependencies](#-core-dependencies)
- [⚙️ Configuration](#️-configuration)
- [🔐 Permissions](#-permissions)
- [📄 License](#-license)

---

## ✨ Features

### 📚 Course Schedule Management
- **Multiple Schedules** — Create and manage multiple course schedules for different semesters or classes
- **QR Code Import/Export** — Quickly share or migrate schedule data via QR code scanning or image import
- **Web Import** — Built-in browser to log into school academic systems and grab course data in one tap (currently only pre-configured for 「FIT」; other schools may test on their own, and [submitting an issue](https://github.com/Lulozi/DormDevise/issues) is welcome to report compatibility)
- **Course Reminders** — Automatic push notifications before class with customizable reminder times
- **Period Time Configuration** — Flexibly set start/end times for each class period to match your school's timetable
- **Week Management** — Supports odd/even weeks, custom weeks, semester start week, and other complex scheduling rules

### 🚪 Smart Door Unlock
- **MQTT Remote Unlock** — Send unlock commands via MQTT protocol with TLS encrypted connection support
- **HTTP POST Unlock** — Trigger door unlock via HTTP requests, seamlessly integrating with dorm LAN devices
- **WiFi Smart Matching** — Automatically detects the currently connected WiFi and prioritizes the most efficient unlock method
- **Long-Press Quick Unlock** — Long-press the door lock icon on the lock page to quickly trigger unlocking
- **Desktop Door Widget** — Place an unlock widget on your phone's home screen for one-tap access without opening the app

### 🎨 Personalized Themes
- **Dynamic Theming** — Support for light/dark mode with freely selectable accent colors
- **Customizable Navigation** — Drag-and-drop reordering of bottom navigation bar tabs
- **Smooth Transitions** — Fluid animation effects when switching themes

### 🧩 Desktop Widgets (Android)
- **Course Schedule Widget** — View today's/tomorrow's classes on your home screen
- **Door Unlock Widget (Full)** — Displays door lock status with one-tap unlock
- **Door Unlock Widget (Compact)** — Minimal unlock button to save home screen space

---

## 📸 Screenshots

### Course Schedule Page

| Default Schedule | Tap to Add |
|:---:|:---:|
| ![Default Schedule](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_默认课表.jpg) | ![Tap to Add](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_点击.jpg) |

| Add Schedule | Schedule Cards |
| :---: | :---: |
| ![Add Schedule](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_新增课表.jpg) | ![Schedule Cards](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_有课表卡片.jpg) |

### Schedule Settings

| Period Time Settings | Schedule Configuration |
|:---:|:---:|
| ![Period Time](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程时间设置.jpg) | ![Schedule Config](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程表设置.jpg) |

### Course Details

|                          Unlocked Schedule                           |                           Locked Schedule                           |
| :----------------------------------------------------------: | :----------------------------------------------------------: |
| ![Unlocked Schedule](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程详细_未锁定.jpg) | ![Locked Schedule](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表页_课程详细_锁定.jpg) |

### Schedule Import/Export

| QR Scan Import | Import Code | QR Code Export |
|:---:|:---:|:---:|
| ![QR Scan](https://img.minio.xiaoheiwu.fun/new/DormDevise_扫码导入课表.jpg) | ![Import Code](https://img.minio.xiaoheiwu.fun/new/DormDevise_导入码导入课表.jpg) | ![QR Export](https://img.minio.xiaoheiwu.fun/new/DormDevise_课表二维码导出.jpg) |

### Door Lock Page

| Door Lock Home | Long-Press Unlock |
|:---:|:---:|
| ![Door Lock](https://img.minio.xiaoheiwu.fun/new/DormDevise_门锁页.jpg) | ![Long-Press](https://img.minio.xiaoheiwu.fun/new/DormDevise_门锁页_长按门锁.jpg) |

### Desktop Widgets

| Door Widget (Full) | Door Widget (Compact) | Course Widget |
|:---:|:---:|:---:|
| ![Door Full](https://img.minio.xiaoheiwu.fun/new/DormDevise_桌面组件_开门组件完整版.jpg) | ![Door Compact](https://img.minio.xiaoheiwu.fun/new/DormDevise_桌面组件_开门组件简洁版.jpg) | ![Course Widget](https://img.minio.xiaoheiwu.fun/new/DormDevise_桌面组件_课表组件.jpg) |

### Profile Page

| Profile Home | Theme Customization |
|:---:|:---:|
| ![Profile](https://img.minio.xiaoheiwu.fun/new/DormDevise_个人页.jpg) | ![Theme](https://img.minio.xiaoheiwu.fun/new/DormDevise_个人页_个性主题.jpg) |

---

## 🏗️ Architecture

This project follows the recommended Flutter layered architecture:

```
lib/
├── main.dart                 # App entry point, initializes all services
├── app.dart                  # Root widget, theme injection & route management
├── models/                   # Data model layer
│   ├── course.dart           # Course model
│   ├── course_schedule_config.dart  # Schedule configuration model
│   ├── mqtt_config.dart      # MQTT configuration model
│   ├── door_widget_settings.dart    # Door widget settings model
│   └── ...
├── services/                 # Business logic layer
│   ├── course_service.dart   # Course data service
│   ├── mqtt_service.dart     # MQTT communication service
│   ├── door_trigger_service.dart    # Door unlock trigger service
│   ├── door_widget_service.dart     # Desktop door widget service
│   ├── course_widget_service.dart   # Desktop course widget service
│   ├── notification_service.dart    # Local notification service
│   ├── alarm_service.dart    # Alarm reminder service
│   ├── web_school_service.dart      # Academic system import service
│   └── theme/                # Theme service
├── views/                    # View layer
│   ├── screens/
│   │   ├── table/            # Course schedule page
│   │   ├── open_door/        # Door unlock page
│   │   └── person/           # Profile page
│   └── widgets/              # View-level reusable widgets
├── widgets/                  # Global reusable widgets
│   ├── door_desktop_widgets.dart    # Desktop door widgets
│   └── door_widget_dialog.dart      # Door widget dialog
└── utils/                    # Utility classes
    ├── constants.dart        # Constant definitions
    ├── course_utils.dart     # Course utility functions
    ├── qr_transfer_codec.dart        # QR code encoding/decoding
    └── ...
```

---

## 🚀 Getting Started

### Prerequisites

- **Flutter SDK** >= 3.31
- **Dart SDK** >= 3.9
- **Android Studio** or **VS Code** + Flutter extensions
- **Android SDK** (min API 26) / **Xcode** (iOS 14+)

### Clone & Run

```bash
# Clone the repository
git clone <your-repo-url>
cd dormdevise

# Install dependencies
flutter pub get

# Run the app
flutter run
```

### Build for Release

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# iOS
flutter build ios --release
```

---

## 📦 Core Dependencies

| Dependency | Purpose |
|:---|:---|
| [mqtt_client](https://pub.dev/packages/mqtt_client) | MQTT protocol communication for smart door lock control |
| [home_widget](https://pub.dev/packages/home_widget) | Android home screen widgets |
| [mobile_scanner](https://pub.dev/packages/mobile_scanner) | QR code scanning for schedule import |
| [qr_flutter](https://pub.dev/packages/qr_flutter) | Generate QR codes for schedule sharing |
| [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview) | In-app browser for academic system login & data scraping |
| [shared_preferences](https://pub.dev/packages/shared_preferences) | Local key-value persistence |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Encrypted storage for sensitive data |
| [provider](https://pub.dev/packages/provider) | State management |
| [flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications) | Local course reminder notifications |
| [connectivity_plus](https://pub.dev/packages/connectivity_plus) / [wifi_scan](https://pub.dev/packages/wifi_scan) | WiFi status detection & matching |
| [animations](https://pub.dev/packages/animations) | Page transition animations |
| [font_awesome_flutter](https://pub.dev/packages/font_awesome_flutter) | Icon library |

---

## ⚙️ Configuration

### MQTT Door Lock Configuration

In the "Door Unlock" page settings, you can configure:

- **MQTT Broker** — Server address, port, TLS certificates
- **Unlock Topic** — MQTT publish topic (supports `{status}` placeholder for dynamic status)
- **HTTP POST** — Alternative unlock method, configure request URL and parameters
- **WiFi Matching** — Set your dormitory WiFi SSID/BSSID for automatic unlock strategy switching

### Course Schedule Configuration

- **Semester Start Date** — Set the first day of the semester for automatic teaching week calculation
- **Period Times** — Customize start/end times for each class period
- **Max Weeks** — Total number of weeks in the semester

---

## 🔐 Permissions

| Permission | Purpose |
|:---|:---|
| `INTERNET` | MQTT/HTTP communication |
| `ACCESS_WIFI_STATE` / `ACCESS_NETWORK_STATE` | WiFi matching detection |
| `CAMERA` | Scanning schedule QR codes |
| `POST_NOTIFICATIONS` | Course reminder notifications |
| `SCHEDULE_EXACT_ALARM` | Precise alarm scheduling |
| `READ/WRITE_EXTERNAL_STORAGE` | Schedule file import/export |
| `RECEIVE_BOOT_COMPLETED` | Desktop widgets auto-start on boot |

---

## 📄 License

This project is open-sourced under the [BSD 3-Clause License](LICENSE).

---

<div align="center">

**Made with ❤️ by [Lulo](https://github.com/Lulozi)**

*Making dormitory life smarter*

</div>
