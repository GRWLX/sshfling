# SSHFling Language Deployment And Library Matrix

This generated matrix records implemented package and consumer verification,
including separate Maven and Gradle Java paths and importable library APIs.
It contains **192 PASS cells** across **24 deployment surfaces**,
**14 language ecosystems**, and **19 library-capable surfaces**.
The cell total is a lifecycle-verification count, not a claim that SSHFling
implements 192 distinct programming languages.

A PASS cell is enforced by the referenced package build script and its clean
consumer validation. Unsupported languages remain classified separately in
`docs/language-support.md` and are not counted here.

## Deployment Surfaces

| ID | Language | Package manager | Deployment type | Interface | Artifact | Make target |
| --- | --- | --- | --- | --- | --- | --- |
| python-pip | Python | pip | wheel dependency | library + CLI | sshfling-VERSION-py3-none-any.whl | `package-python` |
| python-pipx | Python | pipx | isolated application | CLI | sshfling-VERSION-py3-none-any.whl | `package-python` |
| javascript-commonjs | JavaScript | npm | CommonJS dependency | library | sshfling-VERSION.tgz | `package-node` |
| javascript-esm | JavaScript | npm | ES module dependency | library | sshfling-VERSION.tgz | `package-node` |
| typescript-npm | TypeScript | npm | typed dependency | library | sshfling-VERSION.tgz | `package-node` |
| javascript-npm-bin | JavaScript | npm | package executable | CLI | sshfling-VERSION.tgz | `package-node` |
| java-maven | Java | Maven | Maven dependency | library + CLI | io.sshfling:sshfling-cli:VERSION | `package-java` |
| java-gradle | Java | Gradle | Gradle dependency | library + CLI | io.sshfling:sshfling-cli:VERSION | `package-java` |
| java-executable-jar | Java | JAR | direct executable | CLI | sshfling-cli-VERSION.jar | `package-java` |
| dotnet-nuget-library | C#/.NET | NuGet | PackageReference library | library | SSHFling.VERSION.nupkg | `package-dotnet` |
| dotnet-global-tool | C#/.NET | .NET tool | global/tool-path command | CLI | SSHFling.Tool.VERSION.nupkg | `package-dotnet` |
| go-module | Go | Go modules | module dependency and go install | library + CLI | sshfling-go-VERSION.zip | `package-go` |
| rust-cargo | Rust | Cargo | crate dependency and cargo install | library + CLI | sshfling-cli-VERSION.crate | `package-rust` |
| php-composer | PHP | Composer | Composer dependency | library + CLI | sshfling-php-VERSION.zip | `package-php` |
| ruby-rubygems | Ruby | RubyGems | gem dependency and executable | library + CLI | sshfling-VERSION.gem | `package-ruby` |
| ruby-bundler | Ruby | Bundler | bundled application dependency | library + CLI | sshfling-VERSION.gem / source path | `package-ruby` |
| c-cmake-shared | C | CMake | shared-library dependency | library | sshfling-native-VERSION.tar.gz / libsshfling.so | `package-native-libraries` |
| c-cmake-static | C | CMake | static-library dependency | library | sshfling-native-VERSION.tar.gz / libsshfling.a | `package-native-libraries` |
| c-pkg-config | C | pkg-config | compiler dependency | library | sshfling-native-VERSION.tar.gz / sshfling.pc | `package-native-libraries` |
| c-native-cli | C | CMake | installed native executable | CLI | sshfling-native-VERSION.tar.gz / sshfling-c | `package-native-libraries` |
| cpp-cmake-static | C++ | CMake | C++17 static-library dependency | library | sshfling-native-VERSION.tar.gz / sshfling.hpp | `package-native-libraries` |
| visual-basic-nuget-library | Visual Basic/.NET | NuGet | PackageReference library | library | SSHFling.VERSION.nupkg | `package-dotnet` |
| fsharp-nuget-library | F# | NuGet | PackageReference library | library | SSHFling.VERSION.nupkg | `package-dotnet` |
| perl-makemaker | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | sshfling-perl-VERSION.tar.gz | `package-perl` |

## Verification Cells

