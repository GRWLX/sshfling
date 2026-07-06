# Enterprise Readiness Assessment

Assessment date: 2026-07-06

Scope: package publishing readiness for SSHFling, based on the current working tree review of `security_best_practices_report.md`, GitHub Actions workflows, packaging scripts, docs, and tests.

This document is operational compliance guidance for SOC 2, ISO 27001:2022, and
NIST SP 800-53 Rev. 5-style audit readiness. It is not legal advice and does
not assert certification.

## Executive Summary

Overall readiness: 72/100

The package publishing path has meaningful technical controls: version validation, source validation, checksum generation, package-site verification, broad install/runtime tests, and optional APT/RPM repository signing. The main enterprise gaps are governance and evidence gaps: release approval is not represented as a protected gate, production signing-key custody is not documented as an operated control, rollback is not evidenced, and audit trails are not yet packaged for a reviewer.

Estimated time to audit-ready: 2 to 4 weeks, assuming GitHub repository settings and secret custody can be changed outside this documentation-only scope.

## Scope Boundary

In scope:

- Package build and publishing workflows.
- Public package web generation and verification.
- Release artifacts, checksums, signing material, and generated package manifests.
- Release validation workflows and test evidence.
- Operational evidence expected by enterprise customers and SOC 2, ISO 27001,
  and NIST-aligned assessors.

Out of scope for this document:

- Product security fixes already tracked in `security_best_practices_report.md`.
- Legal license review.
- Actual changes to GitHub repository settings, Actions environments, branch/tag protection, or package scripts.

## Control Mapping

| Area | SOC 2 reference | ISO 27001:2022 reference | NIST SP 800-53 Rev. 5 reference | Evidence objective |
| --- | --- | --- | --- | --- |
| Release authorization | CC8.1 | A.8.32 | CM-3, CM-5 | Prove package releases are reviewed, approved, tested, and traceable to a change record. |
| Build and package integrity | CC8.1, CC7.1 | A.8.25, A.8.29 | SA-10, SI-2, CM-6 | Prove artifacts come from the intended source revision and passed validation before publishing. |
| Signing and key management | CC6.1, CC6.6 | A.8.24, A.8.5 | IA-5, SC-12 | Prove signing keys are controlled, rotated, and not exposed to unauthorized users. |
| Secrets handling | CC6.1, CC6.2 | A.5.15, A.5.18, A.8.2 | AC-6, IA-5, PM-12 | Prove repository, workflow, and signing secrets are restricted and reviewed. |
| Rollback and recovery | CC7.4, CC7.5 | A.5.30, A.8.13 | CP-10, IR-4 | Prove a bad package can be withdrawn or reverted with accountable approval. |
| Audit logging | CC7.2, CC7.3 | A.8.15, A.8.16 | AU-2, AU-6, AU-12 | Prove release actions, failures, approvals, and exceptions are retained. |
| Enterprise acceptance | CC2.1, CC3.2 | A.5.8, A.5.37 | CA-2, CA-7, RA-3 | Prove customers receive a clear control checklist and residual-risk statement. |

## Findings

### ER-001: Release Approval Gate Is Not Evidenced

Status: Gap

Control reference: SOC 2 CC8.1; ISO 27001 A.8.32; NIST SP 800-53 CM-3, CM-5

Current state: Tag-triggered release workflows build packages and publish GitHub releases or the public package site. The reviewed workflow files do not show a protected deployment environment, required human approvers, signed tag requirement, or documented release approval record.

Target state: Every production package release is linked to an approved change record, a protected tag, a required reviewer approval, passing validation workflows, and a retained release evidence packet.

Remediation:

1. Require protected tags for `v*` releases and restrict who can create or push them.
2. Add a protected GitHub Actions environment for production package publishing with required reviewers.
3. Require the release ticket to include the evidence packet described in [release-evidence.md](release-evidence.md).
4. Retain approval, run IDs, artifact checksums, Pages deployment URL, and package-site artifact reference with the release.

Estimated effort: 1 to 2 days for repository settings and workflow gating; 1 release cycle to prove operation.

Priority: High

### ER-002: Production Signing-Key Custody Is Not Fully Documented

Status: Partial

Control reference: SOC 2 CC6.1, CC6.6; ISO 27001 A.8.24, A.8.5; NIST SP
800-53 IA-5, SC-12

