import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm") version "2.4.0"
    application
}

val sshflingVersion = providers.gradleProperty("sshflingVersion").get()
val sshflingRepository = providers.gradleProperty("sshflingRepository").get()

repositories {
    maven {
        url = uri(sshflingRepository)
    }
    mavenCentral()
}

dependencies {
    implementation("io.sshfling:sshfling-cli:$sshflingVersion")
    implementation(kotlin("stdlib"))
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_11
    }
}

application {
    mainClass = "io.sshfling.validation.KotlinGradleConsumer"
}
