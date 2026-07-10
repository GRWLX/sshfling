import org.gradle.api.tasks.compile.GroovyCompile

plugins {
    groovy
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
    implementation("org.apache.groovy:groovy:5.0.7")
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

tasks.withType<GroovyCompile>().configureEach {
    groovyOptions.encoding = "UTF-8"
    sourceCompatibility = "11"
    targetCompatibility = "11"
}

application {
    mainClass = "io.sshfling.validation.GroovyGradleConsumer"
}
