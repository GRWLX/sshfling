# Package Publishing

This guide describes the enterprise package-publishing path for SSHFling. It is
for release operators who publish signed release artifacts and a GitHub Pages
package site.

## What Gets Published

The `Release packages with public web` workflow publishes a GitHub Pages package
site that includes:

- Debian and Ubuntu `.deb` packages with APT metadata.
- RHEL, Fedora, Rocky Linux, AlmaLinux, and UBI `.rpm` packages with RPM repo
  metadata.
- A Homebrew formula, macOS `.pkg`, Windows MSI, Windows portable zip, source
  tarball, and checksums.
- Community package manifests for Arch/AUR, Alpine, FreeBSD Ports, OpenBSD
  Ports, pkgsrc, Nix, Guix, Void, Gentoo, Slackware, openSUSE OBS, Snapcraft,
  Termux, AppImage, Scoop, winget, and Chocolatey.

The current matrix is maintained in [Build Targets](../build-targets.md).
Repository registration examples are maintained in
[Repository Registration](../repos.md).

## Behavior Contract For Release Notes

Every package release must preserve these documented runtime behaviors unless
the release notes call out an intentional breaking change:

- `sudo sshfling` creates temporary password access by default.
- Certificate access is explicit with `--certificate`.
- Certificate-only setup options, including `--ca-key`, `--public-key-file`,
  `--out`, `--login-user`, `--key-id`, `--source-address`, and `--no-pty`, are
  invalid unless `--certificate` is present.
- `sshfling password prune` removes expired tracked password grants only. It
  leaves active grants in place, skips unmanaged records, locks expired
  SSHFling-created users by default, deletes those users only with
  `--delete-users`, and locks/expires existing users explicitly allowed with
  `--allow-existing-user` without deleting them.
- Package uninstall removes package files and managed repository entries. Host
  SSH configuration, password grant state, CA material, `/etc/sshfling`
  configuration, and package-manager dependency state require separate host or
  fleet cleanup.

## Prerequisites

- A reviewed release commit on the branch used for release tags.
- A semantic package version with exactly three numeric components, such as
  `0.1.12`.
- GitHub Pages configured to deploy from GitHub Actions.
- GitHub Actions permissions for Pages deployments: `contents: read`,
  `pages: write`, and `id-token: write`.
- A stable production GPG signing key for APT and RPM repository metadata.
- Apple Developer signing and notarization access if the `.pkg` is distributed
  as a production macOS installer.
- Authenticode signing access if the MSI is distributed as a production Windows
  installer.
- Commercial license approval before publishing or redistributing packages.

## Version Validation

Validate the package version before a release run:

```bash
bash packaging/resolve-version.sh 0.1.12
```

The version must match `^[0-9]+[.][0-9]+[.][0-9]+$`. Tags use the same value
with a leading `v`, for example `v0.1.12`.

## Signing Setup

Configure these GitHub repository secrets for stable Linux repository signing:

| Secret | Required | Purpose |
| --- | --- | --- |
| `SSHFLING_REPO_GPG_PRIVATE_KEY` | Yes | ASCII-armored private key used to sign APT metadata, RPM packages, and RPM repo metadata. |
| `SSHFLING_REPO_GPG_FINGERPRINT` | Yes | Approved public fingerprint for the production repo signing key. Package-site publishing fails if the imported key does not match. |
| `SSHFLING_REPO_GPG_KEY_ID` | Optional | Specific key ID or fingerprint to use when the imported keyring contains more than one signing key. |
| `SSHFLING_REPO_GPG_PASSPHRASE` | Optional | Passphrase for the private key, if the key is protected. |

The workflow refuses package-site publishing unless
`SSHFLING_REPO_GPG_PRIVATE_KEY` and `SSHFLING_REPO_GPG_FINGERPRINT` are
configured. Manual workflow dispatches can set `generate_test_signing_key=true`
for disposable dry-run package sites, but tag publishing and manual runs with
`publish=true` require a version tag ref, block ephemeral repository signing
keys, and fail if the signing key fingerprint does not match the approved
fingerprint. Rotating a production key requires client trust-store updates for
APT and RPM consumers.

## Pre-Release Checks

Run the local test suite before publishing:

```bash
make test
```

Build local Linux packages when you are validating packaging changes from a
Linux workstation:

```bash
./packaging/build-deb.sh
./packaging/build-rpm.sh
```

Build platform-specific packages on matching hosts:

```bash
powershell -NoProfile -File packaging/build-msi.ps1
./packaging/build-pkg.sh
```

Package outputs are written to `dist/`.

## Release Workflow Order

Run the release validation workflows in this order for a public package release:

1. `Container image tests`
2. `Release packages without web`
3. `Release packages with public web`
4. `pages-build-deployment`
5. `Package install tests`
6. `Cross OS validation`

