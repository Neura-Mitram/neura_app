plugins {
    id("com.android.application") version "8.10.1"
    id("org.jetbrains.kotlin.android") version "2.1.0"
    id("com.google.gms.google-services") version "4.4.1"
    id("dev.flutter.flutter-gradle-plugin") // Keep last
}

flutter {
    source = "../.."
}

android {
    namespace = "com.byshiladityamallick.neura"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.byshiladityamallick.neura"
        minSdk = 24
        targetSdk = 35
        versionCode = flutter.versionCode?.toString()?.toIntOrNull() ?: 1
        versionName = flutter.versionName ?: "1.0.0"
        multiDexEnabled = true

    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packagingOptions {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
            excludes += "/META-INF/DEPENDENCIES"
            excludes += "**/libflutter.so"
            excludes += "**/libtensorflowlite_jni.so"
        }
    }
}

dependencies {
    // Kotlin
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:2.1.0")

    // Firebase (BOM)
    implementation(platform("com.google.firebase:firebase-bom:34.0.0"))
    implementation("com.google.firebase:firebase-messaging")    // use main module
    implementation("com.google.firebase:firebase-analytics")


    // Networking
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.squareup.okio:okio:3.9.0")

    // Machine Learning
    implementation("org.tensorflow:tensorflow-lite:2.16.1")
    implementation("org.tensorflow:tensorflow-lite-support:0.4.4")

    // UI Components
    implementation("com.google.android.material:material:1.12.0")

    // AndroidX Core
    implementation("androidx.core:core-ktx:1.13.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.0")
    implementation("androidx.multidex:multidex:2.0.1")

    // Location Services
    implementation("com.google.android.gms:play-services-location:21.2.0")

    // Background Work
    implementation("androidx.work:work-runtime-ktx:2.9.0")

    // Testing (optional for release)
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}

repositories {
    google()
    mavenCentral()
    maven("https://jitpack.io")
    maven {
        url = uri("https://storage.googleapis.com/download.flutter.io")
    }
}
