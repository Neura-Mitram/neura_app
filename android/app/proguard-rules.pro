# Flutter Engine
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# TensorFlow Lite
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }

# OkHttp Networking
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**

# Location Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# AndroidX Lifecycle
-keep class androidx.lifecycle.** { *; }
-keep class androidx.work.** { *; }
-keep class androidx.multidex.** { *; }
-dontwarn androidx.**

# Kotlin Coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**


# Native Methods (Critical!)
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve all Flutter classes
-keep class com.byshiladityamallick.neura.** { *; }