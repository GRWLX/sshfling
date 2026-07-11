# Changelog

## v0.1.19 - 2026-07-11

Status: language-catalog publication candidate after `v0.1.18` exposed one
remaining clean-checkout test assumption.

### Fixed

- Updated the language deployment unit tests to allow absent ignored `TODO.txt`
  data in clean CI checkouts while still checking local TODO synchronization
  when the file exists.
- Bumped language package and evidence references to `0.1.19` for a
  fixed-forward language artifact publication without moving `v0.1.18`.

## v0.1.18 - 2026-07-11

Status: language-catalog publication candidate after the `v0.1.17` full package
release attempt exposed CI checkout determinism and missing protected signing
configuration.

### Fixed

- Made the language deployment matrix independent of the ignored local
  `TODO.txt` file so clean GitHub Actions checkouts validate the promoted
  language catalog deterministically.
- Bumped language package and evidence references to `0.1.18` for a
  fixed-forward language artifact publication without moving `v0.1.17`.

## v0.1.17 - 2026-07-11

Status: publishing candidate for the expanded language package catalog after
`v0.1.16`.

### Added

- Promoted the expanded language catalog for publication, including the
  validated functional, scientific, BEAM, systems, scripting, JVM/.NET, web,
  and native library package surfaces.
- Bumped release evidence references to `0.1.17` so package-site validation can
  publish the current post-`v0.1.16` language artifacts without replacing a
  previously published version.

## v0.1.14 - 2026-07-07

Status: release-prep source update. This version is not tagged or published
until final workflow evidence, signing evidence, and release approval are
attached.

### Hardened

- Bumped package identity for a fixed-forward `0.1.14` release candidate after
  `v0.1.13`.
- Hardened expired password-grant pruning so a recreated or mismatched Unix
  identity is skipped before SSHFling removes managed config or metadata.
- Added tests for identity-mismatch prune preservation, incomplete CA keypair
  rejection, and explicit `cert issue --certificate -t/--time` lifetime
  enforcement.
- Required password-host setup to find OpenSSH server tooling up front.
- Recorded package-created service-account UID/GID/home identity in DEB/RPM
  package state and preserved mismatched later accounts during uninstall.
- Added DEB/RPM container tests for service-account identity reuse safety.
- Required macOS package signing/notarization credentials in release workflows,
  and strengthened generated macOS installer helpers with package signature,
  notarization, and Gatekeeper checks.
- Added Windows ZIP checksum verification to install-validation workflows and
  tightened Windows MSI uninstall selection with `DisplayVersion`.
- Updated install, uninstall, repo, wiki, release checklist, and release
  evidence templates for the new package trust, uninstall, and runtime behavior
  gates.

### Evidence Required Before Publishing

- Passing `make test`, `make test-containers`, package rehearsal, release
  security evidence generation/validation, workflow static checks, and
  `git diff --check` from the final clean candidate.
- Tag or protected workflow evidence for `v0.1.14`, release approval, package
  artifact checksums, release matrix/evidence outputs, and package-site
  verification.
- Production APT/RPM signing fingerprint, macOS notarization output, Windows
  Authenticode output, and approved exceptions for any unavailable external
  OS/hardware/secrets.

## v0.1.13 - 2026-07-07

Status: tagged and published source/package release at
`065b03c16a81e9167120e9f41afd4c5e81a79a4a`.
Use the GitHub release, tag, workflow runs, and release ticket as the
authoritative evidence; this changelog is not an attestation.

### Prepared

- Added release security evidence hooks for baseline secret scanning, SPDX SBOM
  generation, dependency inventory, license reporting, Dockerfile hygiene,
  systemd hardening review, and matrix/manifest validation.
- Tightened uninstall scope documentation and validation. Package uninstall is
  documented as removing SSHFling-managed package files only, not host SSH
  state, password grant state, CA material, `/etc/sshfling`, original host
  configuration, or package-manager dependency state.
- Expanded package and cross-OS validation coverage around shared CLI checks,
  bounded workflow timeouts, Windows MSI metadata, macOS package metadata,
  public repository install paths, and community package manifests.
- Added GitHub Packages container publishing workflow coverage and included it
  in the `v0.1.13` hardened source release.

### Evidence Available

