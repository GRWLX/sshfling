# Enterprise Readiness Assessment

Assessment date: 2026-07-07

Scope: package and container publishing readiness for SSHFling, plus
enterprise vulnerability-intake readiness, based on the current working tree
review of `security_best_practices_report.md`, GitHub Actions workflows,
packaging scripts, docs, and tests.

This document is operational compliance guidance for SOC 2, ISO 27001:2022, and
NIST SP 800-53 Rev. 5-style audit readiness. It is not legal advice and does
not assert certification.

Detailed framework crosswalks, CIS-style hardening guidance, evidence sources,
and non-certification caveats are maintained in
[compliance-mapping.md](compliance-mapping.md).

## Executive Summary

Overall readiness: not audit-ready; package-publishing readiness is partial.

The package publishing path has meaningful technical controls: version
validation, source validation, checksum generation, package-site verification,
release evidence generation, broad install/runtime tests, and optional APT/RPM
repository signing for the public package site. The repo still cannot prove the
controls enterprise assessors will care about most: required release approval,
protected tag settings, protected environment reviewers, production
signing-key custody, completed rollback evidence, macOS signing/notarization
evidence, Windows Authenticode signing, container image signing/provenance,
security scans as blocking gates, a complete vulnerability disclosure policy,
and platform coverage for advertised OS, hardware, ARM, IoT, or FPGA/SoC
targets.

Estimated time to audit-ready depends on external GitHub settings, signing
certificate availability, secret-store controls, and release-operation evidence.
The repository alone is not enough to establish an audit-ready state.

## Scope Boundary

In scope:

- Package build and publishing workflows.
- GitHub Packages container image publishing workflow and container release evidence.
- Public package web generation and verification.
- Release artifacts, checksums, signing material, and generated package manifests.
- Release validation workflows and test evidence.
- Explicit platform coverage evidence for advertised OS versions, language
  runtimes, CPU architectures, hardware classes, ARM/IoT targets, and FPGA/SoC
  host control planes.
- Operational evidence expected by enterprise customers and SOC 2, ISO 27001,
  NIST-aligned, and CIS-style hardening reviews.
- Vulnerability disclosure and supported-version policy readiness.

Out of scope for this document:

- Product security fixes already tracked in `security_best_practices_report.md`.
- Legal license review.
- Actual changes to GitHub repository settings, Actions environments, branch/tag protection, or package scripts.

## Control Mapping Summary

The detailed, caveated control mapping lives in
[compliance-mapping.md](compliance-mapping.md). The table below is a short
readiness summary only.

| Area | SOC 2 reference | ISO 27001:2022 reference | NIST SP 800-53 Rev. 5 reference | CIS-style reference | Evidence objective |
| --- | --- | --- | --- | --- | --- |
| Release authorization | CC8.1 | A.8.32 | CM-3, CM-5 | CIS Controls 4, 16 | Prove package releases are reviewed, approved, tested, and traceable to a change record. |
| Build and package integrity | CC8.1, CC7.1 | A.8.25, A.8.29 | SA-10, SI-2, SI-7, CM-6 | CIS Controls 2, 4, 16 | Prove artifacts come from the intended source revision and passed validation before publishing. |
| Container image publication | CC8.1, CC7.1 | A.8.25, A.8.29 | SA-10, SI-2, SI-7, SR-11 | CIS Controls 2, 4, 16 | Prove GHCR images are approved, signed or attested, scanned, and traceable to immutable digests. |
| Signing and key management | CC6.1, CC6.6 | A.8.24, A.8.5 | IA-5, SC-12 | CIS Controls 4, 6 | Prove signing keys are controlled, rotated, and not exposed to unauthorized users. |
| Secrets handling | CC6.1, CC6.2 | A.5.15, A.5.18, A.8.2 | AC-6, IA-5, PM-12 | CIS Controls 5, 6 | Prove repository, workflow, and signing secrets are restricted and reviewed. |
| Rollback and recovery | CC7.4, CC7.5 | A.5.30, A.8.13 | CP-10, IR-4 | CIS Controls 11, 17 | Prove a bad package can be withdrawn or reverted with accountable approval. |
| Audit logging | CC7.2, CC7.3 | A.8.15, A.8.16 | AU-2, AU-6, AU-11, AU-12 | CIS Control 8 | Prove release actions, failures, approvals, and exceptions are retained. |
| Platform coverage claims | CC2.1, CC3.2, CC8.1 | A.5.8, A.5.37, A.8.32 | CA-2, CA-7, CM-8, SA-10 | CIS Controls 2, 15, 16 | Prove advertised OS, runtime, architecture, hardware, ARM, IoT, and FPGA/SoC host claims are backed by release evidence or approved exceptions. |
| Vulnerability disclosure and response | CC7.1, CC7.2 | A.5.24, A.8.8 | SI-2, IR-6, RA-5 | CIS Controls 7, 17 | Prove security reports have a real intake channel, supported-version policy, triage SLA, advisory process, and customer communication path. |
| Enterprise acceptance | CC2.1, CC3.2 | A.5.8, A.5.37 | CA-2, CA-7, RA-3 | CIS Control 15 | Prove customers receive a clear control checklist and residual-risk statement. |

