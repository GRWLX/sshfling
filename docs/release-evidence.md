# Release Evidence Packet

Use this template for every production package release. The completed packet should live in the release ticket or controlled evidence repository and should link back to immutable workflow runs, artifacts, and approvals.

This packet supports SOC 2, ISO 27001:2022, and NIST SP 800-53 Rev. 5 evidence
collection. It is not legal advice and does not assert certification or
attestation by itself.

Release version:

Release date:

Release owner:

Change ticket:

Source tag:

Source commit SHA:

Pages deployment URL:

Pages deployment ID:

Package-site artifact name:

Previous known-good version:

Compliance mapping reference: [compliance-mapping.md](compliance-mapping.md)

Threat model reference: [threat-model.md](threat-model.md)

OpenSSH dependency policy reference: [openssh-dependencies.md](openssh-dependencies.md)

NIST control selection or baseline, if applicable:

SOC 2 system boundary and trust service categories, if applicable:

ISO/IEC 27001 statement of applicability reference, if applicable:

CIS Benchmark or equivalent hardening profile, if applicable:

Non-certification caveat acknowledged by release approver: Yes / No

## v0.1.14 Release-Prep Snapshot

Use this section for the next release ticket. Attach final, immutable evidence
from the `v0.1.14` tag or protected workflow input before publication.

- `0.1.14` is the fixed-forward source/package candidate after the published
  `v0.1.13` release.
- The candidate includes prune identity-mismatch preservation, incomplete CA
  keypair rejection, explicit `cert issue --certificate -t/--time` lifetime
  enforcement, OpenSSH server preflight checks for password-host setup, DEB/RPM
  service-account identity preservation during uninstall, macOS signing and
  notarization workflow gates, generated macOS installer trust checks, Windows
  ZIP checksum verification, and Windows MSI uninstall narrowing.
- Do not publish or call `v0.1.14` enterprise-ready until the approval gates
  below are complete for the final commit.
- Generated evidence for this candidate must remain under ignored paths such as
  `docs/release/enterprise-release-evidence/`, `build/`, `dist/`,
  `package-dist/`, or `release-dist/`; attach reviewed outputs to the release
  ticket or controlled evidence repository instead of committing them.

Required candidate evidence:

- Clean final candidate commit and matching `bin/sshfling --version` output.
- Passing local `make test`, `make test-containers`, release package rehearsal,
  release security scan/evidence validation, workflow static check, and
  `git diff --check`.
- Passing immutable GitHub workflow URLs for release packages, public package
  site verification, package install tests, cross-OS validation, and container
  image tests, or approved exceptions with scope and expiration.
- Production APT/RPM signing fingerprint, macOS notarization output, Windows
  Authenticode output, and evidence that generated test keys were not used for
  production package-site publication.

## v0.1.13 Published Release Snapshot

Use this snapshot to seed the release ticket. Attach final, immutable evidence
from GitHub runs, release assets, and approval records before making enterprise
readiness claims.

- `v0.1.13` is tagged at source commit
  `065b03c16a81e9167120e9f41afd4c5e81a79a4a` on 2026-07-07.
- Remote `refs/tags/v0.1.13` is annotated tag object
  `b8e5b070dbfeae4f61741b579f6aa2f99689942a`; the peeled commit is
  `065b03c16a81e9167120e9f41afd4c5e81a79a4a`. Local signature verification
  reported `error: no signature found`, so treat tag signature evidence as
  absent unless a separate protected-tag control is attached.
- GitHub release `v0.1.13` is published, not draft, and not prerelease:
  https://github.com/GRWLX/sshfling/releases/tag/v0.1.13. GitHub reports it
  was created at 2026-07-07T02:44:14Z and published at 2026-07-07T02:45:05Z.
  The release has eight assets: `RELEASE-EVIDENCE.md`, `SHA256SUMS`,
  `sshfling_0.1.13_all.deb`, `sshfling-0.1.13-1.noarch.rpm`,
  `sshfling-0.1.13.tar.gz`, `sshfling-0.1.13.pkg`,
  `sshfling-0.1.13.msi`, and `sshfling-0.1.13-windows.zip`.
- The published `RELEASE-EVIDENCE.md` asset records source commit
  `065b03c16a81e9167120e9f41afd4c5e81a79a4a`, workflow run
  https://github.com/GRWLX/sshfling/actions/runs/28837775742, artifact sizes,
  and SHA-256 hashes for the six package/source artifacts.
