import org.gradle.api.tasks.JavaExec
import org.gradle.api.tasks.compile.JavaCompile
import org.gradle.jvm.tasks.Jar

plugins {
    application
}

group = "io.sshfling.validation"
version = "1.0.0"

val clojureVersion = "1.12.5"
val sshflingVersion = providers.gradleProperty("sshflingVersion").getOrElse("0.1.18")
val sshflingRepository = providers.gradleProperty("sshflingRepository").get()
val consumerNamespace = "io.sshfling.validation.clojure-gradle-consumer"
val consumerSourcePath = "io/sshfling/validation/clojure_gradle_consumer.clj"

repositories {
    maven {
        url = uri(sshflingRepository)
    }
    mavenCentral()
}

dependencies {
    implementation("io.sshfling:sshfling-cli:$sshflingVersion")
    implementation("org.clojure:clojure:$clojureVersion")
}

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
}

sourceSets {
    main {
        resources.srcDir("src/main/clojure")
    }
}

application {
    mainClass = "clojure.main"
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 11
    options.encoding = "UTF-8"
}

tasks.named<JavaExec>("run") {
    doFirst {
        setArgs(listOf("-m", consumerNamespace) + (args ?: emptyList()))
    }
}

val consumerJar = tasks.named<Jar>("jar")
val verifyClojureSourceInJar = tasks.register("verifyClojureSourceInJar") {
    group = "verification"
    description = "Checks that the Clojure consumer namespace is packaged."
    dependsOn(consumerJar)
    inputs.file(consumerJar.flatMap { it.archiveFile })

    doLast {
        val matches = zipTree(consumerJar.get().archiveFile.get().asFile).matching {
            include(consumerSourcePath)
        }.files
        check(matches.size == 1) {
            "Clojure consumer namespace is missing from the packaged JAR."
        }
    }
}

tasks.named("check") {
    dependsOn(verifyClojureSourceInJar)
}
