# SSHFling Language Deployment And Library Matrix

This generated matrix covers every entry in the first 91-language catalog with
an explicit package manager or distribution mechanism, deployment type, interface,
and artifact boundary. Maven and Gradle are separate JVM deployments, and real
importable library surfaces are named rather than inferred from language names.

Catalog outcomes: **58 PASS**, **17 BLOCKED**, and **16 NOT_APPLICABLE**. The catalog expands to **141 explicit surface cells** (108 PASS, 17 BLOCKED, 16 NOT_APPLICABLE).
Fully implemented runtime deployments retain **648 detailed PASS cells** across **81 surfaces**, including **66 validated library-capable surfaces**.

A source-archive publication PASS proves deterministic archive creation and inventory
only. It is deliberately separate from install, library-consumer, CLI, and runtime
validation. A language can therefore have a PASS publication cell and remain BLOCKED
overall when its toolchain/runtime cell is BLOCKED. Detailed eight-check rows appear
only for runtime deployments whose complete workflow passed.

TODO status audit: **0 row(s) differ** from current package evidence (none). The matrix status is evidence-derived; the TODO status is retained in its own column.

## First-91 Catalog Coverage

| Cell | Order | Language | Package manager / mechanism | Deployment type | Interface | Artifact | Surface | Matrix | TODO | Evidence or boundary |
| --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| C91-001-01 | 1 | Python | pip | wheel dependency | library + CLI | sshfling-VERSION-py3-none-any.whl | PASS | PASS | PASS | The package-python validator supplies the detailed PASS evidence below. |
| C91-001-02 | 1 | Python | pipx | isolated application | CLI | sshfling-VERSION-py3-none-any.whl | PASS | PASS | PASS | The package-python validator supplies the detailed PASS evidence below. |
| C91-002-01 | 2 | TypeScript | npm | typed dependency | library | sshfling-VERSION.tgz | PASS | PASS | PASS | The package-node validator supplies the detailed PASS evidence below. |
| C91-003-01 | 3 | JavaScript | npm | CommonJS dependency | library | sshfling-VERSION.tgz | PASS | PASS | PASS | The package-node validator supplies the detailed PASS evidence below. |
| C91-003-02 | 3 | JavaScript | npm | ES module dependency | library | sshfling-VERSION.tgz | PASS | PASS | PASS | The package-node validator supplies the detailed PASS evidence below. |
| C91-003-03 | 3 | JavaScript | npm | package executable | CLI | sshfling-VERSION.tgz | PASS | PASS | PASS | The package-node validator supplies the detailed PASS evidence below. |
| C91-004-01 | 4 | Java | Maven | Maven dependency | library + CLI | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-004-02 | 4 | Java | Gradle | Gradle dependency | library + CLI | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-004-03 | 4 | Java | JAR | direct executable | CLI | sshfling-cli-VERSION.jar | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-005-01 | 5 | C | CMake | shared-library dependency | library | sshfling-native-VERSION.tar.gz / libsshfling.so | PASS | PASS | PASS | The package-native-libraries validator supplies the detailed PASS evidence below. |
| C91-005-02 | 5 | C | CMake | static-library dependency | library | sshfling-native-VERSION.tar.gz / libsshfling.a | PASS | PASS | PASS | The package-native-libraries validator supplies the detailed PASS evidence below. |
| C91-005-03 | 5 | C | pkg-config | compiler dependency | library | sshfling-native-VERSION.tar.gz / sshfling.pc | PASS | PASS | PASS | The package-native-libraries validator supplies the detailed PASS evidence below. |
| C91-005-04 | 5 | C | CMake | installed native executable | CLI | sshfling-native-VERSION.tar.gz / sshfling-c | PASS | PASS | PASS | The package-native-libraries validator supplies the detailed PASS evidence below. |
| C91-006-01 | 6 | C++ | CMake | C++17 static-library dependency | library | sshfling-native-VERSION.tar.gz / sshfling.hpp | PASS | PASS | PASS | The package-native-libraries validator supplies the detailed PASS evidence below. |
| C91-007-01 | 7 | C#/.NET | NuGet | PackageReference library | library | SSHFling.VERSION.nupkg | PASS | PASS | PASS | The package-dotnet validator supplies the detailed PASS evidence below. |
| C91-007-02 | 7 | C#/.NET | .NET tool | global/tool-path command | CLI | SSHFling.Tool.VERSION.nupkg | PASS | PASS | PASS | The package-dotnet validator supplies the detailed PASS evidence below. |
| C91-008-01 | 8 | SQL | database-specific tooling | portable SQL deployment | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: standard SQL has no portable host-process API and SSHFling has no database protocol |
| C91-009-01 | 9 | Go | Go modules | module dependency and go install | library + CLI | sshfling-go-VERSION.zip | PASS | PASS | PASS | The package-go validator supplies the detailed PASS evidence below. |
| C91-010-01 | 10 | Rust | Cargo | crate dependency and cargo install | library + CLI | sshfling-cli-VERSION.crate | PASS | PASS | PASS | The package-rust validator supplies the detailed PASS evidence below. |
| C91-011-01 | 11 | PHP | Composer | Composer dependency | library + CLI | sshfling-php-VERSION.zip | PASS | PASS | PASS | The package-php validator supplies the detailed PASS evidence below. |
| C91-012-01 | 12 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | installed sshfling command and POSIX runtime scripts | PASS | PASS | PASS | The test target runs sh syntax checks and an isolated local-install lifecycle. |
| C91-013-01 | 13 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | versioned packaging and validation scripts | PASS | PASS | PASS | The test target applies bash -n and executes the Bash release validators. |
| C91-014-01 | 14 | PowerShell | PowerShell module archive | versioned module package | library + CLI | sshfling-powershell-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-015-01 | 15 | Kotlin | Maven | Kotlin/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-015-02 | 15 | Kotlin | Gradle | Kotlin/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-016-01 | 16 | Swift | SwiftPM | versioned source-archive publication | source package | sshfling-swift-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | A PASS source-archive row for swift, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-016-02 | 16 | Swift | SwiftPM | Swift package dependency and executable | library + CLI | sshfling-swift-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: the SwiftPM source archive is publishable, but swift and swiftc runtime validation is unavailable on the validation host |
| C91-017-01 | 17 | R | R CMD | R source package dependency | library | sshfling_VERSION.tar.gz | PASS | PASS | PASS | The per-language validator runs R CMD build, R CMD check, and R CMD INSTALL at VERSION=0.1.16. |
| C91-017-02 | 17 | R | R CMD | versioned source-archive publication | source package | sshfling-r-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for r are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-018-01 | 18 | Ruby | RubyGems | gem dependency and executable | library + CLI | sshfling-VERSION.gem | PASS | PASS | PASS | The package-ruby validator supplies the detailed PASS evidence below. |
| C91-018-02 | 18 | Ruby | Bundler | bundled application dependency | library + CLI | sshfling-VERSION.gem / source path | PASS | PASS | PASS | The package-ruby validator supplies the detailed PASS evidence below. |
| C91-019-01 | 19 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | sshfling-VERSION.tgz plus sshfling-dart-consumer executable | PASS | PASS | PASS | Dart SDK 3.12.2 completes npm run test:dart and the batch reports [PASS] dart. |
| C91-020-01 | 20 | Lua | source archive | Lua source module package | library + CLI | sshfling-lua-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-020-02 | 20 | Lua | LuaRocks | all-platform rock dependency | library + CLI | sshfling-VERSION-1.all.rock | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-021-01 | 21 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | sshfling-perl-VERSION.tar.gz | PASS | PASS | PASS | The package-perl validator supplies the detailed PASS evidence below. |
| C91-022-01 | 22 | Scala | Maven | Scala 3 JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-022-02 | 22 | Scala | Gradle | Scala 3 JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-023-01 | 23 | Visual Basic/.NET | NuGet | PackageReference library | library | SSHFling.VERSION.nupkg | PASS | PASS | PASS | The package-dotnet validator supplies the detailed PASS evidence below. |
| C91-024-01 | 24 | MATLAB | MATLAB package folder | ProcessBuilder launcher package | library | tracked +sshfling candidate; publication disabled | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: a licensed MATLAB runtime and configured JVM are required for conformance |
| C91-025-01 | 25 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | libsshfling_objc.so and sshfling-objective-c validation artifacts | PASS | PASS | PASS | The focused systems validator compiles warning-clean shared-library, CLI, and consumer binaries. |
| C91-025-02 | 25 | Objective-C | CMake/source build | versioned source-archive publication | source package | sshfling-objective-c-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for objective-c, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-026-01 | 26 | Groovy | Maven | Groovy/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-026-02 | 26 | Groovy | Gradle | Groovy/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-027-01 | 27 | Delphi/Object Pascal | Free Pascal units | Object Pascal unit and executable candidate | library + CLI | tracked Pascal units; publication disabled | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: Free Pascal validation cannot establish Delphi compiler compatibility or a supported dual-toolchain package |
| C91-028-01 | 28 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | sshfling-julia-VERSION.tar.gz | PASS | PASS | PASS | The per-language validator installs and precompiles the package, runs Pkg.test, and executes an external consumer at VERSION=0.1.16. |
| C91-028-02 | 28 | Julia | Julia Pkg | versioned source-archive publication | source package | sshfling-julia-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for julia are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-029-01 | 29 | HCL/Terraform | Terraform module | declarative infrastructure module | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: local-exec would be an unsafe shell-string side effect, not a typed launcher |
| C91-030-01 | 30 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | libsshfling_assembly.so and sshfling-assembly validation artifacts | PASS | PASS | PASS | The focused systems validator compiles PIC assembly, links a shared library and CLI, and extracts debug data. |
| C91-030-02 | 30 | Assembly | GNU/Clang toolchain | versioned source-archive publication | source package | sshfling-assembly-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for assembly, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-031-01 | 31 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | COBOL object module and sshfling-cobol validation command | PASS | PASS | PASS | The focused systems validator compiles the module and links the CLI with warnings treated as errors. |
| C91-031-02 | 31 | COBOL | GnuCOBOL | versioned source-archive publication | source package | sshfling-cobol-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for cobol, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-032-01 | 32 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Fortran module objects and sshfling-fortran validation command | PASS | PASS | PASS | The focused systems validator compiles Fortran 2018 sources with warnings treated as errors. |
| C91-032-02 | 32 | Fortran | fpm/source build | versioned source-archive publication | source package | sshfling-fortran-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for fortran, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-033-01 | 33 | SAS | SAS deployment tooling | XCMD external-command integration | CLI adapter candidate | none | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: a licensed, policy-approved XCMD-enabled SAS runtime and safe argument contract are unavailable |
| C91-034-01 | 34 | ABAP | SAP transport/SM69 | authorized external-command integration | CLI adapter candidate | none | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: a licensed SAP system, SM69 definition, authorization design, namespace, and transport validation are required |
| C91-035-01 | 35 | Apex | Salesforce package | managed-platform package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: Apex cannot start host processes; an HTTP relayer would be a separate privileged service |
| C91-036-01 | 36 | PL/SQL | Oracle package/scheduler | credentialed external-job integration | CLI adapter candidate | none | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: a licensed Oracle deployment, scheduler privileges, host credentials, and security review are required |
| C91-037-01 | 37 | T-SQL | SQL Server tooling | database extension | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: xp_cmdshell is a disabled-by-default service-account escape hatch and is rejected for new code |
| C91-038-01 | 38 | Elixir | Mix | Mix path dependency | library | versioned Mix package tree | PASS | PASS | PASS | The per-language validator compiles with warnings as errors and resolves an isolated path dependency. |
| C91-038-02 | 38 | Elixir | Mix | versioned source-archive publication | source package | sshfling-elixir-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for elixir are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-039-01 | 39 | Erlang | OTP/erlc | OTP application dependency | library | sshfling-VERSION OTP application tree | PASS | PASS | PASS | The per-language validator compiles package and consumer modules with erlc -Werror. |
| C91-039-02 | 39 | Erlang | OTP/rebar3 | versioned source-archive publication | source package | sshfling-erlang-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for erlang are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-040-01 | 40 | Haskell | Cabal | Cabal library and executable package | library + CLI | sshfling-VERSION Cabal package | PASS | PASS | PASS | The per-language validator performs an offline Cabal build and resolves both produced executables. |
| C91-040-02 | 40 | Haskell | Cabal | versioned source-archive publication | source package | sshfling-haskell-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for haskell are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-041-01 | 41 | Clojure | Maven | Clojure/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-041-02 | 41 | Clojure | Gradle | Clojure/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | PASS | PASS | PASS | The package-java validator supplies the detailed PASS evidence below. |
| C91-042-01 | 42 | F# | NuGet | PackageReference library | library | SSHFling.VERSION.nupkg | PASS | PASS | PASS | The package-dotnet validator supplies the detailed PASS evidence below. |
| C91-043-01 | 43 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | sshfling.VERSION source archive and Dune install | PASS | PASS | PASS | The per-language validator builds @install and installs it into an isolated Dune prefix. |
| C91-043-02 | 43 | OCaml | opam/Dune | versioned source-archive publication | source package | sshfling-ocaml-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for ocaml are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-044-01 | 44 | Zig | Zig build | Zig module and executable package | library + CLI | Zig prefix with sshfling-zig command | PASS | PASS | PASS | The focused systems validator runs zig build with isolated local and global caches. |
| C91-044-02 | 44 | Zig | Zig build | versioned source-archive publication | source package | sshfling-zig-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for zig, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-045-01 | 45 | Nim | Nimble | Nimble source package | library + CLI | sshfling Nimble package and sshfling-nim validation command | PASS | PASS | PASS | The focused systems validator runs nim check, nim c, and nimble check with isolated caches. |
| C91-045-02 | 45 | Nim | Nimble | versioned source-archive publication | source package | sshfling-nim-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for nim, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-046-01 | 46 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | sshfling shard and sshfling-crystal validation command | PASS | PASS | PASS | The focused systems validator parses the shard metadata and builds the CLI with isolated caches. |
| C91-046-02 | 46 | Crystal | Shards/Crystal | versioned source-archive publication | source package | sshfling-crystal-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for crystal, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-047-01 | 47 | D | Dub/source build | D module and static-library dependency | library + CLI | libsshfling_d.a and sshfling-d validation artifacts | PASS | PASS | PASS | The focused systems validator compiles warning-clean D objects, archives a static library, and links the CLI. |
| C91-047-02 | 47 | D | Dub/source build | versioned source-archive publication | source package | sshfling-d-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for d, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-048-01 | 48 | V | VPM | V module and executable package | library + CLI | sshfling-v-VERSION.tar.gz | PASS | PASS | PASS | The systems validator extracts the deterministic archive, compiles the package and clean consumer with V, and runs both. |
| C91-048-02 | 48 | V | VPM | versioned source-archive publication | source package | sshfling-v-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for v, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-049-01 | 49 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Ada units and sshfling-ada validation command | PASS | PASS | PASS | The focused systems validator uses GNAT 2022 checks with warnings promoted to errors. |
| C91-049-02 | 49 | Ada | Alire/GNAT | versioned source-archive publication | source package | sshfling-ada-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for ada, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-050-01 | 50 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | sshfling-VERSION ASDF source archive | PASS | PASS | PASS | The per-language validator compiles the ASDF system from an isolated source registry. |
| C91-050-02 | 50 | Common Lisp | ASDF/Quicklisp | versioned source-archive publication | source package | sshfling-common-lisp-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for common-lisp are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-051-01 | 51 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | sshfling-guile-VERSION.tar.gz | PASS | PASS | PASS | The per-language validator builds a dist archive, configures it, runs checks, and installs to an isolated prefix. |
| C91-051-02 | 51 | Scheme/Racket | GNU Guile/Autotools | versioned source-archive publication | source package | sshfling-scheme-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for scheme are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-052-01 | 52 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | sshfling-VERSION.tgz Prolog pack | PASS | PASS | PASS | The per-language validator archives and pack-installs the package into an isolated directory. |
| C91-052-02 | 52 | Prolog | SWI-Prolog pack | versioned source-archive publication | source package | sshfling-prolog-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for prolog are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-053-01 | 53 | Smalltalk | GNU Smalltalk package | versioned source-archive publication | source package | sshfling-smalltalk-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | PASS published-source-archive and published-source-inventory rows for smalltalk are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-053-02 | 53 | Smalltalk | GNU Smalltalk package | Smalltalk package dependency | library + CLI | sshfling-smalltalk-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: source publication passes, but gst and gst-package are unavailable for install and consumer validation |
| C91-054-01 | 54 | Tcl | Tcl package archive | versioned source package | library + CLI | sshfling-tcl-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-055-01 | 55 | AWK | source archive | mawk-compatible source package | library + CLI | sshfling-awk-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-056-01 | 56 | sed | source archive | sed command-file package | command file + CLI | sshfling-sed-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-057-01 | 57 | Zsh | source archive | sourceable shell module package | source module + CLI | sshfling-zsh-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-058-01 | 58 | Fish | source archive | sourceable shell module package | source module + CLI | sshfling-fish-VERSION.tar.gz | PASS | PASS | PASS | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| C91-059-01 | 59 | Nix | Nix flakes | flake package and app | CLI | nix build .#default result | PASS | PASS | PASS | Cross-OS CI builds the generated flake in a pinned Nix container and executes its result. |
| C91-060-01 | 60 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | sshfling-guix-scheme-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | The scripting batch builds the archive and CI requires a PASS Guile runtime row at VERSION=0.1.16. |
| C91-060-02 | 60 | Guix Scheme | source archive | versioned source-archive publication | source package | sshfling-guix-scheme-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | PASS package-archive is recorded for guix-scheme in dist/sshfling-scripting-languages-VERSION-validation.tsv. |
| C91-060-03 | 60 | Guix Scheme | Guix | Guix package definition | library + CLI package | sshfling-guix-scheme-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: the archive and Guile module pass, but the validation TSV records guix-definition SKIP because guix is unavailable |
| C91-061-01 | 61 | Solidity | Foundry/Hardhat | EVM contract package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: smart-contract bytecode cannot launch a host process |
| C91-062-01 | 62 | Vyper | Vyper/EVM tooling | EVM contract package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: smart-contract bytecode cannot launch a host process |
| C91-063-01 | 63 | Move | Move package | Move VM package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: Move modules cannot launch a host process |
| C91-064-01 | 64 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | sshfling-webassembly-wasi-VERSION.tar.gz | PASS | PASS | PASS | The systems validator extracts the archive, compiles wasm32-wasi code, and runs it through the tracked Node host adapter. |
| C91-064-02 | 64 | WebAssembly/WASI | WASI component/source | versioned source-archive publication | source package | sshfling-webassembly-wasi-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for webassembly-wasi, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-065-01 | 65 | Elm | npm | Node port dependency | library consumer | sshfling-VERSION.tgz | PASS | PASS | PASS | elm make compiles a Platform.worker and its Node host validates the complete port round trip. |
| C91-066-01 | 66 | PureScript | npm | Node FFI dependency | library consumer | sshfling-VERSION.tgz | PASS | PASS | PASS | The PureScript compiler validates the foreign imports and the generated module executes under Node. |
| C91-067-01 | 67 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | sshfling-VERSION.tgz | PASS | PASS | PASS | The ReScript compiler emits a CommonJS module and the Node test validates its exported status and templates. |
| C91-068-01 | 68 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Forth words, native bridge, and cli.fs | PASS | PASS | PASS | The focused systems validator builds the native bridge and loads the Forth API with Gforth. |
| C91-068-02 | 68 | Forth | Gforth/source package | versioned source-archive publication | source package | sshfling-forth-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for forth, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-069-01 | 69 | APL | Dyalog source package | versioned source-archive publication | source package | sshfling-apl-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | PASS published-source-archive and published-source-inventory rows for apl are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-069-02 | 69 | APL | Dyalog source package | Dyalog namespace package | library | sshfling-apl-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: source publication passes, but the Dyalog interpreter is unavailable for package and consumer validation |
| C91-070-01 | 70 | J | J package | J addon dependency and command | library + CLI | sshfling-j-VERSION.tar.gz | PASS | PASS | PASS | The per-language validator installs the deterministic archive as an isolated J addon and runs its external consumer. |
| C91-070-02 | 70 | J | J package | versioned source-archive publication | source package | sshfling-j-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for j are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-071-01 | 71 | LabVIEW G | VIPM/LabVIEW project | System Exec VI integration | library VI + CLI adapter candidate | none | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: a licensed LabVIEW version/OS matrix and genuine VI package are required; no binary G source is fabricated |
| C91-072-01 | 72 | Scratch | Scratch project | sandboxed visual project | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: a privileged extension host would be a separate service, not a Scratch launcher |
| C91-073-01 | 73 | Q/KDB+ | KX q package | versioned source-archive publication | source package | sshfling-q-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | PASS published-source-archive and published-source-inventory rows for q are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-073-02 | 73 | Q/KDB+ | KX q package | q namespace package | library | sshfling-q-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: source publication passes, but the q runtime is unavailable for package and consumer validation |
| C91-074-01 | 74 | Hack | Composer/HHVM | server-side Hack adapter project | CLI consumer | tracked Composer project; no published Hack artifact | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: the Node bridge passes independently, but HHVM has not compiled and executed the Hack consumer |
| C91-075-01 | 75 | CFML | CommandBox | server-side CFML adapter project | CLI consumer | tracked CommandBox project; no published CFML artifact | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: the Node bridge passes independently, but CommandBox has not executed the CFML consumer |
| C91-076-01 | 76 | Wolfram Language | Wolfram Paclet | RunProcess-based Paclet candidate | library | tracked Paclet source; publication disabled | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: a licensed Wolfram kernel exposed through wolframscript is required for conformance |
| C91-077-01 | 77 | Verilog | HDL simulator project | synthesizable hardware description | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: simulator system tasks are not deployable or synthesizable SSHFling libraries |
| C91-078-01 | 78 | VHDL | HDL simulator project | synthesizable hardware description | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: foreign/simulator interfaces do not form a synthesizable host launcher |
| C91-079-01 | 79 | SystemVerilog | HDL simulator project | synthesizable hardware description | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: DPI and system tasks are simulator mechanisms, not deployable SSHFling packages |
| C91-080-01 | 80 | CUDA | CUDA toolkit | device-code package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: device code cannot launch host processes; a host wrapper would duplicate the C++ surface |
| C91-081-01 | 81 | OpenCL C | OpenCL toolchain | kernel-source package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: OpenCL kernels cannot create host processes; a host wrapper would duplicate C/C++ |
| C91-082-01 | 82 | GLSL | shader toolchain | shader package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: shader stages have no host-process API |
| C91-083-01 | 83 | HLSL | shader toolchain | shader package | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: shader stages have no host-process API |
| C91-084-01 | 84 | WGSL | WebGPU shader tooling | shader module | no library or CLI surface | none | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE | NOT_APPLICABLE: WebGPU shader stages have no host-process API |
| C91-085-01 | 85 | Chapel | Mason | versioned source-archive publication | source package | sshfling-chapel-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | A PASS source-archive row for chapel, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-085-02 | 85 | Chapel | Mason | Chapel module and executable package | library + CLI | sshfling-chapel-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: source publication passes, but chpl is unavailable for package and runtime validation |
| C91-086-01 | 86 | Pony | Corral | Pony package and executable | library + CLI | sshfling-pony-VERSION.tar.gz | PASS | PASS | PASS | The systems validator extracts the deterministic archive, compiles with ponyc, and runs an isolated consumer. |
| C91-086-02 | 86 | Pony | Corral | versioned source-archive publication | source package | sshfling-pony-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for pony, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-087-01 | 87 | Janet | JPM | Janet module package and command | library + CLI | sshfling-janet-VERSION.tar.gz | PASS | PASS | PASS | The per-language validator installs from the deterministic archive into an isolated JPM tree and compiles the external consumer. |
| C91-087-02 | 87 | Janet | JPM | versioned source-archive publication | source package | sshfling-janet-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for janet are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-088-01 | 88 | Odin | Odin source package | Odin collection and executable | library + CLI | sshfling-odin-VERSION.tar.gz | PASS | PASS | PASS | The systems validator extracts the archive, builds the Odin collection and command, and executes an isolated consumer. |
| C91-088-02 | 88 | Odin | Odin source package | versioned source-archive publication | source package | sshfling-odin-VERSION.tar.gz | PASS | PASS | PASS | A PASS source-archive row for odin, including inventory digest and repeat-build identity, is recorded in dist/sshfling-systems-languages-VERSION-validation.tsv. |
| C91-089-01 | 89 | Ballerina | Ballerina package | versioned source-archive publication | source package | sshfling-ballerina-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | PASS published-source-archive and published-source-inventory rows for ballerina are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-089-02 | 89 | Ballerina | Ballerina package | Ballerina module dependency | library | sshfling-ballerina-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: source publication passes, but bal is unavailable for package test and consumer validation |
| C91-090-01 | 90 | Gleam | Gleam/Hex | Hex library package | library | sshfling-VERSION Hex tarball | PASS | PASS | PASS | The per-language validator runs gleam check, exports a Hex tarball, and builds an external consumer. |
| C91-090-02 | 90 | Gleam | Gleam/Hex | versioned source-archive publication | source package | sshfling-gleam-VERSION.tar.gz | PASS | PASS | PASS | PASS published-source-archive and published-source-inventory rows for gleam are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-091-01 | 91 | Roc | Roc source package | versioned source-archive publication | source package | sshfling-roc-VERSION.tar.gz | PASS | BLOCKED | BLOCKED | PASS published-source-archive and published-source-inventory rows for roc are recorded in dist/sshfling-functional-languages-VERSION-validation.tsv. |
| C91-091-02 | 91 | Roc | Roc source package | Roc package and application | library + CLI | sshfling-roc-VERSION.tar.gz | BLOCKED | BLOCKED | BLOCKED | BLOCKED runtime-validation: source publication passes, but the Roc toolchain is unavailable for package and consumer validation |

