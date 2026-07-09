# OpenSSH Dependency Policy

This document records SSHFling's dependency ownership, version, install,
uninstall, and original-state policy for OpenSSH and adjacent runtime tools.
It is based on the package metadata and installer scripts in this repository,
not on a claim about current package versions in external repositories.

SSHFling uses standard OpenSSH tools. It does not vendor, fork, pin, upgrade, or
remove OpenSSH. OpenSSH package versions are owned by the operating system,
container base image, package manager channel, MDM/Intune policy, or other fleet
configuration system that installs them.

## Evidence Sources

The policy below is grounded in these repository files:

| Area | Evidence |
| --- | --- |
| Debian / Ubuntu | `packaging/build-deb.sh` package control, maintainer scripts, and conffile list |
| RHEL / Fedora / Rocky / Alma | `packaging/build-rpm.sh` RPM spec and scriptlets |
| Public installer site | `packaging/build-public-web.sh` APT/RPM/Homebrew/macOS/Windows install and uninstall helpers |
| macOS pkg | `packaging/build-pkg.sh` package payload and `README.pkg.txt` notes |
| Windows MSI / zip | `packaging/build-msi.ps1` package notes, registry metadata, PATH component, and portable zip |
| Community package managers | `packaging/build-community-manifests.sh` generated Arch, Alpine, BSD, Nix, Guix, Void, Gentoo, Slackware, openSUSE, Snap, Termux, AppImage, Scoop, winget, and Chocolatey manifests |
| Runtime behavior | `bin/sshfling`, `production/sshfling-session`, `ssh-client/Dockerfile`, and `ssh-server/Dockerfile` |
| Release validation | `.github/workflows/package-install-tests.yml`, `.github/workflows/cross-os-validation.yml`, and `docs/build-targets.md` |

## Runtime Contract

Client mode needs Python 3 and OpenSSH client tools available on `PATH`.
Interactive and remote-command access use `ssh`; file-copy access through
`sshfling scp` uses native OpenSSH `scp`. The optional `sshfling rsync` command
requires `rsync` on the client and target host, but SSHFling does not vendor or
own that package.

Server-side certificate grants need OpenSSH server tooling on the target host.
The CLI validates managed sshd configuration with `sshd -t` and can inspect
effective configuration with `sshd -T`.

Server-side password grants are Linux-oriented. They require OpenSSH server
tooling, including `sshd`, plus local account management tools such as
`useradd` and `chpasswd`; `usermod` and `chage` are used when present to
unlock, lock, or expire temporary users. Session enforcement uses the packaged
`sshfling-session` wrapper and standard process utilities.

Docker Compose files and container images are a test harness. They are not the
normal production grant path.

Use `sshfling --json doctor --dependencies --mode MODE` to capture read-only
dependency evidence before install, host setup, or release validation. Supported
modes are:

| Mode | What it checks |
| --- | --- |
| `client` | OpenSSH client tools (`ssh`, `ssh-keygen`, `ssh-keyscan`) plus optional `scp` and `rsync`. |
| `password-server` | Linux password-grant prerequisites such as `sshd`, `useradd`, `chpasswd`, `id`, and optional lock/expiry/process tools. |
| `certificate-host` | Certificate-host prerequisites such as `sshd`, `ssh-keygen`, account tools used by `--create-user`, and process tools. |
| `all` | Every dependency mode above. |

The dependency inventory is evidence only. It reports whether tools are present
on `PATH`, their version where a stable version command exists, and whether a
required tool is missing. It does not install, remove, pin, or mark packages for
cleanup.

## Version Ownership

SSHFling release artifacts pin the SSHFling version. They do not pin OpenSSH,
Python, rsync, account-management, `procps`, or `util-linux` versions.

Package metadata declares required capabilities by package name. The selected
version is resolved by the target package manager, repository configuration,
base image, channel, or fleet-management policy at install time. If an
enterprise requires an exact OpenSSH version, that pin belongs in the fleet's
APT/RPM/Homebrew/Nix/Guix/pkgsrc/container/MDM/Intune controls, not in SSHFling
uninstall scripts or release notes.

## Install Ownership