Current state: The public package workflow can sign APT metadata, RPM packages, and RPM repository metadata using `SSHFLING_REPO_GPG_PRIVATE_KEY`, `SSHFLING_REPO_GPG_FINGERPRINT`, `SSHFLING_REPO_GPG_KEY_ID`, and `SSHFLING_REPO_GPG_PASSPHRASE`. Production package-site publishing now fails if the imported signing key does not match the approved fingerprint. The workflow can also generate an ephemeral repository signing key for local or test package sites. Production key owner, rotation, recovery, revocation, and access review are not evidenced in the repo.

Target state: Production package signing uses a stable approved key. Access to signing secrets is limited, reviewed, and logged. Key fingerprint, creation date, expiration, storage location, rotation plan, and emergency revocation process are retained.

Remediation:

1. Document the approved production signing key fingerprint and owner role.
2. Store the private key and passphrase only in protected CI secrets or a managed secret store.
3. Disable ephemeral signing-key generation for production releases.
4. Review signing-secret access at least quarterly.
5. Record key rotation or revocation events in the release evidence packet.

Estimated effort: 1 to 3 days, depending on whether an external key-management system is used.

Priority: High

### ER-003: macOS And Windows Code Signing Are Enterprise Gaps

Status: Gap

Control reference: SOC 2 CC8.1, CC6.6; ISO 27001 A.8.24, A.8.29; NIST SP
800-53 IA-5, SC-12, SA-10

Current state: Documentation states production `.pkg` distribution should be signed and notarized and production MSI distribution should be Authenticode signed. The reviewed workflows do not show Apple Developer ID signing/notarization or Windows Authenticode signing evidence.

Target state: Enterprise macOS and Windows artifacts are signed by approved certificates, notarized where applicable, and verified before release.

Remediation:

1. Add release evidence fields for certificate subject, issuer, fingerprint, and expiration.
2. Require notarization evidence for macOS `.pkg` releases.
3. Require Authenticode verification output for Windows `.msi` and `.zip` launchers.
4. Treat unsigned desktop artifacts as non-enterprise or pre-production unless they are excluded from enterprise desktop scope through a documented, time-bound exception.

Estimated effort: 3 to 7 days after certificates are available.

Priority: High for enterprise desktop distribution

### ER-004: Rollback Procedure Is Not Evidenced

Status: Gap

Control reference: SOC 2 CC7.4, CC7.5; ISO 27001 A.5.30, A.8.13; NIST SP
800-53 CP-10, IR-4

Current state: Package uninstall paths exist and package-site publishing deploys generated content through GitHub Pages. There is no documented release rollback approval path, prior package-site restoration procedure, or post-rollback verification checklist.

Target state: A failed release can be rolled back by an authorized operator with a documented decision, restored artifact source or package-site artifact, Pages deployment evidence, customer communication record, and post-rollback install validation.

Remediation:

1. Record the previous known-good release version, Pages deployment URL, and package-site artifact before publishing.
2. Preserve generated package-site artifacts or an immutable build output for each release.
3. Define who can approve rollback and who can execute it.
4. After rollback, run `Package install tests` and targeted `Cross OS validation` for the restored version.
5. Attach rollback evidence to the incident or release ticket.

Estimated effort: 1 to 2 days for documentation and repository settings; one tabletop exercise to validate.

Priority: High

### ER-005: Release Audit Trail Is Not Packaged For Review

Status: Partial

Control reference: SOC 2 CC7.2, CC7.3, CC8.1; ISO 27001 A.8.15, A.8.16,
A.8.32; NIST SP 800-53 AU-2, AU-6, AU-12, CM-3

Current state: GitHub Actions run logs, generated checksums, GitHub releases, and Pages deployment records provide raw audit data. The repo does not define the retained evidence bundle auditors and enterprise customers should review.

Target state: Each release has a complete evidence packet organized by control objective, including approvals, source commit, tag, workflow run IDs, artifacts, checksums, signing proof, validation proof, runtime behavior documentation verification, exception approvals, and rollback readiness.

Remediation:

1. Use [release-evidence.md](release-evidence.md) as the release evidence standard.
2. Attach the completed packet to the release ticket or store it in a controlled evidence repository.
3. Retain evidence for the full audit period plus the organization's retention requirement.
4. Include exception records for any skipped validation, unsigned artifact, or failed control.

Estimated effort: 1 day to adopt; 30 to 60 minutes per release after automation.

Priority: Medium

### ER-006: Secrets Handling Needs Access Review Evidence

Status: Partial