## Fully Validated Deployment Surfaces

These surfaces alone receive the detailed eight-check lifecycle grid.

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
| kotlin-maven-library | Kotlin | Maven | Kotlin/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| scala-maven-library | Scala | Maven | Scala 3 JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| groovy-maven-library | Groovy | Maven | Groovy/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| kotlin-gradle-library | Kotlin | Gradle | Kotlin/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| scala-gradle-library | Scala | Gradle | Scala 3 JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| groovy-gradle-library | Groovy | Gradle | Groovy/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| clojure-maven-library | Clojure | Maven | Clojure/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| clojure-gradle-library | Clojure | Gradle | Clojure/JVM dependency | library | io.sshfling:sshfling-cli:VERSION | `package-java` |
| react-npm-consumer | React/JSX | npm | server-rendered JSX dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| vue-npm-consumer | Vue | npm | server-rendered component dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| svelte-npm-consumer | Svelte | npm | server-compiled component dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| angular-npm-consumer | Angular | npm | typed server-rendered dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| elm-npm-consumer | Elm | npm | Node port dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| purescript-npm-consumer | PureScript | npm | Node FFI dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| rescript-npm-consumer | Reason/ReScript | npm | CommonJS binding dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| html-css-npm-consumer | HTML/CSS | npm | trusted static-build dependency | library consumer | sshfling-VERSION.tgz | `package-web-language-consumers` |
| tcl-package-library | Tcl | Tcl package archive | versioned source package | library + CLI | sshfling-tcl-VERSION.tar.gz | `package-scripting-languages` |
| awk-source-library | AWK | source archive | mawk-compatible source package | library + CLI | sshfling-awk-VERSION.tar.gz | `package-scripting-languages` |
| sed-command-package | sed | source archive | sed command-file package | command file + CLI | sshfling-sed-VERSION.tar.gz | `package-scripting-languages` |
| lua-source-library | Lua | source archive | Lua source module package | library + CLI | sshfling-lua-VERSION.tar.gz | `package-scripting-languages` |
| lua-luarocks-library | Lua | LuaRocks | all-platform rock dependency | library + CLI | sshfling-VERSION-1.all.rock | `package-scripting-languages` |
| zsh-source-module | Zsh | source archive | sourceable shell module package | source module + CLI | sshfling-zsh-VERSION.tar.gz | `package-scripting-languages` |
| fish-source-module | Fish | source archive | sourceable shell module package | source module + CLI | sshfling-fish-VERSION.tar.gz | `package-scripting-languages` |
| elvish-source-module | Elvish | source archive | importable shell module package | source module + CLI | sshfling-elvish-VERSION.tar.gz | `package-scripting-languages` |
| nushell-source-module | Nushell | source archive | importable shell module package | source module + CLI | sshfling-nushell-VERSION.tar.gz | `package-scripting-languages` |
| powershell-module-package | PowerShell | PowerShell module archive | versioned module package | library + CLI | sshfling-powershell-VERSION.tar.gz | `package-scripting-languages` |
| posix-shell-runtime-cli | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | installed sshfling command and POSIX runtime scripts | `test` |
| bash-maintainer-cli | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | versioned packaging and validation scripts | `test` |
| r-source-package | R | R CMD | R source package dependency | library | sshfling_VERSION.tar.gz | `package-functional-languages` |
| objective-c-cmake-package | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | libsshfling_objc.so and sshfling-objective-c validation artifacts | `package-systems-languages` |
| assembly-source-package | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | libsshfling_assembly.so and sshfling-assembly validation artifacts | `package-systems-languages` |
| cobol-source-package | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | COBOL object module and sshfling-cobol validation command | `package-systems-languages` |
| fortran-fpm-package | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Fortran module objects and sshfling-fortran validation command | `package-systems-languages` |
| elixir-mix-library | Elixir | Mix | Mix path dependency | library | versioned Mix package tree | `package-functional-languages` |
| erlang-otp-library | Erlang | OTP/erlc | OTP application dependency | library | sshfling-VERSION OTP application tree | `package-functional-languages` |
| haskell-cabal-library | Haskell | Cabal | Cabal library and executable package | library + CLI | sshfling-VERSION Cabal package | `package-functional-languages` |
| ocaml-opam-dune-library | OCaml | opam/Dune | Dune-installed opam package | library + CLI | sshfling.VERSION source archive and Dune install | `package-functional-languages` |
| zig-build-package | Zig | Zig build | Zig module and executable package | library + CLI | Zig prefix with sshfling-zig command | `package-systems-languages` |
| nim-nimble-package | Nim | Nimble | Nimble source package | library + CLI | sshfling Nimble package and sshfling-nim validation command | `package-systems-languages` |
| crystal-shard-package | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | sshfling shard and sshfling-crystal validation command | `package-systems-languages` |
| d-dub-package | D | Dub/source build | D module and static-library dependency | library + CLI | libsshfling_d.a and sshfling-d validation artifacts | `package-systems-languages` |
| ada-alire-package | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Ada units and sshfling-ada validation command | `package-systems-languages` |
| common-lisp-asdf-library | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | sshfling-VERSION ASDF source archive | `package-functional-languages` |
| scheme-guile-library | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | sshfling-guile-VERSION.tar.gz | `package-functional-languages` |
| prolog-swi-pack | Prolog | SWI-Prolog pack | Prolog pack dependency | library | sshfling-VERSION.tgz Prolog pack | `package-functional-languages` |
| forth-source-library | Forth | Gforth/source package | loadable Forth source package | library + CLI | Forth words, native bridge, and cli.fs | `package-systems-languages` |
| gleam-hex-library | Gleam | Gleam/Hex | Hex library package | library | sshfling-VERSION Hex tarball | `package-functional-languages` |
| nix-flake-cli | Nix | Nix flakes | flake package and app | CLI | nix build .#default result | `test` |
| guix-scheme-guile-library | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | sshfling-guix-scheme-VERSION.tar.gz | `package-scripting-languages` |
| julia-pkg-library | Julia | Julia Pkg | Julia package dependency and command | library + CLI | sshfling-julia-VERSION.tar.gz | `package-functional-languages` |
| janet-jpm-library | Janet | JPM | Janet module package and command | library + CLI | sshfling-janet-VERSION.tar.gz | `package-functional-languages` |
| j-addon-library | J | J package | J addon dependency and command | library + CLI | sshfling-j-VERSION.tar.gz | `package-functional-languages` |
| v-vpm-library | V | VPM | V module and executable package | library + CLI | sshfling-v-VERSION.tar.gz | `package-systems-languages` |
| wasi-node-host-command | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | sshfling-webassembly-wasi-VERSION.tar.gz | `package-systems-languages` |
| odin-source-library | Odin | Odin source package | Odin collection and executable | library + CLI | sshfling-odin-VERSION.tar.gz | `package-systems-languages` |
| pony-corral-library | Pony | Corral | Pony package and executable | library + CLI | sshfling-pony-VERSION.tar.gz | `package-systems-languages` |
| dart-native-cli-consumer | Dart | pub + npm | compiled server-side adapter | native CLI consumer | sshfling-VERSION.tgz plus sshfling-dart-consumer executable | `package-web-language-consumers` |