- `v0.1.13` shipped hardened package publishing evidence hooks, release security
  evidence generation, public package-site verification, GitHub Packages
  container publishing workflow coverage, uninstall-scope documentation, and
  expanded release validation guidance.

GitHub Actions state verified on 2026-07-07:

- Tag/source commit `065b03c16a81e9167120e9f41afd4c5e81a79a4a` has successful
  `Release packages without web` run
  https://github.com/GRWLX/sshfling/actions/runs/28837775742. The publish job
  generated checksums, release evidence, release matrix evidence, provenance
  attestation, and uploaded release assets.
- Tag/source commit `065b03c16a81e9167120e9f41afd4c5e81a79a4a` has successful
  `Release packages with public web` run
  https://github.com/GRWLX/sshfling/actions/runs/28837775739. The package web
  verification and generated evidence gate passed, but `Deploy package web` and
  package-site attestation were skipped when publish mode was false. Do not cite
  this as Pages deployment evidence without a separate deployment URL and
  deployment ID.
- Tag/source commit `065b03c16a81e9167120e9f41afd4c5e81a79a4a` has successful
  `GitHub Packages` run
  https://github.com/GRWLX/sshfling/actions/runs/28837775737.
- `Package install tests`
  https://github.com/GRWLX/sshfling/actions/runs/28837877578 and `Cross OS
  validation` https://github.com/GRWLX/sshfling/actions/runs/28837877655
  completed with failures when checked. Do not cite them as passing release
  validation without remediation, rerun evidence, or approved exceptions.
- `Container image tests`
  https://github.com/GRWLX/sshfling/actions/runs/28837770659 was in progress
  when checked. Attach the final conclusion or a later matching source-commit
  run before treating it as release validation evidence.

Evidence currently present in the repository:

- Source tag and commit history for `v0.1.13`.
- Published GitHub release URL and asset list for `v0.1.13`.
- Release checklist and evidence templates.
- Release asset evidence generator and matrix validator.
- Release security evidence generator for baseline secret scanning, SBOM,
  dependency inventory, license scan, Dockerfile hygiene, systemd hardening, and
  optional external scanner records.
- Compliance mapping, threat model, and OpenSSH dependency policy documents.
- README and release checklist language for password default, explicit
  certificate mode, access-level classification, prune limits, and uninstall
  limits.

Evidence still required before enterprise publication:

- Protected release approval and protected-tag or equivalent change-control
  evidence for the published tag.
- Passing immutable workflow URLs for release packages, public package site,
  package install tests, cross-OS validation, and container image tests. Do not
  treat queued, in-progress, skipped, or wrong-commit runs as passing evidence.
- Artifact inventory with SHA-256 values, sizes, signing status, release asset
  URLs, `SHA256SUMS`, and provenance or attestation output.
- APT/RPM production signing fingerprint and proof that generated test keys were
  not used.
- macOS notarization and Windows Authenticode verification output, or approved
  exception records.
- Pages deployment URL, deployment ID, package-site artifact name, rollback
  owner, and previous known-good restore source.
- Access-level policy evidence for any operator, sudo-limited, admin, or
  root-equivalent grant paths, including host-control evidence for actual
  privileges.

Generated evidence handling:

- Store generated release matrices, manifests, and artifact evidence under the
  ignored `docs/release/enterprise-release-evidence/` tree.
- Attach or link the reviewed generated files from the release ticket or
  controlled evidence repository instead of committing generated evidence.
- Treat any generated matrix or manifest outside the ignored evidence tree as a
  release hygiene exception that must be moved or explicitly approved.

## Compliance Mapping Status

Use this section to confirm that the release evidence is mapped without
overstating compliance. A mapped control is not an attestation unless the
organization's audit or certification process accepts the evidence.

| Control objective | Mapping source | Evidence owner | Result or exception |
| --- | --- | --- | --- |
| Release authorization and change traceability | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Build and package integrity | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Repository and artifact signing | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Secrets and privileged release access | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Security testing and vulnerability management | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Logging, audit trail, and retention | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Host access and account lifecycle | [compliance-mapping.md](compliance-mapping.md) |  |  |
| CIS-style host and service hardening | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Rollback, incident handling, and recovery | [compliance-mapping.md](compliance-mapping.md) |  |  |
| Customer assurance and residual-risk acceptance | [compliance-mapping.md](compliance-mapping.md) |  |  |

## Approval Gates

| Gate | Required evidence | Result or exception |
| --- | --- | --- |
| Release request approved | Ticket URL, approver, approval timestamp | Release-ticket evidence required |
| Compliance mapping reviewed | Control scope, caveats, evidence owner, and exceptions recorded above | Release-ticket evidence required |
| Source ready | Protected branch status, PR review, commit SHA | Release-ticket evidence required |
| Tag approved | Tag name, tag creator, protected-tag rule, signature status if used | Release-ticket evidence required |
| Build validation passed | `Release packages without web` or equivalent run URL | Release-ticket evidence required |
| Package-site validation passed | `Release packages with public web` run URL and `verify-public-web` output | Release-ticket evidence required |
| Post-publish install validation passed | `Package install tests` run URL | Release-ticket evidence required |
| Cross-OS validation passed | `Cross OS validation` run URL, matrix result summary | Release-ticket evidence required |
| Runtime behavior docs verified | README, repo docs, wiki, and release notes match implemented password, certificate, access-level, prune, and uninstall behavior | Release-ticket evidence required |
| Security gates passed | Secret scan, SBOM, license scan, dependency inventory, SAST, shell lint, Dockerfile lint, vulnerability scan, systemd review | Release-ticket evidence required |
| Rollback ready | Previous version, restore source, authorized rollback owner | Release-ticket evidence required |

## Artifact Inventory

Record every published artifact, including package-site outputs and release assets.

| Artifact | Source workflow | SHA-256 | Size | Signed | Verification evidence |
| --- | --- | --- | --- | --- | --- |
| `sshfling_VERSION_all.deb` |  |  |  |  |  |
| `sshfling-VERSION-1.noarch.rpm` |  |  |  |  |  |
| `sshfling-VERSION.tar.gz` |  |  |  |  |  |
| `sshfling-VERSION.pkg` |  |  |  |  |  |
| `sshfling-VERSION.msi` |  |  |  |  |  |
| `sshfling-VERSION-windows.zip` |  |  |  |  |  |
| `security-scans/sbom.spdx.json` | `make release-security-scan` or equivalent |  |  | N/A | Generated SPDX SBOM and `security-scan-manifest.json` |
| `apt/InRelease` |  |  |  |  |  |
| `apt/Release.gpg` |  |  |  |  |  |
| `rpm/repodata/repomd.xml.asc` |  |  |  |  |  |

## Runtime Behavior Evidence

Record the behavior contract that users and support teams rely on.

| Behavior | Expected release statement | Evidence |
| --- | --- | --- |
| Password default | Password mode is the default access type, but temporary access requires an explicit `-t/--time` lifetime such as `sudo sshfling -t 10m`; bare `sudo sshfling` fails before creating access. | [README.md](../README.md), [tests/cross-os/validate-cli.sh](../tests/cross-os/validate-cli.sh), [tests/cross-os/validate-cli.ps1](../tests/cross-os/validate-cli.ps1) |
| Explicit certificate mode | Certificate access requires `--certificate`; certificate-only setup options fail without it; certificate setup requires a complete CA keypair and fails before creating client material if the CA is missing or incomplete; `cert issue --certificate` requires explicit `-t/--time` or `--seconds`. | [README.md](../README.md), [tests/cross-os/validate-cli.sh](../tests/cross-os/validate-cli.sh), [tests/cross-os/validate-cli.ps1](../tests/cross-os/validate-cli.ps1) |
| Access-level classification | `--access-level` and `--role` classify least-privilege policy intent and do not grant sudo, administrator, group, IAM, or root-equivalent privileges. Host controls enforce actual privileges. | [README.md](../README.md), [wiki Package Publishing](wiki/Package-Publishing.md), [tests/cross-os/validate-cli.sh](../tests/cross-os/validate-cli.sh) |
| Prune semantics | `password prune` requires exactly one selector, `--all` or `--username USER`; it removes expired tracked grants only; active grants and unmanaged records are preserved; existing users explicitly allowed with `--allow-existing-user` are locked/expired but not deleted; root-equivalent users are never mutated from password-grant metadata or host-user markers; recreated or mismatched Unix identities are skipped before SSHFling removes managed config or metadata. | [tests/cross-os/validate-cli.sh](../tests/cross-os/validate-cli.sh), [tests/cross-os/validate-cli.ps1](../tests/cross-os/validate-cli.ps1), [tests/docker/run-production-test.sh](../tests/docker/run-production-test.sh) |
| Transfer wrapper behavior | `sshfling scp` command construction uses native OpenSSH scp with the same password-oriented SSH options as client connect, defaults to forced-command-compatible legacy scp protocol, supports recursive and mode/mtime preserve flags, and rejects unsafe explicit mode or owner/group rewriting. `sshfling rsync` command construction wraps rsync over SSH, reports an actionable local missing-rsync error, and exposes recursive, preserve, symlink, chmod, owner/group, and chown controls without promising owner/group changes when account privileges do not allow them. Attach manual live-transfer smoke evidence before claiming target-side copy, symlink, permission, timeout, or partial-file behavior for a release. | [README.md](../README.md), [docs/ai-temporary-access.md](ai-temporary-access.md), [tests/cross-os/validate-cli.sh](../tests/cross-os/validate-cli.sh), [tests/cross-os/validate-cli.ps1](../tests/cross-os/validate-cli.ps1) |
| Host uninstall scope | `host uninstall` removes managed certificate host config by default; shared CA, wrapper, policy-user, and Unix-account removal are opt-in. Unix-account deletion requires the SSHFling host-user marker written by `host install --create-user`. | [install-uninstall.md](install-uninstall.md), [tests/cross-os/validate-cli.sh](../tests/cross-os/validate-cli.sh) |
| Package uninstall scope | Package uninstall removes package files and managed repo entries, but not host SSH state, password grant state, CA material, `/etc/sshfling` config, dependency package state, or original host configuration. Package-created service accounts are removed only when current UID/GID/home identity matches package state. Dependency autoremove/autopurge is a separate fleet action. macOS package notes and Windows MSI metadata state this scope. | [install-uninstall.md](install-uninstall.md), [tests/docker/run-container-image-tests.sh](../tests/docker/run-container-image-tests.sh), [packaging/build-deb.sh](../packaging/build-deb.sh), [packaging/build-rpm.sh](../packaging/build-rpm.sh) |

## Threat Model And Dependency Review

Use this section to record that release-specific security assumptions still
match the implementation and deployment plan. Do not treat this as a penetration
test or external security assessment.

| Review item | Evidence source | Result or exception |
| --- | --- | --- |
| Threat-model assumptions reviewed | [threat-model.md](threat-model.md), release notes, deployment plan |  |
| Package supply-chain abuse paths accepted or mitigated | Release workflows, protected tag/environment evidence, signing evidence |  |
| Privileged temporary-access risks accepted or mitigated | Policy file, access-level evidence, customer host-control evidence |  |
| Issuer and CA custody risks accepted or mitigated | CA key permissions, issuer token storage, service exposure review |  |
| OpenSSH dependency ownership confirmed | [openssh-dependencies.md](openssh-dependencies.md), package metadata, fleet dependency policy |  |
| Original-state evidence retained where full revert is promised | MDM, Intune, Group Policy, configuration-management, backup, or package inventory records |  |

## CIS-Style Hardening Evidence

This section supports CIS Controls and benchmark-style reviews. It does not
claim conformance to a specific CIS Benchmark unless scan results and exceptions
are attached.

| Area | Evidence source | Result or exception |
| --- | --- | --- |
| Package manager trust is strict | `packaging/verify-public-web.sh`, repo config samples, package-site output |  |
| APT/RPM production signing key is stable and approved | GPG fingerprint, key owner, access review |  |
| Direct artifact checksums are retained | `downloads/SHA256SUMS`, release asset list |  |
| `/etc/sshfling` and `policy.json` ownership is enforced | Package manifest or configuration-management record |  |
| Access-level policy classification is least-privilege | Policy file, grant metadata, host IAM/sudo/PAM/AD/MDM/service-control evidence |  |
| CA key and issuer token access is restricted | File permissions, service account membership, secret-store review |  |
| Issuer service exposure is approved | systemd unit, environment file, network review, `SSHFLING_ALLOW_REMOTE` exception if used |  |
| SSHFling logs are centralized and retained | SIEM query, retention policy, sample `sshfling` and `sshfling-session` log records |  |
| Time synchronization is platform-managed | NTP/chrony or enterprise time-service evidence |  |
| OS-specific CIS Benchmark or equivalent scan completed | Customer scan report, profile name, deviations, remediation owners |  |

## Signing And Key Management Evidence

Control references: SOC 2 CC6.1, CC6.6, CC8.1; ISO 27001 A.8.24, A.8.32; NIST SP 800-53 Rev. 5 IA-5, SC-12, CM-3

APT/RPM repository signing:

- Production signing key fingerprint:
- Key owner role:
- Key storage location:
- Key created:
- Key expires:
- Last key access review:
- Signing workflow run:
- Evidence that `SSHFLING_GENERATE_REPO_SIGNING_KEY` was not used for production:

macOS signing and notarization:

- Developer ID certificate subject:
- Certificate fingerprint:
- Certificate expiration:
- Notarization submission ID:
- Stapling or notarization verification output:

Windows signing:

- Authenticode certificate subject:
- Certificate fingerprint:
- Certificate expiration:
- `signtool verify` or equivalent output:

Exception handling:

- Any unsigned artifact must have an exception owner, reason, compensating control, customer impact statement, expiration date, and re-test date.

## Secrets Handling Evidence

Control references: SOC 2 CC6.1, CC6.2, CC6.3; ISO 27001 A.5.15, A.5.18, A.8.2; NIST SP 800-53 Rev. 5 AC-6, IA-5, PM-12

| Secret or credential | Purpose | Storage location | Access scope | Last reviewed | Rotation trigger |
| --- | --- | --- | --- | --- | --- |
| `GITHUB_TOKEN` | Release and Pages publishing | GitHub Actions runtime | Workflow scoped |  | Per GitHub runtime |
| `SSHFLING_REPO_GPG_PRIVATE_KEY` | APT/RPM signing | GitHub secret or managed store | Protected release environment |  | Key rotation or exposure |
| `SSHFLING_REPO_GPG_FINGERPRINT` | APT/RPM trust anchor | GitHub secret or release record | Protected release environment |  | Key rotation, mismatch, or compromised trust anchor |
| `SSHFLING_REPO_GPG_PASSPHRASE` | GPG signing passphrase | GitHub secret or managed store | Protected release environment |  | Key rotation or exposure |
| `SSHFLING_PKG_SIGN_IDENTITY` | macOS package signing identity | GitHub secret or managed store | Protected `release-signing` environment |  | Certificate rotation or exposure |
| `SSHFLING_PKG_SIGN_CERT_P12_BASE64` | macOS Developer ID Installer certificate/private key bundle | GitHub secret or managed store | Protected `release-signing` environment |  | Certificate rotation or exposure |
| `SSHFLING_PKG_SIGN_CERT_PASSWORD` | macOS signing P12 password | GitHub secret or managed store | Protected `release-signing` environment |  | Certificate rotation or exposure |
| `SSHFLING_PKG_NOTARY_PROFILE` | Notary profile name | GitHub secret or managed store | Protected `release-signing` environment |  | Apple notary credential rotation |
| `SSHFLING_PKG_NOTARY_APPLE_ID` | Apple notary account | GitHub secret or managed store | Protected `release-signing` environment |  | Apple account or team change |
| `SSHFLING_PKG_NOTARY_TEAM_ID` | Apple Developer Team ID | GitHub secret or managed store | Protected `release-signing` environment |  | Apple team change |
| `SSHFLING_PKG_NOTARY_PASSWORD` | Apple notary app-specific password | GitHub secret or managed store | Protected `release-signing` environment |  | Password rotation or exposure |
| `SSHFLING_WINDOWS_SIGN_CERT_SHA1` | Windows Authenticode certificate selector | GitHub secret or managed store | Protected `release-signing` environment |  | Certificate rotation or exposure |
| `SSHFLING_WINDOWS_SIGN_CERT_PFX_BASE64` | Windows Authenticode certificate/private key bundle | GitHub secret or managed store | Protected `release-signing` environment |  | Certificate rotation or exposure |
| `SSHFLING_WINDOWS_SIGN_CERT_PASSWORD` | Windows signing PFX password | GitHub secret or managed store | Protected `release-signing` environment |  | Password rotation or exposure |

Required checks:

- No production secrets committed to the repo.
- Workflow logs reviewed for accidental secret disclosure.
- Access to protected release secrets reviewed before first enterprise release and quarterly afterward.
- Departed maintainers removed from repository, environment, and secret-store access.

## Validation Evidence

Control references: SOC 2 CC7.1, CC8.1; ISO 27001 A.8.8, A.8.25, A.8.29; NIST SP 800-53 Rev. 5 SI-2, SA-10, CM-6

| Validation | Evidence source | Expected result | Actual result |
| --- | --- | --- | --- |
| Local source validation | `make test` | Pass |  |
| Release security evidence | `make release-security-scan-strict`; strict workflow scanner provisioning via `tools/provision-release-scanners.sh` | Baseline and external scanner rows pass, and generated `security-scan-matrix.csv` validates with `security-scan-manifest.json` using `--require-pass`; any override uses `--allow-approved-exceptions` and complete unexpired exception fields |  |
| SBOM generation | `security-scans/sbom.spdx.json` | SPDX 2.3 SBOM generated from tracked release source dependency inputs |  |
| Dependency inventory | `security-scans/dependency-inventory.json` | Container base images, apt packages, package runtime requirements, and Nix package references inventoried |  |
| License scan | `security-scans/license-report.json` | Commercial license markers present in source and package metadata generators |  |
| Package site verification | `packaging/verify-public-web.sh` | Pass and no `trusted=yes`, `gpgcheck=0`, or `repo_gpgcheck=0` |  |
| Container image tests | `Container image tests` workflow | Pass |  |
| Package install tests | `Package install tests` workflow | Pass |  |
| Cross-OS validation | `Cross OS validation` workflow | Pass or approved exception per failed target |  |
| Runtime behavior docs | README, docs/wiki, docs/repos.md, release notes | Password default, explicit certificate mode, access-level classification, prune limits, and uninstall limits match implementation |  |
| Compliance mapping | [compliance-mapping.md](compliance-mapping.md) and this packet | Control scope, evidence owners, caveats, and exceptions recorded without certification claims |  |
| Threat-model review | [threat-model.md](threat-model.md) and release ticket | Assumptions, abuse paths, residual risks, and mitigations accepted or excepted for this release |  |
| OpenSSH dependency policy review | [openssh-dependencies.md](openssh-dependencies.md), package metadata, fleet policy | OpenSSH/Python dependency ownership, uninstall scope, and original-state evidence are recorded without rollback overclaims |  |
| Access-level policy validation | `sshfling policy show`, cross-OS validation, grant metadata, host-control evidence | Access levels classify privilege intent, root-equivalent paths require admin classification, and actual privileges are enforced by host controls |  |
| CIS-style package hardening | `packaging/verify-public-web.sh`, package manager config, signatures, checksums | No `trusted=yes`, `gpgcheck=0`, or `repo_gpgcheck=0`; stable production signing key or approved exception |  |
| Customer host hardening | Customer OS benchmark or equivalent scan | Scan result and deviations attached, or customer-owned exception recorded |  |
| Secret scanning | `security-scans/secret-scan-report.json` and `gitleaks` tree/history output | No unresolved high-confidence secret findings |  |
| SAST | Built-in static checks and `bandit` | No unresolved critical/high findings |  |
| Shell linting | Selected lint command | No unresolved release-blocking findings |  |
| Dockerfile linting | Selected lint command | No unresolved release-blocking findings |  |
| Vulnerability scanning | `trivy fs` and `osv-scanner` | No unresolved critical/high package findings |  |
| systemd unit security review | Selected review command | Findings accepted or remediated |  |

## Rollback Evidence

Control references: SOC 2 CC7.4, CC7.5; ISO 27001 A.5.30, A.8.13; NIST SP 800-53 Rev. 5 CP-10, IR-4

Rollback owner role:

Rollback approver role:

Previous Pages deployment URL:

Previous package-site artifact or release source:

Previous GitHub release URL:

Previous artifact checksums retained:

Rollback trigger criteria:

- Critical package install failure.
- Published artifact checksum mismatch.
- Signing-key compromise or suspected compromise.
- High-severity security regression.
- Incorrect version or package metadata published.

Rollback steps:

1. Open or update the incident/change ticket with rollback reason and approver.
2. Stop further publishing runs for the affected version.
3. Redeploy a known-good package-site artifact or regenerate the package site from the previous known-good release artifacts.
4. Verify checksums and signing metadata for the restored version.
5. Re-run targeted install validation for affected ecosystems.
6. Communicate customer impact, affected versions, mitigation, and fixed version.
7. Record final Pages deployment URL, package-site artifact reference, and validation run IDs.

Post-rollback evidence:

- Approval record:
- Restored version:
- Restored Pages deployment URL:
- Restored package-site artifact or release source:
- Validation run IDs:
- Customer communication link:
- Root-cause ticket:

## Audit Trail

Control references: SOC 2 CC7.2, CC7.3, CC8.1; ISO 27001 A.8.15, A.8.16, A.8.32; NIST SP 800-53 Rev. 5 AU-2, AU-6, AU-12, CM-3

Attach or link:

- Release ticket and approval comments.
- Pull request review history.
- Tag creation event and actor.
- GitHub Actions run URLs and retained logs.
- GitHub release URL and asset list.
- Pages deployment URL, deployment ID, and package-site artifact reference.
- Checksums and signing verification output.
- Completed compliance mapping status, including scope decisions and
  non-certification caveat.
- Threat-model review outcome and accepted residual risks.
- OpenSSH dependency/original-state review outcome and any customer-owned
  dependency cleanup decisions.
- Generated security evidence: `security-scan-report.json`, `security-scan-report.md`, `security-scan-matrix.csv`, `security-scan-manifest.json`, `sbom.spdx.json`, `dependency-inventory.json`, `license-report.json`, and optional scanner outputs.
- GitHub organization audit-log entries for tag creation, environment approval, release publication, secret changes, and Pages publication.
- Exception approvals and closure evidence.

## Enterprise Customer Acceptance

Provide this summary to enterprise customers when requested.

| Question | Evidence to provide |
| --- | --- |
| How do we know the package came from the intended source? | Source tag, commit SHA, release workflow run, artifact checksum. |
| How do we verify Linux repository integrity? | APT/RPM public signing key fingerprint, signed metadata, checksum files. |
| Are macOS and Windows packages signed? | Certificate metadata and verification output, or a documented exception. |
| What tests ran before publication? | Package install and cross-OS validation run URLs. |
| Who approved the release? | Change ticket approver and protected environment approval. |
| How are signing keys protected? | Key inventory, access review, and secret-store scope. |
| What privileged-access risks remain? | Threat-model review, access-level policy evidence, host-control evidence, and accepted residual risks. |
| Who owns OpenSSH and runtime dependency versions? | OpenSSH dependency policy, package metadata, fleet package policy, and original-state evidence if full revert is promised. |
| Does this evidence prove SOC 2, ISO 27001, NIST, or CIS certification? | No. Provide the non-certification caveat and the accepted audit or customer scope. |
| How does this align to CIS-style hardening? | Package-manager trust evidence, host hardening profile, log retention evidence, scan results, and customer-owned exceptions. |
| What happens if a bad package ships? | Rollback owner, previous known-good version, and rollback validation evidence. |
| What residual risks remain? | Open exceptions, expiration dates, and compensating controls. |

## Security Gate Exceptions

Use this process only when a release must proceed with a failed, blocked, or
skipped security-gate row. The default release gate is still `--require-pass`.

Required exception evidence:

- `exception_id` from the release, incident, or risk-acceptance ticket.
- `exception_owner` accountable for remediation or retest.
- `exception_expires` as `YYYY-MM-DD` or ISO-8601 timestamp.
- `blocker_reason`, `actual_result`, or `notes` explaining the gate result.
- Approver, compensating control, customer impact, and re-test plan in the
  exception record below.

Validation command for approved exceptions:

```bash
python3 tools/release_matrix_validate.py \
  --matrix docs/release/enterprise-release-evidence/security-scans/security-scan-matrix.csv \
  --manifest docs/release/enterprise-release-evidence/security-scans/security-scan-manifest.json \
  --require-pass \
  --allow-approved-exceptions
```

Expired or incomplete exceptions fail validation. Do not use this path for
routine scanner unavailability; provision scanners with
`tools/provision-release-scanners.sh` or record why the unavailable scanner is
outside the release scope.

## Exception Record

Use one record per skipped or failed gate.

Control reference:

Release version:

Exception owner:

Approver:

Reason:

Affected artifacts or platforms:

Risk:

Compensating control:

Expiration date:

Re-test plan:

Closure evidence:
