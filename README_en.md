# DormDevise

[中文](README.md)  |  [English](README_en.md)

DormDevise is a cross-platform Flutter app designed for dormitory scenarios, supporting Android (Other platforms have not been packaged and tested).

## Features

- Smart door lock control based on MQTT, with animation feedback, long-press advanced settings, and operation throttling.
- Wi-Fi configuration wizard: scan nearby networks, save credentials, and connect quickly.
- MQTT management center: TLS certificate support, topic subscription debugging, and real-time message preview.
- Personal center: integrates door, network, location, and about settings, with built-in version update check and download process.
- ~~Timetable page (placeholder)~~, reserved for future course data and widget integration.

## Main Dependencies

- [flutter](https://flutter.dev/)
- [mqtt_client](https://pub.dev/packages/mqtt_client)
- [shared_preferences](https://pub.dev/packages/shared_preferences)
- [cached_network_image](https://pub.dev/packages/cached_network_image)
- [file_picker](https://pub.dev/packages/file_picker)
- [uuid](https://pub.dev/packages/uuid)
- [package_info_plus](https://pub.dev/packages/package_info_plus)
- [wifi_scan](https://pub.dev/packages/wifi_scan)
- [permission_handler](https://pub.dev/packages/permission_handler)

## Quick Start

1. Clone the project:

	```bash
	git clone https://github.com/Lulozi/DormDevise.git
	cd dormdevise
	```

2. Install dependencies:

	```bash
	flutter pub get
	```

3. (Optional) Prepare CA/client certificate files in `assets/certs/` if needed, and ensure they are declared in `pubspec.yaml`.

4. Run the project:

	```bash
	flutter run
	```

5. On first launch, complete Wi-Fi and MQTT configuration in-app to enable door control.

## Configuration

- **Wi-Fi Settings**: Scan and save SSID/password. If scanning fails, ensure location and nearby device permissions are granted.
- **MQTT Settings**: Configure host, port, topic, client ID, username/password, and TLS certificates. Includes topic debugging and status preview.
- **Location Settings**: Placeholder for future indoor positioning or geofencing features.
- **Version Update**: Built-in version check and APK download in the About page, with unified download task management.

## Directory Structure

- `lib/`
  - `main.dart`: App entry and global provider initialization.
  - `app.dart`: App shell, bottom navigation, and page container.
  - `screens/open_door/`: Door control UI and Wi-Fi, MQTT, location settings.
  - `screens/person/`: Personal center, about page, and animation widgets.
  - `screens/table/`: Timetable placeholder page.
  - `services/mqtt_service.dart`: MQTT service for publish/subscribe and request-response.
  - `utils/app_toast.dart`: Global toast utility.
- `android/`, `ios/`, `web/`, `windows/`, `linux/`, `macos/`: Platform-specific projects and build scripts.
- `test/`: Test samples (default Flutter example, extend as needed).

## Notes

- Android Wi-Fi scan requires location and nearby device permissions. If permanently denied, enable them in system settings.
- For TLS connections, ensure certificate file paths are correct and readable. Use the in-app file picker if needed.
- MQTT topic subscription debugging records the last topic by default, which can be cleared in settings.
- Some hardware features (Wi-Fi scan, APK download) may not be available on desktop or web.

## Environment & Requirements

To ensure consistent builds and compatibility, please set up your development or CI environment with the following minimum requirements:

- JDK: **Java 21** (OpenJDK 21 or equivalent JDK 21+). Verify with `java -version`.
- Gradle Wrapper: **Gradle 8.12** (see `android/gradle/wrapper/gradle-wrapper.properties`).
- Android Gradle Plugin: **AGP 8.9.1** (defined in `android/settings.gradle.kts`).
- Kotlin plugin: **Kotlin 2.1.0**.
- Flutter: Use a stable Flutter SDK compatible with the packages used; update the SDK as necessary for newer plugin versions.

## Changelog

See the Chinese README for detailed version history.

## License

© 2025 DormDevise. All rights reserved.