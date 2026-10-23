allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// stripe_android's release lint-checks classpath transitively depends on
// com.google.android.gms:play-services-tapandpay:17.1.2, a version that was
// never published to any Maven repo — "lint vital" is an automatic
// release-build check AGP runs on library dependencies, not something the
// app itself needs, so disabling it here avoids the unresolvable dependency
// entirely without touching real runtime/payment code.
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