Control reference: SOC 2 CC6.1, CC6.2, CC6.3; ISO 27001 A.5.15, A.5.18,
A.8.2; NIST SP 800-53 AC-6, IA-5, PM-12

Current state: The workflow uses GitHub-provided tokens and optional repository signing secrets. The security report found no obvious committed production secrets, and `secrets/*` is ignored except `.gitkeep`. Secret owner, scope, reviewer list, rotation evidence, and emergency revocation procedure are not documented.

Target state: All publishing secrets have named owner roles, scoped access, quarterly access review evidence, rotation cadence, and incident revocation steps.

Remediation:

1. Maintain a release-secret inventory covering GitHub tokens, GPG signing material, Apple credentials, Windows code-signing certificates, and package-registry credentials.
2. Restrict production publishing secrets to protected environments.
3. Record quarterly access review results and removed access.
4. Rotate secrets after maintainer departure, suspected exposure, or failed control.

Estimated effort: 1 to 2 days to inventory and configure; quarterly operational effort thereafter.

Priority: High

### ER-007: Security Gates Are Not Yet Blocking Release

Status: Gap

Control reference: SOC 2 CC7.1, CC8.1; ISO 27001 A.8.8, A.8.25, A.8.28,
A.8.29; NIST SP 800-53 SI-2, SA-10, CM-6

Current state: Existing workflows run functional build, install, package-site, and cross-OS validation. The security report notes that secret scanning, SAST, shell linting, Dockerfile linting, vulnerability scanning, and systemd unit security review are not represented as CI gates.

Target state: High-confidence critical/high security findings block production package publication, or exceptions are approved and time-bound.

Remediation:

1. Add release evidence fields for secret scanning, SAST, shell linting, Dockerfile linting, vulnerability scanning, and systemd security review results.
2. Start non-blocking if needed, then make critical/high findings blocking once false positives are triaged.
3. Require documented exceptions with owner, compensating control, expiration date, and re-test result.

Estimated effort: 2 to 5 days depending on tool selection and false-positive triage.

Priority: Medium

## Enterprise Acceptance Checklist

Use this checklist before calling a release enterprise-ready.

| Requirement | Evidence | Status |
| --- | --- | --- |
| Release has approved change ticket | Ticket URL and approver | Required |
| Release tag is protected and traceable | Tag name, commit SHA, creator, signature status if used | Required |
| Build ran from intended source | Workflow run IDs and checkout SHA | Required |
| Package artifacts generated | Artifact names, sizes, SHA-256 values | Required |
| APT/RPM repository signing verified | GPG fingerprint, `InRelease`, `Release.gpg`, RPM signature, `repomd.xml.asc` | Required for fleet Linux repos |
| macOS package signed and notarized | Developer ID certificate and notarization output | Required for enterprise macOS |
| Windows MSI signed | Authenticode verification output | Required for enterprise Windows |
| Runtime behavior docs verified | README, wiki, and release notes confirm password default, explicit `--certificate` mode, prune limits, and uninstall limits | Required |
| Package web verified before publish | `packaging/verify-public-web.sh` output and run ID | Required |
| Install tests passed | `Package install tests` run ID | Required |
| Cross-OS validation passed or exception approved | `Cross OS validation` run ID and exception record | Required |
| Secrets access reviewed | Secret inventory and reviewer approval | Required quarterly and before first enterprise release |
| Rollback target known | Previous version, Pages deployment URL, package-site artifact, rollback owner | Required |
| Exceptions documented | Owner, risk, compensating control, expiration, re-test date | Required when any gate is skipped |

## Minimum Evidence Retention

Retain for each release:

- Release ticket and approval record.
- Tag, commit SHA, and diff summary.
- GitHub Actions run URLs and logs for release, package web, install tests, and cross-OS validation.
- Generated artifact list with SHA-256 values.
- Signing proof and public key fingerprints.
- Runtime behavior documentation verification, including password-default and explicit-certificate statements.
- Pages deployment URL and package-site artifact reference.
- Exception approvals and re-test evidence.
- Rollback or no-rollback decision record.

Retain for each quarter:

- Maintainer and repository admin access review.
- CI secret access review.
- Signing-key inventory review.
- Sample release evidence packet review.

## Blockers Outside This Documentation Scope

- Repository settings must enforce protected tags, required reviews, and protected environments; these cannot be proven from docs alone.
- Production signing secrets and key custody must be configured in GitHub or a managed secret store.
- macOS notarization and Windows Authenticode signing require platform certificates and workflow changes.
- Security scanning gates require workflow changes and triage ownership.
