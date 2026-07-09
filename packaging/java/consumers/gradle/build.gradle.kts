plugins {
    application
}

val sshflingVersion = providers.gradleProperty("sshflingVersion").get()
val sshflingRepository = providers.gradleProperty("sshflingRepository").get()

repositories {
    maven {
        url = uri(sshflingRepository)
    }
}

dependencies {
    implementation("io.sshfling:sshfling-cli:$sshflingVersion")
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

application {
    mainClass = "io.sshfling.validation.GradleConsumer"
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 11
    options.encoding = "UTF-8"
}
