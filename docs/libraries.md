# SSHFling Library APIs

SSHFling's fully validated launcher libraries include the primary Python,
JavaScript/TypeScript, JVM, .NET, Go, Rust, PHP, Ruby, C/C++, and Perl packages,
plus the validated R, Objective-C, systems-language, functional-language, BEAM,
Guile, Prolog, Forth, and Gleam package surfaces listed below. Every API runs the
bundled SSHFling Python runtime with inherited standard streams and returns or
reports its exit status. Python 3 and the applicable OpenSSH tools remain host
dependencies.

These are launcher APIs around the CLI contract, not an in-process SSH server
SDK. The package, clean-consumer, and deployment evidence is tracked in
[language-deployment-support.md](language-deployment-support.md).

The generated index at the end of this document is authoritative for first-91
coverage. It keeps publishable source packages separate from runtime-validated
libraries and marks missing external toolchains as `BLOCKED`.

## Python

Package: `sshfling-VERSION-py3-none-any.whl` via pip.

```python
import sshfling

status = sshfling.run(["--version"])
```

## JavaScript And TypeScript

Package: `sshfling-VERSION.tgz` via npm. CommonJS, ESM, and strict TypeScript
consumers are validated.

```javascript
const sshfling = require("sshfling");

const status = sshfling.run(["--version"], { stdio: "inherit" });
```

```typescript
import sshfling, { RunOptions } from "sshfling";

const options: RunOptions = { stdio: "inherit" };
const status: number = sshfling.run(["--version"], options);
```

## Java And JVM Languages

Coordinates: `io.sshfling:sshfling-cli:VERSION`. Clean Maven and Gradle
consumers are validated for Java, Kotlin 2.4, Scala 3.3, and Groovy 5.

```xml
<dependency>
  <groupId>io.sshfling</groupId>
  <artifactId>sshfling-cli</artifactId>
  <version>VERSION</version>
</dependency>
```

```kotlin
dependencies {
    implementation("io.sshfling:sshfling-cli:VERSION")
}
```

```java
import io.sshfling.cli.SSHFling;

int status = SSHFling.run(new String[] { "--version" });
```

```kotlin
import io.sshfling.cli.SSHFling

val status = SSHFling.run(arrayOf("--version"))
```

```scala
import io.sshfling.cli.SSHFling

val status = SSHFling.run(Array("--version"))
```

```groovy
import io.sshfling.cli.SSHFling

int status = SSHFling.run(["--version"] as String[])
```

The release includes executable, sources, and Javadocs JARs plus the POM.

## .NET

Package ID: `SSHFling` via NuGet. The `SSHFling.Tool` package remains the
separate CLI/global-tool distribution. Clean C#, Visual Basic, and F# consumer
projects are validated against the same package.

```csharp
using SSHFling;

int status = SSHFlingRunner.Run(new[] { "--version" });
int asyncStatus = await SSHFlingRunner.RunAsync(new[] { "--version" });
```

```vbnet
Imports SSHFling

Dim status = SSHFlingRunner.Run(New String() {"--version"})
```

```fsharp
open SSHFling

let status = SSHFlingRunner.Run([| "--version" |])
```

## Go

Module path: `github.com/GRWLX/sshfling/packaging/go`. The release source ZIP
contains the importable module and `cmd/sshfling`.

```go
package main

import (
	"context"
	"log"

	sshfling "github.com/GRWLX/sshfling/packaging/go"
)

func main() {
	if err := sshfling.Run(context.Background(), []string{"--version"}); err != nil {
		log.Fatal(err)
	}
}
```

## Rust

Cargo package: `sshfling-cli`; library crate: `sshfling`.

```rust
fn main() -> Result<(), sshfling::Error> {
    sshfling::run(["--version"])
}
```

## PHP

Composer package: `grwlx/sshfling`.

```php
<?php

require __DIR__ . '/vendor/autoload.php';

use GRWLX\SSHFling\SSHFling;

$status = SSHFling::run(['--version']);
```

## Ruby

Gem: `sshfling`, validated through RubyGems and Bundler.

```ruby
require "sshfling"

status = SSHFling.run(["--version"])
```

## C

