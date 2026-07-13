plugins {
    `java-library`
    application
    `maven-publish`
}

group = "io.sshfling"
version = providers.gradleProperty("revision").getOrElse("0.0.0")

java {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
    withSourcesJar()
    withJavadocJar()
}

application {
    mainClass = "io.sshfling.cli.SSHFling"
}

tasks.withType<JavaCompile>().configureEach {
    options.release = 11
    options.encoding = "UTF-8"
}

tasks.jar {
    manifest {
        attributes["Main-Class"] = "io.sshfling.cli.SSHFling"
    }
}

publishing {
    publications {
        create<MavenPublication>("mavenJava") {
            from(components["java"])
            pom {
                name = "SSHFling CLI"
                description = "Temporary SSH access broker with an importable Java launcher API."
                url = "https://github.com/GRWLX/sshfling"
                licenses {
                    license {
                        name = "Apache License, Version 2.0"
                        url = "https://www.apache.org/licenses/LICENSE-2.0"
                        distribution = "repo"
                    }
                }
                developers {
                    developer {
                        id = "grwlx"
                        name = "GRWLX"
                    }
                }
                scm {
                    connection = "scm:git:https://github.com/GRWLX/sshfling.git"
                    developerConnection = "scm:git:https://github.com/GRWLX/sshfling.git"
                    url = "https://github.com/GRWLX/sshfling"
                }
            }
        }
    }
    repositories {
        maven {
            name = "validation"
            url = uri(
                providers.gradleProperty("publicationRepository")
                    .getOrElse(layout.buildDirectory.dir("repository").get().asFile.absolutePath)
            )
        }
    }
}