SSHFling owns the files installed by its own package or manifest, including the
CLI, templates, packaged service files where present, and packaged SSHFling
configuration defaults.

The platform owns OpenSSH and other shared runtime packages:

| Platform or ecosystem | Declared dependency behavior |
| --- | --- |
| Debian / Ubuntu APT | `.deb` depends on `python3`, `openssh-client`, `passwd`, `procps`, and `util-linux`; it suggests `openssh-server`, `rsync`, and Docker-compatible packages. |
| RHEL / Fedora / Rocky / Alma RPM | `.rpm` requires `python3`, `openssh-clients`, `shadow-utils`, `procps-ng`, and `util-linux`; it recommends `openssh-server` for server-side grant paths and `rsync` for rsync transfers. |
| Arch / AUR | Generated `PKGBUILD` depends on `python`, `openssh`, `shadow`, `procps-ng`, and `util-linux`. |
| Alpine | Generated `APKBUILD` depends on `python3`, `openssh-client`, `shadow`, `procps`, and `util-linux`. |
| openSUSE / OBS | Generated spec requires `python3`, `openssh`, `shadow`, `procps`, and `util-linux`. |
| Void, Gentoo, Guix, Nix, Snap, Termux, AppImage | Generated manifests include the closest ecosystem packages for Python, OpenSSH, account/process tools, and util-linux where that ecosystem supports them. Versions come from the ecosystem input channel or build environment. |
| FreeBSD Ports, OpenBSD Ports, pkgsrc | Generated BSD manifests declare Python integration or dependencies. They do not claim ownership of the host's OpenSSH service configuration or exact OpenSSH package version. |
| macOS pkg | The pkg installs SSHFling files and `/etc/sshfling/policy.json`; it does not bundle Python or OpenSSH. |
| Homebrew | Generated formula depends on `python@3`; OpenSSH client/server availability remains host or fleet policy. |
| Windows MSI | MSI installs under `Program Files\SSHFling`, adds that directory to machine `PATH`, and records dependency scope in `HKLM\Software\SSHFling`; it does not bundle Python, OpenSSH, or Windows OpenSSH Server. |
| Windows portable zip, Scoop, winget, Chocolatey | Portable zip and generated Windows manifests use the packaged zip or MSI. They do not add independent Python or OpenSSH ownership. |
| Containers | Test images install their own OpenSSH packages inside the image. The host's OpenSSH install is unaffected. |

## Uninstall Ownership

Package uninstall removes SSHFling-managed package files for the selected
install path. It is not a dependency rollback mechanism.

Linux uninstall examples intentionally avoid dependency cleanup commands such as
`apt autoremove`, `apt autopurge`, `dnf autoremove`, and `yum autoremove`. The
DNF example uses `--setopt=clean_requirements_on_remove=False` when removing
only SSHFling. Dependency cleanup must be a separate reviewed fleet action.

APT `remove` removes the package but preserves conffiles. APT `purge` can remove
SSHFling conffiles such as `/etc/sshfling/policy.json` and
`/etc/sshfling/sshflingd.env`; it still does not remove OpenSSH, host SSH
configuration created outside the package, temporary grant state, or CA
material. SSHFling runbooks should use `remove` unless the fleet has explicitly
approved conffile cleanup.

RPM uninstall removes the package and repository registration in the published
example. The RPM scriptlets preserve packaged `/etc/sshfling` configuration
during erase so local policy/configuration can be reviewed separately.

The Linux packages record whether the package-created `sshflingd` user, group,
and `/var/lib/sshflingd` directory existed before install. They remove those
package-created account resources only when it is safe and no SSHFling config or
state directory remains, and only when the current UID/GID/home identity still
matches the package-created account record. That record is limited to SSHFling
service account state; it is not an OpenSSH or dependency inventory. The
install-state record is kept under root-owned
`/var/lib/sshfling/package-state`, not under the service-owned
`/var/lib/sshflingd` runtime tree. Normal uninstall cleanup removes that
record; when a UID/GID/home mismatch causes the package-created service account
to be preserved, the record can remain with the preserved account for review.

Homebrew uninstall removes the formula's installed SSHFling files. It does not
restore host OpenSSH or Python to an earlier state.