Artifact: `sshfling-native-VERSION.tar.gz`. The POSIX C11 package installs a
shared library, static archive, public header, `SSHFling::shared` and
`SSHFling::static` CMake targets, `sshfling.pc`, and the `sshfling-c` command.

```cmake
find_package(SSHFling CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE SSHFling::shared)
```

```c
#include <sshfling/sshfling.h>

int main(void) {
    const char *arguments[] = {"--version"};
    return sshfling_run(1, arguments);
}
```

For direct compiler integration, use `pkg-config --cflags --libs sshfling`.
Windows native ABI support is not claimed by this POSIX process-launching
implementation.

## C++

The same native artifact includes a C++17 header wrapper. The clean C++
consumer links the static exported target.

```cpp
#include <sshfling/sshfling.hpp>

int main() {
    return sshfling::run({"--version"});
}
```

## Perl

Artifact: `sshfling-perl-VERSION.tar.gz`, an ExtUtils::MakeMaker/CPAN-style
source distribution containing the `SSHFling` module and `sshfling`
executable.

```perl
use SSHFling;

my $status = SSHFling::run('--version');
```

<!-- BEGIN GENERATED FIRST-91 LIBRARY SURFACES -->

## Generated First-91 Library Surface Index

This index contains 78 explicit library/module surfaces: 76 PASS and 2 BLOCKED. Source-archive publication rows are excluded because publication alone is not library runtime evidence.

