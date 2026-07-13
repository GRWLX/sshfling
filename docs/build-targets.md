# SSHFling Build Targets

This is the build and packaging target matrix for public distribution.

OpenSSH and adjacent runtime dependency ownership, version, install, uninstall,
and original-state policy is tracked in
[openssh-dependencies.md](openssh-dependencies.md).

SSHFling is licensed under the Apache License, Version 2.0. Redistributing or
submitting generated manifests to third-party repositories must preserve the
LICENSE file and any required notices.

## Built Release Artifacts

These artifacts are built directly by GitHub Actions on every version tag.

| Target OS / family | Artifact or repo output | Install path |
| --- | --- | --- |
| Debian | `.deb` plus APT metadata | `apt install sshfling` from the Pages APT repo |
| Ubuntu | `.deb` plus APT metadata | `apt install sshfling` from the Pages APT repo |
| RHEL | `.rpm` plus RPM repo metadata | `dnf install sshfling` or `yum install sshfling` |
| Fedora | `.rpm` plus RPM repo metadata | `dnf install sshfling` |
| Rocky Linux | `.rpm` plus RPM repo metadata | `dnf install sshfling` |
| AlmaLinux | `.rpm` plus RPM repo metadata | `dnf install sshfling` |
| Cross-platform .NET | `SSHFling.Tool.VERSION.nupkg`, `SSHFling.VERSION.nupkg` | Install the global tool or reference the `SSHFling` NuGet library from a verified package source |
| Cross-platform JVM | `sshfling-cli-VERSION.jar`, sources/Javadocs JARs, `sshfling-cli-VERSION.pom` | Run the JAR or consume `io.sshfling:sshfling-cli:VERSION` from Java, Kotlin, Scala, or Groovy |
| Cross-platform Node.js/npm | `sshfling-VERSION.tgz` | `npm install -g sshfling-VERSION.tgz` after checksum verification |
| Cross-platform Python | `sshfling-VERSION-py3-none-any.whl` | `pipx install sshfling-VERSION-py3-none-any.whl` after checksum verification |
| Cross-platform Go | `sshfling-go-VERSION.zip` | Extract, then `go install ./cmd/sshfling` |
| Cross-platform Rust | `sshfling-cli-VERSION.crate` | Extract, then `cargo install --path sshfling-cli-VERSION` |
| Cross-platform PHP | `sshfling-php-VERSION.zip` | Composer artifact repository install as `grwlx/sshfling` |
| Cross-platform Ruby | `sshfling-VERSION.gem` | `gem install --local sshfling-VERSION.gem` |
| POSIX C/C++ | `sshfling-native-VERSION.tar.gz` | Build and install shared/static libraries, CMake exports, pkg-config metadata, and `sshfling-c` |
| Perl 5.26+ | `sshfling-perl-VERSION.tar.gz` | Build/test/install the `SSHFling` module and executable with ExtUtils::MakeMaker |
| macOS | `.pkg` and Homebrew formula | `brew install` or `installer -pkg` |
| Windows | `.msi` and portable zip | MSI installer, winget, Scoop, or Chocolatey |

## Generated Community Targets

These files are generated into the public package site. Some can be used directly. Official/community repos still require submission, maintainer account setup, signing, or review.

| Target OS / ecosystem | Generated files |
| --- | --- |
| Arch Linux / AUR | `arch/PKGBUILD`, `arch/.SRCINFO` |
| Alpine Linux | `alpine/APKBUILD` |
| FreeBSD Ports | `freebsd/security/sshfling` |
| OpenBSD Ports | `openbsd/security/sshfling` |
| NetBSD | `pkgsrc/security/sshfling` |
| DragonFly BSD | `pkgsrc/security/sshfling` |
| illumos | `pkgsrc/security/sshfling` |
| SmartOS | `pkgsrc/security/sshfling` |
| Nix / NixOS | `nix/flake.nix` |
| Guix | `guix/sshfling.scm` |
| Void Linux | `void/template` |
| Gentoo | `gentoo/app-admin/sshfling` |
| Slackware | `slackware/sshfling.SlackBuild`, `slackware/slack-desc`, `slackware/slack-required` |
| openSUSE / OBS | `opensuse/sshfling.spec` |
| Snapcraft | `snap/snapcraft.yaml` |
| Termux / Android | `termux/packages/sshfling/build.sh` |
| AppImage | `appimage/AppImageBuilder.yml` |
| Scoop | `scoop/sshfling.json` |
| winget | `winget/manifests/.../SSHFling/...` |
| Chocolatey | `chocolatey/sshfling.VERSION.nupkg`, `chocolatey/sshfling.nuspec` |

Generated package files and manifests are release inputs. They do not mean
SSHFling is accepted into Debian, Ubuntu, Fedora, EPEL, or another distro-owned
repository. Track official Debian/Ubuntu/Fedora/EPEL readiness in
[official-distro-readiness.md](official-distro-readiness.md).

## Platform Coverage Evidence Expectations

The tables above describe artifacts and generated packaging metadata, not a
blanket support claim for every OS, language runtime, CPU architecture, hardware
class, or embedded target that can consume those files. Language/runtime claim
rules are tracked in [language-support.md](language-support.md); implemented
package, deployment, and library checks are tracked in
[language-deployment-support.md](language-deployment-support.md).

Each enterprise release must keep a compact platform coverage declaration in
the release evidence packet. Do not commit large generated OS-by-architecture
matrices to the repo; generated release evidence belongs under the ignored
`docs/release/enterprise-release-evidence/` tree and should be attached or
linked from the release ticket.

Minimum platform coverage evidence:

| Coverage area | Expected release evidence |
| --- | --- |
| OS and distribution versions | Exact OS name, version, package format, install path, validation workflow run, and exception record for any advertised-but-untested version. |
| Language and runtime dependencies | Python implementation/version, shell or PowerShell version where relevant, OpenSSH client/server versions, and account-management tool availability for password grants. |
| OS-native command execution | A root-owned POSIX login-shell dispatcher clears startup-file variables and untrusted interpreter paths before the Bash forced-session wrapper; policy parsing uses `jq`, with root-managed connection slots held by `flock` or BSD/macOS `lockf`; Unix identity lookup uses POSIX shell with `getent` or macOS directory-service commands; Linux account mutation uses Bash with shadow tools; Windows package/install behavior uses PowerShell. Python remains the shared CLI/runtime and release-tooling language, not the privileged OS-operation backend. |
| CPU architecture | Architecture reported by the validation host or package metadata, with explicit status for `x86_64`/`amd64`, `arm64`/`aarch64`, and any 32-bit, `s390x`, `ppc64le`, or `riscv64` claims. |
| Hardware class | Evidence that the release was validated on the claimed class, such as server VM, desktop workstation, container image, edge appliance, IoT gateway, or customer-managed embedded Linux host. |
| ARM and IoT targets | For ARM, Raspberry Pi OS, OpenWrt, Yocto, Buildroot, or similar edge systems, record whether SSHFling was tested as client-only, certificate server, or password-grant server and which required host tools were present. |
| FPGA and SoC platforms | Evidence applies only to the host CPU/OS control plane running Python and OpenSSH. Do not imply FPGA fabric, bitstream, accelerator, or vendor toolchain support unless separately validated and approved. |
| Unsupported or deferred targets | Release-ticket exception with owner, customer impact, compensating control, expiration, and retest trigger. |

## Automated Verification

`packaging/verify-public-web.sh` checks the generated package site for every target above. The public web release workflow runs this verifier before uploading the GitHub Pages artifact.

`tests/cross-os/validate-cli.sh` and `tests/cross-os/validate-cli.ps1` verify
the stable runtime contract used by release validation, including the explicit
grant lifetime requirement, 24-hour cap, copied wrapper and systemd templates,
active-session PID fields, and detached job start/list/kill PID behavior.

`.github/workflows/container-image-tests.yml` validates the Docker-based local
install path with `make test-containers`. It builds the generated package
artifacts into containers, installs them, and exercises the SSHFling server and
client images against each other.

For a manual public package validation pass, run the workflows in this order
with the same version input:

1. `Container image tests`
2. `Release packages without web`
3. `Release packages with public web`
4. `pages-build-deployment`
5. `Package install tests`
6. `Cross OS validation`

After `Release packages with public web` deploys the GitHub Pages package site,
the downstream install workflows validate the newly published package site.

`.github/workflows/cross-os-validation.yml` is the broad manual post-release
workflow that installs or builds the published package outputs on:

- Debian bookworm, Ubuntu 24.04, Fedora latest, Rocky Linux 9, AlmaLinux 9, and UBI 9 from the public APT/RPM repos.
- Arch Linux and Alpine Linux from the generated `PKGBUILD` and `APKBUILD`.
- openSUSE Tumbleweed from the generated OBS spec.
- Nix from the generated flake.
- Slackware 15.0 from the generated SlackBuild.
- Void Linux from the generated `xbps-src` template.
- FreeBSD 14.4, OpenBSD 7.9, and NetBSD 10.1 source-runtime smoke tests.
- pfSense/OPNsense FreeBSD-family substrate coverage for enterprise-safe public
  x86_64 FreeBSD VM releases currently supported by VMActions: 13.2, 13.3,
  13.4, 13.5, 14.0, 14.1, 14.2, 14.3, 14.4, 15.0, and 15.1. FreeBSD 12.x
  firewall lines are documented as historical coverage only because the public
  CI bootstrap path now depends on an unsigned archive. See
  [firewall-os.md](firewall-os.md) and
  [firewall-os-versions.md](firewall-os-versions.md).
- macOS from the published `.pkg` and generated Homebrew formula.
- Windows from the published MSI and portable zip.
- .NET global tool and NuGet library from the published `SSHFling.Tool.VERSION.nupkg` and `SSHFling.VERSION.nupkg` packages.
- JVM executable and library consumers through direct JAR, Java Maven/Gradle,
  Kotlin Maven/Gradle, Scala Maven/Gradle, and Groovy Maven/Gradle paths,
  including sources and Javadocs.
- Node.js/npm package from the published `sshfling-VERSION.tgz` package.
- Python 3.10 through current supported CPython releases from the universal wheel.
- Go module source archive through `go test`, `go vet`, and clean `go install`.
- Rust crate through Cargo test, Clippy, package verification, install, and uninstall.
- PHP Composer archive through strict metadata, PSR-4 autoload, install, and removal.
- Ruby gem through RubyGems and Bundler install paths.
- POSIX C/C++ source distribution through warning-clean Ninja/Release and
  Make/Debug CMake/CTest builds, ASan/UBSan tests, shared and static external
  consumers, pkg-config, CLI, and removal checks.
- Perl source distribution through MakeMaker tests, isolated module/CLI
  installation, runtime initialization, and prefix removal.

Client mode only needs Python and OpenSSH client tools. Server-side certificate
grants need OpenSSH server tooling on the target host. Server-side password
grants are Linux-oriented because they need account-management tools such as
`useradd`, `chpasswd`, `usermod`, and `chage`. Package uninstall removes
SSHFling package files for the selected install path, not shared Python,
OpenSSH, account-management, `procps`, or `util-linux` dependency state. See
[openssh-dependencies.md](openssh-dependencies.md) for the platform-specific
dependency matrix and original-state evidence requirements.

`.github/workflows/package-install-tests.yml` remains a smaller public-package
install smoke for the primary release artifacts.
