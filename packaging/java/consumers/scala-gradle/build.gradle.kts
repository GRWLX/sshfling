import org.gradle.api.tasks.scala.ScalaCompile

plugins {
    scala
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
    implementation("org.scala-lang:scala3-library_3:3.3.8")
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

scala {
    scalaVersion = "3.3.8"
}

tasks.withType<ScalaCompile>().configureEach {
    scalaCompileOptions.additionalParameters = listOf("-release", "11")
}

application {
    mainClass = "io.sshfling.validation.ScalaGradleConsumer"
}