| Cell | Language | Manager | Deployment | Interface | Check | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- | --- |
| LD-01-01 | Python | pip | wheel dependency | library + CLI | Source surface | PASS | pyproject and sshfling package sources are tracked under packaging/python. |
| LD-01-02 | Python | pip | wheel dependency | library + CLI | Package metadata | PASS | pyproject declares the sshfling project, package data, Python floor, and console script. |
| LD-01-03 | Python | pip | wheel dependency | library + CLI | Package build | PASS | packaging/build-python.sh builds the wheel with pip wheel in a generated project. |
| LD-01-04 | Python | pip | wheel dependency | library + CLI | Artifact contents | PASS | validate_wheel_contents checks the Python module, entry point, license, and templates. |
| LD-01-05 | Python | pip | wheel dependency | library + CLI | Isolated consumer | PASS | validate_pip_install creates a clean venv and installs with --no-index and --no-deps. |
| LD-01-06 | Python | pip | wheel dependency | library + CLI | Public interface | PASS | The installed consumer imports sshfling and invokes sshfling.run(["--version"]). |
| LD-01-07 | Python | pip | wheel dependency | library + CLI | Version contract | PASS | The installed console script must print the exact release version. |
| LD-01-08 | Python | pip | wheel dependency | library + CLI | Runtime assets/workflow | PASS | The venv consumer runs doctor and init and checks executable templates and secrets state. |
| LD-02-01 | Python | pipx | isolated application | CLI | Source surface | PASS | The Python wheel source also defines the pipx application surface. |
| LD-02-02 | Python | pipx | isolated application | CLI | Package metadata | PASS | The pyproject console-script entry maps sshfling to sshfling.cli:main. |
| LD-02-03 | Python | pipx | isolated application | CLI | Package build | PASS | The same validated wheel is the pipx installation artifact. |
| LD-02-04 | Python | pipx | isolated application | CLI | Artifact contents | PASS | Wheel inspection proves the console entry point and bundled templates are present. |
| LD-02-05 | Python | pipx | isolated application | CLI | Isolated consumer | PASS | validate_pipx_install uses isolated PIPX_HOME and PIPX_BIN_DIR directories. |
| LD-02-06 | Python | pipx | isolated application | CLI | Public interface | PASS | pipx exposes the installed sshfling command without importing project checkout code. |
| LD-02-07 | Python | pipx | isolated application | CLI | Version contract | PASS | The pipx command must print the exact release version. |
| LD-02-08 | Python | pipx | isolated application | CLI | Runtime assets/workflow | PASS | The pipx command runs init, validates generated state, and is then uninstalled. |
| LD-03-01 | JavaScript | npm | CommonJS dependency | library | Source surface | PASS | The CommonJS launcher implementation is tracked in packaging/node/index.js. |
| LD-03-02 | JavaScript | npm | CommonJS dependency | library | Package metadata | PASS | package.json declares main, require/default exports, files, engines, and package identity. |
| LD-03-03 | JavaScript | npm | CommonJS dependency | library | Package build | PASS | packaging/build-node.sh creates the tarball with npm pack. |
| LD-03-04 | JavaScript | npm | CommonJS dependency | library | Artifact contents | PASS | Archive checks require index.js, declarations, CLI, license, runtime, and templates. |
| LD-03-05 | JavaScript | npm | CommonJS dependency | library | Isolated consumer | PASS | validate_installed_package installs the tarball into a clean application prefix. |
| LD-03-06 | JavaScript | npm | CommonJS dependency | library | Public interface | PASS | A CommonJS consumer requires sshfling and invokes api.run(["--version"]). |
| LD-03-07 | JavaScript | npm | CommonJS dependency | library | Version contract | PASS | The installed package binary must print the exact release version. |
| LD-03-08 | JavaScript | npm | CommonJS dependency | library | Runtime assets/workflow | PASS | The installed package runs doctor and init and verifies bundled template modes. |
| LD-04-01 | JavaScript | npm | ES module dependency | library | Source surface | PASS | The npm library is importable from an ES module consumer through package exports. |
| LD-04-02 | JavaScript | npm | ES module dependency | library | Package metadata | PASS | package.json exposes the default module target and package metadata. |
| LD-04-03 | JavaScript | npm | ES module dependency | library | Package build | PASS | The npm tarball is built from the generated versioned package directory. |
| LD-04-04 | JavaScript | npm | ES module dependency | library | Artifact contents | PASS | Tarball checks prove the JavaScript API and bundled runtime are shipped together. |
| LD-04-05 | JavaScript | npm | ES module dependency | library | Isolated consumer | PASS | The ESM import executes from the clean npm application prefix. |
| LD-04-06 | JavaScript | npm | ES module dependency | library | Public interface | PASS | The ESM consumer imports sshfling and invokes api.run(["--version"]). |
| LD-04-07 | JavaScript | npm | ES module dependency | library | Version contract | PASS | The shared installed package binary validates the exact release version. |
| LD-04-08 | JavaScript | npm | ES module dependency | library | Runtime assets/workflow | PASS | The ESM API uses the same checked runtime/template paths as the CLI smoke workflow. |
| LD-05-01 | TypeScript | npm | typed dependency | library | Source surface | PASS | Tracked declarations and a strict TypeScript consumer cover the public npm API. |
| LD-05-02 | TypeScript | npm | typed dependency | library | Package metadata | PASS | package.json maps its types field and conditional export to index.d.ts. |
| LD-05-03 | TypeScript | npm | typed dependency | library | Package build | PASS | The declarations ship in the same npm pack output as the JavaScript implementation. |
| LD-05-04 | TypeScript | npm | typed dependency | library | Artifact contents | PASS | Tarball validation requires package/index.d.ts. |
| LD-05-05 | TypeScript | npm | typed dependency | library | Isolated consumer | PASS | The clean npm prefix installs a pinned TypeScript compiler and the packed dependency. |
| LD-05-06 | TypeScript | npm | typed dependency | library | Public interface | PASS | tsc --strict --noEmit validates named/default imports, RunOptions, run, and templateDir. |
| LD-05-07 | TypeScript | npm | typed dependency | library | Version contract | PASS | The typed run signatures return number and are paired with the runtime version smoke test. |
| LD-05-08 | TypeScript | npm | typed dependency | library | Runtime assets/workflow | PASS | The typed dependency resolves the same bundled templates exercised by npm doctor/init. |
| LD-06-01 | JavaScript | npm | package executable | CLI | Source surface | PASS | The Node executable wrapper is tracked under packaging/node/bin. |
| LD-06-02 | JavaScript | npm | package executable | CLI | Package metadata | PASS | package.json maps the sshfling bin name to bin/sshfling.js. |
| LD-06-03 | JavaScript | npm | package executable | CLI | Package build | PASS | npm pack creates the installable CLI tarball. |
| LD-06-04 | JavaScript | npm | package executable | CLI | Artifact contents | PASS | Tarball validation requires the executable wrapper and runtime resources. |
| LD-06-05 | JavaScript | npm | package executable | CLI | Isolated consumer | PASS | npm installs the package into an isolated prefix and creates node_modules/.bin/sshfling. |
| LD-06-06 | JavaScript | npm | package executable | CLI | Public interface | PASS | The installed package exposes a stable sshfling executable. |
| LD-06-07 | JavaScript | npm | package executable | CLI | Version contract | PASS | The npm binary must print the exact release version. |
| LD-06-08 | JavaScript | npm | package executable | CLI | Runtime assets/workflow | PASS | The binary runs doctor/init, validates generated files, and is removed by npm uninstall. |
| LD-07-01 | Java | Maven | Maven dependency | library + CLI | Source surface | PASS | Java sources, Maven metadata, and a clean Maven consumer are tracked. |
| LD-07-02 | Java | Maven | Maven dependency | library + CLI | Package metadata | PASS | The generated POM publishes concrete io.sshfling:sshfling-cli coordinates. |
| LD-07-03 | Java | Maven | Maven dependency | library + CLI | Package build | PASS | packaging/build-java.sh runs Maven clean install with the release version. |
| LD-07-04 | Java | Maven | Maven dependency | library + CLI | Artifact contents | PASS | Maven produces executable, sources, and Javadocs JARs plus a concrete POM. |
| LD-07-05 | Java | Maven | Maven dependency | library + CLI | Isolated consumer | PASS | A clean Maven consumer resolves the package from an isolated local repository. |
| LD-07-06 | Java | Maven | Maven dependency | library + CLI | Public interface | PASS | MavenConsumer compiles against and invokes the public SSHFling.run API. |
| LD-07-07 | Java | Maven | Maven dependency | library + CLI | Version contract | PASS | The Maven consumer API invocation must print the exact release version. |
| LD-07-08 | Java | Maven | Maven dependency | library + CLI | Runtime assets/workflow | PASS | The Maven JAR runs doctor/init and its runtime manifest and templates are inspected. |
| LD-08-01 | Java | Gradle | Gradle dependency | library + CLI | Source surface | PASS | A Java library/application build and clean Gradle consumer are tracked. |
| LD-08-02 | Java | Gradle | Gradle dependency | library + CLI | Package metadata | PASS | Gradle metadata declares group, release property, Java 11, sources, and Javadocs. |
| LD-08-03 | Java | Gradle | Gradle dependency | library + CLI | Package build | PASS | The checksum-pinned Gradle wrapper runs clean build and publish for the generated package project. |
| LD-08-04 | Java | Gradle | Gradle dependency | library + CLI | Artifact contents | PASS | The Gradle publication is checked for JAR, sources, Javadocs, POM, module metadata, and runtime resources. |
| LD-08-05 | Java | Gradle | Gradle dependency | library + CLI | Isolated consumer | PASS | A clean Gradle consumer resolves the coordinate from Gradle's isolated publication repository. |
| LD-08-06 | Java | Gradle | Gradle dependency | library + CLI | Public interface | PASS | GradleConsumer compiles against and invokes the public SSHFling.run API. |
| LD-08-07 | Java | Gradle | Gradle dependency | library + CLI | Version contract | PASS | The Gradle consumer API invocation must print the exact release version. |
| LD-08-08 | Java | Gradle | Gradle dependency | library + CLI | Runtime assets/workflow | PASS | The Gradle artifact embeds the same resource manifest validated by doctor/init JAR smoke tests. |
| LD-09-01 | Java | JAR | direct executable | CLI | Source surface | PASS | SSHFling.java supplies the Java main class and public launcher API. |
| LD-09-02 | Java | JAR | direct executable | CLI | Package metadata | PASS | Maven and Gradle both write the Main-Class manifest entry. |
| LD-09-03 | Java | JAR | direct executable | CLI | Package build | PASS | The Java package target builds the direct executable JAR. |
| LD-09-04 | Java | JAR | direct executable | CLI | Artifact contents | PASS | JAR inspection checks the launcher, resource manifest, Python runtime, and templates. |
| LD-09-05 | Java | JAR | direct executable | CLI | Isolated consumer | PASS | Validation executes the JAR against a temporary smoke-project directory. |
| LD-09-06 | Java | JAR | direct executable | CLI | Public interface | PASS | java -jar provides the direct SSHFling command interface. |
| LD-09-07 | Java | JAR | direct executable | CLI | Version contract | PASS | The direct JAR must print the exact release version. |
| LD-09-08 | Java | JAR | direct executable | CLI | Runtime assets/workflow | PASS | The direct JAR runs doctor/init and validates generated executable and state files. |
| LD-10-01 | C#/.NET | NuGet | PackageReference library | library | Source surface | PASS | A public .NET library project, runner API, and consumer project are tracked. |
| LD-10-02 | C#/.NET | NuGet | PackageReference library | library | Package metadata | PASS | The project declares PackageId SSHFling, net10.0, XML docs, license, and repository metadata. |
| LD-10-03 | C#/.NET | NuGet | PackageReference library | library | Package build | PASS | packaging/build-dotnet.sh packs the SSHFling library in Release configuration. |
| LD-10-04 | C#/.NET | NuGet | PackageReference library | library | Artifact contents | PASS | NuGet inspection requires the DLL, XML docs, license, and README. |
| LD-10-05 | C#/.NET | NuGet | PackageReference library | library | Isolated consumer | PASS | The clean consumer restores SSHFling from only the local package directory. |
| LD-10-06 | C#/.NET | NuGet | PackageReference library | library | Public interface | PASS | The consumer calls SSHFlingRunner.Version and SSHFlingRunner.Run. |
| LD-10-07 | C#/.NET | NuGet | PackageReference library | library | Version contract | PASS | The library API call must print the exact release version. |
| LD-10-08 | C#/.NET | NuGet | PackageReference library | library | Runtime assets/workflow | PASS | Run extracts all embedded runtime assets before invoking Python and cleans the temp directory. |
| LD-11-01 | C#/.NET | .NET tool | global/tool-path command | CLI | Source surface | PASS | The .NET tool project and launcher are tracked under packaging/dotnet/SSHFling.Tool. |
| LD-11-02 | C#/.NET | .NET tool | global/tool-path command | CLI | Package metadata | PASS | The project declares PackAsTool, ToolCommandName sshfling, package metadata, and net10.0. |
| LD-11-03 | C#/.NET | .NET tool | global/tool-path command | CLI | Package build | PASS | packaging/build-dotnet.sh packs the global tool in Release configuration. |
| LD-11-04 | C#/.NET | .NET tool | global/tool-path command | CLI | Artifact contents | PASS | NuGet archive checks require tool runtime files and systemd template resources. |
| LD-11-05 | C#/.NET | .NET tool | global/tool-path command | CLI | Isolated consumer | PASS | dotnet tool install uses an isolated tool path and local package source. |
| LD-11-06 | C#/.NET | .NET tool | global/tool-path command | CLI | Public interface | PASS | The package exposes the sshfling tool command. |
| LD-11-07 | C#/.NET | .NET tool | global/tool-path command | CLI | Version contract | PASS | The installed .NET tool must print the exact release version. |
| LD-11-08 | C#/.NET | .NET tool | global/tool-path command | CLI | Runtime assets/workflow | PASS | The installed tool runs doctor/init and validates templates and state files. |
| LD-12-01 | Go | Go modules | module dependency and go install | library + CLI | Source surface | PASS | The Go module contains an importable root package and cmd/sshfling. |
| LD-12-02 | Go | Go modules | module dependency and go install | library + CLI | Package metadata | PASS | go.mod declares the module path and the build injects the release Version constant. |
| LD-12-03 | Go | Go modules | module dependency and go install | library + CLI | Package build | PASS | packaging/build-go.sh runs formatting, tests, vet, builds, and deterministic archive creation. |
| LD-12-04 | Go | Go modules | module dependency and go install | library + CLI | Artifact contents | PASS | ZIP validation requires go.mod, library/command sources, runtime, and templates. |
| LD-12-05 | Go | Go modules | module dependency and go install | library + CLI | Isolated consumer | PASS | The extracted clean module is tested and installed with isolated Go caches and GOBIN. |
| LD-12-06 | Go | Go modules | module dependency and go install | library + CLI | Public interface | PASS | Go tests invoke sshfling.Run while cmd/sshfling exposes the CLI. |
| LD-12-07 | Go | Go modules | module dependency and go install | library + CLI | Version contract | PASS | The installed Go command must print the exact release version. |
| LD-12-08 | Go | Go modules | module dependency and go install | library + CLI | Runtime assets/workflow | PASS | The Go command runs doctor/init and validates executable templates and generated state. |
| LD-13-01 | Rust | Cargo | crate dependency and cargo install | library + CLI | Source surface | PASS | The Cargo project contains public library and binary targets. |
| LD-13-02 | Rust | Cargo | crate dependency and cargo install | library + CLI | Package metadata | PASS | Cargo.toml declares crate metadata, library/bin targets, Rust floor, and included resources. |
| LD-13-03 | Rust | Cargo | crate dependency and cargo install | library + CLI | Package build | PASS | The build runs cargo fmt, test, clippy, package, and optional publish dry-run. |
| LD-13-04 | Rust | Cargo | crate dependency and cargo install | library + CLI | Artifact contents | PASS | Crate inspection requires Cargo metadata, library/bin sources, runtime, and templates. |
| LD-13-05 | Rust | Cargo | crate dependency and cargo install | library + CLI | Isolated consumer | PASS | The crate is extracted and cargo-installed with isolated CARGO_HOME and target directories. |
| LD-13-06 | Rust | Cargo | crate dependency and cargo install | library + CLI | Public interface | PASS | Rust tests invoke sshfling_cli::run while the package installs the sshfling binary. |
| LD-13-07 | Rust | Cargo | crate dependency and cargo install | library + CLI | Version contract | PASS | The installed Cargo binary must print the exact release version. |
| LD-13-08 | Rust | Cargo | crate dependency and cargo install | library + CLI | Runtime assets/workflow | PASS | The Cargo binary runs doctor/init, validates state, and is removed with cargo uninstall. |
| LD-14-01 | PHP | Composer | Composer dependency | library + CLI | Source surface | PASS | The Composer package contains a PSR-4 library and vendor binary. |
| LD-14-02 | PHP | Composer | Composer dependency | library + CLI | Package metadata | PASS | composer.json declares package identity, PHP floor, PSR-4 autoloading, and bin entry. |
| LD-14-03 | PHP | Composer | Composer dependency | library + CLI | Package build | PASS | The build validates metadata/autoloading and creates a Composer ZIP archive. |
| LD-14-04 | PHP | Composer | Composer dependency | library + CLI | Artifact contents | PASS | Archive checks require composer.json, class source, binary, runtime, and templates. |
| LD-14-05 | PHP | Composer | Composer dependency | library + CLI | Isolated consumer | PASS | A clean application installs from an isolated Composer artifact repository. |
| LD-14-06 | PHP | Composer | Composer dependency | library + CLI | Public interface | PASS | Both generated and installed autoloaders invoke SSHFling::run(["--version"]). |
| LD-14-07 | PHP | Composer | Composer dependency | library + CLI | Version contract | PASS | The installed vendor binary must print the exact release version. |
| LD-14-08 | PHP | Composer | Composer dependency | library + CLI | Runtime assets/workflow | PASS | The Composer binary runs doctor/init and the package is removed with composer remove. |
| LD-15-01 | Ruby | RubyGems | gem dependency and executable | library + CLI | Source surface | PASS | The gem contains a Ruby module API and executable. |
| LD-15-02 | Ruby | RubyGems | gem dependency and executable | library + CLI | Package metadata | PASS | The gemspec declares package identity, Ruby floor, files, bindir, and executable. |
| LD-15-03 | Ruby | RubyGems | gem dependency and executable | library + CLI | Package build | PASS | packaging/build-ruby.sh runs strict gem build with the injected release version. |
| LD-15-04 | Ruby | RubyGems | gem dependency and executable | library + CLI | Artifact contents | PASS | Gem inspection requires the runtime and systemd/secrets templates in data.tar.gz. |
| LD-15-05 | Ruby | RubyGems | gem dependency and executable | library + CLI | Isolated consumer | PASS | RubyGems installs into isolated GEM_HOME, GEM_PATH, and bindir locations. |
| LD-15-06 | Ruby | RubyGems | gem dependency and executable | library + CLI | Public interface | PASS | An installed Ruby consumer requires sshfling and invokes SSHFling.run. |
| LD-15-07 | Ruby | RubyGems | gem dependency and executable | library + CLI | Version contract | PASS | The installed gem command must print the exact release version. |
| LD-15-08 | Ruby | RubyGems | gem dependency and executable | library + CLI | Runtime assets/workflow | PASS | The command runs doctor/init and gem uninstall removes the package and executable. |
| LD-16-01 | Ruby | Bundler | bundled application dependency | library + CLI | Source surface | PASS | The same Ruby library is consumed through a generated Bundler application. |
| LD-16-02 | Ruby | Bundler | bundled application dependency | library + CLI | Package metadata | PASS | Bundler resolves the versioned gemspec through an explicit local path dependency. |
| LD-16-03 | Ruby | Bundler | bundled application dependency | library + CLI | Package build | PASS | The strict gem build precedes local Bundler validation. |
| LD-16-04 | Ruby | Bundler | bundled application dependency | library + CLI | Artifact contents | PASS | Gem archive inspection proves library, executable, runtime, and templates are packaged. |
| LD-16-05 | Ruby | Bundler | bundled application dependency | library + CLI | Isolated consumer | PASS | bundle install --local uses an isolated BUNDLE_PATH with shared gems disabled. |
| LD-16-06 | Ruby | Bundler | bundled application dependency | library + CLI | Public interface | PASS | bundle exec ruby requires sshfling and invokes SSHFling.run(["--version"]). |
| LD-16-07 | Ruby | Bundler | bundled application dependency | library + CLI | Version contract | PASS | bundle exec sshfling must print the exact release version. |
| LD-16-08 | Ruby | Bundler | bundled application dependency | library + CLI | Runtime assets/workflow | PASS | The Bundler command runs init and validation removes bundle state and the lock file. |
| LD-17-01 | C | CMake | shared-library dependency | library | Source surface | PASS | The C11 implementation, public header, and external C consumer are tracked under packaging/native. |
| LD-17-02 | C | CMake | shared-library dependency | library | Package metadata | PASS | CMake exports the versioned SSHFling::shared target and installs the public include directory. |
| LD-17-03 | C | CMake | shared-library dependency | library | Package build | PASS | packaging/build-native-libraries.sh performs warning-clean Ninja/Release, Make/Debug, and ASan/UBSan builds with CTest. |
| LD-17-04 | C | CMake | shared-library dependency | library | Artifact contents | PASS | The install is checked for the shared object, versioned symlinks, header, runtime, and package config. |
| LD-17-05 | C | CMake | shared-library dependency | library | Isolated consumer | PASS | A clean external CMake project resolves find_package(SSHFling) from an isolated prefix. |
| LD-17-06 | C | CMake | shared-library dependency | library | Public interface | PASS | The C consumer links SSHFling::shared and invokes sshfling_version plus sshfling_run. |
| LD-17-07 | C | CMake | shared-library dependency | library | Version contract | PASS | The shared-library consumer output must contain the exact release version. |
| LD-17-08 | C | CMake | shared-library dependency | library | Runtime assets/workflow | PASS | The library launches the bundled runtime and the installed CLI completes an init workflow. |
| LD-18-01 | C | CMake | static-library dependency | library | Source surface | PASS | The same stable C API is available through a separately exported static target. |
| LD-18-02 | C | CMake | static-library dependency | library | Package metadata | PASS | CMake exports SSHFling::static with installed headers and version compatibility metadata. |
| LD-18-03 | C | CMake | static-library dependency | library | Package build | PASS | The native package build produces the static archive from warning-clean C11 objects in Release, Debug, and sanitizer configurations. |
| LD-18-04 | C | CMake | static-library dependency | library | Artifact contents | PASS | Install inspection requires libsshfling.a and the source archive requires the C API header. |
| LD-18-05 | C | CMake | static-library dependency | library | Isolated consumer | PASS | A dedicated clean CMake C project resolves the installed static target. |
| LD-18-06 | C | CMake | static-library dependency | library | Public interface | PASS | The consumer links SSHFling::static and invokes the same public launcher API. |
| LD-18-07 | C | CMake | static-library dependency | library | Version contract | PASS | The static C consumer validates sshfling_version against the exact release version. |
| LD-18-08 | C | CMake | static-library dependency | library | Runtime assets/workflow | PASS | The statically linked launcher executes the installed bundled runtime and templates. |
| LD-19-01 | C | pkg-config | compiler dependency | library | Source surface | PASS | The public C consumer and pkg-config template are tracked with the native implementation. |
| LD-19-02 | C | pkg-config | compiler dependency | library | Package metadata | PASS | sshfling.pc declares the installed include path, library path, linker flag, and version. |
| LD-19-03 | C | pkg-config | compiler dependency | library | Package build | PASS | The native builder configures, compiles, tests, and installs the metadata before consumption. |
| LD-19-04 | C | pkg-config | compiler dependency | library | Artifact contents | PASS | Install and archive checks cover the native library, header, runtime, templates, and source project. |
| LD-19-05 | C | pkg-config | compiler dependency | library | Isolated consumer | PASS | gcc compiles the consumer using only flags returned from the isolated prefix's pkg-config entry. |
| LD-19-06 | C | pkg-config | compiler dependency | library | Public interface | PASS | The resulting program invokes the public C version and run functions. |
| LD-19-07 | C | pkg-config | compiler dependency | library | Version contract | PASS | The pkg-config consumer output must contain the exact release version. |
| LD-19-08 | C | pkg-config | compiler dependency | library | Runtime assets/workflow | PASS | LD_LIBRARY_PATH is isolated to the installation under test while the API launches the bundled runtime. |
| LD-20-01 | C | CMake | installed native executable | CLI | Source surface | PASS | The native executable entry point and process launcher implementation are tracked C11 sources. |
| LD-20-02 | C | CMake | installed native executable | CLI | Package metadata | PASS | The CMake project installs sshfling-c with an install-relative shared-library runtime path. |
| LD-20-03 | C | CMake | installed native executable | CLI | Package build | PASS | The package target compiles and links the executable alongside both native libraries. |
| LD-20-04 | C | CMake | installed native executable | CLI | Artifact contents | PASS | The isolated prefix must contain an executable sshfling-c and the source archive includes its sources. |
| LD-20-05 | C | CMake | installed native executable | CLI | Isolated consumer | PASS | Validation executes only the binary installed under the temporary prefix. |
| LD-20-06 | C | CMake | installed native executable | CLI | Public interface | PASS | sshfling-c forwards arbitrary command arguments to the canonical bundled runtime. |
| LD-20-07 | C | CMake | installed native executable | CLI | Version contract | PASS | The installed native command must print the exact release version. |
| LD-20-08 | C | CMake | installed native executable | CLI | Runtime assets/workflow | PASS | The command runs init, verifies native helper modes, and is removed through the CMake install manifest. |
| LD-21-01 | C++ | CMake | C++17 static-library dependency | library | Source surface | PASS | A typed C++17 header wrapper and external C++ consumer are tracked with the native package. |
| LD-21-02 | C++ | CMake | C++17 static-library dependency | library | Package metadata | PASS | The wrapper consumes installed C API declarations and the project exports SSHFling::static. |
| LD-21-03 | C++ | CMake | C++17 static-library dependency | library | Package build | PASS | The C++ API test compiles warning-clean in Release, Debug, and ASan/UBSan builds before the external consumer runs. |
| LD-21-04 | C++ | CMake | C++17 static-library dependency | library | Artifact contents | PASS | The install requires sshfling.hpp and libsshfling.a; the source archive includes both consumers. |
| LD-21-05 | C++ | CMake | C++17 static-library dependency | library | Isolated consumer | PASS | A clean C++ CMake project resolves the installed package and links its static target. |
| LD-21-06 | C++ | CMake | C++17 static-library dependency | library | Public interface | PASS | The consumer invokes sshfling::version and sshfling::run through the public wrapper. |
| LD-21-07 | C++ | CMake | C++17 static-library dependency | library | Version contract | PASS | The C++ consumer validates the exact release version before launching the runtime. |
| LD-21-08 | C++ | CMake | C++17 static-library dependency | library | Runtime assets/workflow | PASS | The wrapper executes the same bundled runtime and templates through the underlying native library. |
| LD-22-01 | Visual Basic/.NET | NuGet | PackageReference library | library | Source surface | PASS | A clean Visual Basic application consumes the tracked public SSHFling .NET library. |
| LD-22-02 | Visual Basic/.NET | NuGet | PackageReference library | library | Package metadata | PASS | Its PackageReference version is injected from the exact locally packed NuGet version. |
| LD-22-03 | Visual Basic/.NET | NuGet | PackageReference library | library | Package build | PASS | packaging/build-dotnet.sh packs the library and restores the VB project from only the local source. |
| LD-22-04 | Visual Basic/.NET | NuGet | PackageReference library | library | Artifact contents | PASS | NuGet inspection requires the library DLL, XML documentation, license, and README. |
| LD-22-05 | Visual Basic/.NET | NuGet | PackageReference library | library | Isolated consumer | PASS | The Visual Basic project restores and runs outside the library source project. |
| LD-22-06 | Visual Basic/.NET | NuGet | PackageReference library | library | Public interface | PASS | Program.vb calls SSHFlingRunner.Version and SSHFlingRunner.Run. |
| LD-22-07 | Visual Basic/.NET | NuGet | PackageReference library | library | Version contract | PASS | The VB consumer checks the API version and exact runtime version output. |
| LD-22-08 | Visual Basic/.NET | NuGet | PackageReference library | library | Runtime assets/workflow | PASS | The consumer runs init, checks native helpers, and dotnet remove deletes its PackageReference. |
| LD-23-01 | F# | NuGet | PackageReference library | library | Source surface | PASS | A clean F# application consumes the tracked public SSHFling .NET library. |
| LD-23-02 | F# | NuGet | PackageReference library | library | Package metadata | PASS | Its PackageReference version is injected from the exact locally packed NuGet version. |
| LD-23-03 | F# | NuGet | PackageReference library | library | Package build | PASS | packaging/build-dotnet.sh packs the library and restores the F# project from only the local source. |
| LD-23-04 | F# | NuGet | PackageReference library | library | Artifact contents | PASS | NuGet inspection requires the library DLL, XML documentation, license, and README. |
| LD-23-05 | F# | NuGet | PackageReference library | library | Isolated consumer | PASS | The F# project restores and runs outside the library source project. |
| LD-23-06 | F# | NuGet | PackageReference library | library | Public interface | PASS | Program.fs calls SSHFlingRunner.Version and SSHFlingRunner.Run. |
| LD-23-07 | F# | NuGet | PackageReference library | library | Version contract | PASS | The F# consumer checks the API version and exact runtime version output. |
| LD-23-08 | F# | NuGet | PackageReference library | library | Runtime assets/workflow | PASS | The consumer runs init, checks native helpers, and dotnet remove deletes its PackageReference. |
| LD-24-01 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Source surface | PASS | The Perl module, executable, MakeMaker metadata, and API test are tracked under packaging/perl. |
| LD-24-02 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Package metadata | PASS | Makefile.PL declares version, Perl floor, prerequisites, executable, resources, and bundled runtime files. |
| LD-24-03 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Package build | PASS | packaging/build-perl.sh runs Makefile.PL, manifest generation, make test, and make dist. |
| LD-24-04 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Artifact contents | PASS | Archive checks require the module, build metadata, Python runtime, and native template helpers. |
| LD-24-05 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Isolated consumer | PASS | make pure_install installs the distribution into an isolated INSTALL_BASE prefix. |
| LD-24-06 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Public interface | PASS | A clean Perl process imports SSHFling, invokes version and run, and the installed executable is run directly. |
| LD-24-07 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Version contract | PASS | The module and installed command must report the exact release version. |
| LD-24-08 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | Runtime assets/workflow | PASS | The command runs init, checks native helpers, and prefix removal makes the module unimportable. |
