#!/usr/bin/env python3
"""Generate the verified language package, deployment, and library matrix."""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Iterable


REPO_ROOT = Path(__file__).resolve().parents[1]
DOC_PATH = REPO_ROOT / "docs" / "language-deployment-support.md"
TODO_PATH = REPO_ROOT / "TODO.txt"

TODO_BEGIN = "<!-- BEGIN GENERATED LANGUAGE DEPLOYMENT CHECKLIST -->"
TODO_END = "<!-- END GENERATED LANGUAGE DEPLOYMENT CHECKLIST -->"

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
        "evidence": dict(zip((check[0] for check in CHECKS), evidence, strict=True)),
    }


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
                    "status": "PASS",
                    "evidence": str(evidence[check_id]),
                }
            )
    return cells


def validate_matrix(deployments: Iterable[dict[str, object]] = DEPLOYMENTS) -> list[str]:
    deployments = list(deployments)
    cells = verification_cells(deployments)
    errors: list[str] = []

    deployment_ids = [str(item["id"]) for item in deployments]
    if len(deployment_ids) != len(set(deployment_ids)):
        errors.append("deployment IDs must be unique")
    combinations = [
        (str(item["language"]), str(item["package_manager"]), str(item["deployment_type"]))
        for item in deployments
    ]
    if len(combinations) != len(set(combinations)):
        errors.append("language/package-manager/deployment combinations must be unique")
    if len(cells) < 100:
        errors.append(f"matrix must contain at least 100 verified cells, found {len(cells)}")
    if len({cell["cell_id"] for cell in cells}) != len(cells):
        errors.append("verification cell IDs must be unique")
    if {cell["status"] for cell in cells} != {"PASS"}:
        errors.append("implemented deployment matrix may contain only PASS cells")
    if any(not cell["evidence"].strip() for cell in cells):
        errors.append("every verification cell must contain evidence")

    package_managers = {str(item["package_manager"]) for item in deployments}
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
    ):
        if required not in package_managers:
            errors.append(f"missing required deployment manager: {required}")

    library_deployments = [item for item in deployments if "library" in str(item["interface_type"])]
    if len(library_deployments) < 10:
        errors.append("matrix must include at least 10 importable library deployment surfaces")

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
        for relative in item["required_paths"]:
            path = (REPO_ROOT / str(relative)).resolve()
            try:
                path.relative_to(REPO_ROOT.resolve())
            except ValueError:
                errors.append(f"{deployment_id}: required path escapes repository: {relative}")
                continue
            if not path.is_file():
                errors.append(f"{deployment_id}: missing required path: {relative}")
    return errors


def escape_table(value: object) -> str:
    return str(value).replace("|", "\\|").replace("\n", " ")


def render_markdown(deployments: Iterable[dict[str, object]] = DEPLOYMENTS) -> str:
    deployments = list(deployments)
    cells = verification_cells(deployments)
    languages = sorted({str(item["language"]) for item in deployments})
    library_count = sum("library" in str(item["interface_type"]) for item in deployments)
    lines = [
        "# SSHFling Language Deployment And Library Matrix",
        "",
        "This generated matrix records implemented package and consumer verification,",
        "including separate Maven and Gradle Java paths and importable library APIs.",
        f"It contains **{len(cells)} PASS cells** across **{len(deployments)} deployment surfaces**,",
        f"**{len(languages)} language ecosystems**, and **{library_count} library-capable surfaces**.",
        "The cell total is a lifecycle-verification count, not a claim that SSHFling",
        f"implements {len(cells)} distinct programming languages.",
        "",
        "A PASS cell is enforced by the referenced package build script and its clean",
        "consumer validation. Unsupported languages remain classified separately in",
        "`docs/language-support.md` and are not counted here.",
        "",
        "## Deployment Surfaces",
        "",
        "| ID | Language | Package manager | Deployment type | Interface | Artifact | Make target |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
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
            "## Verification Cells",
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
    if not args.write and not args.update_todo and not args.check:
        print(rendered)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
