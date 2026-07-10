# SSHFling Install and Uninstall Runbook

This runbook gives explicit install and uninstall commands by operating system
and package channel. Replace `OWNER`, `REPO`, and `VERSION` with the release
owner, repository name, and package version from the approved release record.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
```

SSHFling is proprietary commercial software. Installing, running,
redistributing, or submitting generated manifests to third-party repositories
requires the rights described in the project LICENSE or a separate written
agreement from GRWLX.

## Enterprise Rules

- Verify the approved release checksums before installing raw package files.
- For APT and RPM repositories, verify the approved repository signing key
  fingerprint before adding the repo to a managed host.
- Package uninstall removes SSHFling-managed package files for the selected
  install channel. It is not a host-state rollback.
- Primary DEB/RPM/pkg/MSI uninstall paths do not remove `/etc/sshfling`, local
  CA material, host SSH configuration created by `sshfling host install`,
  temporary password grant state, audit records, Python, OpenSSH,
  account-management tools, `procps`, or `util-linux`. Generated community
  manifests need ecosystem-specific review because not every package manager
  has the same config-preservation semantics.
- `sshfling scp` uses the platform OpenSSH client. `sshfling rsync` is an
  optional transfer path and requires `rsync` on the client and target host; it
  is not bundled, pinned, installed, or removed by SSHFling package uninstall.
- For production macOS pkg distribution, require an Apple Developer ID Installer
  signature, notarization, stapling verification, and release-ticket evidence,
  or record a time-bound exception before deployment.
- Do not run dependency cleanup commands such as `apt autoremove`,
  `apt autopurge`, `dnf autoremove`, or `yum autoremove` as part of SSHFling
  package removal unless that cleanup is separately approved by fleet policy.
- If exact revert is required, record the original package inventory, dependency
  marks, repository state, host SSH configuration, service accounts, PATH, MDM
  inventory, and backups before deployment.

Optional host-state cleanup before package removal:

```bash
sshfling --json doctor --dependencies --mode all
sudo sshfling shutdown || true
sudo sshfling --json password prune --all --delete-users
sudo sshfling --json cert prune --all
sudo sshfling host uninstall --username temp-remote --dry-run
sudo sshfling host uninstall --username temp-remote --reload
sudo systemctl disable --now sshflingd 2>/dev/null || true
```

`sshfling doctor --dependencies` is read-only evidence; it does not install or
remove OpenSSH, Python, account-management tools, or process tools. Password
prune requires exactly one selector: `--all` to scan the tracked grant store or
`--username USER` for targeted cleanup. It only removes expired grants and
leaves active grants in place. By default, expired SSHFling-created Unix users
are locked and expired; `--delete-users` deletes expired SSHFling-created users
only after managed sshd config removal is verified and SSHFling has recorded
UID/GID/home identity evidence. If the current Unix UID/GID/home does not match
SSHFling grant metadata, prune skips deletion and preserves the managed config
and metadata for investigation. Existing users that were explicitly allowed
with `--allow-existing-user` are locked and expired but are never deleted by
`--delete-users`. Root-equivalent users are never mutated from password-grant
metadata or host-user markers.

Certificate prune removes expired SSHFling-generated client key and certificate
material from the managed certificate session directory. It requires exactly
one selector: `--all` to scan tracked generated certificate sessions or
`--username USER` for targeted cleanup. It does not remove operator-supplied
keys or certificate files outside the managed session directory.

The repository DEB and primary RHEL-family RPM artifacts ship and enable
`sshfling-prune.timer` on systemd hosts. Generated RPM ecosystem packages do
not all carry these scriptlets. The timer runs the guarded password and
certificate prune commands periodically.
Before release, capture `systemctl status sshfling-prune.timer` and
`journalctl -u sshfling-prune.service` evidence from an actual target host.

Use `sshfling host uninstall --delete-user` only for Unix accounts created by
`sshfling host install --create-user`. SSHFling requires its host-user marker
before deleting the Unix account. Shared CA, wrapper, policy-user, and account
removal are opt-in host cleanup actions, not package uninstall side effects.
The live root-owned `sshfling-login-shell` dispatcher is preserved because a
Unix passwd entry may still reference it. Remove it manually only after native
account inspection proves that no remaining user has that login-shell path.
If setup rollback cannot confirm deletion of a newly created account, SSHFling
also preserves the installed wrapper and the account-specific enforcement
config plus any ownership metadata or marker already written. This intentionally
favors a forced, traceable login path over restoring files while a managed
passwd entry survives; resolve the identity mismatch or deletion failure before
removing those files.

## Linux DEB Package

Use this path for a local `.deb` artifact or a package downloaded from the
public package site.

Install from a local build output:

```bash
sudo apt install ./dist/sshfling_${VERSION}_all.deb
sshfling --version
```

Install a raw `.deb` from the public package site with checksum verification:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/apt/sshfling_${VERSION}_all.deb" -o "$tmp/sshfling_${VERSION}_all.deb"
curl -fsSL "${BASE_URL}/apt/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  sshfling_${VERSION}_all.deb$" "$tmp/SHA256SUMS" > "$tmp/sshfling.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling.SHA256SUMS)
sudo apt install "$tmp/sshfling_${VERSION}_all.deb"
sshfling --version
```

