# Compliance Mapping

Assessment date: 2026-07-07

Scope: SSHFling package publishing, release evidence, and host-side operational
hardening guidance visible in this repository. This map supports readiness
discussions for NIST SP 800-53 Rev. 5, SOC 2, ISO/IEC 27001:2022, and
CIS-style hardening programs. It is not legal advice, not an audit opinion, and
not a certification or attestation.

## How To Use This Map

Use this document as a control-objective crosswalk. For each objective, collect
the evidence listed in [release-evidence.md](release-evidence.md), confirm that
the associated control is actually operated for the release, and record gaps or
exceptions before presenting the release to an assessor or enterprise customer.

Status labels:

- `Evidence defined`: the repo defines what evidence should be retained.
- `Partial`: technical evidence exists or is described, but operation is not
  fully proven from repo contents alone.
- `Gap`: the control needs repository settings, workflow changes, external
  records, or customer-environment evidence before it can be treated as
  operated.
- `Customer-owned`: SSHFling can provide product guidance, but the customer's
  platform, identity, logging, endpoint, and configuration-management controls
  must supply the operating evidence.

## Non-Certification Caveats

- This repository does not prove a SOC 2 report, ISO/IEC 27001 certification,
  NIST authorization to operate, FedRAMP authorization, CIS Benchmark score, or
  penetration-test attestation.
- NIST SP 800-53 control selection depends on the organization's system
  categorization, baseline, overlays, and risk decisions. This document does
  not select Low, Moderate, High, privacy, or FedRAMP baselines.
- SOC 2 criteria, trust service categories, system boundaries, and tests of
  operating effectiveness must be scoped with the service organization and CPA
  firm.
- ISO/IEC 27001 conformity depends on an operated ISMS, risk assessment,
  statement of applicability, internal audit, management review, and external
  certification process where certification is pursued.
- CIS-style hardening here means practical alignment to CIS Controls and
  benchmark-style configuration discipline. It does not assert conformance to a
  specific OS CIS Benchmark unless benchmark scan results and exceptions are
  attached.
- Repository documentation cannot prove live GitHub settings, secret custody,
  access reviews, signing-certificate custody, SIEM retention, or customer host
  configuration. Those require external evidence.

## Practical Control Crosswalk

