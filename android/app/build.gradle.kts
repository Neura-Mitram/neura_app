plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services") // Firebase plugin
    id("dev.flutter.flutter-gradle-plugin") // Keep last
}

android {
    namespace = "com.byshiladityamallick.neura"
    compileSdk = 34 // Android 14
    ndkVersion = "27.0.12077973" // Your custom NDK

    defaultConfig {
        applicationId = "com.byshiladityamallick.neura"
        minSdk = 24
        targetSdk = 34 // Required for Android 14
        versionCode = flutter.versionCode.toInteger() ?: 1
        versionName = flutter.versionName ?: "1.0.0"
        multiDexEnabled = true // Critical for Firebase
        
        // Fix: Add quotes around ABI filters
        ndk {
            abiFilters 'armeabi-v7a', 'arm64-v8a', 'x86_64'
        }
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
    
    // Fix: Remove viewBinding (not needed for Flutter)
    // buildFeatures {
    //    viewBinding = true
    // }
    
    // Fix: dexOptions is deprecated - remove this block
    // dexOptions {
    //    javaMaxHeapSize "4g"
    //    preDexLibraries true
    // }
}

flutter {
    source = "../.."
    // Remove multidexEnabled from here (handled in dependencies)
}

dependencies {
    // Kotlin
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.22")
    
    // Firebase (using BOM)
    implementation(platform("com.google.firebase:firebase-bom:32.8.0"))
    implementation("com.google.firebase:firebase-messaging-ktx")
    implementation("com.google.firebase:firebase-analytics-ktx")
    
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
    
    // WorkManager (for background tasks)
    implementation("androidx.work:work-runtime-ktx:2.9.0")
    
    // Fix: Add explicit Flutter embedding dependency
    debugImplementation("io.flutter:flutter_embedding_debug:1.0.0")
    releaseImplementation("io.flutter:flutter_embedding_release:1.0.0")
    
    // Testing (optional for release)
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test.ext:junit:1.1.5")
    androidTestImplementation("androidx.test.espresso:espresso-core:3.5.1")
}

// Fix: Remove force resolution (BOM handles versions)
// configurations.all {
//     resolutionStrategy {
//         force 'androidx.lifecycle:lifecycle-process:2.8.0'
//         force 'com.google.android.gms:play-services-basement:18.4.0'
//     }
// }