Uninstall the DEB package without dependency cleanup:

```bash
sudo apt remove -y sshfling
```

Use `apt purge sshfling` only when a reviewed fleet runbook intentionally
removes SSHFling conffiles such as `/etc/sshfling/policy.json` or
`/etc/sshfling/sshflingd.env`. Purge still does not remove OpenSSH, Python, host
SSH configuration, temporary grant state, or CA material.

DEB maintainer scripts record only SSHFling package-created service account
state under root-owned `/var/lib/sshfling/package-state`. Purge removes that
package state during normal cleanup and removes the package-created
`sshflingd` user/group only when the record says they did not preexist, no
SSHFling config/state directory remains, and the current UID/GID/home still
matches the recorded package-created identity. If identity mismatch causes the
package-created account to be preserved, the package-state record can remain
with it for review.

## Linux RPM Package

Use this path for a local `.rpm` artifact or a package downloaded from the
public package site.

Install from a local build output:

```bash
sudo dnf install ./dist/sshfling-${VERSION}-1.noarch.rpm
sshfling --version
```

Use `yum localinstall` on older yum-only hosts:

```bash
sudo yum localinstall ./dist/sshfling-${VERSION}-1.noarch.rpm
```

Install a raw `.rpm` from the public package site with checksum verification:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/rpm/sshfling-${VERSION}-1.noarch.rpm" -o "$tmp/sshfling-${VERSION}-1.noarch.rpm"
curl -fsSL "${BASE_URL}/rpm/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  sshfling-${VERSION}-1.noarch.rpm$" "$tmp/SHA256SUMS" > "$tmp/sshfling.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling.SHA256SUMS)
sudo dnf install "$tmp/sshfling-${VERSION}-1.noarch.rpm"
sshfling --version
```

Uninstall the RPM package without dependency cleanup:

```bash
sudo dnf --setopt=clean_requirements_on_remove=False remove -y sshfling
```

Use this on older yum-only hosts:

```bash
sudo yum remove -y sshfling
```

RPM scriptlets use root-owned `/var/lib/sshfling/package-state` for install
state and `/var/lib/sshfling/rpm-preserve-config` only as a transient erase
scratch area. They do not read lifecycle state from the service-owned
`/var/lib/sshflingd` tree. A normal RPM erase preserves `/etc/sshfling`
configuration and therefore leaves package-state evidence for review. Package
state is removed only when no preserved SSHFling config/state remains and the
package-created service account can be cleaned safely; identity mismatch
preservation can also keep the package-state record with the preserved service
account for review.

## Public APT Repository

Use this path for Debian and Ubuntu fleet installs from the published Pages
package site.

Install:

```bash
: "${APPROVED_REPO_FINGERPRINT:?set this from the approved release evidence}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/sshfling-repo-fingerprint.txt" -o "$tmp/sshfling-repo-fingerprint.txt"
published_fingerprint="$(tr -d '[:space:]' <"$tmp/sshfling-repo-fingerprint.txt" | tr '[:lower:]' '[:upper:]')"
test "$published_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
curl -fsSL "${BASE_URL}/sshfling-repo.gpg" -o "$tmp/sshfling-repo.gpg"
actual_fingerprint="$(gpg --batch --show-keys --with-colons "$tmp/sshfling-repo.gpg" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
test "$actual_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
sudo install -d -m 0755 /usr/share/keyrings
sudo install -m 0644 "$tmp/sshfling-repo.gpg" /usr/share/keyrings/sshfling-repo.gpg
echo "deb [signed-by=/usr/share/keyrings/sshfling-repo.gpg] ${BASE_URL}/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list
sudo apt update
sudo apt install -y sshfling
sshfling --version
```

Uninstall and unregister the APT repository:

```bash
sudo apt remove -y sshfling
sudo rm -f \
  /etc/apt/sources.list.d/sshfling.list \
  /etc/apt/preferences.d/sshfling \
  /usr/share/keyrings/sshfling-repo.gpg
