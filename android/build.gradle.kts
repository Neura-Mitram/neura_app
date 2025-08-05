// ✅ Required for Google Services plugin
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.1") // ✅ Firebase plugin
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
