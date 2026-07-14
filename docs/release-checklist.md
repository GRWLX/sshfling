# SSHFling Release Checklist

Use this checklist before publishing enterprise package artifacts.

## Branch and Tag Assumptions

- Release from `main` after it is up to date with `origin/main` and required CI is green.
- Use a short-lived `release/vX.Y.Z` branch only when final stabilization needs more than one commit.
- Tags are named `vX.Y.Z`; package workflow inputs use `X.Y.Z`.
- Package versions currently require exactly three numeric components, enforced by `packaging/version.sh`.
- Do not move or replace a published release tag. Publish a new patch version instead.

## Working Tree Hygiene

- `git status --short --branch` is clean before tagging, apart from intentional release-note edits.
- Generated package outputs stay out of source commits: `build/`, `dist/`, `public/`, `package-dist/`, and `release-dist/`.
- Generated release evidence and platform matrices stay out of source commits:
  keep them under ignored paths such as
  `docs/release/enterprise-release-evidence/` and attach or link reviewed
  output from the release ticket.
- Remove interpreter caches and local byproducts such as `__pycache__/`, `.pytest_cache/`, and local logs.
- Check that no local secrets or package credentials are staged: `.env`, `.env.*`, private keys, package-manager credentials, and non-placeholder `secrets/` files.
- Run `make clean` before rebuilding local package artifacts from the exact candidate commit.
- `make release-security-scan` intentionally refuses dirty worktrees. For a
  local, non-release scan before cleanup, run
  `make release-security-scan-local VERSION=X.Y.Z`; it passes `--allow-dirty`
  and writes ignored evidence under `build/release-security-local/`. Do not use
  dirty-tree scan output as release evidence.

## Release Notes

- Use GitHub generated release notes as a starting point, then add a short enterprise-facing summary.
- Call out security-relevant behavior changes, install or uninstall changes, upgrade impact, policy defaults, and compatibility notes.
- Confirm access behavior is described accurately: password access is the
  default access type, temporary grants require explicit `-t/--time`,
  certificate access requires `--certificate`, certificate setup requires an
  existing CA keypair, and certificate-specific setup options are not implicit.
- Confirm cleanup behavior is described accurately: `password prune` requires
  exactly one selector (`--all` or `--username USER`), removes expired tracked
  grants only, `--all` does not remove active grants, `--delete-users` only
  deletes expired SSHFling-created users, break-glass existing-user grants are
  locked/expired but not deleted, root-equivalent users are never mutated from
  password-grant metadata or host-user markers, and package uninstall preserves
  `/etc/sshfling` configuration without restoring dependency state or original
  host configuration.
- Confirm destructive CA operations are described accurately:
  `sshfling ca init --force` replaces the existing CA keypair and requires a
  planned host trust update and certificate reissue.
- Confirm [Install and uninstall runbook](install-uninstall.md) covers every
  advertised channel for the release: Linux DEB/RPM files, signed public APT/RPM
  repos, macOS pkg/Homebrew, Windows MSI/zip/winget/Scoop/Chocolatey,
  BSD/community manifests, containers, and dependency/original-state caveats.
- List supported package artifacts and target ecosystems for the release.
- List platform coverage precisely. Use exact OS versions, package formats,
  Python/OpenSSH versions where known, CPU architectures, hardware classes, and
  ARM/IoT/FPGA scope; do not summarize this as broad Linux, ARM, embedded, or
  FPGA support unless the release evidence backs the claim. See
  [language-support.md](language-support.md) for language/runtime claim rules.
- Include checksum location and the signing-key fingerprint used for APT/RPM metadata, or explicitly state when a generated test key was used.
- Record validation workflow links for `Container image tests`, `Release packages without web`, `Release packages with public web`, `Package install tests`, and `Cross OS validation`.

## Build and Validation

- Run local validation:

```bash
make test
make test-containers
```

- Run release workflows with the same `X.Y.Z` version input:

1. `Container image tests`
2. `Release packages without web`
3. `Release packages with public web`, using tag publishing or `publish=true`
   only when the production signing key is configured
4. `pages-build-deployment`
5. `Package install tests`
6. `Cross OS validation`

