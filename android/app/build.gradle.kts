plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.barcode_scanner"
    // 36 is the current stable compileSdk. Do NOT bump to 37 (or beyond)
    // without first checking permission_handler_android's own compileSdk:
    // versions >=14.0.0 (pulled in by permission_handler >=13.0.0) hardcode
    // compileSdk = 37, a preview-only SDK level that isn't installable as a
    // stable target and breaks :app:compileDebugJavaWithJavac on any machine
    // that doesn't have it. pubspec.yaml caps permission_handler at ^12.0.3
    // (permission_handler_android ^13.0.0, compileSdk 35) specifically to
    // stay clear of that jump.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.barcode_scanner"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