## Findings

### ER-001: Release Approval Gate Is Not Evidenced

Status: Gap

Control reference: SOC 2 CC8.1; ISO 27001 A.8.32; NIST SP 800-53 CM-3, CM-5

Current state: Tag-triggered release workflows build packages and publish
GitHub releases or, when signing secrets are present, the public package site.
The public package-site deploy job names the `github-pages` environment, but
the workflow file cannot prove that the environment has required reviewers. The
reviewed workflow files also do not prove protected tag settings, a signed tag
requirement, or a documented release approval record. The GitHub release asset
workflow does not use a protected environment in source.

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

Current state: The public package workflow can sign APT metadata, RPM packages,
and RPM repository metadata using `SSHFLING_REPO_GPG_PRIVATE_KEY`,
`SSHFLING_REPO_GPG_FINGERPRINT`, `SSHFLING_REPO_GPG_KEY_ID`, and
`SSHFLING_REPO_GPG_PASSPHRASE`. Production package-site deployment requires a
stable signing key and rejects fingerprint mismatch. A tag push without the
required signing secrets is verified as a dry run rather than deployed, which is
safer than publishing unsigned repo metadata but is not evidence of a production
signing control. The GitHub release asset path still relies on checksums,
provenance/attestation, and release evidence unless separate artifact signatures
are added. Production key owner, rotation, recovery, revocation, and access
review are not evidenced in the repo.

Target state: Production package signing uses a stable approved key. Access to signing secrets is limited, reviewed, and logged. Key fingerprint, creation date, expiration, storage location, rotation plan, and emergency revocation process are retained.

Remediation:

1. Document the approved production signing key fingerprint and owner role.
2. Store the private key and passphrase only in protected CI secrets or a managed secret store.
3. Disable ephemeral signing-key generation for production releases.
4. Review signing-secret access at least quarterly.
5. Record key rotation or revocation events in the release evidence packet.

Estimated effort: 1 to 3 days, depending on whether an external key-management system is used.

Priority: High

### ER-003: Desktop Code Signing Evidence Is Incomplete

Status: Partial for macOS; Gap for Windows

Control reference: SOC 2 CC8.1, CC6.6; ISO 27001 A.8.24, A.8.29; NIST SP
800-53 IA-5, SC-12, SA-10

Current state: Documentation states production `.pkg` distribution should be
signed and notarized and production MSI distribution should be Authenticode
signed. The macOS package script can require a signing identity, run
`productbuild --sign`, verify the package with `pkgutil --check-signature`, and
submit/staple/validate notarization when the workflow supplies the signing and
notary environment variables. That is still not enterprise evidence by itself:
Apple credential custody, required workflow variables, certificate metadata,
notarization output, and release approval remain external. The Windows MSI build
still produces `.msi` and `.zip` artifacts without Authenticode signing or
`signtool` verification in source.

Target state: Enterprise macOS and Windows artifacts are signed by approved certificates, notarized where applicable, and verified before release.

Remediation:

1. Add release evidence fields for certificate subject, issuer, fingerprint, and expiration.
2. Require notarization evidence for macOS `.pkg` releases.
3. Add Authenticode signing and verification for Windows `.msi` and `.zip`
   launchers, or attach a documented exception.