| Control objective | NIST SP 800-53 Rev. 5 examples | SOC 2 examples | ISO/IEC 27001:2022 examples | CIS-style examples | SSHFling evidence sources | Current status and gap |
| --- | --- | --- | --- | --- | --- | --- |
| Release authorization and change traceability | CM-3, CM-5, CA-7 | CC8.1 | A.8.32, A.5.37 | CIS Controls 4, 16 | Release ticket, protected tag record, PR reviews, workflow run IDs, release approver, evidence packet | Partial: release workflows use `release-signing`, `release-packages`, `github-packages`, and `github-pages` environments, but protected tags, required environment reviewers, and human approval records are external GitHub settings and must be evidenced per release. |
| Build and package integrity | SA-10, SA-11, SI-7, CM-6, SR-11 | CC7.1, CC8.1 | A.8.25, A.8.29, A.8.32 | CIS Controls 2, 4, 16 | Source tag and commit SHA, package workflows, artifact inventory, SHA-256 values, `packaging/verify-public-web.sh`, generated manifests | Partial: checksums and verification are documented; release gates and immutable evidence retention must be operated. |
| Repository and artifact signing | IA-5, SC-12, SC-13, CM-3 | CC6.1, CC6.6, CC8.1 | A.8.24, A.5.17, A.5.18 | CIS Controls 4, 6 | APT `InRelease`, `Release.gpg`, RPM package signatures, `repomd.xml.asc`, production GPG fingerprint, signing workflow run | Partial: public package-site APT/RPM signing paths are implemented and deployment requires stable signing secrets; standalone GitHub release assets still rely on checksums/provenance unless separately signed, and production key owner, storage, rotation, and access review evidence are gaps. |
| macOS and Windows package authenticity | IA-5, SC-12, SA-10, SI-7 | CC6.6, CC8.1 | A.8.24, A.8.29 | CIS Controls 2, 4 | Apple Developer ID certificate, notarization output, Authenticode certificate, verification command output | Partial: macOS signing/notarization and Windows Authenticode signing/verification can be required when external credentials, runner provisioning, and workflow variables are configured, but release evidence is still required. |
| Secrets and privileged release access | AC-2, AC-3, AC-6, IA-5, PM-12 | CC6.1, CC6.2, CC6.3 | A.5.15, A.5.16, A.5.17, A.5.18, A.8.2 | CIS Controls 5, 6 | Release secret inventory, GitHub environment settings, secret-store access review, rotation records, maintainer offboarding records | Partial: repository docs name required secrets and workflows bind them to protected release environments, but live custody and review evidence must come from GitHub or the managed secret store. |
| Security testing and vulnerability management | RA-5, SI-2, SA-11, SA-15, CM-6 | CC7.1, CC7.2, CC8.1 | A.8.8, A.8.25, A.8.28, A.8.29 | CIS Controls 7, 16 | `make release-security-scan-strict`, optional scanner outputs, SBOM, dependency inventory, SAST, shell lint, Dockerfile lint, systemd review | Partial: GHCR and package release workflows run release security gates before publication, and matrix validation supports explicit approved exceptions; remaining gaps are scanner provisioning evidence, vulnerability triage, release-specific outputs, and approvals. |
| Logging, audit trail, and retention | AU-2, AU-6, AU-9, AU-11, AU-12 | CC7.2, CC7.3, CC8.1 | A.8.15, A.8.16, A.8.32 | CIS Control 8 | GitHub Actions logs, GitHub audit log events, release packet, package-site deployment IDs, `sshfling` and `sshfling-session` system logs | Evidence defined: release packet structure exists; actual retention, log centralization, and reviewer activity must be recorded per release and per environment. |
| Host access and account lifecycle | AC-2, AC-6, IA-2, IA-5 | CC6.1, CC6.2, CC6.6 | A.5.15, A.5.18, A.8.2, A.8.5 | CIS Controls 5, 6 | Password grant defaults, explicit `--certificate` mode, policy limits, prune behavior, host uninstall scope, customer account-management records | Customer-owned: SSHFling documents intended behavior; customer IAM, PAM, SSH, OS account, and logging controls must prove operation. |
| Host and service hardening | CM-2, CM-6, CM-7, AC-6 | CC6.1, CC7.1 | A.8.9, A.8.20, A.8.22 | CIS Controls 4, 12 | Root-owned `/etc/sshfling`, managed `policy.json`, restricted CA/token access, loopback issuer default, package manager strict trust settings | Partial: product guidance exists; OS-specific CIS Benchmark scans and configuration-management enforcement are customer-owned gaps. |
| Platform coverage and hardware claims | CA-2, CA-7, CM-8, SA-10 | CC2.1, CC3.2, CC8.1 | A.5.8, A.5.37, A.8.32 | CIS Controls 2, 15, 16 | Cross-OS validation runs, package install tests, release artifact evidence, customer validation records, platform coverage declaration | Evidence defined: artifact matrices and workflow names do not prove every OS version, runtime, CPU architecture, hardware class, ARM/IoT target, or FPGA/SoC control-plane claim; release-specific evidence or approved exceptions are required. |
| Rollback, incident handling, and recovery | IR-4, IR-6, IR-8, CP-10 | CC7.4, CC7.5 | A.5.24, A.5.26, A.5.30, A.8.13 | CIS Controls 11, 17 | Previous known-good release, package-site artifact, rollback approver, restored Pages deployment, post-rollback validation, customer communication | Evidence defined: rollback evidence template exists, but a tested rollback exercise and operated approval path are external evidence. |
| Customer assurance and risk acceptance | CA-2, CA-7, RA-3, PL-2, SR-3 | CC2.1, CC3.2, CC9.2 | A.5.8, A.5.19, A.5.20, A.5.37 | CIS Control 15 | Enterprise acceptance checklist, exceptions, residual-risk statements, customer-facing evidence summary | Partial: docs define evidence to provide; formal risk acceptance and customer contractual commitments remain outside repo scope. |
| License and redistribution review | PL-4, SA-9, SR-3 | CC2.3, CC9.2 | A.5.31, A.5.32 | Customer procurement controls | `LICENSE`, package metadata, release ticket license approval, third-party repository submission approval | Partial: docs call out commercial license handling; legal approval must be recorded externally. |

## Evidence Source Catalog

| Evidence source | What it supports | Required handling |
| --- | --- | --- |
| [release-evidence.md](release-evidence.md) | Per-release evidence packet for approvals, artifacts, validation, signing, rollback, and exceptions | Complete for every production release and store in a controlled evidence repository or release ticket. |
| [enterprise-readiness.md](enterprise-readiness.md) | Gap register and acceptance checklist | Update when repository settings, signing custody, scanning gates, or rollback process change. |
| GitHub Actions run logs | Build provenance, validation, package-site verification, failed-gate records | Retain immutable run URLs, run IDs, checkout SHAs, matrix summaries, and logs for the audit period. |
| GitHub release and Pages deployment records | Published assets, package-site URL, deployment ID, publication actor | Record release URL, Pages deployment ID, asset list, and package-site artifact reference. |
| Artifact checksums and signatures | Package integrity and authenticity | Retain SHA-256 values and signing verification output for every published artifact. |
| Signing-key inventory | Cryptographic key custody and rotation | Record owner role, fingerprint, storage location, creation, expiration, rotation, revocation, and access reviews. |
| Secret inventory and access reviews | Least privilege and privileged release access | Record repository, environment, and secret-store access before first enterprise release and at least quarterly afterward. |
| Security scan outputs | Vulnerability, SAST, SBOM, dependency, license, and configuration evidence | Attach baseline and optional scanner outputs; document unresolved findings as blocking or approved exceptions. |
| Host/system logs | Operational audit records for grants, sessions, service changes, and policy changes | Centralize and retain according to customer policy; do not log passwords, bearer tokens, cookies, private keys, or raw public keys. |
| Rollback or incident ticket | Recovery readiness and incident handling | Record approver, trigger, restored version, restored deployment, validation run IDs, customer communication, and root cause. |
| Customer CIS Benchmark or configuration scans | OS, SSH, endpoint, and platform hardening | Customer-owned evidence; attach benchmark profile, scan result, deviations, and risk acceptance where used. |
| Platform coverage declaration | OS/runtime/CPU/hardware/ARM/IoT/FPGA support claims | Record exact supported, validated, customer-validated, deferred, and unsupported targets with workflow URLs, host facts, artifact hashes, and exception approvals. |

