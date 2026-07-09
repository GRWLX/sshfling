# SSHFling Library APIs

SSHFling ships importable launcher libraries for Python, JavaScript/TypeScript,
Java, C#, Visual Basic, F#, Go, Rust, PHP, Ruby, C, C++, and Perl. Every API
runs the bundled SSHFling Python runtime with inherited standard streams and
returns or reports its exit status. Python 3 and the applicable OpenSSH tools
remain host dependencies.

These are launcher APIs around the CLI contract, not an in-process SSH server
SDK. The package, clean-consumer, and deployment evidence is tracked in
[language-deployment-support.md](language-deployment-support.md).

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

## Java

Coordinates: `io.sshfling:sshfling-cli:VERSION`. Both Maven and Gradle clean
consumer projects are validated.

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