sudo apt update
```

## Public RPM Repository

Use this path for RHEL-family fleet installs from the published Pages package
site, including RHEL, Fedora, Rocky Linux, AlmaLinux, and UBI.

Install:

```bash
: "${APPROVED_REPO_FINGERPRINT:?set this from the approved release evidence}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/sshfling-repo-fingerprint.txt" -o "$tmp/sshfling-repo-fingerprint.txt"
published_fingerprint="$(tr -d '[:space:]' <"$tmp/sshfling-repo-fingerprint.txt" | tr '[:lower:]' '[:upper:]')"
test "$published_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
curl -fsSL "${BASE_URL}/sshfling-repo.asc" -o "$tmp/sshfling-repo.asc"
actual_fingerprint="$(gpg --batch --show-keys --with-colons "$tmp/sshfling-repo.asc" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
test "$actual_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
sudo install -d -m 0755 /etc/pki/rpm-gpg
sudo install -m 0644 "$tmp/sshfling-repo.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
sudo tee /etc/yum.repos.d/sshfling.repo >/dev/null <<EOF
[sshfling]
name=SSHFling
baseurl=${BASE_URL}/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
EOF
sudo dnf install -y sshfling
sshfling --version
```

Use `sudo yum install -y sshfling` on older yum-only hosts.

Uninstall and unregister the RPM repository:

```bash
sudo dnf --setopt=clean_requirements_on_remove=False remove -y sshfling
sudo rm -f /etc/yum.repos.d/sshfling.repo /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
```

Use this on older yum-only hosts:

```bash
sudo yum remove -y sshfling
sudo rm -f /etc/yum.repos.d/sshfling.repo /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
```

## Public Installer Wrapper

The generated `install.sh` wrapper is a convenience path for interactive hosts.
Use the signed APT and RPM repo commands above as the production trust anchor
for managed Linux fleets.

Install with auto-detection:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/install.sh" -o "$tmp/install.sh"
bash "$tmp/install.sh" install auto
```

Install with an explicit channel:

```bash
bash "$tmp/install.sh" install apt
bash "$tmp/install.sh" install dnf
bash "$tmp/install.sh" install brew
```

Uninstall with an explicit channel:

```bash
bash "$tmp/install.sh" uninstall apt
bash "$tmp/install.sh" uninstall dnf
bash "$tmp/install.sh" uninstall brew
```

For fleet uninstall, prefer the direct package-manager commands in the
platform-specific sections so removal does not depend on downloading a mutable
helper script at uninstall time.

## macOS Homebrew

Install from the generated public formula:

```bash
brew install "${BASE_URL}/homebrew/sshfling.rb"
sshfling --version
```

Uninstall:

```bash
brew uninstall sshfling
```

Homebrew uninstall removes the formula's SSHFling files. It does not restore
host Python or OpenSSH to an earlier state.

## macOS pkg

Production build signing and notarization:

```bash
SSHFLING_VERSION="$VERSION" \
SSHFLING_PKG_REQUIRE_SIGNING=1 \
SSHFLING_PKG_SIGN_IDENTITY="Developer ID Installer: YOUR ORG (TEAMID)" \
SSHFLING_PKG_REQUIRE_NOTARIZATION=1 \
SSHFLING_PKG_NOTARY_PROFILE="sshfling-notary-profile" \
./packaging/build-pkg.sh

pkgutil --check-signature "dist/sshfling-${VERSION}.pkg"
xcrun stapler validate "dist/sshfling-${VERSION}.pkg"
spctl -a -vv -t install "dist/sshfling-${VERSION}.pkg"
```

Use `SSHFLING_PKG_SIGN_KEYCHAIN=/path/to/keychain` when the signing identity is
not on the default keychain search path. Use
`SSHFLING_PKG_SIGN_TIMESTAMP=none` only for offline test builds; production
Developer ID signatures should carry a trusted timestamp.

Install with the generated helper, which verifies SHA-256, package signature,
notarization stapling, and Gatekeeper assessment before running `installer`:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/macos/install-pkg.sh" -o "$tmp/install-pkg.sh"
sudo bash "$tmp/install-pkg.sh"
sshfling --version
```

For enterprise macOS deployment, also attach the package signature and
notarization evidence from the approved release record before installation.

Install a downloaded signed `.pkg` directly:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/downloads/sshfling-${VERSION}.pkg" -o "$tmp/sshfling-${VERSION}.pkg"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  sshfling-${VERSION}.pkg$" "$tmp/SHA256SUMS" > "$tmp/sshfling.SHA256SUMS"
(cd "$tmp" && shasum -a 256 -c sshfling.SHA256SUMS)
pkgutil --check-signature "$tmp/sshfling-${VERSION}.pkg"
xcrun stapler validate "$tmp/sshfling-${VERSION}.pkg"
spctl -a -vv -t install "$tmp/sshfling-${VERSION}.pkg"
sudo installer -pkg "$tmp/sshfling-${VERSION}.pkg" -target /
```

Uninstall:

```bash
sudo rm -f /usr/local/bin/sshfling
sudo rm -f /usr/local/libexec/sshfling/sshfling-unix-identity
sudo rmdir /usr/local/libexec/sshfling 2>/dev/null || true
sudo rm -rf /usr/local/share/sshfling
sudo pkgutil --forget io.sshfling.cli >/dev/null 2>&1 || true
```

The pkg installs `/usr/local/bin/sshfling`, the native identity helper under
`/usr/local/libexec/sshfling`, `/usr/local/share/sshfling`, and a
packaged default policy at
`/usr/local/share/sshfling/defaults/policy.json`. Its postinstall script creates
`/etc/sshfling/policy.json` only when that file is absent; install and upgrade
do not overwrite an existing operator-managed policy file. Uninstall
intentionally preserves `/etc/sshfling` for policy, CA material, and
operator-managed configuration, then forgets the package receipt. The pkg does
not keep separate original-state records and does not bundle Python, OpenSSH,
or `jq`. Client commands need Python and OpenSSH; server-host setup also needs
`jq` for native forced-session policy parsing and uses macOS `lockf` for
root-managed connection slots.

