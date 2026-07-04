# SSHFling Build Targets

This is the build and packaging target matrix for public distribution.

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

`packaging/verify-public-web.sh` checks the generated package site for every target above. The public web release workflow runs this verifier before publishing `gh-pages`.

`.github/workflows/package-install-tests.yml` is a manual post-release workflow that installs or builds the published package outputs on:

- Debian bookworm, Ubuntu 24.04, Fedora latest, Rocky Linux 9, AlmaLinux 9, and UBI 9 from the public APT/RPM repos.
- Arch Linux and Alpine Linux from the generated `PKGBUILD` and `APKBUILD`.
- openSUSE Leap 15.6 from the generated OBS spec.
- Nix from the generated flake.
- Slackware 15.0 from the generated SlackBuild.
- Void Linux from the generated `xbps-src` template.
- FreeBSD 14.4, OpenBSD 7.9, and NetBSD 10.1 source-runtime smoke tests.
- macOS from the published `.pkg` and generated Homebrew formula.
- Windows from the published MSI and portable zip.

Client mode only needs Python and OpenSSH client tools. Server-side certificate grants need OpenSSH server tooling on the target host. Server-side password grants are Linux-oriented because they need account-management tools such as `useradd`, `chpasswd`, `usermod`, and `chage`.
