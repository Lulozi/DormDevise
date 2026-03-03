import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.lulo.dormdevise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(21)
        targetCompatibility = JavaVersion.toVersion(21)
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.lulo.dormdevise"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            //signingConfig = signingConfigs.getByName("debug")
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

// 仅对 release 构建重命名 APK 输出文件，格式：com.lulo.dormdevise-v版本-ABI-release.apk
// 在 assembleRelease 任务完成后遍历产物并拷贝为目标文件名，同步写入 Flutter 输出目录
tasks.whenTaskAdded {
    if (name.startsWith("assemble") && name.endsWith("Release")) {
        doLast {
            // Flutter 最终拷贝产物的目录
            val flutterApkDir = File(project.buildDir, "outputs/flutter-apk")
            android.applicationVariants.matching { it.buildType.name == "release" }.forEach { variant ->
                variant.outputs.forEach { output ->
                    val originalFile = output.outputFile
                    if (originalFile.exists()) {
                        val abi = (output as? com.android.build.gradle.internal.api.BaseVariantOutputImpl)
                            ?.getFilter(com.android.build.OutputFile.ABI) ?: "universal"
                        val targetName = "${variant.applicationId}-v${variant.versionName}-$abi-release.apk"
                        // 拷贝到 Gradle 原始输出目录
                        originalFile.copyTo(File(originalFile.parentFile, targetName), overwrite = true)
                        // 同步拷贝到 Flutter 输出目录
                        val flutterOriginal = File(flutterApkDir, originalFile.name)
                        if (flutterOriginal.exists()) {
                            flutterOriginal.copyTo(File(flutterApkDir, targetName), overwrite = true)
                        }
                        println("APK renamed: ${originalFile.name} -> $targetName")
                    }
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
