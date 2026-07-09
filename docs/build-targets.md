# SSHFling Build Targets

This is the build and packaging target matrix for public distribution.

OpenSSH and adjacent runtime dependency ownership, version, install, uninstall,
and original-state policy is tracked in
[openssh-dependencies.md](openssh-dependencies.md).

SSHFling is proprietary commercial software. Installing, running, redistributing,
or submitting generated manifests to third-party repositories requires the rights
described in the project LICENSE or a separate written agreement from GRWLX.

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
| Cross-platform .NET | `SSHFling.Tool.VERSION.nupkg` | `dotnet tool install --global SSHFling.Tool` from a verified local package source |
| Cross-platform Java | `sshfling-cli-VERSION.jar`, `sshfling-cli-VERSION-sources.jar`, `sshfling-cli-VERSION.pom` | `java -jar sshfling-cli-VERSION.jar` after checksum verification, or Maven from GitHub Packages |
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
| Slackware | `slackware/sshfling.SlackBuild`, `slackware/slack-desc` |
| openSUSE / OBS | `opensuse/sshfling.spec` |
| Snapcraft | `snap/snapcraft.yaml` |
| Termux / Android | `termux/packages/sshfling/build.sh` |
| AppImage | `appimage/AppImageBuilder.yml` |
| Scoop | `scoop/sshfling.json` |
| winget | `winget/manifests/.../SSHFling/...` |
| Chocolatey | `chocolatey/sshfling.VERSION.nupkg`, `chocolatey/sshfling.nuspec` |

## Platform Coverage Evidence Expectations

The tables above describe artifacts and generated packaging metadata, not a
blanket support claim for every OS, language runtime, CPU architecture, hardware
class, or embedded target that can consume those files.

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
- openSUSE Leap 15.6 from the generated OBS spec.
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
- .NET global tool from the published `SSHFling.Tool.VERSION.nupkg` package.

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
