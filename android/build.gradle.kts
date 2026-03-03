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

// Fuerza androidx.core en todos los subproyectos (incluyendo plugins)
subprojects {
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.core" &&
                (requested.name == "core" || requested.name == "core-ktx")) {
                useVersion("1.13.1")
                because("lStar fix - requires API 31+ attribute")
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

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        sourceCompatibility = "17"
        targetCompatibility = "17"
        options.encoding = "UTF-8"
        options.compilerArgs.add("-Xlint:-options")
    }

    tasks.withType<KotlinCompile>().configureEach {
        kotlinOptions {
            jvmTarget = "17"
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}