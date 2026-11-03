import groovy.json.JsonSlurper

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firebase (push notifications): read google-services.json when it's there
// (CI writes it from the GOOGLE_SERVICES_JSON secret). Without it the app
// builds and runs as before, just without pushes.
val firebaseConfig: Map<String, String>? = file("google-services.json").takeIf { it.exists() }?.let { f ->
    val j = JsonSlurper().parse(f) as Map<*, *>
    val project = j["project_info"] as Map<*, *>
    val client = (j["client"] as List<*>).map { it as Map<*, *> }.first {
        val info = it["client_info"] as Map<*, *>
        (info["android_client_info"] as Map<*, *>)["package_name"] == "com.tirth.newsapp"
    }
    mapOf(
        "google_app_id" to (client["client_info"] as Map<*, *>)["mobilesdk_app_id"] as String,
        "google_api_key" to ((client["api_key"] as List<*>).first() as Map<*, *>)["current_key"] as String,
        "gcm_defaultSenderId" to project["project_number"] as String,
        "project_id" to project["project_id"] as String,
    )
}

android {
    namespace = "com.tirth.newsapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Never change this: updates only install over an app with the same id.
        applicationId = "com.tirth.newsapp"
        // Android 13 and newer.
        minSdk = 33
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // What Google's google-services plugin would generate.
        firebaseConfig?.forEach { (name, value) -> resValue("string", name, value) }
    }

    buildFeatures {
        resValues = true
    }

    // The release key comes from GitHub Actions secrets (see build-apk.yml).
    // Every build must use the same key, or Android refuses to install updates.
    val keystorePath = System.getenv("ANDROID_KEYSTORE_PATH")
    signingConfigs {
        create("release") {
            if (keystorePath != null) {
                storeFile = file(keystorePath)
                storeType = "pkcs12"
                storePassword = System.getenv("KEYSTORE_PASSWORD")
                keyAlias = System.getenv("KEY_ALIAS")
                keyPassword = System.getenv("KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                keystorePath != null -> signingConfigs.getByName("release")
                System.getenv("CI") != null ->
                    throw GradleException("Release builds on CI need ANDROID_KEYSTORE_PATH")
                // Local test builds only; these can't update the real app.
                else -> signingConfigs.getByName("debug")
            }
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

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))
    implementation("com.google.firebase:firebase-messaging")
}
