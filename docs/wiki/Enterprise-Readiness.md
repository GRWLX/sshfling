# Enterprise Readiness

Use this checklist before treating SSHFling packages as enterprise-ready for a
release.

## Readiness Summary

| Area | Status | Required action |
| --- | --- | --- |
| Versioning | Ready in repo | Use a three-component numeric version and a matching `vX.Y.Z` tag. |
| Linux packages | Ready in repo | Validate `.deb`, `.rpm`, APT metadata, RPM metadata, and repository signing. |
| macOS package | Build supported | Sign and notarize production `.pkg` artifacts outside the current repo workflow if required by policy. |
| Windows MSI | Build supported | Authenticode-sign production MSI artifacts outside the current repo workflow if required by policy. |
| Public package site | Ready in repo | Enable GitHub Pages from Actions and run the public-web workflow. |
| Community manifests | Generated | Submit manually where ecosystem review or maintainer accounts are required. |
| License signaling | Ready in repo | Confirm commercial license approval before redistribution. |
| Release validation | Ready in repo | Run package install tests and cross-OS validation for each published version. |
| Access behavior contract | Ready in repo | Confirm docs and release notes state password-by-default, explicit certificate mode, prune limits, and uninstall cleanup boundaries. |
| Compliance evidence | Partial | Use the release evidence packet for SOC 2, ISO 27001:2022, and NIST SP 800-53 Rev. 5 mapping; do not claim certification from repo evidence alone. |
| Rollback | Operator-owned | Prefer a fixed forward release after external publication. Republish only before consumption or for package-site generation defects. |
| Fleet policy | Operator-owned | Manage `/etc/sshfling/policy.json` and repository trust through configuration management. |

## Go/No-Go Criteria

A release is ready to publish when all of the following are true:

- The release commit is reviewed and merged.
- `make test` passes on the release commit.
- The version passes `packaging/resolve-version.sh`.
- GitHub Actions secrets for repository signing are configured or the release is
  explicitly marked as a non-production test site.
- GitHub Pages deployment from Actions is enabled.
- License approval for the intended publication channels is recorded.
- The release operator knows whether Apple notarization and Authenticode signing
  are required for this release.
- The support owner has reviewed install, uninstall, and cleanup instructions.
- The user-facing docs and release notes match implemented access behavior:
  password mode is the default, certificate mode requires `--certificate`,
  certificate-specific options fail without `--certificate`, `password prune`
  only removes expired tracked password grants, and package uninstall does not
  promise dependency-state rollback.

Do not publish when:

- The version has fewer or more than three numeric components.
- APT or RPM repository registration would require `trusted=yes`,
  `gpgcheck=0`, or `repo_gpgcheck=0`.
- A production fleet would need to trust an ephemeral repository signing key.
- The package site verifier fails.
- The release requires undocumented manual install steps.
- Docs or release notes describe certificate mode as the default access path.
- Docs or release notes imply `password prune --all` removes active grants or
  unmanaged users.
- Docs or release notes imply package uninstall restores Python, OpenSSH,
  account-management tools, `procps`, or `util-linux` to preinstall state.
- The release claims SOC 2, ISO 27001, NIST, FedRAMP, or other compliance
  certification without a separately approved certification or attestation.

## Release Blockers

Treat these as enterprise no-go findings until fixed or formally excepted:

| Blocker | Why it blocks |
| --- | --- |
| Default access path is documented incorrectly | Operators may create or expect the wrong SSH auth material. |
| Certificate setup is documented as implicit | The implementation requires `--certificate` and rejects certificate-only options without it. |
| Prune semantics are overstated | The implementation prunes expired tracked password grants only and preserves active, unmanaged, and existing-user cases. |
| Uninstall dependency rollback is promised | Package managers and fleet policy own dependency state after uninstall. |
| Unsigned or ephemeral-signed fleet repositories are promoted as production | Enterprise Linux clients need stable package trust. |
| Required macOS notarization or Windows Authenticode signing is missing | Enterprise desktop distribution may fail platform policy. |
| Release evidence lacks approval, validation, signing, rollback, or exception records | SOC 2, ISO 27001, and NIST-aligned reviews need retained proof, not intent. |

## Enterprise Deployment Model

Use native packages as the default enterprise deployment channel:

- APT and RPM repositories for Linux fleets.
- Homebrew or signed `.pkg` for macOS workstations.
- MSI through winget, Intune, SCCM, Group Policy, or an internal software
  distribution system for Windows.
- Source tarball and generated community manifests only where the ecosystem and
  license support that path.

SSHFling server-side access controls remain host-local. Package publishing does
not replace host policy, SSH configuration review, or configuration management.

## Required Release Evidence

Each enterprise release should retain:

- Release version and tag.
- Source commit SHA.
- Package workflow run URLs.
- Package-site deployment URL.
- Checksums file URL.
- Repository signing key fingerprint.
- Cross-OS validation run URL.
- Known exceptions, such as unsigned Apple or Windows artifacts when policy
  allows them.

## Documentation Requirements

Before release, verify that these docs still match behavior:

- [README](../../README.md) for quick start, production usage, uninstall, and
  cleanup.
- [Repository Registration](../repos.md) for package manager commands.
- [Build Targets](../build-targets.md) for supported artifacts and validation
  scope.
- [Operations Runbook](Operations-Runbook.md) for release and incident
  handling.
- [Security and Compliance](Security-and-Compliance.md) for signing, audit, and
  policy expectations.

## Fleet Controls

For enterprise hosts:

- Install from signed package repositories where possible.
- Store the repository public key through configuration management.
- Manage `/etc/sshfling/policy.json` through signed packages or configuration
  management.
- Alert on unexpected package changes, repository key changes, and policy file
  changes.
- Password grants are the default server-access path. Use certificate mode
  explicitly when fleet policy forbids temporary local passwords, when the
  target platform is not a supported Linux password host, or when certificate
  custody and CA operations are already managed.
- Keep `/etc/sshfling` root-owned and expose secrets only through the minimum
  group read access needed by the issuer service.

## Support Readiness

Support is ready when operators can answer:

- Which package version is installed?
- Which repository or installer installed it?
- Which policy file is active?
- Which issuer service token and CA key path are configured?
- Which workflows validated the release?
- Which uninstall path applies to the host?
- Which cleanup steps are required for host SSH configuration, temporary
  password grants, and local CA material?