4. Treat unsigned or unnotarized desktop artifacts as non-enterprise or
   pre-production unless they are excluded from enterprise desktop scope through a
   documented, time-bound exception.

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

Current state: Existing workflows run functional build, install, package-site,
and cross-OS validation. The repository also includes `make
release-security-scan` and optional scanner hooks for release evidence. The
reviewed workflows do not invoke those targets as required publication gates,
and no release policy in source defines critical/high findings as blocking.

Target state: High-confidence critical/high security findings block production package publication, or exceptions are approved and time-bound.

Remediation:

1. Add release evidence fields for secret scanning, SAST, shell linting, Dockerfile linting, vulnerability scanning, and systemd security review results.
2. Start non-blocking if needed, then make critical/high findings blocking once false positives are triaged.
3. Require documented exceptions with owner, compensating control, expiration date, and re-test result.

Estimated effort: 2 to 5 days depending on tool selection and false-positive triage.

Priority: Medium

### ER-008: CIS-Style Host Hardening Is Customer-Environment Dependent

Status: Partial / Customer-owned

Control reference: SOC 2 CC6.1, CC7.1; ISO 27001 A.8.9, A.8.20, A.8.22;
NIST SP 800-53 CM-2, CM-6, CM-7, AC-6; CIS Controls 4, 5, 6, 8, 12

Current state: The wiki documents package-manager trust expectations, host
account behavior, explicit certificate mode, root-owned configuration, issuer
service exposure limits, and logging expectations. The repo does not include
customer OS benchmark scans, SSHD baseline evidence, SIEM retention proof, or
configuration-management enforcement records.

Target state: Enterprise deployments retain a customer-approved host hardening
profile, OS-specific CIS Benchmark or equivalent scan evidence, documented SSH
and account-policy deviations, centralized log retention, and configuration
management proof for `/etc/sshfling`, SSH settings, issuer tokens, and CA
material.

Remediation:

1. Use the CIS-style checklist in [compliance-mapping.md](compliance-mapping.md)
   during enterprise deployment review.
2. Record the customer's selected OS benchmark profile or alternative hardening
   standard.
3. Attach scan results, accepted deviations, remediation owners, and expiration
   dates to the release or deployment evidence.
4. Confirm that SSHFling logs are centralized and retained according to the
   customer's audit-log policy.
5. Treat host-specific hardening evidence as customer-owned unless SSHFling is
   operating the host environment.

Estimated effort: 1 to 3 days for customer evidence collection after the
customer's baseline tooling is available.

Priority: Medium for product release; High for managed enterprise deployments

### ER-009: Platform Coverage Claims Need Explicit Evidence

Status: Gap

Control reference: SOC 2 CC2.1, CC3.2, CC8.1; ISO 27001 A.5.8, A.5.37,
A.8.32; NIST SP 800-53 CA-2, CA-7, CM-8, SA-10; CIS Controls 2, 15, 16

Current state: Build target documentation lists release artifacts, generated
community manifests, and the current cross-OS validation workflow scope. Release
tooling can generate artifact and package-site evidence matrices, but those
matrices do not by themselves prove runtime support for every OS version,
language/runtime version, CPU architecture, hardware class, ARM/IoT target, or
FPGA/SoC host-control-plane claim. Large generated matrices under
`docs/release/enterprise-release-evidence/` are ignored and should be attached
or linked from the release ticket rather than treated as tracked source.

Target state: Every enterprise release keeps a reviewer-friendly platform
coverage declaration that identifies required, validated, community, customer
validated, deferred, and unsupported platforms. Each affirmative platform claim
has evidence such as workflow run URL, package install log, OS release data,
Python/OpenSSH versions, CPU architecture, hardware class, artifact hash, or an
approved exception.

Remediation:

1. Add the platform coverage declaration to the release evidence packet or
   release ticket rather than committing a large generated matrix.
2. For each advertised OS or distribution family, record exact version,
   package format, install source, validation workflow, and owner of any
   exception.
3. Record Python implementation/version, OpenSSH client/server versions, shell
   or PowerShell version where relevant, and account-management tool evidence
   for password-grant server claims.
