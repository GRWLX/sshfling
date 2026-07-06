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

## Approval Gates

| Gate | Required evidence | Result |
| --- | --- | --- |
| Release request approved | Ticket URL, approver, approval timestamp | Pending |
| Source ready | Protected branch status, PR review, commit SHA | Pending |
| Tag approved | Tag name, tag creator, protected-tag rule, signature status if used | Pending |
| Build validation passed | `Release packages without web` or equivalent run URL | Pending |
| Package-site validation passed | `Release packages with public web` run URL and `verify-public-web` output | Pending |
| Post-publish install validation passed | `Package install tests` run URL | Pending |
| Cross-OS validation passed | `Cross OS validation` run URL, matrix result summary | Pending |
| Runtime behavior docs verified | README, repo docs, wiki, and release notes match implemented password, certificate, prune, and uninstall behavior | Pending |
| Security gates passed | Secret scan, SAST, shell lint, Dockerfile lint, vulnerability scan, systemd review | Pending |
| Rollback ready | Previous version, restore source, authorized rollback owner | Pending |

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
| `apt/InRelease` |  |  |  |  |  |
| `apt/Release.gpg` |  |  |  |  |  |
| `rpm/repodata/repomd.xml.asc` |  |  |  |  |  |

## Runtime Behavior Evidence

Record the behavior contract that users and support teams rely on.

| Behavior | Expected release statement | Evidence |
| --- | --- | --- |
| Password default | Bare `sudo sshfling` creates temporary password access. | README/release-notes link: |
| Explicit certificate mode | Certificate access requires `--certificate`; certificate-only setup options fail without it. | README/release-notes link: |
| Prune semantics | `password prune` removes expired tracked grants only; active grants and unmanaged records are preserved; existing users explicitly allowed with `--allow-existing-user` are locked/expired but not deleted. | Test or docs link: |
| Host uninstall scope | `host uninstall` removes managed certificate host config by default; shared CA, wrapper, policy-user, and Unix-account removal are opt-in. | Docs link: |
| Package uninstall scope | Package uninstall removes package files and managed repo entries, but not host SSH state, password grant state, CA material, `/etc/sshfling` config, or dependency package state. | Docs link: |

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
| Apple signing credentials | macOS package signing/notarization | Managed secret store | Protected release environment |  | Certificate rotation or exposure |
| Windows signing certificate | MSI signing | Managed secret store | Protected release environment |  | Certificate rotation or exposure |

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
| Package site verification | `packaging/verify-public-web.sh` | Pass and no `trusted=yes`, `gpgcheck=0`, or `repo_gpgcheck=0` |  |
| Container image tests | `Container image tests` workflow | Pass |  |
| Package install tests | `Package install tests` workflow | Pass |  |
| Cross-OS validation | `Cross OS validation` workflow | Pass or approved exception per failed target |  |
| Runtime behavior docs | README, docs/wiki, docs/repos.md, release notes | Password default, explicit certificate mode, prune limits, and uninstall limits match implementation |  |
| Secret scanning | Selected scanner | No unresolved high-confidence secret findings |  |
| SAST | Selected scanner | No unresolved critical/high findings |  |
| Shell linting | Selected lint command | No unresolved release-blocking findings |  |
| Dockerfile linting | Selected lint command | No unresolved release-blocking findings |  |
| Vulnerability scanning | Selected scanner | No unresolved critical/high package findings |  |
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
| What happens if a bad package ships? | Rollback owner, previous known-good version, and rollback validation evidence. |
| What residual risks remain? | Open exceptions, expiration dates, and compensating controls. |

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
