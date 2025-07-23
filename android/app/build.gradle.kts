plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin") // Flutter plugin must come last
}

android {
    namespace = "com.byshiladityamallick.neura"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"
//    ndkVersion = flutter.ndkVersion

    defaultConfig {
        applicationId = "com.byshiladityamallick.neura"
        minSdk = 24  // Required for foreground services
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    sourceSets["main"].java.srcDirs("src/main/kotlin")
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.jetbrains.kotlin:kotlin-stdlib:2.1.0") // ✅ Needed for Kotlin
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okio:okio:3.9.0")
    implementation("org.tensorflow:tensorflow-lite:2.13.0")
    implementation("com.google.android.material:material:1.12.0")
}