4. Record CPU architecture evidence for `x86_64`/`amd64`, `arm64`/`aarch64`,
   and any 32-bit, `s390x`, `ppc64le`, or `riscv64` claims.
5. Treat ARM, IoT, embedded Linux, and FPGA/SoC platforms as explicit coverage
   tiers. For FPGA/SoC systems, limit claims to the host CPU/OS control plane
   running Python and OpenSSH unless FPGA fabric, bitstream, accelerator, or
   vendor toolchain behavior has separate evidence.
6. Keep generated release evidence under ignored paths such as
   `docs/release/enterprise-release-evidence/` and attach or link the reviewed
   output from the release ticket.

Estimated effort: 1 day to define the declaration format; 30 to 60 minutes per
release after validation jobs and customer evidence are available.

Priority: Medium for product release; High when marketing, sales, or customer
contracts name specific ARM, IoT, or embedded hardware targets.

### ER-010: GHCR Container Image Publishing Needs External Controls

Status: Partial

Control reference: SOC 2 CC8.1, CC7.1; ISO 27001 A.8.25, A.8.29; NIST SP
800-53 SA-10, SI-2, SI-7, SR-11

Current state: `.github/workflows/github-packages.yml` publishes SSHFling
client and server container images to GHCR only from `v*` tag pushes or manual
workflow dispatch. The workflow validates source tests, release security
evidence, release evidence validation, and the container/package lifecycle
matrix before the publish job can run. The publish job uses the
`github-packages` environment, requests `id-token: write` and `packages: write`,
builds from `ssh-client/Dockerfile` and `ssh-server/Dockerfile`, emits
tag/version/SHA image tags, publishes Docker provenance and SBOM attestations,
and signs pushed image digests with keyless Sigstore/cosign.

Remaining gaps: GitHub environment reviewers, protected tag/ruleset
enforcement, image vulnerability thresholds, consumer digest pinning or
signature verification, and retained cosign verification evidence are external
or release-run controls and still need proof before GHCR images can be called
enterprise-ready distribution artifacts.

Target state: Production container images are published only from approved
protected releases, are traceable to source commit and workflow run, are signed
or attested, have SBOM and vulnerability evidence, and are consumed by immutable
digest or verified signature.

Remediation:

1. Configure required reviewers for the `github-packages` environment and
   protected tag/ruleset controls for release tags.
2. Retain image digests, cosign signing and verification output, SBOMs, and
   provenance attestations in release evidence.
3. Define critical/high vulnerability thresholds or approved exceptions before
   publishing production image tags.
4. Require enterprise consumers to pin image digests or verify signatures
   instead of deploying mutable tags.
5. Add release evidence hooks for GHCR digests and verification logs alongside
   package artifacts.

Estimated effort: 1 to 2 days after GitHub environment rules, tag protection,
vulnerability thresholds, and consumer verification requirements are approved.

Priority: High if GHCR images are enterprise distribution artifacts; Medium if
they remain test-harness convenience images only.

### ER-011: Security Policy And Vulnerability Intake

Status: Source policy added; operational evidence still required

Control reference: SOC 2 CC7.1, CC7.2; ISO 27001 A.5.24, A.8.8; NIST SP
800-53 SI-2, IR-6, RA-5

Current state: `SECURITY.md` now defines SSHFling supported-version scope,
private vulnerability reporting expectations, acknowledgement and triage
targets, coordinated disclosure expectations, and security scope. Enterprise
release evidence still needs proof that the private intake channel is monitored
and that support-channel ownership matches the current customer agreement.

Target state: Security reporters and enterprise customers can identify
supported versions, report vulnerabilities through a monitored private channel,
receive expected response timelines, and track fixes, advisories, CVEs or
release notes, and workarounds without exposing sensitive report details.

Remediation:

1. Attach evidence that the private GitHub vulnerability reporting path or
   enterprise support channel is monitored by the release owner.
2. Record the supported release line and any enterprise support exceptions in
   the release ticket.
3. Document how advisories, CVEs if applicable, fixed versions, workarounds,
   and customer notifications are handled for the release.
4. Add a quarterly check that the reporting channel is monitored and the policy
   still matches supported releases.

Estimated effort: 1 day for policy content; ongoing operational review each
release and quarter.

