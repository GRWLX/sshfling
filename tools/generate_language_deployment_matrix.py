#!/usr/bin/env python3
"""Generate the verified language package, deployment, and library matrix."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import re
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DOC_PATH = REPO_ROOT / "docs" / "language-deployment-support.md"
LIBRARIES_DOC_PATH = REPO_ROOT / "docs" / "libraries.md"
TODO_PATH = REPO_ROOT / "TODO.txt"

TODO_BEGIN = "<!-- BEGIN GENERATED LANGUAGE DEPLOYMENT CHECKLIST -->"
TODO_END = "<!-- END GENERATED LANGUAGE DEPLOYMENT CHECKLIST -->"
LIBRARIES_BEGIN = "<!-- BEGIN GENERATED FIRST-91 LIBRARY SURFACES -->"
LIBRARIES_END = "<!-- END GENERATED FIRST-91 LIBRARY SURFACES -->"

ALLOWED_STATUSES = {"PASS", "BLOCKED", "NOT_APPLICABLE"}

CHECKS = (
    ("source", "Source surface"),
    ("metadata", "Package metadata"),
    ("build", "Package build"),
    ("artifact", "Artifact contents"),
    ("consumer", "Isolated consumer"),
    ("interface", "Public interface"),
    ("version", "Version contract"),
    ("runtime", "Runtime assets/workflow"),
)


def deployment(
    deployment_id: str,
    language: str,
    package_manager: str,
    deployment_type: str,
    interface_type: str,
    artifact: str,
    build_target: str,
    required_paths: list[str],
    evidence: tuple[str, ...],
) -> dict[str, object]:
    if len(evidence) != len(CHECKS):
        raise ValueError(f"{deployment_id}: expected {len(CHECKS)} evidence entries")
    return {
        "id": deployment_id,
        "language": language,
        "package_manager": package_manager,
        "deployment_type": deployment_type,
        "interface_type": interface_type,
        "artifact": artifact,
        "build_target": build_target,
        "required_paths": required_paths,
        "status": "PASS",
        "validation_status": "PASS",
        "validation_evidence": (
            f"The {build_target} validator supplies the detailed PASS evidence below."
        ),
        "evidence": dict(zip((check[0] for check in CHECKS), evidence, strict=True)),
    }


def node_language_consumer(
    deployment_id: str,
    language: str,
    deployment_type: str,
    source_paths: list[str],
    build_evidence: str,
    interface_evidence: str,
) -> dict[str, object]:
    consumer_name = deployment_id.removesuffix("-npm-consumer")
    consumer_root = f"packaging/node/consumers/{consumer_name}"
    item = deployment(
        deployment_id,
        language,
        "npm",
        deployment_type,
        "library consumer",
        "sshfling-VERSION.tgz",
        "package-web-language-consumers",
        [
            f"{consumer_root}/package.json",
            *(f"{consumer_root}/{path}" for path in source_paths),
            "packaging/build-web-language-consumers.sh",
        ],
        (
            f"A clean {language} consumer is tracked under {consumer_root}.",
            "Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency.",
            "packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands.",
            build_evidence,
            "The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact.",
            interface_evidence,
            "The consumer invokes the packed library with --version and requires a successful SSHFling status contract.",
            "The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process.",
        ),
    )
    item["validation_evidence"] = build_evidence
    return item


def scripting_language_package(
    deployment_id: str,
    language: str,
    package_manager: str,
    deployment_type: str,
    interface_type: str,
    artifact: str,
    package_root: str,
    source_paths: list[str],
    metadata_evidence: str,
    artifact_evidence: str,
    consumer_evidence: str,
    interface_evidence: str,
) -> dict[str, object]:
    return deployment(
        deployment_id,
        language,
        package_manager,
        deployment_type,
        interface_type,
        artifact,
        "package-scripting-languages",
        [
            *(f"{package_root}/{path}" for path in source_paths),
            "packaging/build-scripting-languages.sh",
        ],
        (
            f"The {language} package source is tracked under {package_root}.",
            metadata_evidence,
            "packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace.",
            artifact_evidence,
            consumer_evidence,
            interface_evidence,
            "The language-level consumer and packaged CLI must report the exact SSHFling release version.",
            "The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal.",
        ),
    )


DEPLOYMENTS = [
    deployment(
        "python-pip",
        "Python",
        "pip",
        "wheel dependency",
        "library + CLI",
        "sshfling-VERSION-py3-none-any.whl",
        "package-python",
        ["packaging/python/pyproject.toml", "packaging/python/src/sshfling/__init__.py", "packaging/build-python.sh"],
        (
            "pyproject and sshfling package sources are tracked under packaging/python.",
            "pyproject declares the sshfling project, package data, Python floor, and console script.",
            "packaging/build-python.sh builds the wheel with pip wheel in a generated project.",
            "validate_wheel_contents checks the Python module, entry point, license, and templates.",
            "validate_pip_install creates a clean venv and installs with --no-index and --no-deps.",
            "The installed consumer imports sshfling and invokes sshfling.run([\"--version\"]).",
            "The installed console script must print the exact release version.",
            "The venv consumer runs doctor and init and checks executable templates and secrets state.",
        ),
    ),
    deployment(
        "python-pipx",
        "Python",
        "pipx",
        "isolated application",
        "CLI",
        "sshfling-VERSION-py3-none-any.whl",
        "package-python",
        ["packaging/python/pyproject.toml", "packaging/build-python.sh"],
        (
            "The Python wheel source also defines the pipx application surface.",
            "The pyproject console-script entry maps sshfling to sshfling.cli:main.",
            "The same validated wheel is the pipx installation artifact.",
            "Wheel inspection proves the console entry point and bundled templates are present.",
            "validate_pipx_install uses isolated PIPX_HOME and PIPX_BIN_DIR directories.",
            "pipx exposes the installed sshfling command without importing project checkout code.",
            "The pipx command must print the exact release version.",
            "The pipx command runs init, validates generated state, and is then uninstalled.",
        ),
    ),
    deployment(
        "javascript-commonjs",
        "JavaScript",
        "npm",
        "CommonJS dependency",
        "library",
        "sshfling-VERSION.tgz",
        "package-node",
        ["packaging/node/package.json", "packaging/node/index.js", "packaging/build-node.sh"],
        (
            "The CommonJS launcher implementation is tracked in packaging/node/index.js.",
            "package.json declares main, require/default exports, files, engines, and package identity.",
            "packaging/build-node.sh creates the tarball with npm pack.",
            "Archive checks require index.js, declarations, CLI, license, runtime, and templates.",
            "validate_installed_package installs the tarball into a clean application prefix.",
            "A CommonJS consumer requires sshfling and invokes api.run([\"--version\"]).",
            "The installed package binary must print the exact release version.",
            "The installed package runs doctor and init and verifies bundled template modes.",
        ),
    ),
    deployment(
        "javascript-esm",
        "JavaScript",
        "npm",
        "ES module dependency",
        "library",
        "sshfling-VERSION.tgz",
        "package-node",
        ["packaging/node/package.json", "packaging/node/index.js", "packaging/build-node.sh"],
        (
            "The npm library is importable from an ES module consumer through package exports.",
            "package.json exposes the default module target and package metadata.",
            "The npm tarball is built from the generated versioned package directory.",
            "Tarball checks prove the JavaScript API and bundled runtime are shipped together.",
            "The ESM import executes from the clean npm application prefix.",
            "The ESM consumer imports sshfling and invokes api.run([\"--version\"]).",
            "The shared installed package binary validates the exact release version.",
            "The ESM API uses the same checked runtime/template paths as the CLI smoke workflow.",
        ),
    ),
    deployment(
        "typescript-npm",
        "TypeScript",
        "npm",
        "typed dependency",
        "library",
        "sshfling-VERSION.tgz",
        "package-node",
        ["packaging/node/index.d.ts", "packaging/node/consumers/typescript.ts", "packaging/build-node.sh"],
        (
            "Tracked declarations and a strict TypeScript consumer cover the public npm API.",
            "package.json maps its types field and conditional export to index.d.ts.",
            "The declarations ship in the same npm pack output as the JavaScript implementation.",
            "Tarball validation requires package/index.d.ts.",
            "The clean npm prefix installs a pinned TypeScript compiler and the packed dependency.",
            "tsc --strict --noEmit validates named/default imports, RunOptions, run, and templateDir.",
            "The typed run signatures return number and are paired with the runtime version smoke test.",
            "The typed dependency resolves the same bundled templates exercised by npm doctor/init.",
        ),
    ),
    deployment(
        "javascript-npm-bin",
        "JavaScript",
        "npm",
        "package executable",
        "CLI",
        "sshfling-VERSION.tgz",
        "package-node",
        ["packaging/node/package.json", "packaging/node/bin/sshfling.js", "packaging/build-node.sh"],
        (
            "The Node executable wrapper is tracked under packaging/node/bin.",
            "package.json maps the sshfling bin name to bin/sshfling.js.",
            "npm pack creates the installable CLI tarball.",
            "Tarball validation requires the executable wrapper and runtime resources.",
            "npm installs the package into an isolated prefix and creates node_modules/.bin/sshfling.",
            "The installed package exposes a stable sshfling executable.",
            "The npm binary must print the exact release version.",
            "The binary runs doctor/init, validates generated files, and is removed by npm uninstall.",
        ),
    ),
    deployment(
        "java-maven",
        "Java",
        "Maven",
        "Maven dependency",
        "library + CLI",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        ["packaging/java/pom.xml", "packaging/java/consumers/maven/pom.xml", "packaging/build-java.sh"],
        (
            "Java sources, Maven metadata, and a clean Maven consumer are tracked.",
            "The generated POM publishes concrete io.sshfling:sshfling-cli coordinates.",
            "packaging/build-java.sh runs Maven clean install with the release version.",
            "Maven produces executable, sources, and Javadocs JARs plus a concrete POM.",
            "A clean Maven consumer resolves the package from an isolated local repository.",
            "MavenConsumer compiles against and invokes the public SSHFling.run API.",
            "The Maven consumer API invocation must print the exact release version.",
            "The Maven JAR runs doctor/init and its runtime manifest and templates are inspected.",
        ),
    ),
    deployment(
        "java-gradle",
        "Java",
        "Gradle",
        "Gradle dependency",
        "library + CLI",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        ["packaging/java/build.gradle.kts", "packaging/java/gradlew", "packaging/java/consumers/gradle/build.gradle.kts"],
        (
            "A Java library/application build and clean Gradle consumer are tracked.",
            "Gradle metadata declares group, release property, Java 11, sources, and Javadocs.",
            "The checksum-pinned Gradle wrapper runs clean build and publish for the generated package project.",
            "The Gradle publication is checked for JAR, sources, Javadocs, POM, module metadata, and runtime resources.",
            "A clean Gradle consumer resolves the coordinate from Gradle's isolated publication repository.",
            "GradleConsumer compiles against and invokes the public SSHFling.run API.",
            "The Gradle consumer API invocation must print the exact release version.",
            "The Gradle artifact embeds the same resource manifest validated by doctor/init JAR smoke tests.",
        ),
    ),
    deployment(
        "java-executable-jar",
        "Java",
        "JAR",
        "direct executable",
        "CLI",
        "sshfling-cli-VERSION.jar",
        "package-java",
        ["packaging/java/src/main/java/io/sshfling/cli/SSHFling.java", "packaging/build-java.sh"],
        (
            "SSHFling.java supplies the Java main class and public launcher API.",
            "Maven and Gradle both write the Main-Class manifest entry.",
            "The Java package target builds the direct executable JAR.",
            "JAR inspection checks the launcher, resource manifest, Python runtime, and templates.",
            "Validation executes the JAR against a temporary smoke-project directory.",
            "java -jar provides the direct SSHFling command interface.",
            "The direct JAR must print the exact release version.",
            "The direct JAR runs doctor/init and validates generated executable and state files.",
        ),
    ),
    deployment(
        "dotnet-nuget-library",
        "C#/.NET",
        "NuGet",
        "PackageReference library",
        "library",
        "SSHFling.VERSION.nupkg",
        "package-dotnet",
        ["packaging/dotnet/SSHFling/SSHFling.csproj", "packaging/dotnet/SSHFling/SSHFlingRunner.cs", "packaging/dotnet/SSHFling.Consumer/SSHFling.Consumer.csproj"],
        (
            "A public .NET library project, runner API, and consumer project are tracked.",
            "The project declares PackageId SSHFling, net10.0, XML docs, license, and repository metadata.",
            "packaging/build-dotnet.sh packs the SSHFling library in Release configuration.",
            "NuGet inspection requires the DLL, XML docs, license, and README.",
            "The clean consumer restores SSHFling from only the local package directory.",
            "The consumer calls SSHFlingRunner.Version and SSHFlingRunner.Run.",
            "The library API call must print the exact release version.",
            "Run extracts all embedded runtime assets before invoking Python and cleans the temp directory.",
        ),
    ),
    deployment(
        "dotnet-global-tool",
        "C#/.NET",
        ".NET tool",
        "global/tool-path command",
        "CLI",
        "SSHFling.Tool.VERSION.nupkg",
        "package-dotnet",
        ["packaging/dotnet/SSHFling.Tool/SSHFling.Tool.csproj", "packaging/dotnet/SSHFling.Tool/Program.cs", "packaging/build-dotnet.sh"],
        (
            "The .NET tool project and launcher are tracked under packaging/dotnet/SSHFling.Tool.",
            "The project declares PackAsTool, ToolCommandName sshfling, package metadata, and net10.0.",
            "packaging/build-dotnet.sh packs the global tool in Release configuration.",
            "NuGet archive checks require tool runtime files and systemd template resources.",
            "dotnet tool install uses an isolated tool path and local package source.",
            "The package exposes the sshfling tool command.",
            "The installed .NET tool must print the exact release version.",
            "The installed tool runs doctor/init and validates templates and state files.",
        ),
    ),
    deployment(
        "go-module",
        "Go",
        "Go modules",
        "module dependency and go install",
        "library + CLI",
        "sshfling-go-VERSION.zip",
        "package-go",
        ["packaging/go/go.mod", "packaging/go/sshfling.go", "packaging/go/cmd/sshfling/main.go", "packaging/build-go.sh"],
        (
            "The Go module contains an importable root package and cmd/sshfling.",
            "go.mod declares the module path and the build injects the release Version constant.",
            "packaging/build-go.sh runs formatting, tests, vet, builds, and deterministic archive creation.",
            "ZIP validation requires go.mod, library/command sources, runtime, and templates.",
            "The extracted clean module is tested and installed with isolated Go caches and GOBIN.",
            "Go tests invoke sshfling.Run while cmd/sshfling exposes the CLI.",
            "The installed Go command must print the exact release version.",
            "The Go command runs doctor/init and validates executable templates and generated state.",
        ),
    ),
    deployment(
        "rust-cargo",
        "Rust",
        "Cargo",
        "crate dependency and cargo install",
        "library + CLI",
        "sshfling-cli-VERSION.crate",
        "package-rust",
        ["packaging/rust/Cargo.toml", "packaging/rust/src/lib.rs", "packaging/rust/src/main.rs", "packaging/build-rust.sh"],
        (
            "The Cargo project contains public library and binary targets.",
            "Cargo.toml declares crate metadata, library/bin targets, Rust floor, and included resources.",
            "The build runs cargo fmt, test, clippy, package, and optional publish dry-run.",
            "Crate inspection requires Cargo metadata, library/bin sources, runtime, and templates.",
            "The crate is extracted and cargo-installed with isolated CARGO_HOME and target directories.",
            "Rust tests invoke sshfling_cli::run while the package installs the sshfling binary.",
            "The installed Cargo binary must print the exact release version.",
            "The Cargo binary runs doctor/init, validates state, and is removed with cargo uninstall.",
        ),
    ),
    deployment(
        "php-composer",
        "PHP",
        "Composer",
        "Composer dependency",
        "library + CLI",
        "sshfling-php-VERSION.zip",
        "package-php",
        ["packaging/php/composer.json", "packaging/php/src/SSHFling.php", "packaging/php/bin/sshfling", "packaging/build-php.sh"],
        (
            "The Composer package contains a PSR-4 library and vendor binary.",
            "composer.json declares package identity, PHP floor, PSR-4 autoloading, and bin entry.",
            "The build validates metadata/autoloading and creates a Composer ZIP archive.",
            "Archive checks require composer.json, class source, binary, runtime, and templates.",
            "A clean application installs from an isolated Composer artifact repository.",
            "Both generated and installed autoloaders invoke SSHFling::run([\"--version\"]).",
            "The installed vendor binary must print the exact release version.",
            "The Composer binary runs doctor/init and the package is removed with composer remove.",
        ),
    ),
    deployment(
        "ruby-rubygems",
        "Ruby",
        "RubyGems",
        "gem dependency and executable",
        "library + CLI",
        "sshfling-VERSION.gem",
        "package-ruby",
        ["packaging/ruby/sshfling.gemspec", "packaging/ruby/lib/sshfling.rb", "packaging/ruby/bin/sshfling", "packaging/build-ruby.sh"],
        (
            "The gem contains a Ruby module API and executable.",
            "The gemspec declares package identity, Ruby floor, files, bindir, and executable.",
            "packaging/build-ruby.sh runs strict gem build with the injected release version.",
            "Gem inspection requires the runtime and systemd/secrets templates in data.tar.gz.",
            "RubyGems installs into isolated GEM_HOME, GEM_PATH, and bindir locations.",
            "An installed Ruby consumer requires sshfling and invokes SSHFling.run.",
            "The installed gem command must print the exact release version.",
            "The command runs doctor/init and gem uninstall removes the package and executable.",
        ),
    ),
    deployment(
        "ruby-bundler",
        "Ruby",
        "Bundler",
        "bundled application dependency",
        "library + CLI",
        "sshfling-VERSION.gem / source path",
        "package-ruby",
        ["packaging/ruby/sshfling.gemspec", "packaging/ruby/lib/sshfling.rb", "packaging/build-ruby.sh"],
        (
            "The same Ruby library is consumed through a generated Bundler application.",
            "Bundler resolves the versioned gemspec through an explicit local path dependency.",
            "The strict gem build precedes local Bundler validation.",
            "Gem archive inspection proves library, executable, runtime, and templates are packaged.",
            "bundle install --local uses an isolated BUNDLE_PATH with shared gems disabled.",
            "bundle exec ruby requires sshfling and invokes SSHFling.run([\"--version\"]).",
            "bundle exec sshfling must print the exact release version.",
            "The Bundler command runs init and validation removes bundle state and the lock file.",
        ),
    ),
    deployment(
        "c-cmake-shared",
        "C",
        "CMake",
        "shared-library dependency",
        "library",
        "sshfling-native-VERSION.tar.gz / libsshfling.so",
        "package-native-libraries",
        [
            "packaging/native/CMakeLists.txt",
            "packaging/native/include/sshfling/sshfling.h",
            "packaging/native/consumers/c/CMakeLists.txt",
            "packaging/build-native-libraries.sh",
        ],
        (
            "The C11 implementation, public header, and external C consumer are tracked under packaging/native.",
            "CMake exports the versioned SSHFling::shared target and installs the public include directory.",
            "packaging/build-native-libraries.sh performs warning-clean Ninja/Release, Make/Debug, and ASan/UBSan builds with CTest.",
            "The install is checked for the shared object, versioned symlinks, header, runtime, and package config.",
            "A clean external CMake project resolves find_package(SSHFling) from an isolated prefix.",
            "The C consumer links SSHFling::shared and invokes sshfling_version plus sshfling_run.",
            "The shared-library consumer output must contain the exact release version.",
            "The library launches the bundled runtime and the installed CLI completes an init workflow.",
        ),
    ),
    deployment(
        "c-cmake-static",
        "C",
        "CMake",
        "static-library dependency",
        "library",
        "sshfling-native-VERSION.tar.gz / libsshfling.a",
        "package-native-libraries",
        [
            "packaging/native/CMakeLists.txt",
            "packaging/native/include/sshfling/sshfling.h",
            "packaging/native/consumers/c-static/CMakeLists.txt",
            "packaging/build-native-libraries.sh",
        ],
        (
            "The same stable C API is available through a separately exported static target.",
            "CMake exports SSHFling::static with installed headers and version compatibility metadata.",
            "The native package build produces the static archive from warning-clean C11 objects in Release, Debug, and sanitizer configurations.",
            "Install inspection requires libsshfling.a and the source archive requires the C API header.",
            "A dedicated clean CMake C project resolves the installed static target.",
            "The consumer links SSHFling::static and invokes the same public launcher API.",
            "The static C consumer validates sshfling_version against the exact release version.",
            "The statically linked launcher executes the installed bundled runtime and templates.",
        ),
    ),
    deployment(
        "c-pkg-config",
        "C",
        "pkg-config",
        "compiler dependency",
        "library",
        "sshfling-native-VERSION.tar.gz / sshfling.pc",
        "package-native-libraries",
        [
            "packaging/native/cmake/sshfling.pc.in",
            "packaging/native/consumers/c/main.c",
            "packaging/build-native-libraries.sh",
        ],
        (
            "The public C consumer and pkg-config template are tracked with the native implementation.",
            "sshfling.pc declares the installed include path, library path, linker flag, and version.",
            "The native builder configures, compiles, tests, and installs the metadata before consumption.",
            "Install and archive checks cover the native library, header, runtime, templates, and source project.",
            "gcc compiles the consumer using only flags returned from the isolated prefix's pkg-config entry.",
            "The resulting program invokes the public C version and run functions.",
            "The pkg-config consumer output must contain the exact release version.",
            "LD_LIBRARY_PATH is isolated to the installation under test while the API launches the bundled runtime.",
        ),
    ),
    deployment(
        "c-native-cli",
        "C",
        "CMake",
        "installed native executable",
        "CLI",
        "sshfling-native-VERSION.tar.gz / sshfling-c",
        "package-native-libraries",
        [
            "packaging/native/src/main.c",
            "packaging/native/src/sshfling.c",
            "packaging/build-native-libraries.sh",
        ],
        (
            "The native executable entry point and process launcher implementation are tracked C11 sources.",
            "The CMake project installs sshfling-c with an install-relative shared-library runtime path.",
            "The package target compiles and links the executable alongside both native libraries.",
            "The isolated prefix must contain an executable sshfling-c and the source archive includes its sources.",
            "Validation executes only the binary installed under the temporary prefix.",
            "sshfling-c forwards arbitrary command arguments to the canonical bundled runtime.",
            "The installed native command must print the exact release version.",
            "The command runs init, verifies native helper modes, and is removed through the CMake install manifest.",
        ),
    ),
    deployment(
        "cpp-cmake-static",
        "C++",
        "CMake",
        "C++17 static-library dependency",
        "library",
        "sshfling-native-VERSION.tar.gz / sshfling.hpp",
        "package-native-libraries",
        [
            "packaging/native/include/sshfling/sshfling.hpp",
            "packaging/native/consumers/cpp/CMakeLists.txt",
            "packaging/native/consumers/cpp/main.cpp",
            "packaging/build-native-libraries.sh",
        ],
        (
            "A typed C++17 header wrapper and external C++ consumer are tracked with the native package.",
            "The wrapper consumes installed C API declarations and the project exports SSHFling::static.",
            "The C++ API test compiles warning-clean in Release, Debug, and ASan/UBSan builds before the external consumer runs.",
            "The install requires sshfling.hpp and libsshfling.a; the source archive includes both consumers.",
            "A clean C++ CMake project resolves the installed package and links its static target.",
            "The consumer invokes sshfling::version and sshfling::run through the public wrapper.",
            "The C++ consumer validates the exact release version before launching the runtime.",
            "The wrapper executes the same bundled runtime and templates through the underlying native library.",
        ),
    ),
    deployment(
        "visual-basic-nuget-library",
        "Visual Basic/.NET",
        "NuGet",
        "PackageReference library",
        "library",
        "SSHFling.VERSION.nupkg",
        "package-dotnet",
        [
            "packaging/dotnet/SSHFling/SSHFling.csproj",
            "packaging/dotnet/SSHFling.Consumer.VB/SSHFling.Consumer.VB.vbproj",
            "packaging/dotnet/SSHFling.Consumer.VB/Program.vb",
            "packaging/build-dotnet.sh",
        ],
        (
            "A clean Visual Basic application consumes the tracked public SSHFling .NET library.",
            "Its PackageReference version is injected from the exact locally packed NuGet version.",
            "packaging/build-dotnet.sh packs the library and restores the VB project from only the local source.",
            "NuGet inspection requires the library DLL, XML documentation, license, and README.",
            "The Visual Basic project restores and runs outside the library source project.",
            "Program.vb calls SSHFlingRunner.Version and SSHFlingRunner.Run.",
            "The VB consumer checks the API version and exact runtime version output.",
            "The consumer runs init, checks native helpers, and dotnet remove deletes its PackageReference.",
        ),
    ),
    deployment(
        "fsharp-nuget-library",
        "F#",
        "NuGet",
        "PackageReference library",
        "library",
        "SSHFling.VERSION.nupkg",
        "package-dotnet",
        [
            "packaging/dotnet/SSHFling/SSHFling.csproj",
            "packaging/dotnet/SSHFling.Consumer.FSharp/SSHFling.Consumer.FSharp.fsproj",
            "packaging/dotnet/SSHFling.Consumer.FSharp/Program.fs",
            "packaging/build-dotnet.sh",
        ],
        (
            "A clean F# application consumes the tracked public SSHFling .NET library.",
            "Its PackageReference version is injected from the exact locally packed NuGet version.",
            "packaging/build-dotnet.sh packs the library and restores the F# project from only the local source.",
            "NuGet inspection requires the library DLL, XML documentation, license, and README.",
            "The F# project restores and runs outside the library source project.",
            "Program.fs calls SSHFlingRunner.Version and SSHFlingRunner.Run.",
            "The F# consumer checks the API version and exact runtime version output.",
            "The consumer runs init, checks native helpers, and dotnet remove deletes its PackageReference.",
        ),
    ),
    deployment(
        "perl-makemaker",
        "Perl",
        "MakeMaker/CPAN",
        "source distribution dependency",
        "library + CLI",
        "sshfling-perl-VERSION.tar.gz",
        "package-perl",
        [
            "packaging/perl/Makefile.PL",
            "packaging/perl/lib/SSHFling.pm",
            "packaging/perl/bin/sshfling",
            "packaging/perl/t/01-api.t",
            "packaging/build-perl.sh",
        ],
        (
            "The Perl module, executable, MakeMaker metadata, and API test are tracked under packaging/perl.",
            "Makefile.PL declares version, Perl floor, prerequisites, executable, resources, and bundled runtime files.",
            "packaging/build-perl.sh runs Makefile.PL, manifest generation, make test, and make dist.",
            "Archive checks require the module, build metadata, Python runtime, and native template helpers.",
            "make pure_install installs the distribution into an isolated INSTALL_BASE prefix.",
            "A clean Perl process imports SSHFling, invokes version and run, and the installed executable is run directly.",
            "The module and installed command must report the exact release version.",
            "The command runs init, checks native helpers, and prefix removal makes the module unimportable.",
        ),
    ),
    deployment(
        "kotlin-maven-library",
        "Kotlin",
        "Maven",
        "Kotlin/JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/kotlin/pom.xml",
            "packaging/java/consumers/kotlin/src/main/kotlin/io/sshfling/validation/KotlinConsumer.kt",
            "packaging/build-java.sh",
        ],
        (
            "A Kotlin source consumer and standalone Maven project are tracked under packaging/java/consumers/kotlin.",
            "The POM pins Kotlin 2.4, JVM target 11, Maven execution metadata, and the SSHFling release coordinate.",
            "packaging/build-java.sh compiles the clean Kotlin project from the isolated Maven repository.",
            "Validation requires the compiled KotlinConsumer.class before executing the application.",
            "The clean project resolves SSHFling and Kotlin dependencies through its generated Maven repository.",
            "KotlinConsumer passes its argument array to the public Java SSHFling.run API.",
            "The Kotlin API consumer must print the exact SSHFling release version.",
            "The Kotlin consumer runs init and verifies both generated native identity helpers.",
        ),
    ),
    deployment(
        "scala-maven-library",
        "Scala",
        "Maven",
        "Scala 3 JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/scala/pom.xml",
            "packaging/java/consumers/scala/src/main/scala/io/sshfling/validation/ScalaConsumer.scala",
            "packaging/build-java.sh",
        ],
        (
            "A Scala 3 source consumer and standalone Maven project are tracked under packaging/java/consumers/scala.",
            "The POM pins Scala 3.3 LTS, the Scala Maven plugin, Java release 11, and the SSHFling coordinate.",
            "packaging/build-java.sh compiles the clean Scala project from the isolated Maven repository.",
            "Validation requires the compiled ScalaConsumer.class before executing the application.",
            "The clean project resolves SSHFling and Scala dependencies through its generated Maven repository.",
            "ScalaConsumer passes its argument array to the public Java SSHFling.run API.",
            "The Scala API consumer must print the exact SSHFling release version.",
            "The Scala consumer runs init and verifies both generated native identity helpers.",
        ),
    ),
    deployment(
        "groovy-maven-library",
        "Groovy",
        "Maven",
        "Groovy/JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/groovy/pom.xml",
            "packaging/java/consumers/groovy/src/main/groovy/io/sshfling/validation/GroovyConsumer.groovy",
            "packaging/build-java.sh",
        ],
        (
            "A Groovy source consumer and standalone Maven project are tracked under packaging/java/consumers/groovy.",
            "The POM pins Groovy 5, GMavenPlus, Java bytecode 11, and the SSHFling release coordinate.",
            "packaging/build-java.sh compiles the clean Groovy project from the isolated Maven repository.",
            "Validation requires the compiled GroovyConsumer.class before executing the application.",
            "The clean project resolves SSHFling and Groovy dependencies through its generated Maven repository.",
            "GroovyConsumer passes its argument array to the public Java SSHFling.run API.",
            "The Groovy API consumer must print the exact SSHFling release version.",
            "The Groovy consumer runs init and verifies both generated native identity helpers.",
        ),
    ),
    deployment(
        "kotlin-gradle-library",
        "Kotlin",
        "Gradle",
        "Kotlin/JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/kotlin-gradle/build.gradle.kts",
            "packaging/java/consumers/kotlin-gradle/src/main/kotlin/io/sshfling/validation/KotlinGradleConsumer.kt",
            "packaging/build-java.sh",
        ],
        (
            "A Kotlin source consumer and standalone Gradle project are tracked under packaging/java/consumers/kotlin-gradle.",
            "The build pins the Kotlin JVM plugin, JVM target 11, repositories, and the SSHFling release coordinate.",
            "packaging/build-java.sh compiles the clean Kotlin Gradle project against the isolated Maven publication.",
            "Validation requires a nonempty KotlinGradleConsumer.class with Java class-file major version 55.",
            "The project resolves SSHFling from the generated repository while Gradle resolves the pinned Kotlin toolchain.",
            "KotlinGradleConsumer passes its argument array to the public Java SSHFling.run API.",
            "The Kotlin Gradle API consumer must print the exact SSHFling release version.",
            "The Kotlin Gradle consumer runs init and verifies both generated native identity helpers.",
        ),
    ),
    deployment(
        "scala-gradle-library",
        "Scala",
        "Gradle",
        "Scala 3 JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/scala-gradle/build.gradle.kts",
            "packaging/java/consumers/scala-gradle/src/main/scala/io/sshfling/validation/ScalaGradleConsumer.scala",
            "packaging/build-java.sh",
        ],
        (
            "A Scala 3 source consumer and standalone Gradle project are tracked under packaging/java/consumers/scala-gradle.",
            "The build pins Scala 3.3, Java release 11 compiler options, repositories, and the SSHFling coordinate.",
            "packaging/build-java.sh compiles the clean Scala Gradle project against the isolated Maven publication.",
            "Validation requires a nonempty ScalaGradleConsumer.class with Java class-file major version 55.",
            "The project resolves SSHFling from the generated repository while Gradle resolves the pinned Scala compiler.",
            "ScalaGradleConsumer passes its argument array to the public Java SSHFling.run API.",
            "The Scala Gradle API consumer must print the exact SSHFling release version.",
            "The Scala Gradle consumer runs init and verifies both generated native identity helpers.",
        ),
    ),
    deployment(
        "groovy-gradle-library",
        "Groovy",
        "Gradle",
        "Groovy/JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/groovy-gradle/build.gradle.kts",
            "packaging/java/consumers/groovy-gradle/src/main/groovy/io/sshfling/validation/GroovyGradleConsumer.groovy",
            "packaging/build-java.sh",
        ],
        (
            "A Groovy source consumer and standalone Gradle project are tracked under packaging/java/consumers/groovy-gradle.",
            "The build pins Groovy 5, Java bytecode 11 compiler options, repositories, and the SSHFling coordinate.",
            "packaging/build-java.sh compiles the clean Groovy Gradle project against the isolated Maven publication.",
            "Validation requires a nonempty GroovyGradleConsumer.class with Java class-file major version 55.",
            "The project resolves SSHFling from the generated repository while Gradle resolves the pinned Groovy compiler.",
            "GroovyGradleConsumer passes its argument array to the public Java SSHFling.run API.",
            "The Groovy Gradle API consumer must print the exact SSHFling release version.",
            "The Groovy Gradle consumer runs init and verifies both generated native identity helpers.",
        ),
    ),
    deployment(
        "clojure-maven-library",
        "Clojure",
        "Maven",
        "Clojure/JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/clojure/pom.xml",
            "packaging/java/consumers/clojure/src/main/clojure/io/sshfling/validation/clojure_consumer.clj",
            "packaging/build-java.sh",
        ],
        (
            "A Clojure namespace and standalone Maven consumer are tracked under packaging/java/consumers/clojure.",
            "The POM pins Clojure 1.12, Java release 11, Maven plugins, and the SSHFling coordinate.",
            "packaging/build-java.sh runs Maven verify from a clean copied Clojure project.",
            "Maven verification requires the Clojure namespace in the packaged consumer JAR.",
            "The consumer resolves SSHFling and Clojure through an isolated Maven repository.",
            "The namespace converts its argument sequence to String[] and invokes SSHFling.run.",
            "The Clojure Maven consumer must print the exact SSHFling release version.",
            "The Clojure Maven consumer runs init and verifies generated native identity helpers.",
        ),
    ),
    deployment(
        "clojure-gradle-library",
        "Clojure",
        "Gradle",
        "Clojure/JVM dependency",
        "library",
        "io.sshfling:sshfling-cli:VERSION",
        "package-java",
        [
            "packaging/java/consumers/clojure-gradle/build.gradle.kts",
            "packaging/java/consumers/clojure-gradle/src/main/clojure/io/sshfling/validation/clojure_gradle_consumer.clj",
            "packaging/build-java.sh",
        ],
        (
            "A Clojure namespace and standalone Gradle consumer are tracked under packaging/java/consumers/clojure-gradle.",
            "The build pins Clojure 1.12, Java 11 compatibility, repositories, and the SSHFling coordinate.",
            "packaging/build-java.sh runs the Gradle check task from a clean copied Clojure project.",
            "Gradle verification requires the Clojure namespace in the packaged consumer JAR and resources output.",
            "The consumer resolves SSHFling only from the generated repository and Clojure from Maven Central.",
            "The namespace converts its argument sequence to String[] and invokes SSHFling.run.",
            "The Clojure Gradle consumer must print the exact SSHFling release version.",
            "The Clojure Gradle consumer runs init and verifies generated native identity helpers.",
        ),
    ),
    node_language_consumer(
        "react-npm-consumer",
        "React/JSX",
        "server-rendered JSX dependency",
        ["src/StatusPage.jsx", "test/render.mjs"],
        "esbuild compiles the JSX module and React renders it to static markup without browser scripts.",
        "The server component invokes sshfling.run and templateDir during Node-side rendering.",
    ),
    node_language_consumer(
        "vue-npm-consumer",
        "Vue",
        "server-rendered component dependency",
        ["src/status-app.mjs", "test/render.mjs"],
        "Vue's server renderer produces markup whose assertions prove the SSHFling package check completed.",
        "The Vue setup function invokes sshfling.run and templateDir exclusively in the Node renderer.",
    ),
    node_language_consumer(
        "svelte-npm-consumer",
        "Svelte",
        "server-compiled component dependency",
        ["src/Status.svelte", "build.mjs", "test/render.mjs"],
        "The Svelte compiler emits a server target and the server renderer validates its generated markup.",
        "The Svelte server module invokes sshfling.run and templateDir without exposing process access to a browser.",
    ),
    node_language_consumer(
        "angular-npm-consumer",
        "Angular",
        "typed server-rendered dependency",
        ["src/server.ts", "tsconfig.json"],
        "Strict TypeScript compilation and Angular renderApplication produce and validate server-rendered markup.",
        "The standalone Angular server component invokes sshfling.run and templateDir under Node.",
    ),
    node_language_consumer(
        "elm-npm-consumer",
        "Elm",
        "Node port dependency",
        ["src/Main.elm", "elm.json", "test.cjs"],
        "elm make compiles a Platform.worker and its Node host validates the complete port round trip.",
        "The Elm worker sends typed arguments over ports to a Node host that invokes the SSHFling library.",
    ),
    node_language_consumer(
        "purescript-npm-consumer",
        "PureScript",
        "Node FFI dependency",
        ["src/Main.purs", "src/Main.js", "test.mjs"],
        "The PureScript compiler validates the foreign imports and the generated module executes under Node.",
        "The foreign module invokes sshfling.run and templateDir, exposing typed values to PureScript.",
    ),
    node_language_consumer(
        "rescript-npm-consumer",
        "Reason/ReScript",
        "CommonJS binding dependency",
        ["src/Main.res", "rescript.json", "test.cjs"],
        "The ReScript compiler emits a CommonJS module and the Node test validates its exported status and templates.",
        "Typed @module bindings call the SSHFling run and templateDir exports from ReScript.",
    ),
    node_language_consumer(
        "html-css-npm-consumer",
        "HTML/CSS",
        "trusted static-build dependency",
        ["build.cjs", "src/styles.css", "test.cjs"],
        "A trusted Node build validates SSHFling before emitting script-free HTML and CSS output.",
        "The build process invokes the SSHFling library; the generated static page explicitly has no process capability.",
    ),
    scripting_language_package(
        "tcl-package-library",
        "Tcl",
        "Tcl package archive",
        "versioned source package",
        "library + CLI",
        "sshfling-tcl-VERSION.tar.gz",
        "packaging/tcl",
        ["package-metadata.json", "pkgIndex.tcl", "sshfling.tcl", "bin/sshfling"],
        "package-metadata.json and pkgIndex.tcl declare the versioned Tcl package and runtime entry point.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "A clean TCLLIBPATH consumer resolves package require -exact before the archive is removed.",
        "The Tcl namespace exposes version, runtime/template paths, and a run procedure that invokes the bundled runtime.",
    ),
    scripting_language_package(
        "awk-source-library",
        "AWK",
        "source archive",
        "mawk-compatible source package",
        "library + CLI",
        "sshfling-awk-VERSION.tar.gz",
        "packaging/awk",
        ["package-metadata.json", "sshfling.awk", "cli.awk", "sshfling"],
        "package-metadata.json declares the AWK source API, CLI contract, runtime, and templates.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "A clean mawk-compatible probe loads sshfling.awk and invokes its public functions.",
        "The source API exposes version, runtime/template paths, and argument-safe execution of the bundled runtime.",
    ),
    scripting_language_package(
        "sed-command-package",
        "sed",
        "source archive",
        "sed command-file package",
        "command file + CLI",
        "sshfling-sed-VERSION.tar.gz",
        "packaging/sed",
        ["package-metadata.json", "sshfling-version.sed"],
        "package-metadata.json declares the sed command-file input and output contract.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "An isolated sed process loads the packaged command file against real and malformed CLI output.",
        "The command file extracts the exact semantic version only from canonical SSHFling version output.",
    ),
    scripting_language_package(
        "lua-source-library",
        "Lua",
        "source archive",
        "Lua source module package",
        "library + CLI",
        "sshfling-lua-VERSION.tar.gz",
        "packaging/lua",
        ["package-metadata.json", "lua/sshfling/init.lua", "bin/sshfling", "sshfling-0.0.0-1.rockspec"],
        "package-metadata.json and the rockspec declare Lua 5.1+ compatibility, module files, and CLI installation.",
        "The batch creates, lists, extracts, and validates the source archive and its bundled runtime assets.",
        "Clean Lua 5.1 and Lua 5.4 paths require the module directly from the extracted archive.",
        "The Lua module exposes version, runtime/template paths, and an argv-preserving run function.",
    ),
    scripting_language_package(
        "lua-luarocks-library",
        "Lua",
        "LuaRocks",
        "all-platform rock dependency",
        "library + CLI",
        "sshfling-VERSION-1.all.rock",
        "packaging/lua",
        ["package-metadata.json", "lua/sshfling/init.lua", "bin/sshfling", "sshfling-0.0.0-1.rockspec"],
        "The rockspec declares the Lua dependency, importable sshfling module, and installed CLI.",
        "LuaRocks packs a nonempty .all.rock after installing and executing the package in an isolated tree.",
        "A clean LuaRocks tree imports sshfling, invokes its API and CLI, then removes both module and executable.",
        "The installed Lua module exposes version and run APIs while the rock installs the matching sshfling command.",
    ),
    scripting_language_package(
        "zsh-source-module",
        "Zsh",
        "source archive",
        "sourceable shell module package",
        "source module + CLI",
        "sshfling-zsh-VERSION.tar.gz",
        "packaging/shell-languages/zsh",
        ["package-metadata.json", "sshfling.zsh"],
        "package-metadata.json declares the source module functions, CLI, runtime, and templates.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "A clean Zsh process sources the installed module and completes the version and init workflows.",
        "The module exposes version, runtime/template paths, and an argv-preserving sshfling_run function.",
    ),
    scripting_language_package(
        "fish-source-module",
        "Fish",
        "source archive",
        "sourceable shell module package",
        "source module + CLI",
        "sshfling-fish-VERSION.tar.gz",
        "packaging/shell-languages/fish",
        ["package-metadata.json", "sshfling.fish"],
        "package-metadata.json declares the source module functions, CLI, runtime, and templates.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "A clean Fish process sources the installed module and completes the version and init workflows.",
        "The module exposes version, runtime/template paths, and an argv-preserving sshfling_run function.",
    ),
    scripting_language_package(
        "elvish-source-module",
        "Elvish",
        "source archive",
        "importable shell module package",
        "source module + CLI",
        "sshfling-elvish-VERSION.tar.gz",
        "packaging/shell-languages/elvish",
        ["package-metadata.json", "sshfling.elv"],
        "package-metadata.json declares the importable module functions, CLI, runtime, and templates.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "A clean Elvish 0.21 process imports the installed module and completes the version and init workflows.",
        "The module exposes version, runtime/template paths, and an argv-preserving run function.",
    ),
    scripting_language_package(
        "nushell-source-module",
        "Nushell",
        "source archive",
        "importable shell module package",
        "source module + CLI",
        "sshfling-nushell-VERSION.tar.gz",
        "packaging/shell-languages/nushell",
        ["package-metadata.json", "sshfling.nu"],
        "package-metadata.json declares the exported module commands, CLI, runtime, and templates.",
        "The batch creates, lists, extracts, and validates the versioned tar archive.",
        "A clean Nushell process imports the installed module and completes the version and init workflows.",
        "The wrapped module command exposes version, runtime/template paths, and argv-preserving external execution.",
    ),
    scripting_language_package(
        "powershell-module-package",
        "PowerShell",
        "PowerShell module archive",
        "versioned module package",
        "library + CLI",
        "sshfling-powershell-VERSION.tar.gz",
        "packaging/shell-languages/powershell",
        ["package-metadata.json", "SSHFling.psd1", "SSHFling.psm1", "sshfling.ps1"],
        "The module manifest declares its version, PowerShell floor, exported functions, project metadata, and native CLI.",
        "The batch creates, lists, extracts, and validates the module archive, manifest, native CLI, runtime, and templates.",
        "A clean pwsh process imports the extracted manifest and executes both module and native-script consumers.",
        "The module exposes version, runtime/template paths, and an argument-list-safe Invoke-SSHFling function.",
    ),
]


def validated_batch_package(
    deployment_id: str,
    language: str,
    package_manager: str,
    deployment_type: str,
    interface_type: str,
    artifact: str,
    build_target: str,
    package_root: str,
    required_paths: list[str],
    metadata_summary: str,
    build_summary: str,
    artifact_summary: str,
    consumer_summary: str,
    interface_summary: str,
    runtime_summary: str,
) -> dict[str, object]:
    """Describe a package whose focused batch validator completed all eight checks."""

    item = deployment(
        deployment_id,
        language,
        package_manager,
        deployment_type,
        interface_type,
        artifact,
        build_target,
        required_paths,
        (
            f"Tracked {language} package sources and its public surface live under {package_root}.",
            metadata_summary,
            build_summary,
            artifact_summary,
            consumer_summary,
            interface_summary,
            f"The focused {language} consumer must print the exact SSHFling release version.",
            runtime_summary,
        ),
    )
    item["validation_evidence"] = build_summary
    return item


# These package trees were omitted by the original deployment matrix even though
# their focused validators exercise real package metadata and language APIs. They
# are appended so the existing LD identifiers remain stable.
DEPLOYMENTS.extend(
    [
        validated_batch_package(
            "posix-shell-runtime-cli",
            "Shell/POSIX sh",
            "Make/install scripts",
            "local install and runtime command set",
            "CLI",
            "installed sshfling command and POSIX runtime scripts",
            "test",
            "scripts and production",
            [
                "Makefile",
                "scripts/install-local.sh",
                "scripts/uninstall-local.sh",
                "native/sshfling-unix-identity",
                "production/sshfling-login-shell",
                "tests/cross-os/validate-local-install.sh",
            ],
            "Make install/uninstall targets declare the command, helper, template, and removal layout.",
            "The test target runs sh syntax checks and an isolated local-install lifecycle.",
            "The isolated prefix is checked for the command, POSIX helpers, templates, and executable modes.",
            "tests/cross-os/validate-local-install.sh invokes the command from a temporary installation prefix.",
            "The installed command and POSIX helper scripts are executable CLI surfaces, not an importable shell library.",
            "Local-install validation exercises version, init assets, helper execution, and uninstall cleanup.",
        ),
        validated_batch_package(
            "bash-maintainer-cli",
            "Bash",
            "Make/source tree",
            "maintainer and packaging command suite",
            "CLI tooling",
            "versioned packaging and validation scripts",
            "test",
            "packaging and tests",
            [
                "Makefile",
                "packaging/version.sh",
                "packaging/build-scripting-languages.sh",
                "tests/release/validate-release-matrix.sh",
            ],
            "The Makefile and version helper define strict Bash entry points and the release-version contract.",
            "The test target applies bash -n and executes the Bash release validators.",
            "The checked surface is the tracked command suite; it is not advertised as a Bash package or library artifact.",
            "Release tests invoke the scripts from the repository and isolated temporary workspaces.",
            "The Bash surface consists of maintainer-facing CLI commands with strict argument and exit-status handling.",
            "Release validation covers version resolution, package workflows, temporary state, and cleanup.",
        ),
        validated_batch_package(
            "r-source-package",
            "R",
            "R CMD",
            "R source package dependency",
            "library",
            "sshfling_VERSION.tar.gz",
            "package-functional-languages",
            "packaging/scientific-languages/r",
            [
                "packaging/scientific-languages/r/DESCRIPTION",
                "packaging/scientific-languages/r/NAMESPACE",
                "packaging/scientific-languages/r/R/sshfling.R",
                "packaging/scientific-languages/r/tests/check-api.R",
                "packaging/build-functional-languages.py",
            ],
            "DESCRIPTION and NAMESPACE declare the versioned R package and exported launcher functions.",
            "The per-language validator runs R CMD build, R CMD check, and R CMD INSTALL at VERSION=0.1.22.",
            "The source archive and installed runtime inventory are recorded and compared byte-for-byte.",
            "A clean external Rscript consumer loads the installed namespace outside the source tree.",
            "The exported R functions preserve argument vectors and return the canonical runtime status.",
            "The consumer validates version, invalid-option, init, missing-runtime, removal, and import-absence cases.",
        ),
        validated_batch_package(
            "objective-c-cmake-package",
            "Objective-C",
            "CMake/source build",
            "Objective-C shared-library dependency",
            "library + CLI",
            "libsshfling_objc.so and sshfling-objective-c validation artifacts",
            "package-systems-languages",
            "packaging/systems-languages/objective-c",
            [
                "packaging/systems-languages/objective-c/CMakeLists.txt",
                "packaging/systems-languages/objective-c/include/SSHFling/SSHFling.h",
                "packaging/systems-languages/objective-c/src/SSHFling.m",
                "packaging/systems-languages/objective-c/consumers/main.m",
                "packaging/build-systems-languages.sh",
            ],
            "CMake metadata and the public SSHFling Objective-C header define the source-package contract.",
            "The focused systems validator compiles warning-clean shared-library, CLI, and consumer binaries.",
            "Validation produces a shared library and CLI in its temporary, isolated output directory.",
            "A separately compiled Objective-C consumer links the temporary library and checks the release version.",
            "SSHFling exposes version and argument-array run methods through the public Objective-C header.",
            "The library consumer and CLI validate version, init, invalid-option, and missing-runtime behavior.",
        ),
        validated_batch_package(
            "assembly-source-package",
            "Assembly",
            "GNU/Clang toolchain",
            "x86_64 ELF source package",
            "library + CLI",
            "libsshfling_assembly.so and sshfling-assembly validation artifacts",
            "package-systems-languages",
            "packaging/systems-languages/assembly",
            [
                "packaging/systems-languages/assembly/package.toml",
                "packaging/systems-languages/assembly/include/sshfling_assembly.h",
                "packaging/systems-languages/assembly/src/sshfling.S",
                "packaging/systems-languages/assembly/src/main.S",
                "packaging/build-systems-languages.sh",
            ],
            "package.toml and the C-compatible header declare the x86_64 assembly package boundary.",
            "The focused systems validator compiles PIC assembly, links a shared library and CLI, and extracts debug data.",
            "Temporary output checks require the shared object, command, and nonempty debug artifact.",
            "A clean C ABI probe links the assembly library and invokes its version and run symbols.",
            "The assembly package exports a stable C ABI plus an executable command.",
            "The API and CLI validate exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "cobol-source-package",
            "COBOL",
            "GnuCOBOL",
            "free-format COBOL source package",
            "library module + CLI",
            "COBOL object module and sshfling-cobol validation command",
            "package-systems-languages",
            "packaging/systems-languages/cobol",
            [
                "packaging/systems-languages/cobol/package.toml",
                "packaging/systems-languages/cobol/src/sshfling.cob",
                "packaging/systems-languages/cobol/app/main.cob",
                "packaging/systems-languages/cobol/consumers/main.cob",
                "packaging/build-systems-languages.sh",
            ],
            "package.toml identifies the module, application, and external consumer sources.",
            "The focused systems validator compiles the module and links the CLI with warnings treated as errors.",
            "The validator requires a nonempty COBOL object and executable in its isolated output directory.",
            "The freshly linked command consumes the compiled COBOL module outside the package source layout.",
            "The COBOL module forwards an argument vector through the shared launcher contract.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "fortran-fpm-package",
            "Fortran",
            "fpm/source build",
            "Fortran 2018 module dependency",
            "library module + CLI",
            "Fortran module objects and sshfling-fortran validation command",
            "package-systems-languages",
            "packaging/systems-languages/fortran",
            [
                "packaging/systems-languages/fortran/fpm.toml",
                "packaging/systems-languages/fortran/src/sshfling.f90",
                "packaging/systems-languages/fortran/app/main.f90",
                "packaging/systems-languages/fortran/consumers/main.f90",
                "packaging/build-systems-languages.sh",
            ],
            "fpm.toml declares the package while the source tree separates the module, app, and consumer.",
            "The focused systems validator compiles Fortran 2018 sources with warnings treated as errors.",
            "Generated module/object files and the command remain isolated validation artifacts.",
            "The compiled command imports the Fortran module and runs outside the source package directory.",
            "The Fortran module exposes the launcher routine consumed by the packaged command.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "elixir-mix-library",
            "Elixir",
            "Mix",
            "Mix path dependency",
            "library",
            "versioned Mix package tree",
            "package-functional-languages",
            "packaging/beam-languages/elixir",
            [
                "packaging/beam-languages/elixir/mix.exs",
                "packaging/beam-languages/elixir/lib/sshfling.ex",
                "packaging/beam-languages/elixir/test/sshfling_consumer_test.exs",
                "packaging/build-functional-languages.py",
            ],
            "mix.exs declares the application, release version, bundled runtime, and public module.",
            "The per-language validator compiles with warnings as errors and resolves an isolated path dependency.",
            "The staged Mix package contains compiled code plus a byte-checked canonical runtime bundle.",
            "An external Mix project depends on the staged package and invokes it from an unrelated directory.",
            "SSHFling.run/1 executes the canonical runtime with an argument list and returns its status.",
            "The external project validates version, init, invalid option, missing runtime, dependency removal, and import absence.",
        ),
        validated_batch_package(
            "erlang-otp-library",
            "Erlang",
            "OTP/erlc",
            "OTP application dependency",
            "library",
            "sshfling-VERSION OTP application tree",
            "package-functional-languages",
            "packaging/beam-languages/erlang",
            [
                "packaging/beam-languages/erlang/rebar.config",
                "packaging/beam-languages/erlang/src/sshfling.app.src",
                "packaging/beam-languages/erlang/src/sshfling.erl",
                "packaging/beam-languages/erlang/test/sshfling_consumer.erl",
                "packaging/build-functional-languages.py",
            ],
            "rebar.config and sshfling.app.src declare the OTP application and bundled resources.",
            "The per-language validator compiles package and consumer modules with erlc -Werror.",
            "The staged OTP application contains its beam module, application metadata, and canonical runtime bundle.",
            "A separately compiled Erlang module resolves the staged package through isolated code paths.",
            "The sshfling module exposes argument-list execution with exact child status propagation.",
            "The consumer validates version, init, invalid option, missing runtime, package removal, and import absence.",
        ),
        validated_batch_package(
            "haskell-cabal-library",
            "Haskell",
            "Cabal",
            "Cabal library and executable package",
            "library + CLI",
            "sshfling-VERSION Cabal package",
            "package-functional-languages",
            "packaging/functional-languages/haskell",
            [
                "packaging/functional-languages/haskell/sshfling.cabal",
                "packaging/functional-languages/haskell/src/SSHFling.hs",
                "packaging/functional-languages/haskell/app/Main.hs",
                "packaging/functional-languages/haskell/test/Consumer.hs",
                "packaging/build-functional-languages.py",
            ],
            "sshfling.cabal declares the library, command, consumer, resources, and versioned package metadata.",
            "The per-language validator performs an offline Cabal build and resolves both produced executables.",
            "Cabal's isolated build tree contains the library, CLI, consumer, and canonical runtime resources.",
            "The dedicated consumer executable imports SSHFling and runs from outside the source directory.",
            "The SSHFling module exposes argument-list execution while the package also provides a command.",
            "The CLI and consumer validate version, init, invalid option, missing runtime, and Cabal cleanup.",
        ),
        validated_batch_package(
            "ocaml-opam-dune-library",
            "OCaml",
            "opam/Dune",
            "Dune-installed opam package",
            "library + CLI",
            "sshfling.VERSION source archive and Dune install",
            "package-functional-languages",
            "packaging/functional-languages/ocaml",
            [
                "packaging/functional-languages/ocaml/sshfling.opam",
                "packaging/functional-languages/ocaml/dune-project",
                "packaging/functional-languages/ocaml/src/sshfling.mli",
                "packaging/functional-languages/ocaml/test/consumer.ml",
                "packaging/build-functional-languages.py",
            ],
            "opam and Dune metadata declare the library, executable, version, and install layout.",
            "The per-language validator builds @install and installs it into an isolated Dune prefix.",
            "The source archive and installed prefix contain the OCaml library, CLI, and runtime resources.",
            "A clean external Dune project resolves the installed library through an isolated OCAMLPATH.",
            "The public .mli exposes list-based argument execution and the package installs a matching command.",
            "The external consumer validates version, init, invalid option, missing runtime, uninstall, and import absence.",
        ),
        validated_batch_package(
            "zig-build-package",
            "Zig",
            "Zig build",
            "Zig module and executable package",
            "library + CLI",
            "Zig prefix with sshfling-zig command",
            "package-systems-languages",
            "packaging/systems-languages/zig",
            [
                "packaging/systems-languages/zig/build.zig.zon",
                "packaging/systems-languages/zig/build.zig",
                "packaging/systems-languages/zig/src/sshfling.zig",
                "packaging/systems-languages/zig/src/main.zig",
                "packaging/build-systems-languages.sh",
            ],
            "build.zig.zon and build.zig declare the named module, command, and install prefix.",
            "The focused systems validator runs zig build with isolated local and global caches.",
            "The Zig prefix must contain the freshly built sshfling-zig command.",
            "The installed command imports the tracked Zig launcher module and runs from the isolated prefix.",
            "The Zig module supplies launcher functions and the build installs a command.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "nim-nimble-package",
            "Nim",
            "Nimble",
            "Nimble source package",
            "library + CLI",
            "sshfling Nimble package and sshfling-nim validation command",
            "package-systems-languages",
            "packaging/systems-languages/nim",
            [
                "packaging/systems-languages/nim/sshfling.nimble",
                "packaging/systems-languages/nim/src/sshfling.nim",
                "packaging/systems-languages/nim/src/sshfling_cli.nim",
                "packaging/systems-languages/nim/consumers/main.nim",
                "packaging/build-systems-languages.sh",
            ],
            "sshfling.nimble declares the source package, public module, command, and version placeholder.",
            "The focused systems validator runs nim check, nim c, and nimble check with isolated caches.",
            "The resulting validation command links the shared launcher object and remains in a temporary output tree.",
            "The command imports the Nim launcher module using only the package source path.",
            "The Nim module is importable and the package includes a separate CLI entry point.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "crystal-shard-package",
            "Crystal",
            "Shards/Crystal",
            "Crystal shard dependency",
            "library + CLI",
            "sshfling shard and sshfling-crystal validation command",
            "package-systems-languages",
            "packaging/systems-languages/crystal",
            [
                "packaging/systems-languages/crystal/shard.yml",
                "packaging/systems-languages/crystal/src/sshfling.cr",
                "packaging/systems-languages/crystal/src/cli.cr",
                "packaging/systems-languages/crystal/consumers/main.cr",
                "packaging/build-systems-languages.sh",
            ],
            "shard.yml declares the shard identity and the sshfling-crystal command target.",
            "The focused systems validator parses the shard metadata and builds the CLI with isolated caches.",
            "The command and its temporary native launcher library are checked in the isolated output tree.",
            "The built command requires the tracked Crystal library source rather than checkout-wide load paths.",
            "The Crystal source exposes launcher methods and a distinct CLI target.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "d-dub-package",
            "D",
            "Dub/source build",
            "D module and static-library dependency",
            "library + CLI",
            "libsshfling_d.a and sshfling-d validation artifacts",
            "package-systems-languages",
            "packaging/systems-languages/d",
            [
                "packaging/systems-languages/d/dub.json",
                "packaging/systems-languages/d/source/sshfling.d",
                "packaging/systems-languages/d/app/main.d",
                "packaging/systems-languages/d/consumers/main.d",
                "packaging/build-systems-languages.sh",
            ],
            "dub.json declares the D package while source, app, and consumer entry points are tracked separately.",
            "The focused systems validator compiles warning-clean D objects, archives a static library, and links the CLI.",
            "Validation requires a nonempty static archive and executable in the temporary output directory.",
            "The command imports the D source module and links only the freshly built static launcher library.",
            "The D module exposes launcher execution and the package includes a command application.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "ada-alire-package",
            "Ada",
            "Alire/GNAT",
            "Ada library unit and executable package",
            "library + CLI",
            "Ada units and sshfling-ada validation command",
            "package-systems-languages",
            "packaging/systems-languages/ada",
            [
                "packaging/systems-languages/ada/alire.toml",
                "packaging/systems-languages/ada/sshfling.gpr",
                "packaging/systems-languages/ada/src/sshfling.ads",
                "packaging/systems-languages/ada/app/sshfling_main.adb",
                "packaging/systems-languages/ada/consumers/main.adb",
                "packaging/build-systems-languages.sh",
            ],
            "Alire and GPR metadata declare the Ada package, public unit, and executable source layout.",
            "The focused systems validator uses GNAT 2022 checks with warnings promoted to errors.",
            "Compiled Ada units and the linked command are confined to the temporary validation output.",
            "The command withs the public SSHFling unit and links the shared launcher object.",
            "The SSHFling package specification is the public Ada API and the app supplies a CLI.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "common-lisp-asdf-library",
            "Common Lisp",
            "ASDF/Quicklisp",
            "ASDF system dependency",
            "library",
            "sshfling-VERSION ASDF source archive",
            "package-functional-languages",
            "packaging/functional-languages/common-lisp",
            [
                "packaging/functional-languages/common-lisp/sshfling.asd",
                "packaging/functional-languages/common-lisp/src/package.lisp",
                "packaging/functional-languages/common-lisp/src/sshfling.lisp",
                "packaging/functional-languages/common-lisp/test/consumer.lisp",
                "packaging/build-functional-languages.py",
            ],
            "sshfling.asd and package.lisp declare the ASDF system and exported launcher symbols.",
            "The per-language validator compiles the ASDF system from an isolated source registry.",
            "A versioned source archive contains the system sources and byte-checked canonical runtime.",
            "An external SBCL script loads only the installed ASDF system from the isolated registry.",
            "The sshfling package exports argument-list execution with child-status propagation.",
            "The consumer validates version, init, invalid option, missing runtime, removal, and import absence.",
        ),
        validated_batch_package(
            "scheme-guile-library",
            "Scheme/Racket",
            "GNU Guile/Autotools",
            "Guile module source package",
            "library + CLI",
            "sshfling-guile-VERSION.tar.gz",
            "package-functional-languages",
            "packaging/functional-languages/scheme",
            [
                "packaging/functional-languages/scheme/configure.ac",
                "packaging/functional-languages/scheme/module/sshfling.scm.in",
                "packaging/functional-languages/scheme/bin/sshfling-guile.in",
                "packaging/functional-languages/scheme/test/consumer.scm",
                "packaging/build-functional-languages.py",
            ],
            "Autotools metadata declares the Guile module, command, version, and install directories; Racket is not claimed.",
            "The per-language validator builds a dist archive, configures it, runs checks, and installs to an isolated prefix.",
            "The source archive and prefix contain compiled Guile module data, CLI, and canonical runtime.",
            "An external Guile script resolves only the installed module and compiled-object directories.",
            "The Guile module exports run; the package also installs sshfling-guile.",
            "The consumer validates version, init, invalid option, missing runtime, uninstall, and import absence.",
        ),
        validated_batch_package(
            "prolog-swi-pack",
            "Prolog",
            "SWI-Prolog pack",
            "Prolog pack dependency",
            "library",
            "sshfling-VERSION.tgz Prolog pack",
            "package-functional-languages",
            "packaging/functional-languages/prolog",
            [
                "packaging/functional-languages/prolog/pack.pl",
                "packaging/functional-languages/prolog/prolog/sshfling.pl",
                "packaging/functional-languages/prolog/test/consumer.pl",
                "packaging/build-functional-languages.py",
            ],
            "pack.pl declares the SWI-Prolog pack and the module file exports its launcher predicates.",
            "The per-language validator archives and pack-installs the package into an isolated directory.",
            "The installed pack contains the Prolog module and byte-checked canonical runtime bundle.",
            "An external Prolog program attaches the isolated pack and imports library(sshfling).",
            "The public predicate accepts an argument list and reports the exact child status.",
            "The consumer validates version, init, invalid option, missing runtime, pack removal, and import absence.",
        ),
        validated_batch_package(
            "forth-source-library",
            "Forth",
            "Gforth/source package",
            "loadable Forth source package",
            "library + CLI",
            "Forth words, native bridge, and cli.fs",
            "package-systems-languages",
            "packaging/systems-languages/forth",
            [
                "packaging/systems-languages/forth/package.toml",
                "packaging/systems-languages/forth/sshfling.fs",
                "packaging/systems-languages/forth/cli.fs",
                "packaging/systems-languages/forth/bridge.c",
                "packaging/systems-languages/forth/consumers/main.fs",
                "packaging/build-systems-languages.sh",
            ],
            "package.toml declares the source words, CLI, bridge, consumer, and runtime requirements.",
            "The focused systems validator builds the native bridge and loads the Forth API with Gforth.",
            "The temporary bridge library and tracked Forth source form the validated package artifacts.",
            "A clean Gforth process loads sshfling.fs and executes cli.fs with isolated HOME and bridge paths.",
            "The source package exposes sshfling-version and run words plus a command-file CLI.",
            "The command validates exact version, init assets, invalid options, and missing runtime behavior.",
        ),
        validated_batch_package(
            "gleam-hex-library",
            "Gleam",
            "Gleam/Hex",
            "Hex library package",
            "library",
            "sshfling-VERSION Hex tarball",
            "package-functional-languages",
            "packaging/beam-languages/gleam",
            [
                "packaging/beam-languages/gleam/gleam.toml",
                "packaging/beam-languages/gleam/src/sshfling.gleam",
                "packaging/beam-languages/gleam/src/sshfling_ffi.erl",
                "packaging/beam-languages/gleam/test/consumer.gleam",
                "packaging/build-functional-languages.py",
            ],
            "gleam.toml declares the Hex package, target runtime, source modules, and bundled resources.",
            "The per-language validator runs gleam check, exports a Hex tarball, and builds an external consumer.",
            "The exported Hex tarball is nonempty and includes the Gleam/Erlang API plus canonical runtime.",
            "A separate Gleam project imports the staged package and runs dedicated status-case modules.",
            "The typed Gleam API delegates through an Erlang FFI while preserving argument lists and status.",
            "The consumer validates version, init, invalid option, missing runtime, package removal, and import absence.",
        ),
        validated_batch_package(
            "nix-flake-cli",
            "Nix",
            "Nix flakes",
            "flake package and app",
            "CLI",
            "nix build .#default result",
            "test",
            "flake.nix and generated public Nix metadata",
            [
                "flake.nix",
                ".github/workflows/cross-os-validation.yml",
                ".github/workflows/package-install-tests.yml",
                "tests/cross-os/validate-cli.sh",
            ],
            "flake.nix declares versioned packages and apps for four Linux/macOS architectures.",
            "Cross-OS CI builds the generated flake in a pinned Nix container and executes its result.",
            "The derivation installs the command, native helpers, runtime templates, documentation, and wrappers.",
            "tests/cross-os/validate-cli.sh consumes only ./result/bin/sshfling from the Nix build result.",
            "The flake exposes a packaged sshfling CLI app; it does not claim an importable Nix-language library.",
            "The Nix consumer validates the exact version and packaged CLI runtime in its isolated result closure.",
        ),
    ]
)

DEPLOYMENTS.append(
    validated_batch_package(
        "guix-scheme-guile-library",
        "Guix Scheme",
        "Guile source module",
        "versioned Guile module package",
        "library + CLI",
        "sshfling-guix-scheme-VERSION.tar.gz",
        "package-scripting-languages",
        "packaging/guix-scheme",
        [
            "packaging/guix-scheme/package-metadata.json",
            "packaging/guix-scheme/sshfling.scm",
            "packaging/guix-scheme/sshfling-package.scm",
            "packaging/build-scripting-languages.sh",
            ".github/workflows/package-install-tests.yml",
        ],
        "package-metadata.json declares the Guile module, Guix definition, CLI, runtime, and templates.",
        "The scripting batch builds the archive and CI requires a PASS Guile runtime row at VERSION=0.1.22.",
        "Archive checks require the rendered module, package definition, command, runtime, and templates.",
        "An isolated Guile process imports the extracted module and invokes its version and run functions.",
        "The Guile module exposes version, runtime/template paths, and argument-list-safe execution; Guix package-manager validation is separate.",
        "The Guile consumer and packaged CLI validate version, init assets, removal, and import absence.",
    )
)

DEPLOYMENTS.extend(
    [
        validated_batch_package(
            "julia-pkg-library",
            "Julia",
            "Julia Pkg",
            "Julia package dependency and command",
            "library + CLI",
            "sshfling-julia-VERSION.tar.gz",
            "package-functional-languages",
            "packaging/scientific-languages/julia",
            [
                "packaging/scientific-languages/julia/Project.toml",
                "packaging/scientific-languages/julia/src/SSHFling.jl",
                "packaging/scientific-languages/julia/bin/sshfling.jl",
                "packaging/scientific-languages/julia/test/runtests.jl",
                "packaging/build-functional-languages.py",
            ],
            "Project.toml declares the versioned package while the module, command, and tests are separate tracked surfaces.",
            "The per-language validator installs and precompiles the package, runs Pkg.test, and executes an external consumer at VERSION=0.1.22.",
            "The deterministic source archive contains the Julia package and byte-checked canonical runtime bundle.",
            "An unrelated Julia project uses Pkg.develop on the extracted archive and imports SSHFling.",
            "SSHFling.run accepts ARGS and the packaged Julia command exposes the same status-preserving contract.",
            "The consumer validates version, init, invalid option, missing runtime, Pkg removal, and import absence.",
        ),
        validated_batch_package(
            "janet-jpm-library",
            "Janet",
            "JPM",
            "Janet module package and command",
            "library + CLI",
            "sshfling-janet-VERSION.tar.gz",
            "package-functional-languages",
            "packaging/functional-languages/janet",
            [
                "packaging/functional-languages/janet/project.janet",
                "packaging/functional-languages/janet/src/sshfling/init.janet",
                "packaging/functional-languages/janet/bin/sshfling",
                "packaging/functional-languages/janet/test/consumer.janet",
                "packaging/build-functional-languages.py",
            ],
            "project.janet declares the JPM package, module path, executable, version, and bundled resources.",
            "The per-language validator installs from the deterministic archive into an isolated JPM tree and compiles the external consumer.",
            "The versioned source archive and installed package contain the Janet module, command, and canonical runtime.",
            "A clean Janet consumer imports only the installed module outside the source package directory.",
            "The Janet module exposes argument-array execution and the package installs a matching command.",
            "The consumer validates version, init, invalid option, missing runtime, package removal, and import absence.",
        ),
        validated_batch_package(
            "j-addon-library",
            "J",
            "J package",
            "J addon dependency and command",
            "library + CLI",
            "sshfling-j-VERSION.tar.gz",
            "package-functional-languages",
            "packaging/scientific-languages/j",
            [
                "packaging/scientific-languages/j/manifest.ijs",
                "packaging/scientific-languages/j/src/sshfling.ijs",
                "packaging/scientific-languages/j/bin/sshfling.ijs",
                "packaging/scientific-languages/j/test/consumer.ijs",
                "packaging/build-functional-languages.py",
            ],
            "manifest.ijs declares the addon while source, command, and consumer scripts are tracked separately.",
            "The per-language validator installs the deterministic archive as an isolated J addon and runs its external consumer.",
            "The source archive contains the addon, command, consumer, and byte-checked canonical runtime.",
            "An external J script loads the installed addon outside its source and installation directories.",
            "The J addon exposes argument-list execution and includes a command script.",
            "The consumer validates exact version, init, invalid option, missing runtime, addon removal, and import absence.",
        ),
        validated_batch_package(
            "v-vpm-library",
            "V",
            "VPM",
            "V module and executable package",
            "library + CLI",
            "sshfling-v-VERSION.tar.gz",
            "package-systems-languages",
            "packaging/systems-languages/v",
            [
                "packaging/systems-languages/v/v.mod",
                "packaging/systems-languages/v/sshfling/sshfling.v",
                "packaging/systems-languages/v/cmd/sshfling/main.v",
                "packaging/systems-languages/v/consumers/main.v",
                "packaging/build-systems-languages.sh",
            ],
            "v.mod declares the package while module, command, and consumer entry points are tracked separately.",
            "The systems validator extracts the deterministic archive, compiles the package and clean consumer with V, and runs both.",
            "The archive inventory includes the V module, CLI, consumer, shared launcher sources, runtime, and templates.",
            "A clean consumer imports the extracted package without repository-wide module paths.",
            "The V module supplies launcher functions and the package includes an executable command.",
            "The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence.",
        ),
        validated_batch_package(
            "wasi-node-host-command",
            "WebAssembly/WASI",
            "WASI component/source",
            "host-imported WASI command module",
            "CLI module",
            "sshfling-webassembly-wasi-VERSION.tar.gz",
            "package-systems-languages",
            "packaging/systems-languages/webassembly-wasi",
            [
                "packaging/systems-languages/webassembly-wasi/package.toml",
                "packaging/systems-languages/webassembly-wasi/wit/sshfling.wit",
                "packaging/systems-languages/webassembly-wasi/src/main.c",
                "packaging/systems-languages/webassembly-wasi/host/sshfling-wasi.mjs",
                "packaging/systems-languages/webassembly-wasi/consumers/node/main.mjs",
                "packaging/build-systems-languages.sh",
            ],
            "package.toml and WIT declare the WASI command imports, host adapter, consumer, and runtime contract.",
            "The systems validator extracts the archive, compiles wasm32-wasi code, and runs it through the tracked Node host adapter.",
            "The archive contains the WASI module source, WIT, host/consumer modules, runtime, templates, and inventory manifest.",
            "A clean Node consumer executes the built module through the extracted host adapter.",
            "The public boundary is a WASI command module with an explicit trusted host process, not direct kernel process access.",
            "The host-backed command validates version, init, invalid option, missing runtime, removal, and post-removal failure.",
        ),
        validated_batch_package(
            "odin-source-library",
            "Odin",
            "Odin source package",
            "Odin collection and executable",
            "library + CLI",
            "sshfling-odin-VERSION.tar.gz",
            "package-systems-languages",
            "packaging/systems-languages/odin",
            [
                "packaging/systems-languages/odin/package.toml",
                "packaging/systems-languages/odin/sshfling/sshfling.odin",
                "packaging/systems-languages/odin/cmd/sshfling/main.odin",
                "packaging/systems-languages/odin/consumers/main.odin",
                "packaging/build-systems-languages.sh",
            ],
            "package.toml declares the collection, command, consumer, and bundled runtime resources.",
            "The systems validator extracts the archive, builds the Odin collection and command, and executes an isolated consumer.",
            "The deterministic archive contains Odin sources, shared launcher sources, runtime, templates, and inventory manifest.",
            "A clean consumer imports the extracted sshfling collection outside the repository source tree.",
            "The Odin collection exports launcher functions and the package includes a command.",
            "The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence.",
        ),
        validated_batch_package(
            "pony-corral-library",
            "Pony",
            "Corral",
            "Pony package and executable",
            "library + CLI",
            "sshfling-pony-VERSION.tar.gz",
            "package-systems-languages",
            "packaging/systems-languages/pony",
            [
                "packaging/systems-languages/pony/corral.json",
                "packaging/systems-languages/pony/sshfling/sshfling.pony",
                "packaging/systems-languages/pony/main.pony",
                "packaging/systems-languages/pony/consumers/main.pony",
                "packaging/build-systems-languages.sh",
            ],
            "corral.json declares the package while the public package, command, and consumer are tracked separately.",
            "The systems validator extracts the deterministic archive, compiles with ponyc, and runs an isolated consumer.",
            "The versioned source archive includes an inventory manifest, package sources, runtime, and templates.",
            "The isolated consumer imports the extracted Pony package and runs without checkout load paths.",
            "The Pony package exposes launcher behavior and the package builds a corresponding command.",
            "The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence.",
        ),
    ]
)

_dart_deployment = deployment(
    "dart-native-cli-consumer",
    "Dart",
    "pub + npm",
    "compiled server-side adapter",
    "native CLI consumer",
    "sshfling-VERSION.tgz plus sshfling-dart-consumer executable",
    "package-web-language-consumers",
    [
        "packaging/node/consumers/dart/package.json",
        "packaging/node/consumers/dart/pubspec.yaml",
        "packaging/node/consumers/dart/bin/sshfling_consumer.dart",
        "packaging/node/consumers/dart/bridge.cjs",
        "packaging/build-web-language-consumers.sh",
    ],
    (
        "The typed Dart adapter and explicit trusted Node bridge are tracked under packaging/node/consumers/dart.",
        "pubspec.yaml declares Dart 3 compatibility while package.json pins the packed npm dependency and formatting, analysis, compile, and test commands.",
        "The web-language batch performs dart format, dart analyze, offline pub resolution, and dart compile exe after installing only the packed SSHFling npm artifact.",
        "Validation requires the native sshfling-dart-consumer executable and the installed sshfling-VERSION.tgz dependency.",
        "The batch copies the Dart project to a temporary directory, installs the packed dependency, compiles, and executes the native adapter.",
        "The server-side executable launches a fixed Node bridge, which imports sshfling, invokes run, and checks templateDir.",
        "The adapter reaches the packed library's validated --version path and rejects any nonzero status; exact string validation remains on the parent npm artifact.",
        "The native adapter requires successful packed-library execution and bundled-template discovery, then the isolated workspace is removed.",
    ),
)
_dart_deployment["validation_evidence"] = (
    "Dart SDK 3.12.2 completes formatting, analysis, offline resolution, native compilation, "
    "and npm run test:dart; the batch reports [PASS] dart."
)
DEPLOYMENTS.append(_dart_deployment)

_swift_deployment = validated_batch_package(
    "swift-swiftpm-library",
    "Swift",
    "SwiftPM",
    "Swift package dependency and executable",
    "library + CLI",
    "sshfling-swift-VERSION.tar.gz",
    "package-systems-languages",
    "packaging/systems-languages/swift",
    [
        "packaging/systems-languages/swift/Package.swift",
        "packaging/systems-languages/swift/Sources/SSHFling/SSHFling.swift",
        "packaging/systems-languages/swift/Sources/sshfling/main.swift",
        "packaging/systems-languages/swift/Consumers/SSHFlingConsumer/Package.swift",
        "packaging/systems-languages/swift/Consumers/SSHFlingConsumer/Sources/SSHFlingConsumer/main.swift",
        "packaging/build-systems-languages.sh",
        "tools/validate_promoted_language_evidence.py",
        ".github/workflows/language-runtime-validation.yml",
    ],
    "Package.swift declares the Swift library and executable products while the external consumer uses an explicit local-path package dependency.",
    "The Ubuntu 24.04 strict systems validator extracts the deterministic archive, builds the package and external consumer with SwiftPM, and executes both.",
    "The versioned archive contains the SwiftPM manifest, library, executable, consumer project, canonical runtime, templates, and inventory manifest.",
    "A separate SwiftPM project imports the extracted SSHFling product without repository-wide package paths.",
    "The Swift library exposes argument-array execution and the package provides a matching executable command.",
    "The consumer and CLI validate version, init, invalid option, missing runtime, source archive extraction, removal, and import absence.",
)
_swift_evidence = _swift_deployment["evidence"]
assert isinstance(_swift_evidence, dict)
_swift_evidence["version"] = (
    "The hosted SwiftPM consumer and packaged command each report the exact release output sshfling VERSION."
)
_swift_deployment["validation_evidence"] = (
    "The Ubuntu 24.04 strict catalog records RUNTIME swift PASS with archive-lifecycle "
    "mode and the complete SwiftPM library, CLI, removal, and post-removal capability set."
)
DEPLOYMENTS.append(_swift_deployment)

DEPLOYMENTS.append(
    validated_batch_package(
        "guix-scheme-guix-package",
        "Guix Scheme",
        "Guix",
        "Guix package definition",
        "library + CLI package",
        "sshfling-guix-scheme-VERSION.tar.gz",
        "package-scripting-languages",
        "packaging/guix-scheme",
        [
            "packaging/guix-scheme/package-metadata.json",
            "packaging/guix-scheme/sshfling.scm",
            "packaging/guix-scheme/sshfling-package.scm",
            "packaging/build-scripting-languages.sh",
        ],
        "package-metadata.json declares the Guile module, Guix definition, CLI, runtime, and templates.",
        "The scripting batch validates the Guile module and records guix-definition PASS from guix build --dry-run --no-substitutes.",
        "The deterministic archive contains the rendered Guile module, package definition, command, runtime, and templates.",
        "A clean Guile process imports the extracted module, and Guix resolves the package definition from the same staged prefix.",
        "The Guix package definition exposes the versioned launcher module and CLI package boundary.",
        "The packaged CLI validates version, init assets, removal, post-removal module absence, and package-definition dry-run behavior.",
    )
)

DEPLOYMENTS.append(
    node_language_consumer(
        "cfml-npm-consumer",
        "CFML",
        "server-side CFML adapter project",
        ["box.json", "test.cfm", "bridge.cjs", "test-bridge.cjs"],
        "CommandBox executes the CFML template after the Node bridge verifies the packed SSHFling npm API.",
        "The CFML template invokes a template-relative Node bridge from a server-side process boundary.",
    )
)

DEPLOYMENTS.append(
    node_language_consumer(
        "hack-npm-consumer",
        "Hack",
        "server-side Hack adapter project",
        ["composer.json", ".hhconfig", "src/main.hack", "bridge.cjs", "test-bridge.cjs"],
        "HHVM 4.172 executes src/main.hack inside the hhvm/hhvm container with Node v22.23.1 after the Node bridge verifies the packed SSHFling npm API.",
        "The Hack entry point invokes a fixed Node bridge from a server-side HHVM process boundary.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "ballerina-package-library",
        "Ballerina",
        "Ballerina package",
        "Ballerina module dependency",
        "library",
        "sshfling-ballerina-VERSION.tar.gz and grwlx-sshfling-any-VERSION.bala",
        "package-functional-languages",
        "packaging/functional-languages/ballerina",
        [
            "packaging/functional-languages/ballerina/Ballerina.toml",
            "packaging/functional-languages/ballerina/Dependencies.toml",
            "packaging/functional-languages/ballerina/sshfling.bal",
            "packaging/functional-languages/ballerina/tests/sshfling_test.bal",
            "packaging/build-functional-languages.py",
            "tools/validate_promoted_language_evidence.py",
        ],
        "Ballerina.toml declares the grwlx/sshfling package, Ballerina 2201.12.0 distribution, bundled resources, README, and license.",
        "The functional-language validator runs bal test, bal pack, local repository push, external consumer tests, and removal/import-failure checks.",
        "The deterministic source archive plus generated BALA contain the public module, tests, canonical runtime, templates, README, and license.",
        "A separate Ballerina package resolves grwlx/sshfling from the isolated local repository and imports only the installed package.",
        "The module exposes run and runAndCapture APIs for child status and exact stdout validation.",
        "The external consumer validates version, init, invalid option, missing runtime, local-repository install, removal, and import absence.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "chapel-mason-library",
        "Chapel",
        "Mason",
        "Chapel module and executable package",
        "library + CLI",
        "sshfling-chapel-VERSION.tar.gz",
        "package-systems-languages",
        "packaging/systems-languages/chapel",
        [
            "packaging/systems-languages/chapel/Mason.toml",
            "packaging/systems-languages/chapel/src/SSHFling.chpl",
            "packaging/systems-languages/chapel/src/main.chpl",
            "packaging/systems-languages/chapel/consumers/main.chpl",
            "packaging/build-systems-languages.sh",
            "tools/validate_promoted_language_evidence.py",
        ],
        "Mason.toml declares the Chapel package while the module binds the common C launcher through the verified header.",
        "The systems-language validator extracts the deterministic archive, runs mason modules, compiles the package and external consumer with chpl, and executes both.",
        "The source archive contains Chapel sources, Mason metadata, shared launcher sources, runtime, templates, and inventory manifest.",
        "A clean consumer imports the extracted SSHFling module outside the repository source tree.",
        "The Chapel module exposes launcher version and argument-array execution; the package also builds a CLI.",
        "The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence.",
    )
)

_harbour_deployment = deployment(
    "harbour-hbmk2-cli",
    "Harbour",
    "hbmk2",
    "Harbour CLI package",
    "CLI",
    "sshfling-harbour-VERSION.tar.gz",
    "package-systems-languages",
    [
        "packaging/systems-languages/harbour/sshfling.hbp",
        "packaging/systems-languages/harbour/src/sshfling.prg",
        "packaging/systems-languages/harbour/src/bridge.c",
        "packaging/build-systems-languages.sh",
        "tools/validate_promoted_language_evidence.py",
    ],
    (
        "A Harbour/xBase package source and bridge are tracked under packaging/systems-languages/harbour.",
        "sshfling.hbp declares the terminal target, include path, Harbour source, C bridge, and common launcher source.",
        "The systems validator extracts the deterministic archive and builds the command with hbmk2 from an isolated source package.",
        "The source archive contains Harbour source, C bridge, common launcher sources, runtime, templates, and inventory manifest.",
        "The validator builds and runs the CLI from a temporary output directory without repository source paths.",
        "The Harbour procedure accepts argv with hb_AParams and delegates to the C bridge.",
        "The CLI prints the exact SSHFling release version.",
        "The CLI validates init assets, invalid option status, missing runtime status, and clean temporary workspace behavior.",
    ),
)
_harbour_deployment["validation_evidence"] = (
    "The systems-language validator records RUNTIME harbour PASS with build-only "
    "mode and compile, CLI runtime, init workflow, and exit workflow capabilities."
)
DEPLOYMENTS.append(_harbour_deployment)

DEPLOYMENTS.append(
    validated_batch_package(
        "ring-source-library",
        "Ring",
        "Ring source package",
        "Ring library and POSIX status-wrapper command",
        "library + CLI",
        "sshfling-ring-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/functional-languages/ring",
        [
            "packaging/functional-languages/ring/package.ring",
            "packaging/functional-languages/ring/lib.ring",
            "packaging/functional-languages/ring/main.ring",
            "packaging/functional-languages/ring/bin/sshfling-ring",
            "packaging/functional-languages/ring/test/consumer.ring",
            "packaging/build-functional-languages.py",
            "tools/validate_promoted_language_evidence.py",
        ],
        "package.ring declares the Ring package metadata while the library, main script, command wrapper, and consumer are tracked separately.",
        "The functional-language validator extracts the deterministic archive, parses package metadata with Ring, and executes a clean external Ring consumer.",
        "The source archive contains Ring source, package metadata, the status-preserving command wrapper, and the canonical runtime bundle.",
        "A separate Ring consumer loads only the extracted package library outside the source checkout.",
        "lib.ring exposes argument-list execution; bin/sshfling-ring maps the Ring-reported status to a POSIX command status.",
        "The consumer and command validate exact version output, init assets, invalid option status, missing runtime status, removal, and import absence.",
    )
)

_red_deployment = deployment(
    "red-redsystem-cli",
    "Red",
    "Red/System compiler",
    "Red/System source package",
    "CLI",
    "sshfling-red-VERSION.tar.gz",
    "package-systems-languages",
    [
        "packaging/systems-languages/red/package.toml",
        "packaging/systems-languages/red/src/sshfling.reds",
        "packaging/systems-languages/red/src/main.reds",
        "packaging/build-systems-languages.sh",
        "tools/provision-promoted-language-runtimes.sh",
        "tools/validate_promoted_language_evidence.py",
    ],
    (
        "A Red/System package source and CLI entry point are tracked under packaging/systems-languages/red.",
        "package.toml declares the Red/System package name, version, launcher ABI, library source, CLI source, and shared-library dependency.",
        "The systems validator compiles the CLI with the pinned Red/System toolchain from an isolated source archive.",
        "The source archive contains Red/System sources, common launcher sources, runtime, templates, and inventory manifest.",
        "The validator runs the compiled command from a temporary output directory with a matching 32-bit launcher shared object.",
        "The CLI delegates argv handling to the shared launcher ABI through the Red/System import declarations.",
        "The CLI prints the exact SSHFling release version.",
        "The CLI validates init assets, invalid option status, missing runtime status, and clean temporary workspace behavior.",
    ),
)
_red_deployment["validation_evidence"] = (
    "The systems-language validator records RUNTIME red PASS with build-only "
    "mode and compile, CLI runtime, init workflow, and exit workflow capabilities."
)
DEPLOYMENTS.append(_red_deployment)

_object_pascal_deployment = deployment(
    "object-pascal-fpc-package",
    "Delphi/Object Pascal",
    "Free Pascal units",
    "Object Pascal unit and executable package",
    "library + CLI",
    "sshfling-object-pascal-VERSION.tar.gz",
    "package-systems-languages",
    [
        "packaging/systems-languages/object-pascal/package.toml",
        "packaging/systems-languages/object-pascal/src/sshfling.pas",
        "packaging/systems-languages/object-pascal/app/main.pas",
        "packaging/systems-languages/object-pascal/consumers/main.pas",
        "packaging/build-systems-languages.sh",
        "tools/validate_promoted_language_evidence.py",
    ],
    (
        "A Free Pascal-compatible Object Pascal unit, CLI, and consumer are tracked under packaging/systems-languages/object-pascal.",
        "package.toml declares the package identity, Free Pascal compiler boundary, unit source, CLI source, and launcher ABI.",
        "The systems validator compiles the package CLI and isolated consumer with fpc in objfpc mode.",
        "The source archive contains Object Pascal sources, runtime, templates, license, and inventory manifest.",
        "A clean consumer compiles against the extracted SSHFling unit outside the repository source tree.",
        "The unit exposes RunSSHFling for argument-array execution and the package includes a CLI.",
        "The consumer and CLI print the exact SSHFling release version.",
        "The consumer and CLI validate version, init, invalid option, and missing runtime behavior; Delphi compiler compatibility is not claimed.",
    ),
)
_object_pascal_deployment["validation_evidence"] = (
    "The systems-language validator records RUNTIME object-pascal PASS with "
    "build-only mode plus Free Pascal compile, library consumer, CLI runtime, "
    "init workflow, and exit workflow capabilities."
)
DEPLOYMENTS.append(_object_pascal_deployment)

_roc_deployment = deployment(
    "roc-source-package",
    "Roc",
    "Roc source package",
    "Roc package and application",
    "library + CLI",
    "sshfling-roc-VERSION.tar.gz",
    "package-functional-languages",
    [
        "packaging/functional-languages/roc/package.roc",
        "packaging/functional-languages/roc/SSHFling.roc",
        "packaging/functional-languages/roc/main.roc",
        "packaging/functional-languages/roc/test/consumer.roc",
        "packaging/build-functional-languages.py",
        "tools/provision-promoted-language-runtimes.sh",
        "tools/validate_promoted_language_evidence.py",
    ],
    (
        "A Roc package module, application entry point, and external consumer are tracked under packaging/functional-languages/roc.",
        "package.roc exposes the SSHFling module while the source package records its versioned module API and basic-cli platform boundary.",
        "The functional-language validator runs roc check, roc build, and a clean external Roc consumer against the deterministic source archive.",
        "The source archive contains Roc sources, license, README, and the byte-checked canonical runtime bundle.",
        "A separate Roc application imports the extracted package by path and runs outside the repository source tree with explicit runtime resources.",
        "The module exposes run!, runtime_path!, template_directory!, and package_version while the package also builds a CLI application.",
        "The Roc consumer and CLI print the exact SSHFling release version.",
        "The consumer validates init assets, invalid option status, missing runtime status, package removal, and import absence.",
    ),
)
_roc_deployment["validation_evidence"] = (
    "The functional-language validator records roc PASS with source archive, "
    "roc check/build, external consumer check/build, exact version, init, "
    "invalid option, missing runtime, removal, and import-absence evidence."
)
DEPLOYMENTS.append(_roc_deployment)

DEPLOYMENTS.append(
    validated_batch_package(
        "smalltalk-gnu-package",
        "Smalltalk",
        "GNU Smalltalk package",
        "Smalltalk package dependency",
        "library + CLI",
        "sshfling-smalltalk-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/functional-languages/smalltalk",
        [
            "packaging/functional-languages/smalltalk/package.xml",
            "packaging/functional-languages/smalltalk/src/SSHFling.st",
            "packaging/functional-languages/smalltalk/test/consumer.st",
            "packaging/build-functional-languages.py",
        ],
        "package.xml declares the GNU Smalltalk package files, source file-in, test consumer, and bundled runtime assets.",
        "The per-language validator runs gst-package --dist and executes GNU Smalltalk consumers with the pinned GST runtime.",
        "The staged package distribution contains the Smalltalk source, consumer, and byte-checked canonical runtime bundle.",
        "A clean external Smalltalk consumer files in the package source outside the source tree.",
        "SSHFling class>>run: accepts a Smalltalk argument collection and returns the canonical runtime status.",
        "The consumer validates version, init, invalid option, missing runtime, package removal, and import absence.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "apl-gnu-package",
        "APL",
        "GNU APL",
        "GNU APL source package",
        "library",
        "sshfling-apl-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/scientific-languages/apl",
        [
            "packaging/scientific-languages/apl/apl-package.json",
            "packaging/scientific-languages/apl/src/sshfling.apl",
            "packaging/scientific-languages/apl/test/consumer.apl",
            "packaging/build-functional-languages.py",
            "tools/provision-promoted-language-runtimes.sh",
        ],
        "apl-package.json declares the GNU APL interpreter boundary, package identity, source entry, and bundled runtime assets.",
        "The per-language validator executes the pinned GNU APL runtime against a deterministic source archive.",
        "The staged source package contains GNU APL source, consumer script, license, README, and the byte-checked canonical runtime bundle.",
        "A clean external APL consumer loads the extracted package source outside the repository source tree.",
        "SSHFling∆Run accepts a nested APL argument vector and returns the canonical runtime status.",
        "The consumer validates version, init, invalid option, missing runtime, package removal, and import absence.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "matlab-octave-package",
        "MATLAB",
        "GNU Octave",
        "MATLAB-compatible source package",
        "library",
        "sshfling-matlab-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/scientific-languages/matlab",
        [
            "packaging/scientific-languages/matlab/matlab-package.json",
            "packaging/scientific-languages/matlab/+sshfling/run.m",
            "packaging/scientific-languages/matlab/+sshfling/runtimePath.m",
            "packaging/scientific-languages/matlab/+sshfling/templateDirectory.m",
            "packaging/scientific-languages/matlab/test/consumer.m",
            "packaging/build-functional-languages.py",
        ],
        "matlab-package.json declares the GNU Octave validation boundary and explicitly does not claim MathWorks MATLAB runtime conformance.",
        "The per-language validator executes octave-cli against a deterministic MATLAB-compatible source archive.",
        "The staged source package contains +sshfling package functions, consumer script, license, README, and the byte-checked canonical runtime bundle.",
        "A clean external Octave consumer imports the extracted +sshfling package outside the repository source tree.",
        "sshfling.run accepts a cell array of character-vector arguments and returns the canonical runtime status.",
        "The consumer validates version, init, invalid option, missing runtime, package removal, and import absence.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "wolfram-language-mathics-package",
        "Wolfram Language",
        "Mathics3",
        "Mathics-compatible source package",
        "library",
        "sshfling-wolfram-language-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/scientific-languages/wolfram-language",
        [
            "packaging/scientific-languages/wolfram-language/mathics-package.json",
            "packaging/scientific-languages/wolfram-language/src/SSHFling.wl",
            "packaging/scientific-languages/wolfram-language/bin/sshfling-mathics-runner",
            "packaging/scientific-languages/wolfram-language/test/consumer.wl",
            "packaging/build-functional-languages.py",
            "tools/provision-promoted-language-runtimes.sh",
        ],
        "mathics-package.json declares the Mathics3 validation boundary and explicitly does not claim Wolfram Engine runtime conformance.",
        "The per-language validator executes Mathics3 against a deterministic Wolfram Language-compatible source archive.",
        "The staged source package contains Wolfram Language package source, the Mathics runner bridge, consumer script, license, README, and the byte-checked canonical runtime bundle.",
        "A clean external Mathics consumer imports the extracted SSHFling package outside the repository source tree.",
        "SSHFling`RunSSHFling accepts a Wolfram string list, hex-encodes arguments for the packaged runner bridge, and returns the canonical runtime status.",
        "The consumer validates argument boundaries, version, init, invalid option, missing runtime, package removal, and import absence.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "raku-meta6-library",
        "Raku",
        "META6/source archive",
        "Raku module and command package",
        "library + CLI",
        "sshfling-raku-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/functional-languages/raku",
        [
            "packaging/functional-languages/raku/META6.json",
            "packaging/functional-languages/raku/lib/SSHFling.rakumod",
            "packaging/functional-languages/raku/bin/sshfling-raku",
            "packaging/functional-languages/raku/test/consumer.raku",
            "packaging/build-functional-languages.py",
            "tools/provision-promoted-language-runtimes.sh",
            "tools/validate_promoted_language_evidence.py",
        ],
        "META6.json declares the package identity, provided SSHFling module, command wrapper, and bundled runtime resource boundary.",
        "The functional-language validator extracts the deterministic archive and executes a clean external Raku consumer from an unrelated directory.",
        "The staged source package contains Raku module source, command wrapper, consumer script, license, README, and the byte-checked canonical runtime bundle.",
        "A separate Raku consumer imports the extracted module via an explicit lib path outside the source checkout.",
        "SSHFling.run accepts a Raku argument list and delegates through Proc::Async without shell string expansion.",
        "The consumer and command validate argument boundaries, version, init, invalid option, missing runtime, package removal, and import absence.",
    )
)

DEPLOYMENTS.append(
    validated_batch_package(
        "haxe-haxelib-neko-package",
        "Haxe",
        "haxelib/Neko",
        "Haxe library and Neko command package",
        "library + CLI",
        "sshfling-haxe-VERSION.tar.gz",
        "package-functional-languages",
        "packaging/functional-languages/haxe",
        [
            "packaging/functional-languages/haxe/haxelib.json",
            "packaging/functional-languages/haxe/build.hxml",
            "packaging/functional-languages/haxe/src/sshfling/SSHFling.hx",
            "packaging/functional-languages/haxe/src/sshfling/PackageRootMacro.hx",
            "packaging/functional-languages/haxe/src/Main.hx",
            "packaging/functional-languages/haxe/test/Consumer.hx",
            "packaging/build-functional-languages.py",
            "tools/provision-promoted-language-runtimes.sh",
            "tools/validate_promoted_language_evidence.py",
        ],
        "haxelib.json declares the package identity, source class path, Haxe package metadata, and bundled runtime boundary.",
        "The functional-language validator extracts the deterministic archive, builds the Neko command target, and compiles a clean external Haxe consumer.",
        "The staged source package contains Haxe module source, macro source, hxml build metadata, consumer source, license, README, and the byte-checked canonical runtime bundle.",
        "A separate Haxe consumer imports the extracted sshfling package via an explicit source path outside the source checkout.",
        "SSHFling.run accepts a Haxe string array and delegates through Sys.command(command, args) without shell string construction.",
        "The consumer and command validate argument boundaries, version, init, invalid option, missing runtime, package removal, and import absence.",
    )
)


FIRST_91_CATALOG: tuple[tuple[str, str], ...] = (
    ("Python", "PASS"),
    ("TypeScript", "PASS"),
    ("JavaScript", "PASS"),
    ("Java", "PASS"),
    ("C", "PASS"),
    ("C++", "PASS"),
    ("C#/.NET", "PASS"),
    ("SQL", "NOT_APPLICABLE"),
    ("Go", "PASS"),
    ("Rust", "PASS"),
    ("PHP", "PASS"),
    ("Shell/POSIX sh", "PASS"),
    ("Bash", "PASS"),
    ("PowerShell", "PASS"),
    ("Kotlin", "PASS"),
    ("Swift", "PASS"),
    ("R", "PASS"),
    ("Ruby", "PASS"),
    ("Dart", "PASS"),
    ("Lua", "PASS"),
    ("Perl", "PASS"),
    ("Scala", "PASS"),
    ("Visual Basic/.NET", "PASS"),
    ("MATLAB", "PASS"),
    ("Objective-C", "PASS"),
    ("Groovy", "PASS"),
    ("Delphi/Object Pascal", "PASS"),
    ("Julia", "PASS"),
    ("HCL/Terraform", "NOT_APPLICABLE"),
    ("Assembly", "PASS"),
    ("COBOL", "PASS"),
    ("Fortran", "PASS"),
    ("SAS", "BLOCKED"),
    ("ABAP", "BLOCKED"),
    ("Apex", "NOT_APPLICABLE"),
    ("PL/SQL", "BLOCKED"),
    ("T-SQL", "NOT_APPLICABLE"),
    ("Elixir", "PASS"),
    ("Erlang", "PASS"),
    ("Haskell", "PASS"),
    ("Clojure", "PASS"),
    ("F#", "PASS"),
    ("OCaml", "PASS"),
    ("Zig", "PASS"),
    ("Nim", "PASS"),
    ("Crystal", "PASS"),
    ("D", "PASS"),
    ("V", "PASS"),
    ("Ada", "PASS"),
    ("Common Lisp", "PASS"),
    ("Scheme/Racket", "PASS"),
    ("Prolog", "PASS"),
    ("Smalltalk", "PASS"),
    ("Tcl", "PASS"),
    ("AWK", "PASS"),
    ("sed", "PASS"),
    ("Zsh", "PASS"),
    ("Fish", "PASS"),
    ("Nix", "PASS"),
    ("Guix Scheme", "PASS"),
    ("Solidity", "NOT_APPLICABLE"),
    ("Vyper", "NOT_APPLICABLE"),
    ("Move", "NOT_APPLICABLE"),
    ("WebAssembly/WASI", "PASS"),
    ("Elm", "PASS"),
    ("PureScript", "PASS"),
    ("Reason/ReScript", "PASS"),
    ("Forth", "PASS"),
    ("APL", "PASS"),
    ("J", "PASS"),
    ("LabVIEW G", "BLOCKED"),
    ("Scratch", "NOT_APPLICABLE"),
    ("Q/KDB+", "BLOCKED"),
    ("Hack", "PASS"),
    ("CFML", "PASS"),
    ("Wolfram Language", "PASS"),
    ("Verilog", "NOT_APPLICABLE"),
    ("VHDL", "NOT_APPLICABLE"),
    ("SystemVerilog", "NOT_APPLICABLE"),
    ("CUDA", "NOT_APPLICABLE"),
    ("OpenCL C", "NOT_APPLICABLE"),
    ("GLSL", "NOT_APPLICABLE"),
    ("HLSL", "NOT_APPLICABLE"),
    ("WGSL", "NOT_APPLICABLE"),
    ("Chapel", "PASS"),
    ("Pony", "PASS"),
    ("Janet", "PASS"),
    ("Odin", "PASS"),
    ("Ballerina", "PASS"),
    ("Gleam", "PASS"),
    ("Roc", "PASS"),
)


def catalog_surface(
    surface_id: str,
    language: str,
    package_manager: str,
    deployment_type: str,
    interface_type: str,
    artifact: str,
    status: str,
    validation_evidence: str,
    rationale: str,
    required_paths: list[str],
) -> dict[str, object]:
    return {
        "id": surface_id,
        "language": language,
        "package_manager": package_manager,
        "deployment_type": deployment_type,
        "interface_type": interface_type,
        "artifact": artifact,
        "status": status,
        "validation_status": status,
        "validation_evidence": validation_evidence,
        "rationale": rationale,
        "required_paths": required_paths,
    }


def source_publication(
    language: str,
    slug: str,
    package_manager: str,
    package_root: str,
    batch: str,
) -> dict[str, object]:
    if batch == "functional":
        validator = "packaging/build-functional-languages.py"
        evidence_artifact = "sshfling-functional-languages-VERSION-validation.tsv"
        evidence = (
            f"PASS published-source-archive and published-source-inventory rows for {slug} "
            f"are recorded in dist/{evidence_artifact}."
        )
    elif batch == "systems":
        validator = "packaging/build-systems-languages.sh"
        evidence_artifact = "sshfling-systems-languages-VERSION-validation.tsv"
        evidence = (
            f"A PASS source-archive row for {slug}, including inventory digest and "
            f"repeat-build identity, is recorded in dist/{evidence_artifact}."
        )
    else:
        raise ValueError(f"unsupported source-publication batch: {batch}")
    return catalog_surface(
        f"{slug}-{batch}-source-archive",
        language,
        package_manager,
        "versioned source-archive publication",
        "source package",
        f"sshfling-{slug}-VERSION.tar.gz",
        "PASS",
        evidence,
        (
            "Publication PASS proves deterministic archive creation and inventory; "
            "it does not by itself claim toolchain, install, library-consumer, or runtime PASS."
        ),
        [package_root, validator],
    )


FUNCTIONAL_SOURCE_PACKAGES = (
    ("R", "r", "R CMD", "packaging/scientific-languages/r"),
    ("Julia", "julia", "Julia Pkg", "packaging/scientific-languages/julia"),
    ("MATLAB", "matlab", "GNU Octave", "packaging/scientific-languages/matlab"),
    ("Wolfram Language", "wolfram-language", "Mathics3", "packaging/scientific-languages/wolfram-language"),
    ("Elixir", "elixir", "Mix", "packaging/beam-languages/elixir"),
    ("Erlang", "erlang", "OTP/rebar3", "packaging/beam-languages/erlang"),
    ("Haskell", "haskell", "Cabal", "packaging/functional-languages/haskell"),
    ("OCaml", "ocaml", "opam/Dune", "packaging/functional-languages/ocaml"),
    ("Common Lisp", "common-lisp", "ASDF/Quicklisp", "packaging/functional-languages/common-lisp"),
    ("Scheme/Racket", "scheme", "GNU Guile/Autotools", "packaging/functional-languages/scheme"),
    ("Prolog", "prolog", "SWI-Prolog pack", "packaging/functional-languages/prolog"),
    ("Smalltalk", "smalltalk", "GNU Smalltalk package", "packaging/functional-languages/smalltalk"),
    ("APL", "apl", "GNU APL source package", "packaging/scientific-languages/apl"),
    ("J", "j", "J package", "packaging/scientific-languages/j"),
    ("Q/KDB+", "q", "KX q package", "packaging/scientific-languages/q"),
    ("Janet", "janet", "JPM", "packaging/functional-languages/janet"),
    ("Ballerina", "ballerina", "Ballerina package", "packaging/functional-languages/ballerina"),
    ("Gleam", "gleam", "Gleam/Hex", "packaging/beam-languages/gleam"),
    ("Roc", "roc", "Roc source package", "packaging/functional-languages/roc"),
)

SYSTEMS_SOURCE_PACKAGES = (
    ("Swift", "swift", "SwiftPM", "packaging/systems-languages/swift"),
    ("Objective-C", "objective-c", "CMake/source build", "packaging/systems-languages/objective-c"),
    ("Assembly", "assembly", "GNU/Clang toolchain", "packaging/systems-languages/assembly"),
    ("COBOL", "cobol", "GnuCOBOL", "packaging/systems-languages/cobol"),
    ("Fortran", "fortran", "fpm/source build", "packaging/systems-languages/fortran"),
    ("Delphi/Object Pascal", "object-pascal", "Free Pascal units", "packaging/systems-languages/object-pascal"),
    ("Zig", "zig", "Zig build", "packaging/systems-languages/zig"),
    ("Nim", "nim", "Nimble", "packaging/systems-languages/nim"),
    ("Crystal", "crystal", "Shards/Crystal", "packaging/systems-languages/crystal"),
    ("D", "d", "Dub/source build", "packaging/systems-languages/d"),
    ("V", "v", "VPM", "packaging/systems-languages/v"),
    ("Ada", "ada", "Alire/GNAT", "packaging/systems-languages/ada"),
    ("WebAssembly/WASI", "webassembly-wasi", "WASI component/source", "packaging/systems-languages/webassembly-wasi"),
    ("Forth", "forth", "Gforth/source package", "packaging/systems-languages/forth"),
    ("Chapel", "chapel", "Mason", "packaging/systems-languages/chapel"),
    ("Pony", "pony", "Corral", "packaging/systems-languages/pony"),
    ("Odin", "odin", "Odin source package", "packaging/systems-languages/odin"),
)

CATALOG_SURFACES = [
    *(source_publication(language, slug, manager, root, "functional") for language, slug, manager, root in FUNCTIONAL_SOURCE_PACKAGES),
    *(source_publication(language, slug, manager, root, "systems") for language, slug, manager, root in SYSTEMS_SOURCE_PACKAGES),
]

# Guix Scheme predates the two batch source-archive publishers but has the same
# split contract: source publication remains distinct from runtime/package checks.
CATALOG_SURFACES.append(
    catalog_surface(
        "guix-scheme-source-archive",
        "Guix Scheme",
        "source archive",
        "versioned source-archive publication",
        "source package",
        "sshfling-guix-scheme-VERSION.tar.gz",
        "PASS",
        "PASS package-archive is recorded for guix-scheme in dist/sshfling-scripting-languages-VERSION-validation.tsv.",
        "Archive publication is separate from the Guile and Guix package-definition runtime checks.",
        ["packaging/guix-scheme/package-metadata.json", "packaging/build-scripting-languages.sh"],
    )
)


def blocked_runtime(
    surface_id: str,
    language: str,
    package_manager: str,
    deployment_type: str,
    interface_type: str,
    artifact: str,
    reason: str,
    required_paths: list[str],
) -> dict[str, object]:
    return catalog_surface(
        surface_id,
        language,
        package_manager,
        deployment_type,
        interface_type,
        artifact,
        "BLOCKED",
        f"BLOCKED runtime-validation: {reason}",
        "Tracked source or metadata is not install/runtime PASS evidence; publication status is reported separately where applicable.",
        required_paths,
    )


def not_applicable_surface(
    surface_id: str,
    language: str,
    package_manager: str,
    deployment_type: str,
    reason: str,
) -> dict[str, object]:
    return catalog_surface(
        surface_id,
        language,
        package_manager,
        deployment_type,
        "no library or CLI surface",
        "none",
        "NOT_APPLICABLE",
        f"NOT_APPLICABLE: {reason}",
        "No artifact is emitted, so this row makes no package, library, CLI, or runtime PASS claim.",
        [
            "packaging/domain-languages/manifest.tsv",
            "packaging/build-domain-languages.sh",
            "docs/language-external-blockers.md",
        ],
    )


CATALOG_SURFACES.extend(
    [
        blocked_runtime(
            "dart-pub-runtime",
            "Dart",
            "pub",
            "server-side Dart adapter project",
            "CLI consumer",
            "tracked pub project; no published Dart artifact",
            "the Node bridge passes independently, but the Dart SDK has not executed the pub consumer",
            ["packaging/node/consumers/dart/pubspec.yaml", "packaging/node/consumers/dart/bin/sshfling_consumer.dart", "packaging/build-web-language-consumers.sh"],
        ),
        blocked_runtime(
            "matlab-package-folder-runtime",
            "MATLAB",
            "MATLAB package folder",
            "ProcessBuilder launcher package",
            "library",
            "tracked +sshfling candidate; publication disabled",
            "a licensed MATLAB runtime and configured JVM are required for conformance",
            ["packaging/domain-languages/matlab/+sshfling/run.m", "packaging/domain-languages/matlab/test_launcher.m", "packaging/build-domain-languages.sh"],
        ),
        blocked_runtime(
            "julia-pkg-runtime",
            "Julia",
            "Julia Pkg",
            "Julia package dependency and command",
            "library + CLI",
            "sshfling-julia-VERSION.tar.gz",
            "source publication passes, but the Julia runtime/toolchain is unavailable for install, test, consumer, and removal validation",
            ["packaging/scientific-languages/julia/Project.toml", "packaging/scientific-languages/julia/src/SSHFling.jl", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "sas-xcmd-runtime",
            "SAS",
            "SAS deployment tooling",
            "XCMD external-command integration",
            "CLI adapter candidate",
            "none",
            "a licensed, policy-approved XCMD-enabled SAS runtime and safe argument contract are unavailable",
            ["packaging/domain-languages/manifest.tsv", "packaging/build-domain-languages.sh", "docs/language-external-blockers.md"],
        ),
        blocked_runtime(
            "abap-sm69-runtime",
            "ABAP",
            "SAP transport/SM69",
            "authorized external-command integration",
            "CLI adapter candidate",
            "none",
            "a licensed SAP system, SM69 definition, authorization design, namespace, and transport validation are required",
            ["packaging/domain-languages/manifest.tsv", "packaging/build-domain-languages.sh", "docs/language-external-blockers.md"],
        ),
        blocked_runtime(
            "plsql-scheduler-runtime",
            "PL/SQL",
            "Oracle package/scheduler",
            "credentialed external-job integration",
            "CLI adapter candidate",
            "none",
            "a licensed Oracle deployment, scheduler privileges, host credentials, and security review are required",
            ["packaging/domain-languages/manifest.tsv", "packaging/build-domain-languages.sh", "docs/language-external-blockers.md"],
        ),
        blocked_runtime(
            "v-vpm-runtime",
            "V",
            "VPM",
            "V module and executable package",
            "library + CLI",
            "sshfling-v-VERSION.tar.gz",
            "source publication passes, but the V compiler is unavailable for package and runtime validation",
            ["packaging/systems-languages/v/v.mod", "packaging/systems-languages/v/sshfling/sshfling.v", "packaging/build-systems-languages.sh"],
        ),
        blocked_runtime(
            "smalltalk-package-runtime",
            "Smalltalk",
            "GNU Smalltalk package",
            "Smalltalk package dependency",
            "library + CLI",
            "sshfling-smalltalk-VERSION.tar.gz",
            "source publication passes, but gst and gst-package are unavailable for install and consumer validation",
            ["packaging/functional-languages/smalltalk/package.xml", "packaging/functional-languages/smalltalk/src/SSHFling.st", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "wasi-module-runtime",
            "WebAssembly/WASI",
            "WASI component/source",
            "host-imported WASI command module",
            "CLI module",
            "sshfling-webassembly-wasi-VERSION.tar.gz",
            "source publication passes, but a wasm32-wasi compiler, wasmtime, and explicit host runner are required",
            ["packaging/systems-languages/webassembly-wasi/package.toml", "packaging/systems-languages/webassembly-wasi/wit/sshfling.wit", "packaging/build-systems-languages.sh"],
        ),
        blocked_runtime(
            "apl-gnu-runtime",
            "APL",
            "GNU APL",
            "GNU APL source package",
            "library",
            "sshfling-apl-VERSION.tar.gz",
            "source publication passes, but the GNU APL interpreter is unavailable for package and consumer validation",
            ["packaging/scientific-languages/apl/apl-package.json", "packaging/scientific-languages/apl/src/sshfling.apl", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "j-package-runtime",
            "J",
            "J package",
            "J addon/source package",
            "library",
            "sshfling-j-VERSION.tar.gz",
            "source publication passes, but the J consumer failed the exact-version output contract in the VERSION=0.1.22 full batch run",
            ["packaging/scientific-languages/j/manifest.ijs", "packaging/scientific-languages/j/src/sshfling.ijs", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "labview-vi-runtime",
            "LabVIEW G",
            "VIPM/LabVIEW project",
            "System Exec VI integration",
            "library VI + CLI adapter candidate",
            "none",
            "a licensed LabVIEW version/OS matrix and genuine VI package are required; no binary G source is fabricated",
            ["packaging/domain-languages/manifest.tsv", "packaging/build-domain-languages.sh", "docs/language-external-blockers.md"],
        ),
        blocked_runtime(
            "q-kdb-package-runtime",
            "Q/KDB+",
            "KX q package",
            "q namespace package",
            "library",
            "sshfling-q-VERSION.tar.gz",
            "source publication passes, but the q runtime is unavailable for package and consumer validation",
            ["packaging/scientific-languages/q/manifest.yaml", "packaging/scientific-languages/q/src/sshfling.q", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "hack-hhvm-runtime",
            "Hack",
            "Composer/HHVM",
            "server-side Hack adapter project",
            "CLI consumer",
            "tracked Composer project; no published Hack artifact",
            "the Node bridge passes independently, but HHVM has not compiled and executed the Hack consumer",
            ["packaging/node/consumers/hack/composer.json", "packaging/node/consumers/hack/src/main.hack", "packaging/build-web-language-consumers.sh"],
        ),
        blocked_runtime(
            "cfml-commandbox-runtime",
            "CFML",
            "CommandBox",
            "server-side CFML adapter project",
            "CLI consumer",
            "tracked CommandBox project; no published CFML artifact",
            "the Node bridge passes independently, but CommandBox has not executed the CFML consumer",
            ["packaging/node/consumers/cfml/box.json", "packaging/node/consumers/cfml/test.cfm", "packaging/build-web-language-consumers.sh"],
        ),
        blocked_runtime(
            "wolfram-paclet-runtime",
            "Wolfram Language",
            "Wolfram Paclet",
            "RunProcess-based Paclet candidate",
            "library",
            "tracked Paclet source; publication disabled",
            "a licensed Wolfram kernel exposed through wolframscript is required for conformance",
            ["packaging/domain-languages/wolfram-language/PacletInfo.wl", "packaging/domain-languages/wolfram-language/Kernel/SSHFling.wl", "packaging/build-domain-languages.sh"],
        ),
        blocked_runtime(
            "chapel-mason-runtime",
            "Chapel",
            "Mason",
            "Chapel module and executable package",
            "library + CLI",
            "sshfling-chapel-VERSION.tar.gz",
            "source publication passes, but chpl is unavailable for package and runtime validation",
            ["packaging/systems-languages/chapel/Mason.toml", "packaging/systems-languages/chapel/src/SSHFling.chpl", "packaging/build-systems-languages.sh"],
        ),
        blocked_runtime(
            "pony-corral-runtime",
            "Pony",
            "Corral",
            "Pony package and executable",
            "library + CLI",
            "sshfling-pony-VERSION.tar.gz",
            "source publication passes, but ponyc is unavailable for package and runtime validation",
            ["packaging/systems-languages/pony/corral.json", "packaging/systems-languages/pony/sshfling/sshfling.pony", "packaging/build-systems-languages.sh"],
        ),
        blocked_runtime(
            "janet-jpm-runtime",
            "Janet",
            "JPM",
            "Janet module package",
            "library + CLI",
            "sshfling-janet-VERSION.tar.gz",
            "source publication passes, but janet and jpm are unavailable for install and consumer validation",
            ["packaging/functional-languages/janet/project.janet", "packaging/functional-languages/janet/src/sshfling/init.janet", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "odin-source-runtime",
            "Odin",
            "Odin source package",
            "Odin collection and executable",
            "library + CLI",
            "sshfling-odin-VERSION.tar.gz",
            "source publication passes, but the Odin compiler is unavailable for package and runtime validation",
            ["packaging/systems-languages/odin/package.toml", "packaging/systems-languages/odin/sshfling/sshfling.odin", "packaging/build-systems-languages.sh"],
        ),
        blocked_runtime(
            "ballerina-package-runtime",
            "Ballerina",
            "Ballerina package",
            "Ballerina module dependency",
            "library",
            "sshfling-ballerina-VERSION.tar.gz",
            "source publication passes, but bal is unavailable for package test and consumer validation",
            ["packaging/functional-languages/ballerina/Ballerina.toml", "packaging/functional-languages/ballerina/sshfling.bal", "packaging/build-functional-languages.py"],
        ),
        blocked_runtime(
            "roc-package-runtime",
            "Roc",
            "Roc source package",
            "Roc package and application",
            "library + CLI",
            "sshfling-roc-VERSION.tar.gz",
            "source publication passes, but the Roc toolchain is unavailable for package and consumer validation",
            ["packaging/functional-languages/roc/package.roc", "packaging/functional-languages/roc/SSHFling.roc", "packaging/build-functional-languages.py"],
        ),
        not_applicable_surface("sql-no-portable-launcher", "SQL", "database-specific tooling", "portable SQL deployment", "standard SQL has no portable host-process API and SSHFling has no database protocol"),
        not_applicable_surface("hcl-no-safe-launcher", "HCL/Terraform", "Terraform module", "declarative infrastructure module", "local-exec would be an unsafe shell-string side effect, not a typed launcher"),
        not_applicable_surface("apex-no-process-api", "Apex", "Salesforce package", "managed-platform package", "Apex cannot start host processes; an HTTP relayer would be a separate privileged service"),
        not_applicable_surface("tsql-no-safe-launcher", "T-SQL", "SQL Server tooling", "database extension", "xp_cmdshell is a disabled-by-default service-account escape hatch and is rejected for new code"),
        not_applicable_surface("solidity-no-host-launcher", "Solidity", "Foundry/Hardhat", "EVM contract package", "smart-contract bytecode cannot launch a host process"),
        not_applicable_surface("vyper-no-host-launcher", "Vyper", "Vyper/EVM tooling", "EVM contract package", "smart-contract bytecode cannot launch a host process"),
        not_applicable_surface("move-no-host-launcher", "Move", "Move package", "Move VM package", "Move modules cannot launch a host process"),
        not_applicable_surface("scratch-no-host-launcher", "Scratch", "Scratch project", "sandboxed visual project", "a privileged extension host would be a separate service, not a Scratch launcher"),
        not_applicable_surface("verilog-no-deployment", "Verilog", "HDL simulator project", "synthesizable hardware description", "simulator system tasks are not deployable or synthesizable SSHFling libraries"),
        not_applicable_surface("vhdl-no-deployment", "VHDL", "HDL simulator project", "synthesizable hardware description", "foreign/simulator interfaces do not form a synthesizable host launcher"),
        not_applicable_surface("systemverilog-no-deployment", "SystemVerilog", "HDL simulator project", "synthesizable hardware description", "DPI and system tasks are simulator mechanisms, not deployable SSHFling packages"),
        not_applicable_surface("cuda-device-no-launcher", "CUDA", "CUDA toolkit", "device-code package", "device code cannot launch host processes; a host wrapper would duplicate the C++ surface"),
        not_applicable_surface("opencl-device-no-launcher", "OpenCL C", "OpenCL toolchain", "kernel-source package", "OpenCL kernels cannot create host processes; a host wrapper would duplicate C/C++"),
        not_applicable_surface("glsl-no-launcher", "GLSL", "shader toolchain", "shader package", "shader stages have no host-process API"),
        not_applicable_surface("hlsl-no-launcher", "HLSL", "shader toolchain", "shader package", "shader stages have no host-process API"),
        not_applicable_surface("wgsl-no-launcher", "WGSL", "WebGPU shader tooling", "shader module", "WebGPU shader stages have no host-process API"),
    ]
)

_PROMOTED_RUNTIME_SURFACES = {
    "dart-pub-runtime",
    "julia-pkg-runtime",
    "janet-jpm-runtime",
    "j-package-runtime",
    "v-vpm-runtime",
    "wasi-module-runtime",
    "odin-source-runtime",
    "pony-corral-runtime",
    "cfml-commandbox-runtime",
    "hack-hhvm-runtime",
    "smalltalk-package-runtime",
    "apl-gnu-runtime",
    "matlab-package-folder-runtime",
    "wolfram-paclet-runtime",
    "chapel-mason-runtime",
    "ballerina-package-runtime",
    "roc-package-runtime",
}
CATALOG_SURFACES = [
    item for item in CATALOG_SURFACES if item["id"] not in _PROMOTED_RUNTIME_SURFACES
]


def verification_cells(deployments: Iterable[dict[str, object]] = DEPLOYMENTS) -> list[dict[str, str]]:
    cells: list[dict[str, str]] = []
    for deployment_index, item in enumerate(deployments, start=1):
        evidence = item["evidence"]
        assert isinstance(evidence, dict)
        for check_index, (check_id, check_name) in enumerate(CHECKS, start=1):
            cells.append(
                {
                    "cell_id": f"LD-{deployment_index:02d}-{check_index:02d}",
                    "deployment_id": str(item["id"]),
                    "language": str(item["language"]),
                    "package_manager": str(item["package_manager"]),
                    "deployment_type": str(item["deployment_type"]),
                    "interface_type": str(item["interface_type"]),
                    "check_id": check_id,
                    "check_name": check_name,
                    "status": str(item["status"]),
                    "evidence": str(evidence[check_id]),
                }
            )
    return cells


def catalog_cells(
    deployments: Iterable[dict[str, object]] = DEPLOYMENTS,
    catalog_surfaces: Iterable[dict[str, object]] = CATALOG_SURFACES,
) -> list[dict[str, str]]:
    """Return explicit package, publication, and runtime boundaries for entries 1-91."""

    surfaces = [*deployments, *catalog_surfaces]
    todo_status_by_language = dict(todo_first_91_catalog())
    cells: list[dict[str, str]] = []
    for order, (language, catalog_status) in enumerate(FIRST_91_CATALOG, start=1):
        matches = [item for item in surfaces if item["language"] == language]
        for surface_index, item in enumerate(matches, start=1):
            cells.append(
                {
                    "cell_id": f"C91-{order:03d}-{surface_index:02d}",
                    "order": str(order),
                    "surface_id": str(item["id"]),
                    "language": language,
                    "package_manager": str(item["package_manager"]),
                    "deployment_type": str(item["deployment_type"]),
                    "interface_type": str(item["interface_type"]),
                    "artifact": str(item["artifact"]),
                    "status": str(item["status"]),
                    "catalog_status": catalog_status,
                    "todo_status": todo_status_by_language.get(language, catalog_status),
                    "evidence": str(item["validation_evidence"]),
                    "rationale": str(
                        item.get("rationale", "Detailed eight-check evidence follows.")
                    ),
                }
            )
    return cells


def derived_catalog_status(cells: Iterable[dict[str, str]]) -> str:
    statuses = {cell["status"] for cell in cells}
    if "BLOCKED" in statuses:
        return "BLOCKED"
    if statuses == {"NOT_APPLICABLE"}:
        return "NOT_APPLICABLE"
    if "PASS" in statuses and "NOT_APPLICABLE" not in statuses:
        return "PASS"
    return "INVALID"


def todo_first_91_catalog(path: Path = TODO_PATH) -> list[tuple[str, str]]:
    if not path.is_file():
        return []
    rows: list[tuple[str, str]] = []
    in_catalog = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "## All Language Catalog":
            in_catalog = True
            continue
        if in_catalog and line.startswith("## "):
            break
        if not in_catalog or not line.startswith("|"):
            continue
        parts = [part.strip() for part in line.strip().strip("|").split("|")]
        if len(parts) < 4 or not parts[0].isdigit():
            continue
        order = int(parts[0])
        if order > 91:
            break
        rows.append((parts[1], parts[3]))
    return rows


CONTRADICTORY_PASS_EVIDENCE = re.compile(
    r"(?<![-\w])(SKIP|BLOCKED|NOT_APPLICABLE|FAIL|FAILED)(?![-\w])"
)


def status_evidence_errors(
    records: Iterable[dict[str, object]],
    label: str,
) -> list[str]:
    errors: list[str] = []
    for item in records:
        item_id = str(item["id"])
        status = str(item.get("status", ""))
        validation_status = str(item.get("validation_status", ""))
        validation_evidence = str(item.get("validation_evidence", ""))
        if status not in ALLOWED_STATUSES:
            errors.append(f"{label} {item_id}: unsupported status {status!r}")
        if status != validation_status:
            errors.append(
                f"{label} {item_id}: status {status} disagrees with validation status "
                f"{validation_status}"
            )
        if not validation_evidence.strip():
            errors.append(f"{label} {item_id}: validation evidence is empty")
        if status == "PASS" and CONTRADICTORY_PASS_EVIDENCE.search(validation_evidence):
            errors.append(
                f"{label} {item_id}: PASS evidence contains SKIP/BLOCKED/FAIL status"
            )
        evidence = item.get("evidence")
        if status == "PASS" and isinstance(evidence, dict):
            for check_id, value in evidence.items():
                if CONTRADICTORY_PASS_EVIDENCE.search(str(value)):
                    errors.append(
                        f"{label} {item_id}: PASS {check_id} evidence contains "
                        "SKIP/BLOCKED/FAIL status"
                    )
    return errors


def validate_required_paths(records: Iterable[dict[str, object]]) -> list[str]:
    errors: list[str] = []
    root = REPO_ROOT.resolve()
    for item in records:
        item_id = str(item["id"])
        for relative in item["required_paths"]:
            path = (REPO_ROOT / str(relative)).resolve()
            try:
                path.relative_to(root)
            except ValueError:
                errors.append(f"{item_id}: required path escapes repository: {relative}")
                continue
            if not path.exists():
                errors.append(f"{item_id}: missing required path: {relative}")
    return errors


def validate_matrix(
    deployments: Iterable[dict[str, object]] = DEPLOYMENTS,
    catalog_surfaces: Iterable[dict[str, object]] = CATALOG_SURFACES,
) -> list[str]:
    deployments = list(deployments)
    catalog_surfaces = list(catalog_surfaces)
    cells = verification_cells(deployments)
    coverage = catalog_cells(deployments, catalog_surfaces)
    all_surfaces = [*deployments, *catalog_surfaces]
    errors: list[str] = []

    surface_ids = [str(item["id"]) for item in all_surfaces]
    if len(surface_ids) != len(set(surface_ids)):
        errors.append("deployment and catalog surface IDs must be unique")
    combinations = [
        (str(item["language"]), str(item["package_manager"]), str(item["deployment_type"]))
        for item in all_surfaces
    ]
    if len(combinations) != len(set(combinations)):
        errors.append("language/package-manager/deployment combinations must be unique")
    if len(FIRST_91_CATALOG) != 91:
        errors.append(
            f"first catalog slice must contain 91 entries, found {len(FIRST_91_CATALOG)}"
        )
    catalog_names = [language for language, _status in FIRST_91_CATALOG]
    if len(catalog_names) != len(set(catalog_names)):
        errors.append("first-91 catalog language names must be unique")
    todo_catalog = todo_first_91_catalog()
    if todo_catalog:
        if [language for language, _status in todo_catalog] != catalog_names:
            errors.append("first-91 catalog language order disagrees with TODO.txt")
        if any(status not in ALLOWED_STATUSES for _language, status in todo_catalog):
            errors.append("TODO.txt first-91 catalog contains an unsupported status")

    if len(cells) < 400:
        errors.append(
            f"matrix must contain at least 400 detailed verification cells, found {len(cells)}"
        )
    if len({cell["cell_id"] for cell in cells}) != len(cells):
        errors.append("verification cell IDs must be unique")
    if {cell["status"] for cell in cells} != {"PASS"}:
        errors.append("detailed eight-check deployments may contain only PASS cells")
    if any(not cell["evidence"].strip() for cell in cells):
        errors.append("every detailed verification cell must contain evidence")
    if len({cell["cell_id"] for cell in coverage}) != len(coverage):
        errors.append("first-91 catalog cell IDs must be unique")

    by_language: dict[str, list[dict[str, str]]] = {}
    for cell in coverage:
        by_language.setdefault(cell["language"], []).append(cell)
    for language, expected_status in FIRST_91_CATALOG:
        language_cells = by_language.get(language, [])
        if not language_cells:
            errors.append(f"{language}: no explicit first-91 deployment/package boundary")
            continue
        actual_status = derived_catalog_status(language_cells)
        if actual_status != expected_status:
            errors.append(
                f"{language}: catalog status {expected_status} disagrees with surface status "
                f"{actual_status}"
            )
        if expected_status == "PASS" and not any(
            cell["status"] == "PASS"
            and any(
                token in cell["interface_type"].lower()
                for token in ("library", "cli", "command", "module")
            )
            for cell in language_cells
        ):
            errors.append(
                f"{language}: PASS catalog row lacks a validated library-or-CLI surface"
            )

    errors.extend(status_evidence_errors(deployments, "deployment"))
    errors.extend(status_evidence_errors(catalog_surfaces, "catalog surface"))
    errors.extend(validate_required_paths(all_surfaces))

    package_managers = {str(item["package_manager"]) for item in all_surfaces}
    for required in (
        "Maven",
        "Gradle",
        "NuGet",
        "pip",
        "npm",
        "Cargo",
        "Composer",
        "RubyGems",
        "Bundler",
        "CMake",
        "pkg-config",
        "MakeMaker/CPAN",
        "Cabal",
        "Mix",
        "SwiftPM",
        "Julia Pkg",
        "Guix",
    ):
        if required not in package_managers:
            errors.append(f"missing required deployment manager: {required}")

    library_deployments = [
        item for item in deployments if "library" in str(item["interface_type"]).lower()
    ]
    if len(library_deployments) < 50:
        errors.append("matrix must include at least 50 validated importable library surfaces")

    makefile = (REPO_ROOT / "Makefile").read_text(encoding="utf-8")
    for item in deployments:
        deployment_id = str(item["id"])
        build_target = str(item["build_target"])
        if f"{build_target}:" not in makefile:
            errors.append(f"{deployment_id}: missing Make target {build_target}")
        evidence = item["evidence"]
        assert isinstance(evidence, dict)
        if set(evidence) != {check[0] for check in CHECKS}:
            errors.append(f"{deployment_id}: evidence must cover every required check")

    for language in ("Java", "Kotlin", "Scala", "Groovy", "Clojure"):
        managers = {
            item["package_manager"] for item in deployments if item["language"] == language
        }
        if not {"Maven", "Gradle"}.issubset(managers):
            errors.append(f"{language}: Maven and Gradle deployment surfaces are both required")
    return errors


def escape_table(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(
    deployments: Iterable[dict[str, object]] = DEPLOYMENTS,
    catalog_surfaces: Iterable[dict[str, object]] = CATALOG_SURFACES,
) -> str:
    deployments = list(deployments)
    catalog_surfaces = list(catalog_surfaces)
    cells = verification_cells(deployments)
    coverage = catalog_cells(deployments, catalog_surfaces)
    library_count = sum(
        "library" in str(item["interface_type"]).lower() for item in deployments
    )
    catalog_counts = Counter(status for _language, status in FIRST_91_CATALOG)
    surface_counts = Counter(cell["status"] for cell in coverage)
    todo_statuses = dict(todo_first_91_catalog())
    todo_mismatches = [
        language
        for language, status in FIRST_91_CATALOG
        if todo_statuses and todo_statuses.get(language) != status
    ]
    lines = [
        "# SSHFling Language Deployment And Library Matrix",
        "",
        "This generated matrix covers every entry in the first 91-language catalog with",
        "an explicit package manager or distribution mechanism, deployment type, interface,",
        "and artifact boundary. Maven and Gradle are separate JVM deployments, and real",
        "importable library surfaces are named rather than inferred from language names.",
        "",
        (
            f"Catalog outcomes: **{catalog_counts['PASS']} PASS**, "
            f"**{catalog_counts['BLOCKED']} BLOCKED**, and "
            f"**{catalog_counts['NOT_APPLICABLE']} NOT_APPLICABLE**. The catalog expands "
            f"to **{len(coverage)} explicit surface cells** "
            f"({surface_counts['PASS']} PASS, {surface_counts['BLOCKED']} BLOCKED, "
            f"{surface_counts['NOT_APPLICABLE']} NOT_APPLICABLE)."
        ),
        (
            f"Fully implemented runtime deployments retain **{len(cells)} detailed PASS "
            f"cells** across **{len(deployments)} surfaces**, including **{library_count} "
            "validated library-capable surfaces**."
        ),
        "",
        "A source-archive publication PASS proves deterministic archive creation and inventory",
        "only. It is deliberately separate from install, library-consumer, CLI, and runtime",
        "validation. A language can therefore have a PASS publication cell and remain BLOCKED",
        "overall when its toolchain/runtime cell is BLOCKED. Detailed eight-check rows appear",
        "only for runtime deployments whose complete workflow passed.",
        "",
        (
            f"TODO status audit: **{len(todo_mismatches)} row(s) differ** from current package "
            f"evidence ({', '.join(todo_mismatches) if todo_mismatches else 'none'}). "
            "The matrix status is evidence-derived; the TODO status is retained in its own column."
        ),
        "",
        "## First-91 Catalog Coverage",
        "",
        "| Cell | Order | Language | Package manager / mechanism | Deployment type | Interface | Artifact | Surface | Matrix | TODO | Evidence or boundary |",
        "| --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for cell in coverage:
        lines.append(
            "| {cell_id} | {order} | {language} | {manager} | {deployment} | {interface} | {artifact} | {status} | {catalog_status} | {todo_status} | {detail} |".format(
                cell_id=cell["cell_id"],
                order=cell["order"],
                language=escape_table(cell["language"]),
                manager=escape_table(cell["package_manager"]),
                deployment=escape_table(cell["deployment_type"]),
                interface=escape_table(cell["interface_type"]),
                artifact=escape_table(cell["artifact"]),
                status=cell["status"],
                catalog_status=cell["catalog_status"],
                todo_status=cell["todo_status"],
                detail=escape_table(cell["evidence"]),
            )
        )

    lines.extend(
        [
            "",
            "## Fully Validated Deployment Surfaces",
            "",
            "These surfaces alone receive the detailed eight-check lifecycle grid.",
            "",
            "| ID | Language | Package manager | Deployment type | Interface | Artifact | Make target |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for item in deployments:
        lines.append(
            "| {id} | {language} | {manager} | {deployment} | {interface} | {artifact} | `{target}` |".format(
                id=escape_table(item["id"]),
                language=escape_table(item["language"]),
                manager=escape_table(item["package_manager"]),
                deployment=escape_table(item["deployment_type"]),
                interface=escape_table(item["interface_type"]),
                artifact=escape_table(item["artifact"]),
                target=escape_table(item["build_target"]),
            )
        )

    lines.extend(
        [
            "",
            "## Detailed Eight-Check Verification Cells",
            "",
            "| Cell | Language | Manager | Deployment | Interface | Check | Status | Evidence |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
    )
    for cell in cells:
        lines.append(
            "| {cell_id} | {language} | {manager} | {deployment} | {interface} | {check} | {status} | {evidence} |".format(
                cell_id=cell["cell_id"],
                language=escape_table(cell["language"]),
                manager=escape_table(cell["package_manager"]),
                deployment=escape_table(cell["deployment_type"]),
                interface=escape_table(cell["interface_type"]),
                check=escape_table(cell["check_name"]),
                status=cell["status"],
                evidence=escape_table(cell["evidence"]),
            )
        )
    lines.append("")
    return "\n".join(lines)


def render_library_index(
    deployments: Iterable[dict[str, object]] = DEPLOYMENTS,
    catalog_surfaces: Iterable[dict[str, object]] = CATALOG_SURFACES,
) -> str:
    library_cells = [
        cell
        for cell in catalog_cells(deployments, catalog_surfaces)
        if not cell["interface_type"].lower().startswith("no library")
        if any(
            token in cell["interface_type"].lower()
            for token in ("library", "module")
        )
    ]
    counts = Counter(cell["status"] for cell in library_cells)
    lines = [
        LIBRARIES_BEGIN,
        "",
        "## Generated First-91 Library Surface Index",
        "",
        (
            f"This index contains {len(library_cells)} explicit library/module surfaces: "
            f"{counts['PASS']} PASS and {counts['BLOCKED']} BLOCKED. Source-archive "
            "publication rows are excluded because publication alone is not library runtime evidence."
        ),
        "",
        "| Order | Language | Package manager | Deployment | Interface | Status | Artifact | Evidence or blocker |",
        "| ---: | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for cell in library_cells:
        lines.append(
            "| {order} | {language} | {manager} | {deployment} | {interface} | {status} | {artifact} | {evidence} |".format(
                order=cell["order"],
                language=escape_table(cell["language"]),
                manager=escape_table(cell["package_manager"]),
                deployment=escape_table(cell["deployment_type"]),
                interface=escape_table(cell["interface_type"]),
                status=cell["status"],
                artifact=escape_table(cell["artifact"]),
                evidence=escape_table(cell["evidence"]),
            )
        )
    lines.extend(["", LIBRARIES_END])
    return "\n".join(lines)


def render_todo_checklist(deployments: Iterable[dict[str, object]] = DEPLOYMENTS) -> str:
    deployments = list(deployments)
    cells = verification_cells(deployments)
    lines = [
        TODO_BEGIN,
        "",
        "## Implemented Language Deployment And Library Cells",
        "",
        (
            f"Generated implementation checklist: {len(cells)} PASS cells across "
            f"{len(deployments)} package/deployment surfaces. These are verification cells, "
            "not distinct-language claims."
        ),
        "",
    ]
    for cell in cells:
        lines.append(
            "- [x] {cell_id}. {language} / {manager} / {deployment} / {check}. "
            "- status: PASS; interface: {interface}; evidence: {evidence}; "
            "owner: language-deployment-matrix".format(
                cell_id=cell["cell_id"],
                language=cell["language"],
                manager=cell["package_manager"],
                deployment=cell["deployment_type"],
                check=cell["check_name"],
                interface=cell["interface_type"],
                evidence=cell["evidence"],
            )
        )
    lines.extend(["", TODO_END])
    return "\n".join(lines)


def replace_between(text: str, start: str, end: str, replacement: str) -> str:
    start_index = text.find(start)
    end_index = text.find(end)
    if start_index != -1 and end_index != -1 and end_index > start_index:
        return text[:start_index] + replacement + text[end_index + len(end) :]
    return text.rstrip() + "\n\n" + replacement + "\n"


def write_outputs(update_todo: bool = False) -> None:
    DOC_PATH.parent.mkdir(parents=True, exist_ok=True)
    DOC_PATH.write_text(render_markdown(), encoding="utf-8")
    current_libraries = (
        LIBRARIES_DOC_PATH.read_text(encoding="utf-8")
        if LIBRARIES_DOC_PATH.is_file()
        else "# SSHFling Library APIs\n"
    )
    LIBRARIES_DOC_PATH.write_text(
        replace_between(
            current_libraries,
            LIBRARIES_BEGIN,
            LIBRARIES_END,
            render_library_index(),
        ),
        encoding="utf-8",
    )
    if update_todo and TODO_PATH.exists():
        current = TODO_PATH.read_text(encoding="utf-8")
        TODO_PATH.write_text(
            replace_between(current, TODO_BEGIN, TODO_END, render_todo_checklist()),
            encoding="utf-8",
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write the generated Markdown matrix")
    parser.add_argument("--update-todo", action="store_true", help="update the ignored root TODO checklist")
    parser.add_argument("--check", action="store_true", help="verify the generated Markdown is current")
    args = parser.parse_args(argv)

    errors = validate_matrix()
    if errors:
        for error in errors:
            print(error)
        return 1

    rendered = render_markdown()
    if args.write or args.update_todo:
        write_outputs(update_todo=args.update_todo)
    if args.check:
        if not DOC_PATH.is_file() or DOC_PATH.read_text(encoding="utf-8") != rendered:
            print(
                f"{DOC_PATH.relative_to(REPO_ROOT)} is not current; "
                "run tools/generate_language_deployment_matrix.py --write"
            )
            return 1
        if not LIBRARIES_DOC_PATH.is_file():
            print(f"{LIBRARIES_DOC_PATH.relative_to(REPO_ROOT)} is missing")
            return 1
        current_libraries = LIBRARIES_DOC_PATH.read_text(encoding="utf-8")
        expected_libraries = replace_between(
            current_libraries,
            LIBRARIES_BEGIN,
            LIBRARIES_END,
            render_library_index(),
        )
        if current_libraries != expected_libraries:
            print(
                f"{LIBRARIES_DOC_PATH.relative_to(REPO_ROOT)} is not current; "
                "run tools/generate_language_deployment_matrix.py --write"
            )
            return 1
    if not args.write and not args.update_todo and not args.check:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