- Source version in `bin/sshfling` is `0.1.13`.
- `v0.1.13` is tagged at source commit
  `065b03c16a81e9167120e9f41afd4c5e81a79a4a`.
- GitHub release `v0.1.13` is published at
  https://github.com/GRWLX/sshfling/releases/tag/v0.1.13 with eight assets:
  `RELEASE-EVIDENCE.md`, `SHA256SUMS`, Linux DEB/RPM packages, source tarball,
  macOS pkg, Windows MSI, and Windows zip.
- The tag is annotated but not signed; use protected-tag evidence or another
  approved release-control record if tag signature evidence is required.
- Tag/source-commit package workflows `Release packages without web` and
  `Release packages with public web` completed successfully for the release
  commit. The public-web run verified generated package-site evidence, but final
  Pages deployment evidence is still required when the package site is in
  enterprise scope.
- Previous published release `v0.1.12` is tagged at commit
  `58b23b5fa9b90491c41b41fc206d8e907b00e8df`.
- GitHub release `v0.1.12` is published at
  https://github.com/GRWLX/sshfling/releases/tag/v0.1.12 with eight assets:
  `RELEASE-EVIDENCE.md`, `SHA256SUMS`, Linux DEB/RPM packages, source tarball,
  macOS pkg, Windows MSI, and Windows zip.
- Release checklist and evidence templates exist in
  `docs/release-checklist.md` and `docs/release-evidence.md`.
- Local release security evidence can be generated with
  `make release-security-scan` and validated with
  `make release-security-evidence-validate`.

### Evidence To Attach Or Except Before Enterprise Claims

- Attach the release approval, protected tag or equivalent change-control
  evidence, and final workflow run URLs for release packages, public package
  web, package install tests, cross-OS validation, and container image tests.
- Attach `v0.1.13` package artifact checksums, generated evidence files,
  repository signing fingerprint, Pages deployment ID, release approval, and
  any accepted workflow exceptions.
- macOS notarization and Windows Authenticode evidence must be attached or
  formally excepted before enterprise publication claims.
- Optional external scanners are not required by the baseline generator unless
  strict mode is selected, but skipped scanner coverage should be called out in
  the release ticket.

## v0.1.12 - 2026-07-06

Status: tagged source release at
`58b23b5fa9b90491c41b41fc206d8e907b00e8df`.

### Shipped

- Prepared enterprise package publishing workflows, package-site generation,
  repository registration documentation, and release evidence templates.
- Added package builders and public package verification for Linux packages,
  macOS package outputs, Windows MSI/zip outputs, source archives, checksums,
  repository metadata, and community package manifests.
- Added release evidence generation and validation tooling for artifact
  inventories and release matrix checks.
- Expanded validation coverage across container tests, package install tests,
  cross-OS runtime checks, firewall OS compatibility checks, and packaged CLI
  validation.
- Added enterprise-facing documentation for operations, package publishing,
  security and compliance evidence collection, AI-assisted temporary access,
  and release readiness.
- Added detached job PID lifecycle handling, session PID reporting, 24-hour
  grant support, and validation fixes for Windows detached job behavior.

### Verified Release Evidence

- Immutable GitHub release URL and asset list:
  https://github.com/GRWLX/sshfling/releases/tag/v0.1.12.
- Passing tag-scoped `Release packages without web` run:
  https://github.com/GRWLX/sshfling/actions/runs/28824244828.
- Passing tag/source-commit `Container image tests` run:
  https://github.com/GRWLX/sshfling/actions/runs/28824243992.

### Evidence Still To Attach Or Except

- Failed tag-scoped `Release packages with public web` run:
  https://github.com/GRWLX/sshfling/actions/runs/28824244749. Rerun or approve
  an exception before using it as package-site validation evidence.
- Tag-scoped `Package install tests` and `Cross OS validation` run URLs, or a
  documented release-ticket approval for using older rehearsal runs from a
  different commit.
- `SHA256SUMS`, artifact provenance, repository signing fingerprint, Pages
  deployment ID, package-site artifact reference, and any signing or notarization
  outputs.

### Conservative Notes

- This changelog does not assert SOC 2, ISO 27001, FedRAMP, NIST, or similar
  certification.
- Published artifact integrity, signing status, and install validation remain
  release-ticket evidence items unless linked to immutable workflow runs and
  artifacts.
