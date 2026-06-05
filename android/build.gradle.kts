allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Force all Flutter plugins to use compileSdk 36 to satisfy AAR metadata requirements
subprojects {
    afterEvaluate {
        if (extensions.findByName("android") != null) {
            extensions.getByName<com.android.build.gradle.BaseExtension>("android").apply {
                compileSdkVersion(36)
            }
        }
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


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