Priority: High for enterprise/customer-facing releases.

## Enterprise Acceptance Checklist

Use this checklist before calling a release enterprise-ready.

| Requirement | Evidence | Status |
| --- | --- | --- |
| Release has approved change ticket | Ticket URL and approver | Required |
| Release tag is protected and traceable | Tag name, commit SHA, creator, signature status if used | Required |
| Build ran from intended source | Workflow run IDs and checkout SHA | Required |
| Package artifacts generated | Artifact names, sizes, SHA-256 values | Required |
| GHCR image publication controlled | Image names, immutable digests, signing/attestation proof, SBOM, vulnerability scan, protected publish approval | Required if container images are enterprise artifacts |
| Platform coverage declared | Exact OS/runtime/CPU/hardware/ARM/IoT/FPGA scope, evidence links, and exceptions | Required before making broad support claims |
| APT/RPM repository signing verified | GPG fingerprint, `InRelease`, `Release.gpg`, RPM signature, `repomd.xml.asc` | Required for fleet Linux repos |
| macOS package signed and notarized | Developer ID certificate and notarization output | Required for enterprise macOS |
| Windows MSI signed | Authenticode verification output | Required for enterprise Windows |
| Runtime behavior docs verified | README, wiki, and release notes confirm password default, explicit `--certificate` mode, prune limits, and uninstall limits | Required |
| Security policy published | Supported versions, private reporting channel, SLA, advisory process, and customer notification path | Required before enterprise release |
| Package web verified before publish | `packaging/verify-public-web.sh` output and run ID | Required |
| Install tests passed | `Package install tests` run ID | Required |
| Cross-OS validation passed or exception approved | `Cross OS validation` run ID and exception record | Required |
| Secrets access reviewed | Secret inventory and reviewer approval | Required quarterly and before first enterprise release |
| CIS-style host hardening reviewed | Selected OS benchmark or equivalent hardening profile, scan results, deviations, and retention/logging evidence | Required for managed enterprise deployments; customer-owned for self-managed hosts |
| Rollback target known | Previous version, Pages deployment URL, package-site artifact, rollback owner | Required |
| Exceptions documented | Owner, risk, compensating control, expiration, re-test date | Required when any gate is skipped |

## Minimum Evidence Retention

Retain for each release:

- Release ticket and approval record.
- Tag, commit SHA, and diff summary.
- GitHub Actions run URLs and logs for release, package web, install tests, and cross-OS validation.
- Generated artifact list with SHA-256 values.
- GHCR image names, immutable digests, signing or attestation proof, SBOM,
  vulnerability scan output, and publish approval when container images are in
  enterprise scope.
- Platform coverage declaration covering OS versions, Python/OpenSSH versions,
  CPU architecture, hardware class, ARM/IoT/FPGA scope, evidence links, and
  exceptions.
- Signing proof and public key fingerprints.
- Runtime behavior documentation verification, including password-default and explicit-certificate statements.
- Pages deployment URL and package-site artifact reference.
- Exception approvals and re-test evidence.
- Rollback or no-rollback decision record.

Retain for each quarter:

- Maintainer and repository admin access review.
- CI secret access review.
- Signing-key inventory review.
- Vulnerability reporting channel and security policy review.
- Sample release evidence packet review.

## Blockers Outside This Documentation Scope

- Repository settings must enforce protected tags, required reviews, and protected environments; these cannot be proven from docs alone.
- Production signing secrets and key custody must be configured in GitHub or a managed secret store.
- macOS notarization requires platform certificates, required workflow variables,
  and retained notarization evidence. Windows Authenticode signing still requires
  platform certificates and workflow changes.
- GHCR container publishing now has source-defined test/security/container gates,
  SBOM/provenance, digest signing, and a named publish environment. GitHub
  environment reviewers, tag protection, vulnerability thresholds, and consumer
  digest/signature verification still require release evidence or policy.
- Security scanning gates require workflow changes and triage ownership.
- Vulnerability-intake ownership and quarterly security-policy review need operational evidence in the release or compliance packet.
- Broad OS, runtime, CPU architecture, hardware, ARM, IoT, or FPGA/SoC support
  claims require release-specific evidence; current artifact matrices and
  workflow names are not enough by themselves.