## .NET Global Tool

The NuGet package ID is `SSHFling.Tool` and the installed command is
`sshfling`. This package is a .NET wrapper around the bundled Python CLI and
templates; it does not bundle Python, OpenSSH, Docker, host account-management
tools, or host SSH configuration.

Install from a downloaded release package after verifying the published
checksum:

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/downloads/SSHFling.Tool.${VERSION}.nupkg" -o "$tmp/SSHFling.Tool.${VERSION}.nupkg"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  SSHFling.Tool.${VERSION}.nupkg$" "$tmp/SHA256SUMS" > "$tmp/SSHFling.Tool.SHA256SUMS"
(cd "$tmp" && sha256sum -c SSHFling.Tool.SHA256SUMS)
dotnet tool install --global SSHFling.Tool --add-source "$tmp" --version "$VERSION"
sshfling --version
```

Uninstall:

```bash
dotnet tool uninstall --global SSHFling.Tool
```

Global tool uninstall removes the .NET tool shim and package from the user's
.NET tool installation. It does not remove SSHFling project directories, host
SSH configuration, CA material, temporary grant state, Python, OpenSSH, Docker,
or any shared host dependencies.

## .NET NuGet Library

The separate `SSHFling` package exposes `SSHFlingRunner.Run` and
`SSHFlingRunner.RunAsync` to .NET applications. Clean C#, Visual Basic, and F#
consumers are validated against this same package. Download and checksum
`SSHFling.VERSION.nupkg` as above, then add it from the verified directory:

```bash
dotnet add package SSHFling --source "$tmp" --version "$VERSION"
```

Remove the application dependency with:

```bash
dotnet remove package SSHFling
```

Package removal does not remove application-created SSHFling projects or shared
Python/OpenSSH dependencies. See [libraries.md](libraries.md) for the API.

## Java Executable JAR

The Java package coordinates are `io.sshfling:sshfling-cli`. The direct
download artifact is `sshfling-cli-VERSION.jar`; the package also publishes
`sshfling-cli-VERSION-sources.jar`, `sshfling-cli-VERSION-javadoc.jar`, and
`sshfling-cli-VERSION.pom`. Clean Java, Kotlin, Scala, and Groovy consumers are
validated with both Maven and Gradle against the same coordinate.

Install from a downloaded release package after verifying the published
checksum:

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
curl -fsSL "${BASE_URL}/downloads/sshfling-cli-${VERSION}.jar" -o "$tmp/sshfling-cli-${VERSION}.jar"
curl -fsSL "${BASE_URL}/downloads/sshfling-cli-${VERSION}-javadoc.jar" -o "$tmp/sshfling-cli-${VERSION}-javadoc.jar"
curl -fsSL "${BASE_URL}/downloads/sshfling-cli-${VERSION}.pom" -o "$tmp/sshfling-cli-${VERSION}.pom"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  sshfling-cli-${VERSION}.jar$" "$tmp/SHA256SUMS" > "$tmp/sshfling-cli.jar.SHA256SUMS"
grep "  sshfling-cli-${VERSION}-javadoc.jar$" "$tmp/SHA256SUMS" > "$tmp/sshfling-cli.javadoc.SHA256SUMS"
grep "  sshfling-cli-${VERSION}.pom$" "$tmp/SHA256SUMS" > "$tmp/sshfling-cli.pom.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-cli.jar.SHA256SUMS && sha256sum -c sshfling-cli.javadoc.SHA256SUMS && sha256sum -c sshfling-cli.pom.SHA256SUMS)
java -jar "$tmp/sshfling-cli-${VERSION}.jar" --version
```

Maven uses `io.sshfling:sshfling-cli:VERSION`; Gradle uses
`implementation("io.sshfling:sshfling-cli:VERSION")`. Both call the public
`io.sshfling.cli.SSHFling.run` API. See [libraries.md](libraries.md).

Uninstall direct-download Java usage by deleting the downloaded JAR/POM/source/
Javadocs files and removing any shell alias or wrapper your deployment created.
Maven/Gradle cache cleanup is consumer-owned; package removal does not remove SSHFling project
directories, host SSH configuration, CA material, temporary grant state, Python,
OpenSSH, Docker, Java, Maven, Gradle, or any shared host dependencies.

## Node.js npm Package

The npm package name is `sshfling` and the installed command is `sshfling`.
This package is a Node.js wrapper around the bundled Python CLI and templates;
it does not bundle Python, OpenSSH, Docker, host account-management tools, or
host SSH configuration.

