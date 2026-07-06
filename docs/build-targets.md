# SSHFling Build Targets

This is the build and packaging target matrix for public distribution.

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

## Automated Verification

`packaging/verify-public-web.sh` checks the generated package site for every target above. The public web release workflow runs this verifier before uploading the GitHub Pages artifact.

`tests/cross-os/validate-cli.sh` and `tests/cross-os/validate-cli.ps1` verify the stable runtime contract used by release validation, including the 24-hour policy default, copied wrapper and systemd templates, active-session PID fields, and detached job start/list/kill PID behavior.

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

Client mode only needs Python and OpenSSH client tools. Server-side certificate grants need OpenSSH server tooling on the target host. Server-side password grants are Linux-oriented because they need account-management tools such as `useradd`, `chpasswd`, `usermod`, and `chage`.

`.github/workflows/package-install-tests.yml` remains a smaller public-package
install smoke for the primary release artifacts.