## Detailed Eight-Check Verification Cells

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
| LD-25-01 | Kotlin | Maven | Kotlin/JVM dependency | library | Source surface | PASS | A Kotlin source consumer and standalone Maven project are tracked under packaging/java/consumers/kotlin. |
| LD-25-02 | Kotlin | Maven | Kotlin/JVM dependency | library | Package metadata | PASS | The POM pins Kotlin 2.4, JVM target 11, Maven execution metadata, and the SSHFling release coordinate. |
| LD-25-03 | Kotlin | Maven | Kotlin/JVM dependency | library | Package build | PASS | packaging/build-java.sh compiles the clean Kotlin project from the isolated Maven repository. |
| LD-25-04 | Kotlin | Maven | Kotlin/JVM dependency | library | Artifact contents | PASS | Validation requires the compiled KotlinConsumer.class before executing the application. |
| LD-25-05 | Kotlin | Maven | Kotlin/JVM dependency | library | Isolated consumer | PASS | The clean project resolves SSHFling and Kotlin dependencies through its generated Maven repository. |
| LD-25-06 | Kotlin | Maven | Kotlin/JVM dependency | library | Public interface | PASS | KotlinConsumer passes its argument array to the public Java SSHFling.run API. |
| LD-25-07 | Kotlin | Maven | Kotlin/JVM dependency | library | Version contract | PASS | The Kotlin API consumer must print the exact SSHFling release version. |
| LD-25-08 | Kotlin | Maven | Kotlin/JVM dependency | library | Runtime assets/workflow | PASS | The Kotlin consumer runs init and verifies both generated native identity helpers. |
| LD-26-01 | Scala | Maven | Scala 3 JVM dependency | library | Source surface | PASS | A Scala 3 source consumer and standalone Maven project are tracked under packaging/java/consumers/scala. |
| LD-26-02 | Scala | Maven | Scala 3 JVM dependency | library | Package metadata | PASS | The POM pins Scala 3.3 LTS, the Scala Maven plugin, Java release 11, and the SSHFling coordinate. |
| LD-26-03 | Scala | Maven | Scala 3 JVM dependency | library | Package build | PASS | packaging/build-java.sh compiles the clean Scala project from the isolated Maven repository. |
| LD-26-04 | Scala | Maven | Scala 3 JVM dependency | library | Artifact contents | PASS | Validation requires the compiled ScalaConsumer.class before executing the application. |
| LD-26-05 | Scala | Maven | Scala 3 JVM dependency | library | Isolated consumer | PASS | The clean project resolves SSHFling and Scala dependencies through its generated Maven repository. |
| LD-26-06 | Scala | Maven | Scala 3 JVM dependency | library | Public interface | PASS | ScalaConsumer passes its argument array to the public Java SSHFling.run API. |
| LD-26-07 | Scala | Maven | Scala 3 JVM dependency | library | Version contract | PASS | The Scala API consumer must print the exact SSHFling release version. |
| LD-26-08 | Scala | Maven | Scala 3 JVM dependency | library | Runtime assets/workflow | PASS | The Scala consumer runs init and verifies both generated native identity helpers. |
| LD-27-01 | Groovy | Maven | Groovy/JVM dependency | library | Source surface | PASS | A Groovy source consumer and standalone Maven project are tracked under packaging/java/consumers/groovy. |
| LD-27-02 | Groovy | Maven | Groovy/JVM dependency | library | Package metadata | PASS | The POM pins Groovy 5, GMavenPlus, Java bytecode 11, and the SSHFling release coordinate. |
| LD-27-03 | Groovy | Maven | Groovy/JVM dependency | library | Package build | PASS | packaging/build-java.sh compiles the clean Groovy project from the isolated Maven repository. |
| LD-27-04 | Groovy | Maven | Groovy/JVM dependency | library | Artifact contents | PASS | Validation requires the compiled GroovyConsumer.class before executing the application. |
| LD-27-05 | Groovy | Maven | Groovy/JVM dependency | library | Isolated consumer | PASS | The clean project resolves SSHFling and Groovy dependencies through its generated Maven repository. |
| LD-27-06 | Groovy | Maven | Groovy/JVM dependency | library | Public interface | PASS | GroovyConsumer passes its argument array to the public Java SSHFling.run API. |
| LD-27-07 | Groovy | Maven | Groovy/JVM dependency | library | Version contract | PASS | The Groovy API consumer must print the exact SSHFling release version. |
| LD-27-08 | Groovy | Maven | Groovy/JVM dependency | library | Runtime assets/workflow | PASS | The Groovy consumer runs init and verifies both generated native identity helpers. |
| LD-28-01 | Kotlin | Gradle | Kotlin/JVM dependency | library | Source surface | PASS | A Kotlin source consumer and standalone Gradle project are tracked under packaging/java/consumers/kotlin-gradle. |
| LD-28-02 | Kotlin | Gradle | Kotlin/JVM dependency | library | Package metadata | PASS | The build pins the Kotlin JVM plugin, JVM target 11, repositories, and the SSHFling release coordinate. |
| LD-28-03 | Kotlin | Gradle | Kotlin/JVM dependency | library | Package build | PASS | packaging/build-java.sh compiles the clean Kotlin Gradle project against the isolated Maven publication. |
| LD-28-04 | Kotlin | Gradle | Kotlin/JVM dependency | library | Artifact contents | PASS | Validation requires a nonempty KotlinGradleConsumer.class with Java class-file major version 55. |
| LD-28-05 | Kotlin | Gradle | Kotlin/JVM dependency | library | Isolated consumer | PASS | The project resolves SSHFling from the generated repository while Gradle resolves the pinned Kotlin toolchain. |
| LD-28-06 | Kotlin | Gradle | Kotlin/JVM dependency | library | Public interface | PASS | KotlinGradleConsumer passes its argument array to the public Java SSHFling.run API. |
| LD-28-07 | Kotlin | Gradle | Kotlin/JVM dependency | library | Version contract | PASS | The Kotlin Gradle API consumer must print the exact SSHFling release version. |
| LD-28-08 | Kotlin | Gradle | Kotlin/JVM dependency | library | Runtime assets/workflow | PASS | The Kotlin Gradle consumer runs init and verifies both generated native identity helpers. |
| LD-29-01 | Scala | Gradle | Scala 3 JVM dependency | library | Source surface | PASS | A Scala 3 source consumer and standalone Gradle project are tracked under packaging/java/consumers/scala-gradle. |
| LD-29-02 | Scala | Gradle | Scala 3 JVM dependency | library | Package metadata | PASS | The build pins Scala 3.3, Java release 11 compiler options, repositories, and the SSHFling coordinate. |
| LD-29-03 | Scala | Gradle | Scala 3 JVM dependency | library | Package build | PASS | packaging/build-java.sh compiles the clean Scala Gradle project against the isolated Maven publication. |
| LD-29-04 | Scala | Gradle | Scala 3 JVM dependency | library | Artifact contents | PASS | Validation requires a nonempty ScalaGradleConsumer.class with Java class-file major version 55. |
| LD-29-05 | Scala | Gradle | Scala 3 JVM dependency | library | Isolated consumer | PASS | The project resolves SSHFling from the generated repository while Gradle resolves the pinned Scala compiler. |
| LD-29-06 | Scala | Gradle | Scala 3 JVM dependency | library | Public interface | PASS | ScalaGradleConsumer passes its argument array to the public Java SSHFling.run API. |
| LD-29-07 | Scala | Gradle | Scala 3 JVM dependency | library | Version contract | PASS | The Scala Gradle API consumer must print the exact SSHFling release version. |
| LD-29-08 | Scala | Gradle | Scala 3 JVM dependency | library | Runtime assets/workflow | PASS | The Scala Gradle consumer runs init and verifies both generated native identity helpers. |
| LD-30-01 | Groovy | Gradle | Groovy/JVM dependency | library | Source surface | PASS | A Groovy source consumer and standalone Gradle project are tracked under packaging/java/consumers/groovy-gradle. |
| LD-30-02 | Groovy | Gradle | Groovy/JVM dependency | library | Package metadata | PASS | The build pins Groovy 5, Java bytecode 11 compiler options, repositories, and the SSHFling coordinate. |
| LD-30-03 | Groovy | Gradle | Groovy/JVM dependency | library | Package build | PASS | packaging/build-java.sh compiles the clean Groovy Gradle project against the isolated Maven publication. |
| LD-30-04 | Groovy | Gradle | Groovy/JVM dependency | library | Artifact contents | PASS | Validation requires a nonempty GroovyGradleConsumer.class with Java class-file major version 55. |
| LD-30-05 | Groovy | Gradle | Groovy/JVM dependency | library | Isolated consumer | PASS | The project resolves SSHFling from the generated repository while Gradle resolves the pinned Groovy compiler. |
| LD-30-06 | Groovy | Gradle | Groovy/JVM dependency | library | Public interface | PASS | GroovyGradleConsumer passes its argument array to the public Java SSHFling.run API. |
| LD-30-07 | Groovy | Gradle | Groovy/JVM dependency | library | Version contract | PASS | The Groovy Gradle API consumer must print the exact SSHFling release version. |
| LD-30-08 | Groovy | Gradle | Groovy/JVM dependency | library | Runtime assets/workflow | PASS | The Groovy Gradle consumer runs init and verifies both generated native identity helpers. |
| LD-31-01 | Clojure | Maven | Clojure/JVM dependency | library | Source surface | PASS | A Clojure namespace and standalone Maven consumer are tracked under packaging/java/consumers/clojure. |
| LD-31-02 | Clojure | Maven | Clojure/JVM dependency | library | Package metadata | PASS | The POM pins Clojure 1.12, Java release 11, Maven plugins, and the SSHFling coordinate. |
| LD-31-03 | Clojure | Maven | Clojure/JVM dependency | library | Package build | PASS | packaging/build-java.sh runs Maven verify from a clean copied Clojure project. |
| LD-31-04 | Clojure | Maven | Clojure/JVM dependency | library | Artifact contents | PASS | Maven verification requires the Clojure namespace in the packaged consumer JAR. |
| LD-31-05 | Clojure | Maven | Clojure/JVM dependency | library | Isolated consumer | PASS | The consumer resolves SSHFling and Clojure through an isolated Maven repository. |
| LD-31-06 | Clojure | Maven | Clojure/JVM dependency | library | Public interface | PASS | The namespace converts its argument sequence to String[] and invokes SSHFling.run. |
| LD-31-07 | Clojure | Maven | Clojure/JVM dependency | library | Version contract | PASS | The Clojure Maven consumer must print the exact SSHFling release version. |
| LD-31-08 | Clojure | Maven | Clojure/JVM dependency | library | Runtime assets/workflow | PASS | The Clojure Maven consumer runs init and verifies generated native identity helpers. |
| LD-32-01 | Clojure | Gradle | Clojure/JVM dependency | library | Source surface | PASS | A Clojure namespace and standalone Gradle consumer are tracked under packaging/java/consumers/clojure-gradle. |
| LD-32-02 | Clojure | Gradle | Clojure/JVM dependency | library | Package metadata | PASS | The build pins Clojure 1.12, Java 11 compatibility, repositories, and the SSHFling coordinate. |
| LD-32-03 | Clojure | Gradle | Clojure/JVM dependency | library | Package build | PASS | packaging/build-java.sh runs the Gradle check task from a clean copied Clojure project. |
| LD-32-04 | Clojure | Gradle | Clojure/JVM dependency | library | Artifact contents | PASS | Gradle verification requires the Clojure namespace in the packaged consumer JAR and resources output. |
| LD-32-05 | Clojure | Gradle | Clojure/JVM dependency | library | Isolated consumer | PASS | The consumer resolves SSHFling only from the generated repository and Clojure from Maven Central. |
| LD-32-06 | Clojure | Gradle | Clojure/JVM dependency | library | Public interface | PASS | The namespace converts its argument sequence to String[] and invokes SSHFling.run. |
| LD-32-07 | Clojure | Gradle | Clojure/JVM dependency | library | Version contract | PASS | The Clojure Gradle consumer must print the exact SSHFling release version. |
| LD-32-08 | Clojure | Gradle | Clojure/JVM dependency | library | Runtime assets/workflow | PASS | The Clojure Gradle consumer runs init and verifies generated native identity helpers. |
| LD-33-01 | React/JSX | npm | server-rendered JSX dependency | library consumer | Source surface | PASS | A clean React/JSX consumer is tracked under packaging/node/consumers/react. |
| LD-33-02 | React/JSX | npm | server-rendered JSX dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-33-03 | React/JSX | npm | server-rendered JSX dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-33-04 | React/JSX | npm | server-rendered JSX dependency | library consumer | Artifact contents | PASS | esbuild compiles the JSX module and React renders it to static markup without browser scripts. |
| LD-33-05 | React/JSX | npm | server-rendered JSX dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-33-06 | React/JSX | npm | server-rendered JSX dependency | library consumer | Public interface | PASS | The server component invokes sshfling.run and templateDir during Node-side rendering. |
| LD-33-07 | React/JSX | npm | server-rendered JSX dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-33-08 | React/JSX | npm | server-rendered JSX dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-34-01 | Vue | npm | server-rendered component dependency | library consumer | Source surface | PASS | A clean Vue consumer is tracked under packaging/node/consumers/vue. |
| LD-34-02 | Vue | npm | server-rendered component dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-34-03 | Vue | npm | server-rendered component dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-34-04 | Vue | npm | server-rendered component dependency | library consumer | Artifact contents | PASS | Vue's server renderer produces markup whose assertions prove the SSHFling package check completed. |
| LD-34-05 | Vue | npm | server-rendered component dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-34-06 | Vue | npm | server-rendered component dependency | library consumer | Public interface | PASS | The Vue setup function invokes sshfling.run and templateDir exclusively in the Node renderer. |
| LD-34-07 | Vue | npm | server-rendered component dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-34-08 | Vue | npm | server-rendered component dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-35-01 | Svelte | npm | server-compiled component dependency | library consumer | Source surface | PASS | A clean Svelte consumer is tracked under packaging/node/consumers/svelte. |
| LD-35-02 | Svelte | npm | server-compiled component dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-35-03 | Svelte | npm | server-compiled component dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-35-04 | Svelte | npm | server-compiled component dependency | library consumer | Artifact contents | PASS | The Svelte compiler emits a server target and the server renderer validates its generated markup. |
| LD-35-05 | Svelte | npm | server-compiled component dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-35-06 | Svelte | npm | server-compiled component dependency | library consumer | Public interface | PASS | The Svelte server module invokes sshfling.run and templateDir without exposing process access to a browser. |
| LD-35-07 | Svelte | npm | server-compiled component dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-35-08 | Svelte | npm | server-compiled component dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-36-01 | Angular | npm | typed server-rendered dependency | library consumer | Source surface | PASS | A clean Angular consumer is tracked under packaging/node/consumers/angular. |
| LD-36-02 | Angular | npm | typed server-rendered dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-36-03 | Angular | npm | typed server-rendered dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-36-04 | Angular | npm | typed server-rendered dependency | library consumer | Artifact contents | PASS | Strict TypeScript compilation and Angular renderApplication produce and validate server-rendered markup. |
| LD-36-05 | Angular | npm | typed server-rendered dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-36-06 | Angular | npm | typed server-rendered dependency | library consumer | Public interface | PASS | The standalone Angular server component invokes sshfling.run and templateDir under Node. |
| LD-36-07 | Angular | npm | typed server-rendered dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-36-08 | Angular | npm | typed server-rendered dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-37-01 | Elm | npm | Node port dependency | library consumer | Source surface | PASS | A clean Elm consumer is tracked under packaging/node/consumers/elm. |
| LD-37-02 | Elm | npm | Node port dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-37-03 | Elm | npm | Node port dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-37-04 | Elm | npm | Node port dependency | library consumer | Artifact contents | PASS | elm make compiles a Platform.worker and its Node host validates the complete port round trip. |
| LD-37-05 | Elm | npm | Node port dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-37-06 | Elm | npm | Node port dependency | library consumer | Public interface | PASS | The Elm worker sends typed arguments over ports to a Node host that invokes the SSHFling library. |
| LD-37-07 | Elm | npm | Node port dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-37-08 | Elm | npm | Node port dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-38-01 | PureScript | npm | Node FFI dependency | library consumer | Source surface | PASS | A clean PureScript consumer is tracked under packaging/node/consumers/purescript. |
| LD-38-02 | PureScript | npm | Node FFI dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-38-03 | PureScript | npm | Node FFI dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-38-04 | PureScript | npm | Node FFI dependency | library consumer | Artifact contents | PASS | The PureScript compiler validates the foreign imports and the generated module executes under Node. |
| LD-38-05 | PureScript | npm | Node FFI dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-38-06 | PureScript | npm | Node FFI dependency | library consumer | Public interface | PASS | The foreign module invokes sshfling.run and templateDir, exposing typed values to PureScript. |
| LD-38-07 | PureScript | npm | Node FFI dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-38-08 | PureScript | npm | Node FFI dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-39-01 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Source surface | PASS | A clean Reason/ReScript consumer is tracked under packaging/node/consumers/rescript. |
| LD-39-02 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-39-03 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-39-04 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Artifact contents | PASS | The ReScript compiler emits a CommonJS module and the Node test validates its exported status and templates. |
| LD-39-05 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-39-06 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Public interface | PASS | Typed @module bindings call the SSHFling run and templateDir exports from ReScript. |
| LD-39-07 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-39-08 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-40-01 | HTML/CSS | npm | trusted static-build dependency | library consumer | Source surface | PASS | A clean HTML/CSS consumer is tracked under packaging/node/consumers/html-css. |
| LD-40-02 | HTML/CSS | npm | trusted static-build dependency | library consumer | Package metadata | PASS | Its package manifest pins the language/framework compiler dependencies and receives the packed SSHFling dependency. |
| LD-40-03 | HTML/CSS | npm | trusted static-build dependency | library consumer | Package build | PASS | packaging/build-web-language-consumers.sh installs the clean consumer and runs its build and test commands. |
| LD-40-04 | HTML/CSS | npm | trusted static-build dependency | library consumer | Artifact contents | PASS | A trusted Node build validates SSHFling before emitting script-free HTML and CSS output. |
| LD-40-05 | HTML/CSS | npm | trusted static-build dependency | library consumer | Isolated consumer | PASS | The batch validator copies the consumer into a temporary directory and installs only from the packed SSHFling artifact. |
| LD-40-06 | HTML/CSS | npm | trusted static-build dependency | library consumer | Public interface | PASS | The build process invokes the SSHFling library; the generated static page explicitly has no process capability. |
| LD-40-07 | HTML/CSS | npm | trusted static-build dependency | library consumer | Version contract | PASS | The consumer invokes the packed library with --version and requires a successful SSHFling status contract. |
| LD-40-08 | HTML/CSS | npm | trusted static-build dependency | library consumer | Runtime assets/workflow | PASS | The consumer checks the bundled template directory while keeping SSH execution in the trusted Node process. |
| LD-41-01 | Tcl | Tcl package archive | versioned source package | library + CLI | Source surface | PASS | The Tcl package source is tracked under packaging/tcl. |
| LD-41-02 | Tcl | Tcl package archive | versioned source package | library + CLI | Package metadata | PASS | package-metadata.json and pkgIndex.tcl declare the versioned Tcl package and runtime entry point. |
| LD-41-03 | Tcl | Tcl package archive | versioned source package | library + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-41-04 | Tcl | Tcl package archive | versioned source package | library + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-41-05 | Tcl | Tcl package archive | versioned source package | library + CLI | Isolated consumer | PASS | A clean TCLLIBPATH consumer resolves package require -exact before the archive is removed. |
| LD-41-06 | Tcl | Tcl package archive | versioned source package | library + CLI | Public interface | PASS | The Tcl namespace exposes version, runtime/template paths, and a run procedure that invokes the bundled runtime. |
| LD-41-07 | Tcl | Tcl package archive | versioned source package | library + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-41-08 | Tcl | Tcl package archive | versioned source package | library + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-42-01 | AWK | source archive | mawk-compatible source package | library + CLI | Source surface | PASS | The AWK package source is tracked under packaging/awk. |
| LD-42-02 | AWK | source archive | mawk-compatible source package | library + CLI | Package metadata | PASS | package-metadata.json declares the AWK source API, CLI contract, runtime, and templates. |
| LD-42-03 | AWK | source archive | mawk-compatible source package | library + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-42-04 | AWK | source archive | mawk-compatible source package | library + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-42-05 | AWK | source archive | mawk-compatible source package | library + CLI | Isolated consumer | PASS | A clean mawk-compatible probe loads sshfling.awk and invokes its public functions. |
| LD-42-06 | AWK | source archive | mawk-compatible source package | library + CLI | Public interface | PASS | The source API exposes version, runtime/template paths, and argument-safe execution of the bundled runtime. |
| LD-42-07 | AWK | source archive | mawk-compatible source package | library + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-42-08 | AWK | source archive | mawk-compatible source package | library + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-43-01 | sed | source archive | sed command-file package | command file + CLI | Source surface | PASS | The sed package source is tracked under packaging/sed. |
| LD-43-02 | sed | source archive | sed command-file package | command file + CLI | Package metadata | PASS | package-metadata.json declares the sed command-file input and output contract. |
| LD-43-03 | sed | source archive | sed command-file package | command file + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-43-04 | sed | source archive | sed command-file package | command file + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-43-05 | sed | source archive | sed command-file package | command file + CLI | Isolated consumer | PASS | An isolated sed process loads the packaged command file against real and malformed CLI output. |
| LD-43-06 | sed | source archive | sed command-file package | command file + CLI | Public interface | PASS | The command file extracts the exact semantic version only from canonical SSHFling version output. |
| LD-43-07 | sed | source archive | sed command-file package | command file + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-43-08 | sed | source archive | sed command-file package | command file + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-44-01 | Lua | source archive | Lua source module package | library + CLI | Source surface | PASS | The Lua package source is tracked under packaging/lua. |
| LD-44-02 | Lua | source archive | Lua source module package | library + CLI | Package metadata | PASS | package-metadata.json and the rockspec declare Lua 5.1+ compatibility, module files, and CLI installation. |
| LD-44-03 | Lua | source archive | Lua source module package | library + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-44-04 | Lua | source archive | Lua source module package | library + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the source archive and its bundled runtime assets. |
| LD-44-05 | Lua | source archive | Lua source module package | library + CLI | Isolated consumer | PASS | Clean Lua 5.1 and Lua 5.4 paths require the module directly from the extracted archive. |
| LD-44-06 | Lua | source archive | Lua source module package | library + CLI | Public interface | PASS | The Lua module exposes version, runtime/template paths, and an argv-preserving run function. |
| LD-44-07 | Lua | source archive | Lua source module package | library + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-44-08 | Lua | source archive | Lua source module package | library + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-45-01 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Source surface | PASS | The Lua package source is tracked under packaging/lua. |
| LD-45-02 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Package metadata | PASS | The rockspec declares the Lua dependency, importable sshfling module, and installed CLI. |
| LD-45-03 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-45-04 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Artifact contents | PASS | LuaRocks packs a nonempty .all.rock after installing and executing the package in an isolated tree. |
| LD-45-05 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Isolated consumer | PASS | A clean LuaRocks tree imports sshfling, invokes its API and CLI, then removes both module and executable. |
| LD-45-06 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Public interface | PASS | The installed Lua module exposes version and run APIs while the rock installs the matching sshfling command. |
| LD-45-07 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-45-08 | Lua | LuaRocks | all-platform rock dependency | library + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-46-01 | Zsh | source archive | sourceable shell module package | source module + CLI | Source surface | PASS | The Zsh package source is tracked under packaging/shell-languages/zsh. |
| LD-46-02 | Zsh | source archive | sourceable shell module package | source module + CLI | Package metadata | PASS | package-metadata.json declares the source module functions, CLI, runtime, and templates. |
| LD-46-03 | Zsh | source archive | sourceable shell module package | source module + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-46-04 | Zsh | source archive | sourceable shell module package | source module + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-46-05 | Zsh | source archive | sourceable shell module package | source module + CLI | Isolated consumer | PASS | A clean Zsh process sources the installed module and completes the version and init workflows. |
| LD-46-06 | Zsh | source archive | sourceable shell module package | source module + CLI | Public interface | PASS | The module exposes version, runtime/template paths, and an argv-preserving sshfling_run function. |
| LD-46-07 | Zsh | source archive | sourceable shell module package | source module + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-46-08 | Zsh | source archive | sourceable shell module package | source module + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-47-01 | Fish | source archive | sourceable shell module package | source module + CLI | Source surface | PASS | The Fish package source is tracked under packaging/shell-languages/fish. |
| LD-47-02 | Fish | source archive | sourceable shell module package | source module + CLI | Package metadata | PASS | package-metadata.json declares the source module functions, CLI, runtime, and templates. |
| LD-47-03 | Fish | source archive | sourceable shell module package | source module + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-47-04 | Fish | source archive | sourceable shell module package | source module + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-47-05 | Fish | source archive | sourceable shell module package | source module + CLI | Isolated consumer | PASS | A clean Fish process sources the installed module and completes the version and init workflows. |
| LD-47-06 | Fish | source archive | sourceable shell module package | source module + CLI | Public interface | PASS | The module exposes version, runtime/template paths, and an argv-preserving sshfling_run function. |
| LD-47-07 | Fish | source archive | sourceable shell module package | source module + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-47-08 | Fish | source archive | sourceable shell module package | source module + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-48-01 | Elvish | source archive | importable shell module package | source module + CLI | Source surface | PASS | The Elvish package source is tracked under packaging/shell-languages/elvish. |
| LD-48-02 | Elvish | source archive | importable shell module package | source module + CLI | Package metadata | PASS | package-metadata.json declares the importable module functions, CLI, runtime, and templates. |
| LD-48-03 | Elvish | source archive | importable shell module package | source module + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-48-04 | Elvish | source archive | importable shell module package | source module + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-48-05 | Elvish | source archive | importable shell module package | source module + CLI | Isolated consumer | PASS | A clean Elvish 0.21 process imports the installed module and completes the version and init workflows. |
| LD-48-06 | Elvish | source archive | importable shell module package | source module + CLI | Public interface | PASS | The module exposes version, runtime/template paths, and an argv-preserving run function. |
| LD-48-07 | Elvish | source archive | importable shell module package | source module + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-48-08 | Elvish | source archive | importable shell module package | source module + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-49-01 | Nushell | source archive | importable shell module package | source module + CLI | Source surface | PASS | The Nushell package source is tracked under packaging/shell-languages/nushell. |
| LD-49-02 | Nushell | source archive | importable shell module package | source module + CLI | Package metadata | PASS | package-metadata.json declares the exported module commands, CLI, runtime, and templates. |
| LD-49-03 | Nushell | source archive | importable shell module package | source module + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-49-04 | Nushell | source archive | importable shell module package | source module + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the versioned tar archive. |
| LD-49-05 | Nushell | source archive | importable shell module package | source module + CLI | Isolated consumer | PASS | A clean Nushell process imports the installed module and completes the version and init workflows. |
| LD-49-06 | Nushell | source archive | importable shell module package | source module + CLI | Public interface | PASS | The wrapped module command exposes version, runtime/template paths, and argv-preserving external execution. |
| LD-49-07 | Nushell | source archive | importable shell module package | source module + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-49-08 | Nushell | source archive | importable shell module package | source module + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-50-01 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Source surface | PASS | The PowerShell package source is tracked under packaging/shell-languages/powershell. |
| LD-50-02 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Package metadata | PASS | The module manifest declares its version, PowerShell floor, exported functions, project metadata, and native CLI. |
| LD-50-03 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Package build | PASS | packaging/build-scripting-languages.sh stages a versioned package in an isolated workspace. |
| LD-50-04 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Artifact contents | PASS | The batch creates, lists, extracts, and validates the module archive, manifest, native CLI, runtime, and templates. |
| LD-50-05 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Isolated consumer | PASS | A clean pwsh process imports the extracted manifest and executes both module and native-script consumers. |
| LD-50-06 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Public interface | PASS | The module exposes version, runtime/template paths, and an argument-list-safe Invoke-SSHFling function. |
| LD-50-07 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Version contract | PASS | The language-level consumer and packaged CLI must report the exact SSHFling release version. |
| LD-50-08 | PowerShell | PowerShell module archive | versioned module package | library + CLI | Runtime assets/workflow | PASS | The isolated consumer runs init, checks 24 byte-identical templates and 11 executable assets, then verifies removal. |
| LD-51-01 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Source surface | PASS | Tracked Shell/POSIX sh package sources and its public surface live under scripts and production. |
| LD-51-02 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Package metadata | PASS | Make install/uninstall targets declare the command, helper, template, and removal layout. |
| LD-51-03 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Package build | PASS | The test target runs sh syntax checks and an isolated local-install lifecycle. |
| LD-51-04 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Artifact contents | PASS | The isolated prefix is checked for the command, POSIX helpers, templates, and executable modes. |
| LD-51-05 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Isolated consumer | PASS | tests/cross-os/validate-local-install.sh invokes the command from a temporary installation prefix. |
| LD-51-06 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Public interface | PASS | The installed command and POSIX helper scripts are executable CLI surfaces, not an importable shell library. |
| LD-51-07 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Version contract | PASS | The focused Shell/POSIX sh consumer must print the exact SSHFling release version. |
| LD-51-08 | Shell/POSIX sh | Make/install scripts | local install and runtime command set | CLI | Runtime assets/workflow | PASS | Local-install validation exercises version, init assets, helper execution, and uninstall cleanup. |
| LD-52-01 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Source surface | PASS | Tracked Bash package sources and its public surface live under packaging and tests. |
| LD-52-02 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Package metadata | PASS | The Makefile and version helper define strict Bash entry points and the release-version contract. |
| LD-52-03 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Package build | PASS | The test target applies bash -n and executes the Bash release validators. |
| LD-52-04 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Artifact contents | PASS | The checked surface is the tracked command suite; it is not advertised as a Bash package or library artifact. |
| LD-52-05 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Isolated consumer | PASS | Release tests invoke the scripts from the repository and isolated temporary workspaces. |
| LD-52-06 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Public interface | PASS | The Bash surface consists of maintainer-facing CLI commands with strict argument and exit-status handling. |
| LD-52-07 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Version contract | PASS | The focused Bash consumer must print the exact SSHFling release version. |
| LD-52-08 | Bash | Make/source tree | maintainer and packaging command suite | CLI tooling | Runtime assets/workflow | PASS | Release validation covers version resolution, package workflows, temporary state, and cleanup. |
| LD-53-01 | R | R CMD | R source package dependency | library | Source surface | PASS | Tracked R package sources and its public surface live under packaging/scientific-languages/r. |
| LD-53-02 | R | R CMD | R source package dependency | library | Package metadata | PASS | DESCRIPTION and NAMESPACE declare the versioned R package and exported launcher functions. |
| LD-53-03 | R | R CMD | R source package dependency | library | Package build | PASS | The per-language validator runs R CMD build, R CMD check, and R CMD INSTALL at VERSION=0.1.16. |
| LD-53-04 | R | R CMD | R source package dependency | library | Artifact contents | PASS | The source archive and installed runtime inventory are recorded and compared byte-for-byte. |
| LD-53-05 | R | R CMD | R source package dependency | library | Isolated consumer | PASS | A clean external Rscript consumer loads the installed namespace outside the source tree. |
| LD-53-06 | R | R CMD | R source package dependency | library | Public interface | PASS | The exported R functions preserve argument vectors and return the canonical runtime status. |
| LD-53-07 | R | R CMD | R source package dependency | library | Version contract | PASS | The focused R consumer must print the exact SSHFling release version. |
| LD-53-08 | R | R CMD | R source package dependency | library | Runtime assets/workflow | PASS | The consumer validates version, invalid-option, init, missing-runtime, removal, and import-absence cases. |
| LD-54-01 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Source surface | PASS | Tracked Objective-C package sources and its public surface live under packaging/systems-languages/objective-c. |
| LD-54-02 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Package metadata | PASS | CMake metadata and the public SSHFling Objective-C header define the source-package contract. |
| LD-54-03 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Package build | PASS | The focused systems validator compiles warning-clean shared-library, CLI, and consumer binaries. |
| LD-54-04 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Artifact contents | PASS | Validation produces a shared library and CLI in its temporary, isolated output directory. |
| LD-54-05 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Isolated consumer | PASS | A separately compiled Objective-C consumer links the temporary library and checks the release version. |
| LD-54-06 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Public interface | PASS | SSHFling exposes version and argument-array run methods through the public Objective-C header. |
| LD-54-07 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Version contract | PASS | The focused Objective-C consumer must print the exact SSHFling release version. |
| LD-54-08 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | Runtime assets/workflow | PASS | The library consumer and CLI validate version, init, invalid-option, and missing-runtime behavior. |
| LD-55-01 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Source surface | PASS | Tracked Assembly package sources and its public surface live under packaging/systems-languages/assembly. |
| LD-55-02 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Package metadata | PASS | package.toml and the C-compatible header declare the x86_64 assembly package boundary. |
| LD-55-03 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Package build | PASS | The focused systems validator compiles PIC assembly, links a shared library and CLI, and extracts debug data. |
| LD-55-04 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Artifact contents | PASS | Temporary output checks require the shared object, command, and nonempty debug artifact. |
| LD-55-05 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Isolated consumer | PASS | A clean C ABI probe links the assembly library and invokes its version and run symbols. |
| LD-55-06 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Public interface | PASS | The assembly package exports a stable C ABI plus an executable command. |
| LD-55-07 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Version contract | PASS | The focused Assembly consumer must print the exact SSHFling release version. |
| LD-55-08 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | Runtime assets/workflow | PASS | The API and CLI validate exact version, init assets, invalid options, and missing runtime behavior. |
| LD-56-01 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Source surface | PASS | Tracked COBOL package sources and its public surface live under packaging/systems-languages/cobol. |
| LD-56-02 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Package metadata | PASS | package.toml identifies the module, application, and external consumer sources. |
| LD-56-03 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Package build | PASS | The focused systems validator compiles the module and links the CLI with warnings treated as errors. |
| LD-56-04 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Artifact contents | PASS | The validator requires a nonempty COBOL object and executable in its isolated output directory. |
| LD-56-05 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Isolated consumer | PASS | The freshly linked command consumes the compiled COBOL module outside the package source layout. |
| LD-56-06 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Public interface | PASS | The COBOL module forwards an argument vector through the shared launcher contract. |
| LD-56-07 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Version contract | PASS | The focused COBOL consumer must print the exact SSHFling release version. |
| LD-56-08 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-57-01 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Source surface | PASS | Tracked Fortran package sources and its public surface live under packaging/systems-languages/fortran. |
| LD-57-02 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Package metadata | PASS | fpm.toml declares the package while the source tree separates the module, app, and consumer. |
| LD-57-03 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Package build | PASS | The focused systems validator compiles Fortran 2018 sources with warnings treated as errors. |
| LD-57-04 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Artifact contents | PASS | Generated module/object files and the command remain isolated validation artifacts. |
| LD-57-05 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Isolated consumer | PASS | The compiled command imports the Fortran module and runs outside the source package directory. |
| LD-57-06 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Public interface | PASS | The Fortran module exposes the launcher routine consumed by the packaged command. |
| LD-57-07 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Version contract | PASS | The focused Fortran consumer must print the exact SSHFling release version. |
| LD-57-08 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-58-01 | Elixir | Mix | Mix path dependency | library | Source surface | PASS | Tracked Elixir package sources and its public surface live under packaging/beam-languages/elixir. |
| LD-58-02 | Elixir | Mix | Mix path dependency | library | Package metadata | PASS | mix.exs declares the application, release version, bundled runtime, and public module. |
| LD-58-03 | Elixir | Mix | Mix path dependency | library | Package build | PASS | The per-language validator compiles with warnings as errors and resolves an isolated path dependency. |
| LD-58-04 | Elixir | Mix | Mix path dependency | library | Artifact contents | PASS | The staged Mix package contains compiled code plus a byte-checked canonical runtime bundle. |
| LD-58-05 | Elixir | Mix | Mix path dependency | library | Isolated consumer | PASS | An external Mix project depends on the staged package and invokes it from an unrelated directory. |
| LD-58-06 | Elixir | Mix | Mix path dependency | library | Public interface | PASS | SSHFling.run/1 executes the canonical runtime with an argument list and returns its status. |
| LD-58-07 | Elixir | Mix | Mix path dependency | library | Version contract | PASS | The focused Elixir consumer must print the exact SSHFling release version. |
| LD-58-08 | Elixir | Mix | Mix path dependency | library | Runtime assets/workflow | PASS | The external project validates version, init, invalid option, missing runtime, dependency removal, and import absence. |
| LD-59-01 | Erlang | OTP/erlc | OTP application dependency | library | Source surface | PASS | Tracked Erlang package sources and its public surface live under packaging/beam-languages/erlang. |
| LD-59-02 | Erlang | OTP/erlc | OTP application dependency | library | Package metadata | PASS | rebar.config and sshfling.app.src declare the OTP application and bundled resources. |
| LD-59-03 | Erlang | OTP/erlc | OTP application dependency | library | Package build | PASS | The per-language validator compiles package and consumer modules with erlc -Werror. |
| LD-59-04 | Erlang | OTP/erlc | OTP application dependency | library | Artifact contents | PASS | The staged OTP application contains its beam module, application metadata, and canonical runtime bundle. |
| LD-59-05 | Erlang | OTP/erlc | OTP application dependency | library | Isolated consumer | PASS | A separately compiled Erlang module resolves the staged package through isolated code paths. |
| LD-59-06 | Erlang | OTP/erlc | OTP application dependency | library | Public interface | PASS | The sshfling module exposes argument-list execution with exact child status propagation. |
| LD-59-07 | Erlang | OTP/erlc | OTP application dependency | library | Version contract | PASS | The focused Erlang consumer must print the exact SSHFling release version. |
| LD-59-08 | Erlang | OTP/erlc | OTP application dependency | library | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, package removal, and import absence. |
| LD-60-01 | Haskell | Cabal | Cabal library and executable package | library + CLI | Source surface | PASS | Tracked Haskell package sources and its public surface live under packaging/functional-languages/haskell. |
| LD-60-02 | Haskell | Cabal | Cabal library and executable package | library + CLI | Package metadata | PASS | sshfling.cabal declares the library, command, consumer, resources, and versioned package metadata. |
| LD-60-03 | Haskell | Cabal | Cabal library and executable package | library + CLI | Package build | PASS | The per-language validator performs an offline Cabal build and resolves both produced executables. |
| LD-60-04 | Haskell | Cabal | Cabal library and executable package | library + CLI | Artifact contents | PASS | Cabal's isolated build tree contains the library, CLI, consumer, and canonical runtime resources. |
| LD-60-05 | Haskell | Cabal | Cabal library and executable package | library + CLI | Isolated consumer | PASS | The dedicated consumer executable imports SSHFling and runs from outside the source directory. |
| LD-60-06 | Haskell | Cabal | Cabal library and executable package | library + CLI | Public interface | PASS | The SSHFling module exposes argument-list execution while the package also provides a command. |
| LD-60-07 | Haskell | Cabal | Cabal library and executable package | library + CLI | Version contract | PASS | The focused Haskell consumer must print the exact SSHFling release version. |
| LD-60-08 | Haskell | Cabal | Cabal library and executable package | library + CLI | Runtime assets/workflow | PASS | The CLI and consumer validate version, init, invalid option, missing runtime, and Cabal cleanup. |
| LD-61-01 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Source surface | PASS | Tracked OCaml package sources and its public surface live under packaging/functional-languages/ocaml. |
| LD-61-02 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Package metadata | PASS | opam and Dune metadata declare the library, executable, version, and install layout. |
| LD-61-03 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Package build | PASS | The per-language validator builds @install and installs it into an isolated Dune prefix. |
| LD-61-04 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Artifact contents | PASS | The source archive and installed prefix contain the OCaml library, CLI, and runtime resources. |
| LD-61-05 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Isolated consumer | PASS | A clean external Dune project resolves the installed library through an isolated OCAMLPATH. |
| LD-61-06 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Public interface | PASS | The public .mli exposes list-based argument execution and the package installs a matching command. |
| LD-61-07 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Version contract | PASS | The focused OCaml consumer must print the exact SSHFling release version. |
| LD-61-08 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | Runtime assets/workflow | PASS | The external consumer validates version, init, invalid option, missing runtime, uninstall, and import absence. |
| LD-62-01 | Zig | Zig build | Zig module and executable package | library + CLI | Source surface | PASS | Tracked Zig package sources and its public surface live under packaging/systems-languages/zig. |
| LD-62-02 | Zig | Zig build | Zig module and executable package | library + CLI | Package metadata | PASS | build.zig.zon and build.zig declare the named module, command, and install prefix. |
| LD-62-03 | Zig | Zig build | Zig module and executable package | library + CLI | Package build | PASS | The focused systems validator runs zig build with isolated local and global caches. |
| LD-62-04 | Zig | Zig build | Zig module and executable package | library + CLI | Artifact contents | PASS | The Zig prefix must contain the freshly built sshfling-zig command. |
| LD-62-05 | Zig | Zig build | Zig module and executable package | library + CLI | Isolated consumer | PASS | The installed command imports the tracked Zig launcher module and runs from the isolated prefix. |
| LD-62-06 | Zig | Zig build | Zig module and executable package | library + CLI | Public interface | PASS | The Zig module supplies launcher functions and the build installs a command. |
| LD-62-07 | Zig | Zig build | Zig module and executable package | library + CLI | Version contract | PASS | The focused Zig consumer must print the exact SSHFling release version. |
| LD-62-08 | Zig | Zig build | Zig module and executable package | library + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-63-01 | Nim | Nimble | Nimble source package | library + CLI | Source surface | PASS | Tracked Nim package sources and its public surface live under packaging/systems-languages/nim. |
| LD-63-02 | Nim | Nimble | Nimble source package | library + CLI | Package metadata | PASS | sshfling.nimble declares the source package, public module, command, and version placeholder. |
| LD-63-03 | Nim | Nimble | Nimble source package | library + CLI | Package build | PASS | The focused systems validator runs nim check, nim c, and nimble check with isolated caches. |
| LD-63-04 | Nim | Nimble | Nimble source package | library + CLI | Artifact contents | PASS | The resulting validation command links the shared launcher object and remains in a temporary output tree. |
| LD-63-05 | Nim | Nimble | Nimble source package | library + CLI | Isolated consumer | PASS | The command imports the Nim launcher module using only the package source path. |
| LD-63-06 | Nim | Nimble | Nimble source package | library + CLI | Public interface | PASS | The Nim module is importable and the package includes a separate CLI entry point. |
| LD-63-07 | Nim | Nimble | Nimble source package | library + CLI | Version contract | PASS | The focused Nim consumer must print the exact SSHFling release version. |
| LD-63-08 | Nim | Nimble | Nimble source package | library + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-64-01 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Source surface | PASS | Tracked Crystal package sources and its public surface live under packaging/systems-languages/crystal. |
| LD-64-02 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Package metadata | PASS | shard.yml declares the shard identity and the sshfling-crystal command target. |
| LD-64-03 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Package build | PASS | The focused systems validator parses the shard metadata and builds the CLI with isolated caches. |
| LD-64-04 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Artifact contents | PASS | The command and its temporary native launcher library are checked in the isolated output tree. |
| LD-64-05 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Isolated consumer | PASS | The built command requires the tracked Crystal library source rather than checkout-wide load paths. |
| LD-64-06 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Public interface | PASS | The Crystal source exposes launcher methods and a distinct CLI target. |
| LD-64-07 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Version contract | PASS | The focused Crystal consumer must print the exact SSHFling release version. |
| LD-64-08 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-65-01 | D | Dub/source build | D module and static-library dependency | library + CLI | Source surface | PASS | Tracked D package sources and its public surface live under packaging/systems-languages/d. |
| LD-65-02 | D | Dub/source build | D module and static-library dependency | library + CLI | Package metadata | PASS | dub.json declares the D package while source, app, and consumer entry points are tracked separately. |
| LD-65-03 | D | Dub/source build | D module and static-library dependency | library + CLI | Package build | PASS | The focused systems validator compiles warning-clean D objects, archives a static library, and links the CLI. |
| LD-65-04 | D | Dub/source build | D module and static-library dependency | library + CLI | Artifact contents | PASS | Validation requires a nonempty static archive and executable in the temporary output directory. |
| LD-65-05 | D | Dub/source build | D module and static-library dependency | library + CLI | Isolated consumer | PASS | The command imports the D source module and links only the freshly built static launcher library. |
| LD-65-06 | D | Dub/source build | D module and static-library dependency | library + CLI | Public interface | PASS | The D module exposes launcher execution and the package includes a command application. |
| LD-65-07 | D | Dub/source build | D module and static-library dependency | library + CLI | Version contract | PASS | The focused D consumer must print the exact SSHFling release version. |
| LD-65-08 | D | Dub/source build | D module and static-library dependency | library + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-66-01 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Source surface | PASS | Tracked Ada package sources and its public surface live under packaging/systems-languages/ada. |
| LD-66-02 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Package metadata | PASS | Alire and GPR metadata declare the Ada package, public unit, and executable source layout. |
| LD-66-03 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Package build | PASS | The focused systems validator uses GNAT 2022 checks with warnings promoted to errors. |
| LD-66-04 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Artifact contents | PASS | Compiled Ada units and the linked command are confined to the temporary validation output. |
| LD-66-05 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Isolated consumer | PASS | The command withs the public SSHFling unit and links the shared launcher object. |
| LD-66-06 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Public interface | PASS | The SSHFling package specification is the public Ada API and the app supplies a CLI. |
| LD-66-07 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Version contract | PASS | The focused Ada consumer must print the exact SSHFling release version. |
| LD-66-08 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-67-01 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Source surface | PASS | Tracked Common Lisp package sources and its public surface live under packaging/functional-languages/common-lisp. |
| LD-67-02 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Package metadata | PASS | sshfling.asd and package.lisp declare the ASDF system and exported launcher symbols. |
| LD-67-03 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Package build | PASS | The per-language validator compiles the ASDF system from an isolated source registry. |
| LD-67-04 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Artifact contents | PASS | A versioned source archive contains the system sources and byte-checked canonical runtime. |
| LD-67-05 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Isolated consumer | PASS | An external SBCL script loads only the installed ASDF system from the isolated registry. |
| LD-67-06 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Public interface | PASS | The sshfling package exports argument-list execution with child-status propagation. |
| LD-67-07 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Version contract | PASS | The focused Common Lisp consumer must print the exact SSHFling release version. |
| LD-67-08 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, removal, and import absence. |
| LD-68-01 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Source surface | PASS | Tracked Scheme/Racket package sources and its public surface live under packaging/functional-languages/scheme. |
| LD-68-02 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Package metadata | PASS | Autotools metadata declares the Guile module, command, version, and install directories; Racket is not claimed. |
| LD-68-03 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Package build | PASS | The per-language validator builds a dist archive, configures it, runs checks, and installs to an isolated prefix. |
| LD-68-04 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Artifact contents | PASS | The source archive and prefix contain compiled Guile module data, CLI, and canonical runtime. |
| LD-68-05 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Isolated consumer | PASS | An external Guile script resolves only the installed module and compiled-object directories. |
| LD-68-06 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Public interface | PASS | The Guile module exports run; the package also installs sshfling-guile. |
| LD-68-07 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Version contract | PASS | The focused Scheme/Racket consumer must print the exact SSHFling release version. |
| LD-68-08 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, uninstall, and import absence. |
| LD-69-01 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Source surface | PASS | Tracked Prolog package sources and its public surface live under packaging/functional-languages/prolog. |
| LD-69-02 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Package metadata | PASS | pack.pl declares the SWI-Prolog pack and the module file exports its launcher predicates. |
| LD-69-03 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Package build | PASS | The per-language validator archives and pack-installs the package into an isolated directory. |
| LD-69-04 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Artifact contents | PASS | The installed pack contains the Prolog module and byte-checked canonical runtime bundle. |
| LD-69-05 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Isolated consumer | PASS | An external Prolog program attaches the isolated pack and imports library(sshfling). |
| LD-69-06 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Public interface | PASS | The public predicate accepts an argument list and reports the exact child status. |
| LD-69-07 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Version contract | PASS | The focused Prolog consumer must print the exact SSHFling release version. |
| LD-69-08 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, pack removal, and import absence. |
| LD-70-01 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Source surface | PASS | Tracked Forth package sources and its public surface live under packaging/systems-languages/forth. |
| LD-70-02 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Package metadata | PASS | package.toml declares the source words, CLI, bridge, consumer, and runtime requirements. |
| LD-70-03 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Package build | PASS | The focused systems validator builds the native bridge and loads the Forth API with Gforth. |
| LD-70-04 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Artifact contents | PASS | The temporary bridge library and tracked Forth source form the validated package artifacts. |
| LD-70-05 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Isolated consumer | PASS | A clean Gforth process loads sshfling.fs and executes cli.fs with isolated HOME and bridge paths. |
| LD-70-06 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Public interface | PASS | The source package exposes sshfling-version and run words plus a command-file CLI. |
| LD-70-07 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Version contract | PASS | The focused Forth consumer must print the exact SSHFling release version. |
| LD-70-08 | Forth | Gforth/source package | loadable Forth source package | library + CLI | Runtime assets/workflow | PASS | The command validates exact version, init assets, invalid options, and missing runtime behavior. |
| LD-71-01 | Gleam | Gleam/Hex | Hex library package | library | Source surface | PASS | Tracked Gleam package sources and its public surface live under packaging/beam-languages/gleam. |
| LD-71-02 | Gleam | Gleam/Hex | Hex library package | library | Package metadata | PASS | gleam.toml declares the Hex package, target runtime, source modules, and bundled resources. |
| LD-71-03 | Gleam | Gleam/Hex | Hex library package | library | Package build | PASS | The per-language validator runs gleam check, exports a Hex tarball, and builds an external consumer. |
| LD-71-04 | Gleam | Gleam/Hex | Hex library package | library | Artifact contents | PASS | The exported Hex tarball is nonempty and includes the Gleam/Erlang API plus canonical runtime. |
| LD-71-05 | Gleam | Gleam/Hex | Hex library package | library | Isolated consumer | PASS | A separate Gleam project imports the staged package and runs dedicated status-case modules. |
| LD-71-06 | Gleam | Gleam/Hex | Hex library package | library | Public interface | PASS | The typed Gleam API delegates through an Erlang FFI while preserving argument lists and status. |
| LD-71-07 | Gleam | Gleam/Hex | Hex library package | library | Version contract | PASS | The focused Gleam consumer must print the exact SSHFling release version. |
| LD-71-08 | Gleam | Gleam/Hex | Hex library package | library | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, package removal, and import absence. |
| LD-72-01 | Nix | Nix flakes | flake package and app | CLI | Source surface | PASS | Tracked Nix package sources and its public surface live under flake.nix and generated public Nix metadata. |
| LD-72-02 | Nix | Nix flakes | flake package and app | CLI | Package metadata | PASS | flake.nix declares versioned packages and apps for four Linux/macOS architectures. |
| LD-72-03 | Nix | Nix flakes | flake package and app | CLI | Package build | PASS | Cross-OS CI builds the generated flake in a pinned Nix container and executes its result. |
| LD-72-04 | Nix | Nix flakes | flake package and app | CLI | Artifact contents | PASS | The derivation installs the command, native helpers, runtime templates, documentation, and wrappers. |
| LD-72-05 | Nix | Nix flakes | flake package and app | CLI | Isolated consumer | PASS | tests/cross-os/validate-cli.sh consumes only ./result/bin/sshfling from the Nix build result. |
| LD-72-06 | Nix | Nix flakes | flake package and app | CLI | Public interface | PASS | The flake exposes a packaged sshfling CLI app; it does not claim an importable Nix-language library. |
| LD-72-07 | Nix | Nix flakes | flake package and app | CLI | Version contract | PASS | The focused Nix consumer must print the exact SSHFling release version. |
| LD-72-08 | Nix | Nix flakes | flake package and app | CLI | Runtime assets/workflow | PASS | The Nix consumer validates the exact version and packaged CLI runtime in its isolated result closure. |
| LD-73-01 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Source surface | PASS | Tracked Guix Scheme package sources and its public surface live under packaging/guix-scheme. |
| LD-73-02 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Package metadata | PASS | package-metadata.json declares the Guile module, Guix definition, CLI, runtime, and templates. |
| LD-73-03 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Package build | PASS | The scripting batch builds the archive and CI requires a PASS Guile runtime row at VERSION=0.1.16. |
| LD-73-04 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Artifact contents | PASS | Archive checks require the rendered module, package definition, command, runtime, and templates. |
| LD-73-05 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Isolated consumer | PASS | An isolated Guile process imports the extracted module and invokes its version and run functions. |
| LD-73-06 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Public interface | PASS | The Guile module exposes version, runtime/template paths, and argument-list-safe execution; Guix package-manager validation is separate. |
| LD-73-07 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Version contract | PASS | The focused Guix Scheme consumer must print the exact SSHFling release version. |
| LD-73-08 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | Runtime assets/workflow | PASS | The Guile consumer and packaged CLI validate version, init assets, removal, and import absence. |
| LD-74-01 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Source surface | PASS | Tracked Julia package sources and its public surface live under packaging/scientific-languages/julia. |
| LD-74-02 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Package metadata | PASS | Project.toml declares the versioned package while the module, command, and tests are separate tracked surfaces. |
| LD-74-03 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Package build | PASS | The per-language validator installs and precompiles the package, runs Pkg.test, and executes an external consumer at VERSION=0.1.16. |
| LD-74-04 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Artifact contents | PASS | The deterministic source archive contains the Julia package and byte-checked canonical runtime bundle. |
| LD-74-05 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Isolated consumer | PASS | An unrelated Julia project uses Pkg.develop on the extracted archive and imports SSHFling. |
| LD-74-06 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Public interface | PASS | SSHFling.run accepts ARGS and the packaged Julia command exposes the same status-preserving contract. |
| LD-74-07 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Version contract | PASS | The focused Julia consumer must print the exact SSHFling release version. |
| LD-74-08 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, Pkg removal, and import absence. |
| LD-75-01 | Janet | JPM | Janet module package and command | library + CLI | Source surface | PASS | Tracked Janet package sources and its public surface live under packaging/functional-languages/janet. |
| LD-75-02 | Janet | JPM | Janet module package and command | library + CLI | Package metadata | PASS | project.janet declares the JPM package, module path, executable, version, and bundled resources. |
| LD-75-03 | Janet | JPM | Janet module package and command | library + CLI | Package build | PASS | The per-language validator installs from the deterministic archive into an isolated JPM tree and compiles the external consumer. |
| LD-75-04 | Janet | JPM | Janet module package and command | library + CLI | Artifact contents | PASS | The versioned source archive and installed package contain the Janet module, command, and canonical runtime. |
| LD-75-05 | Janet | JPM | Janet module package and command | library + CLI | Isolated consumer | PASS | A clean Janet consumer imports only the installed module outside the source package directory. |
| LD-75-06 | Janet | JPM | Janet module package and command | library + CLI | Public interface | PASS | The Janet module exposes argument-array execution and the package installs a matching command. |
| LD-75-07 | Janet | JPM | Janet module package and command | library + CLI | Version contract | PASS | The focused Janet consumer must print the exact SSHFling release version. |
| LD-75-08 | Janet | JPM | Janet module package and command | library + CLI | Runtime assets/workflow | PASS | The consumer validates version, init, invalid option, missing runtime, package removal, and import absence. |
| LD-76-01 | J | J package | J addon dependency and command | library + CLI | Source surface | PASS | Tracked J package sources and its public surface live under packaging/scientific-languages/j. |
| LD-76-02 | J | J package | J addon dependency and command | library + CLI | Package metadata | PASS | manifest.ijs declares the addon while source, command, and consumer scripts are tracked separately. |
| LD-76-03 | J | J package | J addon dependency and command | library + CLI | Package build | PASS | The per-language validator installs the deterministic archive as an isolated J addon and runs its external consumer. |
| LD-76-04 | J | J package | J addon dependency and command | library + CLI | Artifact contents | PASS | The source archive contains the addon, command, consumer, and byte-checked canonical runtime. |
| LD-76-05 | J | J package | J addon dependency and command | library + CLI | Isolated consumer | PASS | An external J script loads the installed addon outside its source and installation directories. |
| LD-76-06 | J | J package | J addon dependency and command | library + CLI | Public interface | PASS | The J addon exposes argument-list execution and includes a command script. |
| LD-76-07 | J | J package | J addon dependency and command | library + CLI | Version contract | PASS | The focused J consumer must print the exact SSHFling release version. |
| LD-76-08 | J | J package | J addon dependency and command | library + CLI | Runtime assets/workflow | PASS | The consumer validates exact version, init, invalid option, missing runtime, addon removal, and import absence. |
| LD-77-01 | V | VPM | V module and executable package | library + CLI | Source surface | PASS | Tracked V package sources and its public surface live under packaging/systems-languages/v. |
| LD-77-02 | V | VPM | V module and executable package | library + CLI | Package metadata | PASS | v.mod declares the package while module, command, and consumer entry points are tracked separately. |
| LD-77-03 | V | VPM | V module and executable package | library + CLI | Package build | PASS | The systems validator extracts the deterministic archive, compiles the package and clean consumer with V, and runs both. |
| LD-77-04 | V | VPM | V module and executable package | library + CLI | Artifact contents | PASS | The archive inventory includes the V module, CLI, consumer, shared launcher sources, runtime, and templates. |
| LD-77-05 | V | VPM | V module and executable package | library + CLI | Isolated consumer | PASS | A clean consumer imports the extracted package without repository-wide module paths. |
| LD-77-06 | V | VPM | V module and executable package | library + CLI | Public interface | PASS | The V module supplies launcher functions and the package includes an executable command. |
| LD-77-07 | V | VPM | V module and executable package | library + CLI | Version contract | PASS | The focused V consumer must print the exact SSHFling release version. |
| LD-77-08 | V | VPM | V module and executable package | library + CLI | Runtime assets/workflow | PASS | The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence. |
| LD-78-01 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Source surface | PASS | Tracked WebAssembly/WASI package sources and its public surface live under packaging/systems-languages/webassembly-wasi. |
| LD-78-02 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Package metadata | PASS | package.toml and WIT declare the WASI command imports, host adapter, consumer, and runtime contract. |
| LD-78-03 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Package build | PASS | The systems validator extracts the archive, compiles wasm32-wasi code, and runs it through the tracked Node host adapter. |
| LD-78-04 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Artifact contents | PASS | The archive contains the WASI module source, WIT, host/consumer modules, runtime, templates, and inventory manifest. |
| LD-78-05 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Isolated consumer | PASS | A clean Node consumer executes the built module through the extracted host adapter. |
| LD-78-06 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Public interface | PASS | The public boundary is a WASI command module with an explicit trusted host process, not direct kernel process access. |
| LD-78-07 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Version contract | PASS | The focused WebAssembly/WASI consumer must print the exact SSHFling release version. |
| LD-78-08 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | Runtime assets/workflow | PASS | The host-backed command validates version, init, invalid option, missing runtime, removal, and post-removal failure. |
| LD-79-01 | Odin | Odin source package | Odin collection and executable | library + CLI | Source surface | PASS | Tracked Odin package sources and its public surface live under packaging/systems-languages/odin. |
| LD-79-02 | Odin | Odin source package | Odin collection and executable | library + CLI | Package metadata | PASS | package.toml declares the collection, command, consumer, and bundled runtime resources. |
| LD-79-03 | Odin | Odin source package | Odin collection and executable | library + CLI | Package build | PASS | The systems validator extracts the archive, builds the Odin collection and command, and executes an isolated consumer. |
| LD-79-04 | Odin | Odin source package | Odin collection and executable | library + CLI | Artifact contents | PASS | The deterministic archive contains Odin sources, shared launcher sources, runtime, templates, and inventory manifest. |
| LD-79-05 | Odin | Odin source package | Odin collection and executable | library + CLI | Isolated consumer | PASS | A clean consumer imports the extracted sshfling collection outside the repository source tree. |
| LD-79-06 | Odin | Odin source package | Odin collection and executable | library + CLI | Public interface | PASS | The Odin collection exports launcher functions and the package includes a command. |
| LD-79-07 | Odin | Odin source package | Odin collection and executable | library + CLI | Version contract | PASS | The focused Odin consumer must print the exact SSHFling release version. |
| LD-79-08 | Odin | Odin source package | Odin collection and executable | library + CLI | Runtime assets/workflow | PASS | The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence. |
| LD-80-01 | Pony | Corral | Pony package and executable | library + CLI | Source surface | PASS | Tracked Pony package sources and its public surface live under packaging/systems-languages/pony. |
| LD-80-02 | Pony | Corral | Pony package and executable | library + CLI | Package metadata | PASS | corral.json declares the package while the public package, command, and consumer are tracked separately. |
| LD-80-03 | Pony | Corral | Pony package and executable | library + CLI | Package build | PASS | The systems validator extracts the deterministic archive, compiles with ponyc, and runs an isolated consumer. |
| LD-80-04 | Pony | Corral | Pony package and executable | library + CLI | Artifact contents | PASS | The versioned source archive includes an inventory manifest, package sources, runtime, and templates. |
| LD-80-05 | Pony | Corral | Pony package and executable | library + CLI | Isolated consumer | PASS | The isolated consumer imports the extracted Pony package and runs without checkout load paths. |
| LD-80-06 | Pony | Corral | Pony package and executable | library + CLI | Public interface | PASS | The Pony package exposes launcher behavior and the package builds a corresponding command. |
| LD-80-07 | Pony | Corral | Pony package and executable | library + CLI | Version contract | PASS | The focused Pony consumer must print the exact SSHFling release version. |
| LD-80-08 | Pony | Corral | Pony package and executable | library + CLI | Runtime assets/workflow | PASS | The consumer and CLI validate version, init, invalid option, missing runtime, uninstall, and import absence. |
| LD-81-01 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Source surface | PASS | The typed Dart adapter and explicit trusted Node bridge are tracked under packaging/node/consumers/dart. |
| LD-81-02 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Package metadata | PASS | pubspec.yaml declares Dart 3 compatibility while package.json pins the packed npm dependency and compile/test commands. |
| LD-81-03 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Package build | PASS | The web-language batch performs offline pub resolution and dart compile exe after installing only the packed SSHFling npm artifact. |
| LD-81-04 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Artifact contents | PASS | Validation requires the native sshfling-dart-consumer executable and the installed sshfling-VERSION.tgz dependency. |
| LD-81-05 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Isolated consumer | PASS | The batch copies the Dart project to a temporary directory, installs the packed dependency, compiles, and executes the native adapter. |
| LD-81-06 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Public interface | PASS | The server-side executable launches a fixed Node bridge, which imports sshfling, invokes run, and checks templateDir. |
| LD-81-07 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Version contract | PASS | The adapter reaches the packed library's validated --version path and rejects any nonzero status; exact string validation remains on the parent npm artifact. |
| LD-81-08 | Dart | pub + npm | compiled server-side adapter | native CLI consumer | Runtime assets/workflow | PASS | The native adapter requires successful packed-library execution and bundled-template discovery, then the isolated workspace is removed. |