| Order | Language | Package manager | Deployment | Interface | Status | Artifact | Evidence or blocker |
| ---: | --- | --- | --- | --- | --- | --- | --- |
| 1 | Python | pip | wheel dependency | library + CLI | PASS | sshfling-VERSION-py3-none-any.whl | The package-python validator supplies the detailed PASS evidence below. |
| 2 | TypeScript | npm | typed dependency | library | PASS | sshfling-VERSION.tgz | The package-node validator supplies the detailed PASS evidence below. |
| 3 | JavaScript | npm | CommonJS dependency | library | PASS | sshfling-VERSION.tgz | The package-node validator supplies the detailed PASS evidence below. |
| 3 | JavaScript | npm | ES module dependency | library | PASS | sshfling-VERSION.tgz | The package-node validator supplies the detailed PASS evidence below. |
| 4 | Java | Maven | Maven dependency | library + CLI | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 4 | Java | Gradle | Gradle dependency | library + CLI | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 5 | C | CMake | shared-library dependency | library | PASS | sshfling-native-VERSION.tar.gz / libsshfling.so | The package-native-libraries validator supplies the detailed PASS evidence below. |
| 5 | C | CMake | static-library dependency | library | PASS | sshfling-native-VERSION.tar.gz / libsshfling.a | The package-native-libraries validator supplies the detailed PASS evidence below. |
| 5 | C | pkg-config | compiler dependency | library | PASS | sshfling-native-VERSION.tar.gz / sshfling.pc | The package-native-libraries validator supplies the detailed PASS evidence below. |
| 6 | C++ | CMake | C++17 static-library dependency | library | PASS | sshfling-native-VERSION.tar.gz / sshfling.hpp | The package-native-libraries validator supplies the detailed PASS evidence below. |
| 7 | C#/.NET | NuGet | PackageReference library | library | PASS | SSHFling.VERSION.nupkg | The package-dotnet validator supplies the detailed PASS evidence below. |
| 9 | Go | Go modules | module dependency and go install | library + CLI | PASS | sshfling-go-VERSION.zip | The package-go validator supplies the detailed PASS evidence below. |
| 10 | Rust | Cargo | crate dependency and cargo install | library + CLI | PASS | sshfling-cli-VERSION.crate | The package-rust validator supplies the detailed PASS evidence below. |
| 11 | PHP | Composer | Composer dependency | library + CLI | PASS | sshfling-php-VERSION.zip | The package-php validator supplies the detailed PASS evidence below. |
| 14 | PowerShell | PowerShell module archive | versioned module package | library + CLI | PASS | sshfling-powershell-VERSION.tar.gz | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 15 | Kotlin | Maven | Kotlin/JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 15 | Kotlin | Gradle | Kotlin/JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 16 | Swift | SwiftPM | Swift package dependency and executable | library + CLI | PASS | sshfling-swift-VERSION.tar.gz | The Ubuntu 24.04 strict catalog records RUNTIME swift PASS with archive-lifecycle mode and the complete SwiftPM library, CLI, removal, and post-removal capability set. |
| 17 | R | R CMD | R source package dependency | library | PASS | sshfling_VERSION.tar.gz | The per-language validator runs R CMD build, R CMD check, and R CMD INSTALL at VERSION=0.1.19. |
| 18 | Ruby | RubyGems | gem dependency and executable | library + CLI | PASS | sshfling-VERSION.gem | The package-ruby validator supplies the detailed PASS evidence below. |
| 18 | Ruby | Bundler | bundled application dependency | library + CLI | PASS | sshfling-VERSION.gem / source path | The package-ruby validator supplies the detailed PASS evidence below. |
| 20 | Lua | source archive | Lua source module package | library + CLI | PASS | sshfling-lua-VERSION.tar.gz | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 20 | Lua | LuaRocks | all-platform rock dependency | library + CLI | PASS | sshfling-VERSION-1.all.rock | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 21 | Perl | MakeMaker/CPAN | source distribution dependency | library + CLI | PASS | sshfling-perl-VERSION.tar.gz | The package-perl validator supplies the detailed PASS evidence below. |
| 22 | Scala | Maven | Scala 3 JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 22 | Scala | Gradle | Scala 3 JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 23 | Visual Basic/.NET | NuGet | PackageReference library | library | PASS | SSHFling.VERSION.nupkg | The package-dotnet validator supplies the detailed PASS evidence below. |
| 24 | MATLAB | GNU Octave | MATLAB-compatible source package | library | PASS | sshfling-matlab-VERSION.tar.gz | The per-language validator executes octave-cli against a deterministic MATLAB-compatible source archive. |
| 25 | Objective-C | CMake/source build | Objective-C shared-library dependency | library + CLI | PASS | libsshfling_objc.so and sshfling-objective-c validation artifacts | The focused systems validator compiles warning-clean shared-library, CLI, and consumer binaries. |
| 26 | Groovy | Maven | Groovy/JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 26 | Groovy | Gradle | Groovy/JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 27 | Delphi/Object Pascal | Free Pascal units | Object Pascal unit and executable package | library + CLI | PASS | sshfling-object-pascal-VERSION.tar.gz | The systems-language validator records RUNTIME object-pascal PASS with build-only mode plus Free Pascal compile, library consumer, CLI runtime, init workflow, and exit workflow capabilities. |
| 28 | Julia | Julia Pkg | Julia package dependency and command | library + CLI | PASS | sshfling-julia-VERSION.tar.gz | The per-language validator installs and precompiles the package, runs Pkg.test, and executes an external consumer at VERSION=0.1.19. |
| 30 | Assembly | GNU/Clang toolchain | x86_64 ELF source package | library + CLI | PASS | libsshfling_assembly.so and sshfling-assembly validation artifacts | The focused systems validator compiles PIC assembly, links a shared library and CLI, and extracts debug data. |
| 31 | COBOL | GnuCOBOL | free-format COBOL source package | library module + CLI | PASS | COBOL object module and sshfling-cobol validation command | The focused systems validator compiles the module and links the CLI with warnings treated as errors. |
| 32 | Fortran | fpm/source build | Fortran 2018 module dependency | library module + CLI | PASS | Fortran module objects and sshfling-fortran validation command | The focused systems validator compiles Fortran 2018 sources with warnings treated as errors. |
| 38 | Elixir | Mix | Mix path dependency | library | PASS | versioned Mix package tree | The per-language validator compiles with warnings as errors and resolves an isolated path dependency. |
| 39 | Erlang | OTP/erlc | OTP application dependency | library | PASS | sshfling-VERSION OTP application tree | The per-language validator compiles package and consumer modules with erlc -Werror. |
| 40 | Haskell | Cabal | Cabal library and executable package | library + CLI | PASS | sshfling-VERSION Cabal package | The per-language validator performs an offline Cabal build and resolves both produced executables. |
| 41 | Clojure | Maven | Clojure/JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 41 | Clojure | Gradle | Clojure/JVM dependency | library | PASS | io.sshfling:sshfling-cli:VERSION | The package-java validator supplies the detailed PASS evidence below. |
| 42 | F# | NuGet | PackageReference library | library | PASS | SSHFling.VERSION.nupkg | The package-dotnet validator supplies the detailed PASS evidence below. |
| 43 | OCaml | opam/Dune | Dune-installed opam package | library + CLI | PASS | sshfling.VERSION source archive and Dune install | The per-language validator builds @install and installs it into an isolated Dune prefix. |
| 44 | Zig | Zig build | Zig module and executable package | library + CLI | PASS | Zig prefix with sshfling-zig command | The focused systems validator runs zig build with isolated local and global caches. |
| 45 | Nim | Nimble | Nimble source package | library + CLI | PASS | sshfling Nimble package and sshfling-nim validation command | The focused systems validator runs nim check, nim c, and nimble check with isolated caches. |
| 46 | Crystal | Shards/Crystal | Crystal shard dependency | library + CLI | PASS | sshfling shard and sshfling-crystal validation command | The focused systems validator parses the shard metadata and builds the CLI with isolated caches. |
| 47 | D | Dub/source build | D module and static-library dependency | library + CLI | PASS | libsshfling_d.a and sshfling-d validation artifacts | The focused systems validator compiles warning-clean D objects, archives a static library, and links the CLI. |
| 48 | V | VPM | V module and executable package | library + CLI | PASS | sshfling-v-VERSION.tar.gz | The systems validator extracts the deterministic archive, compiles the package and clean consumer with V, and runs both. |
| 49 | Ada | Alire/GNAT | Ada library unit and executable package | library + CLI | PASS | Ada units and sshfling-ada validation command | The focused systems validator uses GNAT 2022 checks with warnings promoted to errors. |
| 50 | Common Lisp | ASDF/Quicklisp | ASDF system dependency | library | PASS | sshfling-VERSION ASDF source archive | The per-language validator compiles the ASDF system from an isolated source registry. |
| 51 | Scheme/Racket | GNU Guile/Autotools | Guile module source package | library + CLI | PASS | sshfling-guile-VERSION.tar.gz | The per-language validator builds a dist archive, configures it, runs checks, and installs to an isolated prefix. |
| 52 | Prolog | SWI-Prolog pack | Prolog pack dependency | library | PASS | sshfling-VERSION.tgz Prolog pack | The per-language validator archives and pack-installs the package into an isolated directory. |
| 53 | Smalltalk | GNU Smalltalk package | Smalltalk package dependency | library + CLI | PASS | sshfling-smalltalk-VERSION.tar.gz | The per-language validator runs gst-package --dist and executes GNU Smalltalk consumers with the pinned GST runtime. |
| 54 | Tcl | Tcl package archive | versioned source package | library + CLI | PASS | sshfling-tcl-VERSION.tar.gz | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 55 | AWK | source archive | mawk-compatible source package | library + CLI | PASS | sshfling-awk-VERSION.tar.gz | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 57 | Zsh | source archive | sourceable shell module package | source module + CLI | PASS | sshfling-zsh-VERSION.tar.gz | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 58 | Fish | source archive | sourceable shell module package | source module + CLI | PASS | sshfling-fish-VERSION.tar.gz | The package-scripting-languages validator supplies the detailed PASS evidence below. |
| 60 | Guix Scheme | Guile source module | versioned Guile module package | library + CLI | PASS | sshfling-guix-scheme-VERSION.tar.gz | The scripting batch builds the archive and CI requires a PASS Guile runtime row at VERSION=0.1.19. |
| 60 | Guix Scheme | Guix | Guix package definition | library + CLI package | PASS | sshfling-guix-scheme-VERSION.tar.gz | The scripting batch validates the Guile module and records guix-definition PASS from guix build --dry-run --no-substitutes. |
| 64 | WebAssembly/WASI | WASI component/source | host-imported WASI command module | CLI module | PASS | sshfling-webassembly-wasi-VERSION.tar.gz | The systems validator extracts the archive, compiles wasm32-wasi code, and runs it through the tracked Node host adapter. |
| 65 | Elm | npm | Node port dependency | library consumer | PASS | sshfling-VERSION.tgz | elm make compiles a Platform.worker and its Node host validates the complete port round trip. |
| 66 | PureScript | npm | Node FFI dependency | library consumer | PASS | sshfling-VERSION.tgz | The PureScript compiler validates the foreign imports and the generated module executes under Node. |
| 67 | Reason/ReScript | npm | CommonJS binding dependency | library consumer | PASS | sshfling-VERSION.tgz | The ReScript compiler emits a CommonJS module and the Node test validates its exported status and templates. |
| 68 | Forth | Gforth/source package | loadable Forth source package | library + CLI | PASS | Forth words, native bridge, and cli.fs | The focused systems validator builds the native bridge and loads the Forth API with Gforth. |
| 69 | APL | GNU APL | GNU APL source package | library | PASS | sshfling-apl-VERSION.tar.gz | The per-language validator executes the pinned GNU APL runtime against a deterministic source archive. |
| 70 | J | J package | J addon dependency and command | library + CLI | PASS | sshfling-j-VERSION.tar.gz | The per-language validator installs the deterministic archive as an isolated J addon and runs its external consumer. |
| 71 | LabVIEW G | VIPM/LabVIEW project | System Exec VI integration | library VI + CLI adapter candidate | BLOCKED | none | BLOCKED runtime-validation: a licensed LabVIEW version/OS matrix and genuine VI package are required; no binary G source is fabricated |
| 73 | Q/KDB+ | KX q package | q namespace package | library | BLOCKED | sshfling-q-VERSION.tar.gz | BLOCKED runtime-validation: source publication passes, but the q runtime is unavailable for package and consumer validation |
| 74 | Hack | npm | server-side Hack adapter project | library consumer | PASS | sshfling-VERSION.tgz | HHVM 4.172 executes src/main.hack inside the hhvm/hhvm container with Node v22.23.1 after the Node bridge verifies the packed SSHFling npm API. |
| 75 | CFML | npm | server-side CFML adapter project | library consumer | PASS | sshfling-VERSION.tgz | CommandBox executes the CFML template after the Node bridge verifies the packed SSHFling npm API. |
| 76 | Wolfram Language | Mathics3 | Mathics-compatible source package | library | PASS | sshfling-wolfram-language-VERSION.tar.gz | The per-language validator executes Mathics3 against a deterministic Wolfram Language-compatible source archive. |
| 85 | Chapel | Mason | Chapel module and executable package | library + CLI | PASS | sshfling-chapel-VERSION.tar.gz | The systems-language validator extracts the deterministic archive, runs mason modules, compiles the package and external consumer with chpl, and executes both. |
| 86 | Pony | Corral | Pony package and executable | library + CLI | PASS | sshfling-pony-VERSION.tar.gz | The systems validator extracts the deterministic archive, compiles with ponyc, and runs an isolated consumer. |
| 87 | Janet | JPM | Janet module package and command | library + CLI | PASS | sshfling-janet-VERSION.tar.gz | The per-language validator installs from the deterministic archive into an isolated JPM tree and compiles the external consumer. |
| 88 | Odin | Odin source package | Odin collection and executable | library + CLI | PASS | sshfling-odin-VERSION.tar.gz | The systems validator extracts the archive, builds the Odin collection and command, and executes an isolated consumer. |
| 89 | Ballerina | Ballerina package | Ballerina module dependency | library | PASS | sshfling-ballerina-VERSION.tar.gz and grwlx-sshfling-any-VERSION.bala | The functional-language validator runs bal test, bal pack, local repository push, external consumer tests, and removal/import-failure checks. |
| 90 | Gleam | Gleam/Hex | Hex library package | library | PASS | sshfling-VERSION Hex tarball | The per-language validator runs gleam check, exports a Hex tarball, and builds an external consumer. |
| 91 | Roc | Roc source package | Roc package and application | library + CLI | PASS | sshfling-roc-VERSION.tar.gz | The functional-language validator records roc PASS with source archive, roc check/build, external consumer check/build, exact version, init, invalid option, missing runtime, removal, and import-absence evidence. |

<!-- END GENERATED FIRST-91 LIBRARY SURFACES -->