- Confirm release assets include the expected `.deb`, `.rpm`, `.pkg`, `.msi`,
  Windows zip, `.NET` global-tool and library `.nupkg` files, Java executable,
  source, and Javadocs JARs plus POM validated by Java, Kotlin, Scala, and
  Groovy consumers, Node.js npm `.tgz`, Python wheel, Go module zip, Rust `.crate`, PHP
  Composer zip, Ruby `.gem`, C/C++ native source distribution, Perl source
  distribution, main source tarball, and `SHA256SUMS`.
- Confirm the public package site has APT/RPM metadata, repository signing files when production signing is enabled, Homebrew and macOS installer scripts, Windows installer scripts, and generated community manifests.
- Confirm the install/uninstall runbook matches generated file names, public
  site paths, package identifiers, uninstall scope, and checksum/signing
  verification commands for the release.
- Confirm macOS pkg metadata includes the package notes/license and Windows MSI metadata includes Add/Remove Programs uninstall and dependency scope.
- Capture a compact platform coverage declaration for the release. Keep any
  generated matrix in the ignored release evidence directory and retain only
  links, hashes, summaries, and exception IDs in tracked docs or release notes.

Required platform coverage evidence:

| Coverage area | Evidence to capture |
| --- | --- |
| OS versions | `os-release`, platform version command, package format, install source, validation workflow run URL, and package install result. |
| Language/runtime | `python3 --version`, OpenSSH `ssh -V` and `sshd -V` where available, shell or PowerShell version, and account-management tool availability for password grants. |
| Native command language | Evidence that OS-facing wrappers, package maintainer scripts, and cross-OS command execution tests use POSIX sh/Bash on Unix-like hosts and PowerShell on Windows where practical, with Python reserved for the CLI/runtime and release tooling. |
| CPU architecture | `uname -m`, package metadata architecture, or runner architecture for each support claim, including `x86_64`/`amd64`, `arm64`/`aarch64`, and any 32-bit or non-mainstream architecture. |
| Hardware class | VM, container, desktop, server, edge appliance, IoT gateway, embedded Linux host, or customer-managed hardware evidence. |
| ARM and IoT | Client-only, certificate-server, or password-server mode tested; required host tools present; storage, clock, and service-manager assumptions recorded. |
| FPGA and SoC | Host CPU/OS control-plane evidence only, unless bitstream, accelerator, vendor board support package, or FPGA toolchain evidence is separately approved. |
| Deferred targets | Exception ID, owner, customer impact, expiration, compensating control, and retest trigger. |

## v0.1.24 Release-Prep Checks

Use this sequence to build or verify `v0.1.24` evidence from the final release
candidate before making an enterprise publication or readiness claim.

```bash
git status --short --branch
make clean
make test
make test-containers
tools/provision-release-scanners.sh
make release-package-rehearsal VERSION=0.1.24
make release-security-scan-strict VERSION=0.1.24
make release-security-evidence-validate RELEASE_MATRIX_VALIDATE_FLAGS=--require-pass
make package VERSION=0.1.24
make release-assets-evidence VERSION=0.1.24
make release-matrix-validate \
  RELEASE_MATRIX=docs/release/enterprise-release-evidence/generated/release-assets-matrix.csv \
  RELEASE_MANIFEST=docs/release/enterprise-release-evidence/generated/release-assets-manifest.json \
  RELEASE_MATRIX_VALIDATE_FLAGS=--require-pass
```

Attach or link the generated security scan report, SBOM, dependency inventory,
license report, release asset inventory, matrix files, manifest files, package
checksums, platform coverage declaration, and workflow logs. Keep generated
matrices and manifests in ignored release-evidence paths; do not stage them as
tracked source files. If optional external scanners are skipped, record that as
a release-ticket limitation unless `make release-security-scan-strict` is the
approved gate.

Use `RELEASE_MATRIX_VALIDATE_FLAGS="--require-pass --allow-approved-exceptions"`
only after the generated matrix rows include complete, unexpired exception
metadata and the release ticket contains the approver, compensating control,
customer impact, and re-test plan.

For exploratory local checks on a dirty checkout, use
`make release-security-scan-local VERSION=0.1.24` instead of the release
sequence above. Clean CI and tag/release workflow scans must not pass
`--allow-dirty`.

If GHCR images are in scope, attach the GitHub Packages validation run, image
digests, cosign signing evidence, SBOM/provenance evidence, and the protected
`github-packages` environment approval or exception.

