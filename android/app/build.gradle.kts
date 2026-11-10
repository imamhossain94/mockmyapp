import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from an untracked `android/key.properties`.
//
// Absent on a fresh clone and in CI without the secret, and that is deliberate:
// the build then falls back to the debug key so `flutter run --release` and the
// CI APK job keep working for contributors who have no keystore. What it must
// never do is let a *store upload* go out debug-signed — Play rejects those
// outright — so `release` fails loudly instead of silently downgrading. See the
// check in the release block below.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasReleaseKeystore = keystoreProperties.getProperty("storeFile") != null

// A second, side-by-side install, for trying a build against real data.
//
// Off unless `MOCKUP_DEV_ID` is in the environment, so an ordinary build is
// exactly what it has always been. With it set, the app takes an applicationId
// and a name of its own — which is what lets a build signed on one machine sit
// *beside* one signed on another rather than demanding the uninstall that wipes
// app storage. Android keys storage off the applicationId, so the two installs
// never share a byte and neither can clear the other.
//
// `MOCKUP_DEV_ID=1` means `.dev`, which is what it has always meant. Any other
// value is taken as the suffix itself, because `.dev` gets occupied too: a third
// machine's debug key mismatches the second machine's `.dev` install exactly the
// way it mismatches the first machine's release install, and then there is
// nowhere left to put the build.
//
// It applies to release as well as debug. A release build is the one you
// sideload to see the app as a user will — debug is too slow to judge the canvas
// by — so it needs somewhere to go just as much as a debug build does. The
// `bundleRelease` guard below refuses a suffixed applicationId outright, so this
// cannot reach Play by accident.
val devSuffix = System.getenv("MOCKUP_DEV_ID")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
    ?.let { if (it == "1") "dev" else it.removePrefix(".") }

android {
    namespace = "com.newagedevs.mockmyapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.newagedevs.mockmyapp"
        // Android 8. ML Kit's GenAI Prompt API — Gemini Nano, for on-device
        // captions — will not link below it, and the project's own floor is
        // "modern devices only" anyway; Flutter's default is 24.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appLabel"] = "MockMyApp"
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            if (devSuffix != null) {
                applicationIdSuffix = ".$devSuffix"
                // Named apart on the home screen too. Two icons reading
                // "MockMyApp" is how the wrong one gets opened, and the wrong
                // one here is the one holding the work.
                manifestPlaceholders["appLabel"] = "MockMyApp $devSuffix"
            }
        }

        release {
            if (devSuffix != null) {
                applicationIdSuffix = ".$devSuffix"
                manifestPlaceholders["appLabel"] = "MockMyApp $devSuffix"
            }

            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Local convenience only. An `appbundle` built this way cannot
                // be uploaded, which is what the guard below is for.
                signingConfigs.getByName("debug")
            }
        }
    }
}

// A debug-signed bundle is rejected by the Play Console after a full upload and
// a wait. Failing here instead turns a slow, confusing rejection into an
// immediate, obvious one.
tasks.matching { it.name.contains("bundleRelease", ignoreCase = true) }.configureEach {
    doFirst {
        check(hasReleaseKeystore) {
            "Refusing to build a release bundle with the debug key.\n" +
                "Create android/key.properties with storeFile, storePassword, " +
                "keyAlias and keyPassword. It is gitignored — never commit it " +
                "or the .jks it points at."
        }

        // The side-by-side applicationId is for sideloading onto a device that
        // already holds a build signed elsewhere. Play only knows
        // `com.newagedevs.mockmyapp`, so a suffixed bundle is either rejected on
        // upload or, worse, accepted as some other app entirely.
        check(devSuffix == null) {
            "Refusing to build a release bundle with MOCKUP_DEV_ID set.\n" +
                "That would package com.newagedevs.mockmyapp.$devSuffix, which is " +
                "not the app Play knows. Unset MOCKUP_DEV_ID and build again."
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

// On-device AI. Nothing here sends a user's words or pictures anywhere: the
// translator downloads its language packs once, Gemini Nano is a system
// component the phone already carries (or does not), and text recognition's
// model arrives through Google Play services.
dependencies {
    implementation("com.google.mlkit:translate:17.0.3")
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
    implementation("com.google.mlkit:genai-prompt:1.0.0-beta4")
}