## CIS-Style Hardening Checklist

Use this checklist when an enterprise customer asks how SSHFling aligns to CIS
Controls or benchmark-style host hardening. It is intentionally practical and
does not claim benchmark certification.

| Area | Hardening expectation | Evidence |
| --- | --- | --- |
| Package manager trust | Fleet installs use signed APT/RPM metadata and do not rely on `trusted=yes`, `gpgcheck=0`, or `repo_gpgcheck=0`. | Package-site verification output, repository config samples, public signing key fingerprint. |
| Artifact integrity | Direct downloads include SHA-256 values and published artifacts are not replaced under the same version after external consumption. | `downloads/SHA256SUMS`, GitHub release asset list, release ticket. |
| OS account lifecycle | Temporary password users are time-limited, policy-limited, and pruned; unmanaged users are not deleted by SSHFling prune operations. | Runtime behavior evidence, policy settings, prune logs, customer account review. |
| SSH access mode | Password mode is Linux-oriented; certificate mode is explicit and should be used for firewall appliances or environments that prohibit temporary local passwords. | README/wiki statements, release notes, customer deployment standard. |
| Configuration ownership | `/etc/sshfling` and `policy.json` are root-owned and managed through packages or configuration management. | File ownership evidence, configuration-management run, package manifest. |
| Issuer service exposure | `sshfling serve` remains loopback-only unless an approved deployment uses TLS, mTLS, VPN, or equivalent controls and sets `SSHFLING_ALLOW_REMOTE=1`. | Service unit, environment file, network exposure review, exception approval. |
| CA and token custody | CA keys and issuer tokens are readable only by required privileged users or service identities. | File permissions, group membership, secret-store access review. |
| Logging and monitoring | `sshfling` and `sshfling-session` logs are collected, reviewed, and retained according to enterprise policy; time sync is standardized by the platform owner. | SIEM query, retention policy, time-source configuration, review evidence. |
| Vulnerability and configuration scans | Release artifacts and customer hosts are scanned with approved tooling; OS-specific CIS Benchmark results are retained where required. | Security scan outputs, endpoint scan reports, benchmark exceptions. |
| Recovery | A known-good package-site artifact and package version can be restored with approval and post-rollback validation. | Rollback section of the release evidence packet. |

## Gap Register

| Gap ID | Gap | Needed evidence or decision |
| --- | --- | --- |
| CMP-001 | Production release approval is not proven from source files alone. | Protected tag rule, protected environment approval, release ticket approver, and workflow run IDs. |
| CMP-002 | Production signing-key custody is not fully evidenced. | Key owner, fingerprint, storage, expiration, rotation plan, revocation process, and access review. |
| CMP-003 | macOS notarization and Windows Authenticode signing are not evidenced. | Certificate metadata, notarization result, signature verification output, or approved exception. |
| CMP-004 | Security scan gates need per-release operation evidence. | Scanner outputs, generated matrix/manifest validation, triaged false positives, and approved exception records. |
| CMP-005 | Release evidence packet is defined but not proven as operated for a completed production release. | Completed packet for a release, stored in the release ticket or controlled evidence repository. |
| CMP-006 | Rollback process is documented but not exercised. | Tabletop or live rollback exercise, restored deployment evidence, and post-rollback validation run IDs. |
| CMP-007 | CIS Benchmark conformance is not claimed or evidenced. | Customer-selected OS benchmark profile, scan result, exceptions, remediation plan, and acceptance record. |
| CMP-008 | Organization-level policies are outside this repository. | Access control, incident response, logging retention, risk management, vendor management, and evidence-retention policies. |
| CMP-009 | NIST, SOC 2, and ISO scope decisions are not defined here. | System boundary, NIST baseline or control selection, SOC 2 trust service categories, ISO statement of applicability. |
| CMP-010 | Platform and hardware support claims need release-specific evidence. | Exact OS/runtime/CPU/hardware/ARM/IoT/FPGA scope, validation logs or customer evidence, unsupported target list, exception owner, and expiration. |

## References

- NIST SP 800-53 Rev. 5, Update 1: <https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final>
- AICPA SOC suite resources: <https://www.aicpa-cima.com/resources/landing/system-and-organization-controls-soc-suite-of-services>
- ISO/IEC 27001:2022 overview: <https://www.iso.org/standard/27001>
- CIS Controls v8.1: <https://www.cisecurity.org/controls/v8-1>
- CIS Controls Navigator v8.1: <https://www.cisecurity.org/controls/cis-controls-navigator>
