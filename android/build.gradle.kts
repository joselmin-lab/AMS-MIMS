import org.gradle.api.file.Directory
import org.gradle.api.tasks.Delete
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}
allprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core-ktx:1.10.1")
            force("androidx.core:core:1.10.1")
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

/**
 * Force Java/Kotlin 17 across ALL subprojects (including plugins),
 * using TASK configuration only (safe with AGP property finalization).
 */
subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
        options.encoding = "UTF-8"
        // Quita warnings por flags antiguas si algún plugin las usa
        options.compilerArgs.add("-Xlint:-options")
    }

    tasks.withType<KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}


// ESTO FUERZA A USAR LA VERSIÓN CORRECTA DE ANDROIDX QUE TIENE LSTAR
allprojects {
    configurations.all {
        resolutionStrategy {
            force("androidx.core:core-ktx:1.12.0")
            force("androidx.core:core:1.12.0")
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}