The .NET global tool package removes the user-level `SSHFling.Tool`
registration only. It does not uninstall Python, OpenSSH, Docker, host
account-management tools, host SSH configuration, or SSHFling project state.

The macOS pkg uninstall helper removes `/usr/local/bin/sshfling` and
`/usr/local/share/sshfling`, then forgets the pkg receipt. It intentionally
preserves `/etc/sshfling`.

MSI uninstall removes the installed SSHFling product directory and the PATH
entry added by the MSI. It does not uninstall Python, OpenSSH, Windows OpenSSH
Server, host SSH configuration, temporary grant state, CA material, or policy
stored outside the install directory. For the portable Windows zip, remove the
extracted directory and only PATH entries your deployment added.

BSD and community package-manager uninstalls follow the owning package manager's
normal file-removal behavior. They do not imply rollback of OpenSSH, Python, or
base-system SSH configuration unless the local package manager and fleet policy
explicitly manage that rollback.

Container cleanup removes containers, images, networks, or volumes selected by
the operator. It does not change host OpenSSH packages. Exact image dependency
state requires recording the image digest and build inputs.

## Host SSH State

OpenSSH server configuration changed by SSHFling commands is application state,
not package-manager dependency state.

Use `sshfling host uninstall` to remove managed certificate host SSH
configuration. By default it removes the managed sshd snippet and the selected
user's authorized-principals file. Shared CA, wrapper, policy-user, and Unix
account removal are opt-in flags. Unix-account deletion requires the
SSHFling-created host-user marker written by `host install --create-user`.

Use `sshfling password prune --all` to clean expired tracked password grants,
or `sshfling password prune --username USER` for targeted cleanup. Prune
requires exactly one selector. It removes expired grants only; `--delete-users`
deletes expired SSHFling-created Unix users only when UID/GID/home identity
evidence is present and still matches the current account. Without identity
evidence, `--delete-users` locks and expires instead of deleting; with an
identity mismatch, prune preserves managed config and metadata for
investigation. Existing users explicitly allowed with `--allow-existing-user`
are locked and expired but not deleted. Root-equivalent users are never mutated
from password-grant metadata or host-user markers, and password grant creation
refuses root-equivalent Unix users.

Use `sshfling cert prune --all` or `sshfling cert prune --username USER` to
remove expired SSHFling-generated client key and certificate material from the
managed certificate session directory. Certificate prune only removes material
that SSHFling generated and tracked; it does not remove operator-supplied keys
or certificates outside that directory.

Package uninstall does not run those host-state cleanup commands automatically.
That separation is intentional so package removal does not destroy CA material,
local access policy, audit evidence, or active incident-response state.

For release or incident evidence, capture dependency state and host cleanup
state separately:

```bash
sshfling --json doctor --dependencies --mode all
sudo sshfling --json password prune --all --delete-users
```

## Original-State Evidence

SSHFling uninstall does not guarantee exact restoration to the preinstall state.
Exact restoration requires original-state evidence recorded before deployment.

Recommended evidence by environment:

| Environment | Evidence to record outside SSHFling |
| --- | --- |
| Linux fleets | Package inventory and manual/auto dependency marks, repository configuration, `/etc/ssh` and `/etc/sshfling` baselines, service-account inventory, and configuration-management state. |
| macOS fleets | MDM inventory, package receipts, Homebrew bundle or fleet policy, `/etc/ssh` and `/etc/sshfling` baselines, and backup records. |
| Windows fleets | Intune/SCCM/Group Policy app inventory, Python inventory, Windows OpenSSH capability state, MSI product inventory, machine PATH baseline, and backup records. |
| BSD fleets | `pkg`/ports/pkgsrc inventory, `/etc` and localbase configuration baselines, and backup or configuration-management records. |
| Containers | Image digest, Dockerfile or build recipe, package index state, runtime volume list, and compose or orchestrator configuration. |
| Nix / Guix | Flake/channel or Guix revision, profile generation, store path, and garbage-collection policy. |

If dependency cleanup is required, treat it as a fleet change with its own
review, evidence, rollback plan, and owner.