Install from a downloaded release package after verifying the published
checksum:

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "${BASE_URL}/downloads/sshfling-${VERSION}.tgz" -o "$tmp/sshfling-${VERSION}.tgz"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  sshfling-${VERSION}.tgz$" "$tmp/SHA256SUMS" > "$tmp/sshfling-npm.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-npm.SHA256SUMS)
npm install -g "$tmp/sshfling-${VERSION}.tgz"
sshfling --version
```

Uninstall:

```bash
npm uninstall -g sshfling
```

Global npm uninstall removes the npm package and global command shim from the
selected npm prefix. It does not remove SSHFling project directories, host SSH
configuration, CA material, temporary grant state, Python, OpenSSH, Docker,
Node.js, npm, or any shared host dependencies.

## Python Wheel

The universal wheel is `sshfling-VERSION-py3-none-any.whl`. It installs the
primary Python implementation, bundled templates, importable `sshfling` module,
and `sshfling` console command. Python 3.10 or newer is required.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
wheel="sshfling-${VERSION}-py3-none-any.whl"
curl -fsSL "${BASE_URL}/downloads/${wheel}" -o "$tmp/$wheel"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${wheel}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-python.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-python.SHA256SUMS)
pipx install "$tmp/$wheel"
sshfling --version
```

Uninstall with `pipx uninstall sshfling`. This removes the pipx environment and
command shim only; it preserves generated projects, host state, Python, pipx,
and OpenSSH.

## Go Module

The `sshfling-go-VERSION.zip` artifact contains an importable Go module and
`cmd/sshfling`. The compiled launcher embeds the canonical Python runtime and
templates. Go 1.22 or newer is required to build it; Python 3 and OpenSSH remain
run-time dependencies.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
archive="sshfling-go-${VERSION}.zip"
curl -fsSL "${BASE_URL}/downloads/${archive}" -o "$tmp/$archive"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${archive}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-go.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-go.SHA256SUMS)
unzip -q "$tmp/$archive" -d "$tmp/source"
(cd "$tmp/source/sshfling-go-${VERSION}" && GOBIN="$HOME/.local/bin" go install ./cmd/sshfling)
sshfling --version
```

Uninstall by removing the `sshfling` binary from the `GOBIN` used above after
confirming that path belongs to this installation. Removing it does not remove
the Go build cache, Python, OpenSSH, or generated SSHFling state.

## Rust Crate

The `sshfling-cli-VERSION.crate` artifact contains the `sshfling` Rust library
and binary with embedded runtime resources. Rust 1.70 or newer is required to
build it; Python 3 and OpenSSH remain run-time dependencies.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
crate="sshfling-cli-${VERSION}.crate"
curl -fsSL "${BASE_URL}/downloads/${crate}" -o "$tmp/$crate"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${crate}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-rust.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-rust.SHA256SUMS)
tar -xzf "$tmp/$crate" -C "$tmp"
cargo install --path "$tmp/sshfling-cli-${VERSION}" --locked
sshfling --version
```

Uninstall with `cargo uninstall sshfling-cli`. Cargo removes its binary and
registration but preserves generated projects, Cargo caches, Rust, Python,
OpenSSH, and host state.

## PHP Composer Package

The Composer package is `sshfling-php-VERSION.zip` with package name
`grwlx/sshfling`. It provides a PSR-4 API and Composer binary. PHP 8.1 or newer,
Composer, Python 3, and OpenSSH are required.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
app="$HOME/.local/share/sshfling-composer"
archive="sshfling-php-${VERSION}.zip"
mkdir -p "$app"
curl -fsSL "${BASE_URL}/downloads/${archive}" -o "$tmp/$archive"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${archive}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-php.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-php.SHA256SUMS)
composer config --working-dir "$app" repositories.sshfling artifact "$tmp"
composer require --working-dir "$app" "grwlx/sshfling:${VERSION}"
"$app/vendor/bin/sshfling" --version
```

Uninstall with `composer remove --working-dir "$app" grwlx/sshfling`, then
remove the app directory only if it contains no other packages. Composer does
not remove PHP, Python, OpenSSH, generated projects, or host state.

## Ruby Gem

The RubyGem is `sshfling-VERSION.gem`. It provides the `SSHFling` Ruby module
and `sshfling` executable. Ruby 3.0 or newer, Python 3, and OpenSSH are required.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
gem_home="$HOME/.local/share/sshfling-gems"
package="sshfling-${VERSION}.gem"
curl -fsSL "${BASE_URL}/downloads/${package}" -o "$tmp/$package"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${package}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-ruby.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-ruby.SHA256SUMS)
GEM_HOME="$gem_home" GEM_PATH="$gem_home" gem install --local --bindir "$HOME/.local/bin" --no-document "$tmp/$package"
sshfling --version
```

Uninstall:

```bash
GEM_HOME="$gem_home" GEM_PATH="$gem_home" gem uninstall --all --executables --bindir "$HOME/.local/bin" sshfling
```

This removes gem-owned files and the executable while preserving Ruby, Python,
OpenSSH, generated projects, and host state.

## C And C++ Native Libraries

