// build.gradle.kts (root)

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