For `v0.1.24`, attach fresh workflow evidence from the final commit. Do not
reuse `v0.1.13` workflow results, ignored local scan output, or dirty-tree scan
output as release evidence for this candidate. Historical `v0.1.13` evidence is
summarized in [release-evidence.md](release-evidence.md) for traceability only.

Do not treat `v0.1.24` as enterprise-ready until these version-specific items
are present:

- Clean release commit and matching tag or protected workflow input.
- `Release packages without web`, `Release packages with public web`, `Package install tests`, `Cross OS validation`, and `Container image tests` run URLs.
- GitHub release asset list, `SHA256SUMS`, provenance or attestation output,
  and package-site deployment reference.
- Platform coverage evidence for advertised OS versions, Python/OpenSSH
  versions, CPU architectures, hardware classes, ARM/IoT targets, and FPGA/SoC
  host control-plane claims.
- Production APT/RPM signing-key fingerprint and evidence that generated test signing keys were not used.
- macOS notarization and Windows Authenticode evidence, or approved exception records with expiration and re-test dates.
- Runtime behavior docs and release notes matching password default, explicit
  certificate mode, transfer permission controls, prune semantics,
  package-created account identity safety, and uninstall scope.

Historical `v0.1.13` state checked on 2026-07-07 showed a published release and
asset list, a passing tag/source-commit `Release packages without web` run, a
passing tag/source-commit `Release packages with public web` verification run,
and successful GitHub Packages publication from
`065b03c16a81e9167120e9f41afd4c5e81a79a4a`. The public-web deploy job was
skipped when package-site publish mode was false, so a Pages deployment URL and
deployment ID still need separate evidence when the public package site is in
enterprise scope. `Package install tests` and `Cross OS validation` completed
with failures for the release commit and require remediation, rerun, or approved
exceptions before enterprise readiness. Attach the final container image test
conclusion rather than treating an in-progress run as passing evidence.

## Publish Gate

- Confirm version references agree across `bin/sshfling`, `Makefile`, package metadata, release workflow input, tag name, and release notes.
- Confirm `LICENSE` and commercial distribution language are included in package templates and public package pages.
- Tag only after the release commit is merged and validation inputs are final.
- After publishing, verify the GitHub release, GitHub Pages package site, direct download URLs, checksums, and at least one clean install path from a fresh host or container.

## Release Blockers

Do not publish an enterprise release until these are fixed or formally excepted:

- Docs or release notes describe certificate access as the default.
- Docs or release notes omit that certificate setup requires `--certificate`.
- Docs or release notes overstate `password prune` cleanup by implying active grants or unmanaged records are removed, or by implying existing users are deleted instead of locked/expired.
- Docs or release notes overstate transfer behavior by implying `scp` can set
  owner/group or arbitrary modes, implying `rsync` is bundled, or omitting that
  target umask, account privileges, symlink behavior, timeout, and partial-file
  failure modes affect transfer results.
- Docs or release notes mention `sshfling ca init --force` without warning that
  it replaces the existing CA keypair and requires planned host trust rotation.
- Docs, release notes, or package metadata imply package uninstall removes `/etc/sshfling` configuration, restores original host SSH configuration, or restores package-manager dependencies such as Python, OpenSSH, account-management tools, `procps`, or `util-linux`.
- Docs or release notes omit explicit install and uninstall commands for a
  package channel advertised in the release artifacts, package site, or
  community manifest list.
- Docs, release notes, package metadata, or sales-facing copy claim broad OS,
  language, ARM, IoT, embedded, hardware appliance, or FPGA support without
  release evidence or an approved exception. See
  [language-support.md](language-support.md) for language/runtime claim rules.
- Generated release evidence, matrices, package trees, or local scan outputs
  are staged for commit instead of remaining ignored artifacts linked from the
  release ticket.
- A failed workflow run for the target tag/source commit is being cited as
  passing evidence, or a successful run from a different commit is being used
  without explicit release-ticket approval of the mismatch.
- Production APT/RPM repository publication uses an ephemeral signing key, lacks an approved repository signing fingerprint, or requires weak trust settings such as `trusted=yes`, `gpgcheck=0`, or `repo_gpgcheck=0`.
- Required macOS notarization, Windows Authenticode signing, release approval, validation evidence, rollback owner, or exception records are missing.
- The release claims SOC 2, ISO 27001, NIST, FedRAMP, or similar compliance certification without an approved external attestation or certification record.