The `sshfling-native-VERSION.tar.gz` source distribution builds POSIX C11
shared/static libraries, a C++17 header wrapper, CMake package exports,
pkg-config metadata, and `sshfling-c`. Building requires CMake 3.20 or newer
and C/C++ compilers; running still requires Python 3 and OpenSSH.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
prefix="$HOME/.local/share/sshfling-native"
archive="sshfling-native-${VERSION}.tar.gz"
curl -fsSL "${BASE_URL}/downloads/${archive}" -o "$tmp/$archive"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${archive}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-native.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-native.SHA256SUMS)
tar -xzf "$tmp/$archive" -C "$tmp"
cmake -S "$tmp/sshfling-native-${VERSION}" -B "$tmp/build" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$prefix"
cmake --build "$tmp/build" --parallel
ctest --test-dir "$tmp/build" --output-on-failure
cmake --install "$tmp/build"
"$prefix/bin/sshfling-c" --version
```

Consumers can set `CMAKE_PREFIX_PATH=$prefix` and link `SSHFling::shared` or
`SSHFling::static`, or set `PKG_CONFIG_PATH=$prefix/lib/pkgconfig`. Remove the
isolated installation with `rm -rf "$prefix"`. This preserves compilers,
CMake, Python, OpenSSH, generated projects, and host state.

## Perl Source Distribution

The `sshfling-perl-VERSION.tar.gz` CPAN-style source distribution provides the
`SSHFling` module and executable. Perl 5.26 or newer, MakeMaker, make, Python 3,
and OpenSSH are required.

```bash
BASE_URL="https://OWNER.github.io/REPO"
VERSION="0.1.14"
tmp="$(mktemp -d)"
prefix="$HOME/.local/share/sshfling-perl"
archive="sshfling-perl-${VERSION}.tar.gz"
curl -fsSL "${BASE_URL}/downloads/${archive}" -o "$tmp/$archive"
curl -fsSL "${BASE_URL}/downloads/SHA256SUMS" -o "$tmp/SHA256SUMS"
grep "  ${archive}$" "$tmp/SHA256SUMS" > "$tmp/sshfling-perl.SHA256SUMS"
(cd "$tmp" && sha256sum -c sshfling-perl.SHA256SUMS)
tar -xzf "$tmp/$archive" -C "$tmp"
(cd "$tmp/SSHFling-${VERSION}" && \
  perl Makefile.PL INSTALL_BASE="$prefix" && make test && make install)
PERL5LIB="$prefix/lib/perl5" "$prefix/bin/sshfling" --version
```

Remove the isolated module and command with `rm -rf "$prefix"`. This preserves
Perl, MakeMaker, make, Python, OpenSSH, generated projects, and host state.

## Windows MSI

Install with the generated checksum and Authenticode-verifying helper from an
elevated PowerShell session:

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
$Installer = Join-Path $env:TEMP "sshfling-install.ps1"
Invoke-WebRequest -Uri "$BaseUrl/windows/install.ps1" -OutFile $Installer
& $Installer
$Command = Join-Path $env:ProgramFiles "SSHFling\sshfling.cmd"
& $Command --version
```

Install a downloaded MSI directly:

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
$Version = "0.1.14"
$Msi = Join-Path $env:TEMP "sshfling-$Version.msi"
$Sums = Join-Path $env:TEMP "sshfling-SHA256SUMS"
Invoke-WebRequest -Uri "$BaseUrl/downloads/sshfling-$Version.msi" -OutFile $Msi
Invoke-WebRequest -Uri "$BaseUrl/downloads/SHA256SUMS" -OutFile $Sums
$ExpectedLine = Get-Content $Sums | Where-Object { $_ -like "* sshfling-$Version.msi" } | Select-Object -First 1
if (-not $ExpectedLine) { throw "Checksum entry not found for sshfling-$Version.msi" }
$Expected = $ExpectedLine.Split()[0].ToLowerInvariant()
$Actual = (Get-FileHash -Algorithm SHA256 -Path $Msi).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA-256 mismatch for sshfling-$Version.msi" }
$Signature = Get-AuthenticodeSignature -FilePath $Msi
if ($Signature.Status -ne "Valid") { throw "Invalid Authenticode signature: $($Signature.Status)" }
Start-Process msiexec.exe -Wait -ArgumentList "/i", $Msi, "/qn", "/norestart"
$Command = Join-Path $env:ProgramFiles "SSHFling\sshfling.cmd"
& $Command --version
```

Uninstall with the generated helper:

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
$Uninstaller = Join-Path $env:TEMP "sshfling-uninstall.ps1"
Invoke-WebRequest -Uri "$BaseUrl/windows/uninstall.ps1" -OutFile $Uninstaller
& $Uninstaller
```

Uninstall by MSI product registration:

```powershell
$Version = "0.1.14"
$UninstallRoots = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
$Products = Get-ItemProperty -Path $UninstallRoots -ErrorAction SilentlyContinue |
  Where-Object {
    $_.DisplayName -eq "SSHFling" -and
    $_.Publisher -eq "SSHFling Maintainers" -and
    $_.DisplayVersion -eq $Version -and
    $_.WindowsInstaller -eq 1 -and
    $_.URLInfoAbout -eq "https://github.com/GRWLX/sshfling"
  }
foreach ($Product in $Products) {
  $ProductCode = $Product.PSChildName
  if ($ProductCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
    throw "Could not determine MSI product code for SSHFling."
  }
  Start-Process msiexec.exe -Wait -ArgumentList "/x", $ProductCode, "/qn", "/norestart"
}
```

MSI uninstall removes the installed SSHFling product directory and the machine
PATH entry added by the MSI. It does not remove Python, OpenSSH, Windows
OpenSSH Server, host SSH configuration, temporary grant state, CA material, or
configuration stored outside the install directory.

## Windows Portable Zip

Install for the current user:

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
$Version = "0.1.14"
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\SSHFling"
$Zip = Join-Path $env:TEMP "sshfling-$Version-windows.zip"
$Sums = Join-Path $env:TEMP "sshfling-SHA256SUMS"
Invoke-WebRequest -Uri "$BaseUrl/downloads/sshfling-$Version-windows.zip" -OutFile $Zip
Invoke-WebRequest -Uri "$BaseUrl/downloads/SHA256SUMS" -OutFile $Sums
$ExpectedLine = Get-Content $Sums | Where-Object { $_ -like "* sshfling-$Version-windows.zip" } | Select-Object -First 1
if (-not $ExpectedLine) { throw "Checksum entry not found for sshfling-$Version-windows.zip" }
$Expected = $ExpectedLine.Split()[0].ToLowerInvariant()
$Actual = (Get-FileHash -Algorithm SHA256 -Path $Zip).Hash.ToLowerInvariant()
if ($Actual -ne $Expected) { throw "SHA-256 mismatch for sshfling-$Version-windows.zip" }
Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Expand-Archive -Path $Zip -DestinationPath $InstallDir
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$PathParts = @(($UserPath -split ';') | Where-Object { $_ })
if ($PathParts -notcontains $InstallDir) {
  $NewPath = ($PathParts + $InstallDir) -join ';'
  [Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
}
```

Open a new PowerShell session, then verify:

```powershell
sshfling --version
```

Uninstall the portable zip install and remove only the PATH entry that this
deployment added:

```powershell
$InstallDir = Join-Path $env:LOCALAPPDATA "Programs\SSHFling"
$UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
$NewPath = (($UserPath -split ';') | Where-Object { $_ -and ($_ -ne $InstallDir) }) -join ';'
[Environment]::SetEnvironmentVariable("Path", $NewPath, "User")
Remove-Item -Recurse -Force $InstallDir -ErrorAction SilentlyContinue
```

The portable zip does not create an MSI product registration. Uninstall is file
and PATH cleanup only.

## Windows winget

The generated winget manifests are published under
`${BASE_URL}/winget/manifests/g/OWNER/SSHFling/VERSION/`. Official winget use
requires submission to, and acceptance by, the winget package repository.

Install after the manifest is accepted:

```powershell
winget install OWNER.SSHFling
```

Uninstall:

```powershell
winget uninstall OWNER.SSHFling
```

For release validation from a local checkout of the generated manifest tree:

```powershell
winget install --manifest .\winget\manifests\g\OWNER\SSHFling\VERSION
winget uninstall OWNER.SSHFling
```

winget uses the generated MSI manifest, so MSI dependency and uninstall scope
still applies.

## Windows Scoop

Install directly from the generated Scoop manifest:

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
scoop install "$BaseUrl/scoop/sshfling.json"
sshfling --version
```

Uninstall:

```powershell
scoop uninstall sshfling
```

Scoop uses the Windows portable zip. Remove any custom PATH entries or shims
created outside Scoop separately.

## Windows Chocolatey

Install with the generated checksum-verifying helper from an elevated
PowerShell session:

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
$ChocoInstaller = Join-Path $env:TEMP "sshfling-chocolatey-install.ps1"
Invoke-WebRequest -Uri "$BaseUrl/chocolatey/install.ps1" -OutFile $ChocoInstaller
& $ChocoInstaller
sshfling --version
```

Install after the package is accepted into an approved Chocolatey source:

```powershell
choco install sshfling -y
```

Uninstall:

```powershell
choco uninstall sshfling -y
```

Chocolatey uses the generated MSI package, so MSI dependency and uninstall
scope still applies.

## BSD and Community Manifests

Generated community manifests are published at `${BASE_URL}/community.html`.
Some can be used directly. Official or community repositories still require the
normal maintainer account, review, signing, and submission process.

| Ecosystem | Install command after manifest import or approval | Uninstall command |
| --- | --- | --- |
| Arch / AUR | `curl -fsSLO "${BASE_URL}/arch/PKGBUILD" && makepkg -si` | `sudo pacman -R sshfling` |
| Alpine | `abuild -r` from the generated `APKBUILD`, then `sudo apk add path/to/sshfling-${VERSION}-r0.apk` | `sudo apk del sshfling` |
| FreeBSD Ports | `cd /usr/ports/security/sshfling && sudo make install clean` | `sudo pkg delete sshfling` |
| OpenBSD Ports | `cd /usr/ports/security/sshfling && doas make install` | `doas pkg_delete sshfling` |
| pkgsrc for NetBSD, DragonFly BSD, illumos, SmartOS | `cd /usr/pkgsrc/security/sshfling && sudo bmake install clean` | `sudo pkg_delete sshfling` |
| Nix / NixOS | `NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure ./nix` | `nix profile remove sshfling` |
| Guix | `guix package -f guix/sshfling.scm` | `guix remove sshfling` |
| Void Linux | `./xbps-src pkg sshfling` then `sudo xbps-install --repository hostdir/binpkgs sshfling` | `sudo xbps-remove sshfling` |
| Gentoo | `sudo emerge --ask app-admin/sshfling` | `sudo emerge --unmerge app-admin/sshfling` |
| Slackware | `sudo sh slackware/sshfling.SlackBuild` then `sudo installpkg /tmp/sshfling-${VERSION}-*.txz` | `sudo removepkg sshfling` |
| openSUSE / OBS | `sudo zypper install sshfling` after OBS publication | `sudo zypper remove sshfling` |
| Snapcraft | `snapcraft` then `sudo snap install ./sshfling_*.snap --dangerous` | `sudo snap remove sshfling` |
| Termux | `pkg install ./sshfling_${VERSION}_*.deb` after building the Termux package | `pkg uninstall sshfling` |
| AppImage | `appimage-builder --recipe appimage/AppImageBuilder.yml`, then copy the AppImage to an approved location and add a launcher if needed | Remove the AppImage file and launcher |

BSD and community package-manager uninstalls follow the owning package manager's
normal file-removal behavior. They do not imply rollback of OpenSSH, Python,
base-system SSH configuration, package indexes, or profile/store generations
unless the local package manager and fleet policy explicitly manage that
rollback.

## Containers

Containers are a test harness and packaged runtime path. They are not the normal
production host grant path, and they do not change the host's OpenSSH packages.

Build and run the local Docker Compose harness:

```bash
./scripts/install-local.sh
sshfling init ./my-sshfling --with-key --session-seconds 60
cd ./my-sshfling
sshfling network create
sshfling server up --build
sshfling client run 'whoami && hostname && date -u'
```

Stop and remove the Compose harness from the generated project directory:

```bash
sshfling server down
docker compose -f compose.client.yml down --remove-orphans
docker network rm timed-ssh-net 2>/dev/null || true
docker image rm timed-ssh-server:latest timed-ssh-client:latest 2>/dev/null || true
```

Remove a local source checkout install, if used:

```bash
./scripts/uninstall-local.sh
```

If `scripts/install-local.sh` was run with a custom `PREFIX`, run uninstall with
the same `PREFIX`. The local helper removes the fixed local-install file paths it
created under that prefix, including the native account and identity backends in
`$PREFIX/libexec/sshfling`; it does not record or restore preexisting files that
a local install may have overwritten.

Published container images, when enabled, use GitHub Container Registry names:

```bash
docker pull ghcr.io/OWNER/sshfling-client:VERSION
docker pull ghcr.io/OWNER/sshfling-server:VERSION
```

Remove pulled images:

```bash
docker image rm ghcr.io/OWNER/sshfling-client:VERSION ghcr.io/OWNER/sshfling-server:VERSION
```

Container cleanup removes selected containers, images, networks, and volumes
only. Exact dependency rollback inside a container requires recording the image
digest, Dockerfile, package index state, and build inputs used for that image.

## Original-State Caveats

SSHFling packages declare runtime capabilities where each ecosystem supports
dependency metadata, but the dependency versions are resolved by the target
operating system, package manager channel, container base image, MDM/Intune
policy, or fleet configuration.

Record this evidence before enterprise deployment when exact restoration matters:

| Environment | Evidence to keep outside SSHFling |
| --- | --- |
| Linux | Package inventory, manual/auto dependency marks, repository configuration, `/etc/ssh` and `/etc/sshfling` baselines, service-account inventory, and configuration-management state. |
| macOS | MDM inventory, package receipts, Homebrew bundle or fleet policy, `/etc/ssh` and `/etc/sshfling` baselines, and backup records. |
| Windows | Intune/SCCM/Group Policy app inventory, Python inventory, Windows OpenSSH capability state, MSI product inventory, machine/user PATH baseline, and backup records. |
| BSD | `pkg`/ports/pkgsrc inventory, `/etc` and localbase configuration baselines, and backup or configuration-management records. |
| Containers | Image digest, Dockerfile or build recipe, package index state, runtime volume list, and compose or orchestrator configuration. |
| Nix / Guix | Flake/channel or Guix revision, profile generation, store path, and garbage-collection policy. |

Treat dependency cleanup as a separate fleet change with its own owner, review,
evidence, rollback plan, and release-ticket approval.