`Container image tests`, `Package install tests`, and `Cross OS validation` are
manual release gates when you are publishing a specific version. Manual
`Release packages with public web` runs are verification dry runs unless the
`publish` input is set to `true`. Tag pushes publish after the package site is
verified and the protected `github-pages` environment approves the deploy job.

For a tag-based release, create and push an annotated version tag from the
reviewed release commit:

```bash
git tag -a v0.1.12 -m "SSHFling 0.1.12"
git push origin v0.1.12
```

For a manual workflow dispatch, use the same version value without the leading
`v`.

After `pages-build-deployment` succeeds, dispatch `Package install tests` and
`Cross OS validation` with the published version.

## Public Site Verification

The public-web workflow runs:

```bash
bash packaging/build-public-web.sh package-dist public
bash packaging/verify-public-web.sh public
```

The verifier requires all declared package outputs, generated community
manifests, checksums, public install scripts, and signed-repository files when
repo signing is enabled.

For local verification, provide the same environment variables the workflow
uses and ensure `package-dist/` contains the Linux, macOS, Windows, and source
artifacts:

```bash
VERSION=0.1.12 \
REPOSITORY=GRWLX/sshfling \
OWNER=GRWLX \
SSHFLING_GENERATE_REPO_SIGNING_KEY=1 \
bash packaging/build-public-web.sh package-dist public

VERSION=0.1.12 \
REPOSITORY=GRWLX/sshfling \
bash packaging/verify-public-web.sh public
```

## Installation Examples

Use signed repository registration for production Linux fleets. Saved installer
files are convenience wrappers for interactive hosts; do not pipe a remote
script directly into a shell.

For APT and DNF/Yum, use the signed fleet registration examples first.

## Signed Fleet Repository Registration

Use signed repository registration for managed Linux fleets.

APT:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
APPROVED_REPO_FINGERPRINT="PASTE_APPROVED_RELEASE_FINGERPRINT"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE_URL/sshfling-repo.gpg" -o "$tmp/sshfling-repo.gpg"
actual_fingerprint="$(gpg --batch --show-keys --with-colons "$tmp/sshfling-repo.gpg" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
test "$actual_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
sudo install -d -m 0755 /usr/share/keyrings
sudo install -m 0644 "$tmp/sshfling-repo.gpg" /usr/share/keyrings/sshfling-repo.gpg
printf 'deb [signed-by=/usr/share/keyrings/sshfling-repo.gpg] %s/apt ./\n' "$BASE_URL" >"$tmp/sshfling.list"
sudo install -m 0644 "$tmp/sshfling.list" /etc/apt/sources.list.d/sshfling.list
sudo apt update
sudo apt install -y sshfling
```

DNF/Yum:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
APPROVED_REPO_FINGERPRINT="PASTE_APPROVED_RELEASE_FINGERPRINT"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE_URL/sshfling-repo.asc" -o "$tmp/sshfling-repo.asc"
actual_fingerprint="$(gpg --batch --show-keys --with-colons "$tmp/sshfling-repo.asc" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
test "$actual_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
sudo install -d -m 0755 /etc/pki/rpm-gpg
sudo install -m 0644 "$tmp/sshfling-repo.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
cat >"$tmp/sshfling.repo" <<EOF
[sshfling]
name=SSHFling
baseurl=${BASE_URL}/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
EOF
sudo install -m 0644 "$tmp/sshfling.repo" /etc/yum.repos.d/sshfling.repo
sudo dnf install -y sshfling
```

Use `sudo yum install -y sshfling` on older yum-based hosts.

## Convenience Wrappers

Use these saved installer scripts for interactive hosts after you have decided
that a convenience wrapper is appropriate.

Convenience wrapper for interactive Linux hosts:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE_URL/install.sh" -o "$tmp/install.sh"
bash "$tmp/install.sh" apt
bash "$tmp/install.sh" dnf
```

For Homebrew:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
brew install "$BASE_URL/homebrew/sshfling.rb"
```

## Community Repository Submission

The package site generates community manifests, but official ecosystem
publication still requires ecosystem-specific maintainership, review, signing,
and license acceptance. Treat generated files as release inputs, not automatic
publication.

Before submitting to a third-party repository:

- Confirm the commercial license permits that redistribution path.
- Confirm the manifest points to the intended release tarball or package URL.
- Confirm checksums match the published artifact.
- Confirm the ecosystem accepts proprietary or unfree packages.
- Record the submitted manifest URL and review ticket in the release notes.

## Publish Evidence

Attach or link this evidence in the release ticket:

- Tag name and commit SHA.
- Release notes that accurately describe password default access, explicit
  certificate mode, prune behavior, and uninstall limits.
- Successful `Release packages with public web` run.
- Successful `pages-build-deployment` run.
- Successful `Package install tests` run for the released version.
- Successful `Cross OS validation` run for the released version.
- Published package-site URL.
- GPG signing key fingerprint used for the repository.
- Checksums file URL for raw downloads.
