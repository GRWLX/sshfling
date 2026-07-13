# SSHFling Enterprise Publishing Wiki

This wiki is the enterprise release-operator entry point for publishing and
operating SSHFling packages.

SSHFling is licensed under the Apache License, Version 2.0. Redistributing or
submitting generated package manifests to third-party repositories must preserve
the project `LICENSE` file and any required notices.

## Start Here

- [Package Publishing](Package-Publishing.md): release prerequisites, GitHub
  Actions workflow order, signing setup, public package-site validation, and
  installer examples.
- [Enterprise Readiness](Enterprise-Readiness.md): go/no-go checklist for
  package publishing, fleet deployment, supportability, and release evidence.
- [Operations Runbook](Operations-Runbook.md): release-day procedure,
  monitoring, rollback guidance, key rotation, and incident handling.
- [Security and Compliance](Security-and-Compliance.md): package signing,
  repository trust, access controls, audit expectations, and SOC 2, ISO 27001,
  NIST, and CIS-style evidence mapping without certification claims.

## Canonical Project Docs

- [README](../../README.md): user quick start, production SSHFling commands,
  uninstall and cleanup, Docker test harness, and local package build commands.
- [Repository Registration](../repos.md): APT, RPM, Homebrew, macOS pkg,
  Windows MSI, and community package registration examples.
- [Build Targets](../build-targets.md): release artifact matrix and
  cross-platform validation scope.
- [Release Checklist](../release-checklist.md): pre-tag and publish gates for
  enterprise package releases.
- [Release Evidence Packet](../release-evidence.md): template for release
  approvals, artifacts, signing, validation, rollback, and exceptions.
- [Compliance Mapping](../compliance-mapping.md): caveated SOC 2, ISO
  27001:2022, NIST SP 800-53 Rev. 5, and CIS-style control crosswalk.
- [SSHFling Threat Model](../threat-model.md): package, access, issuer,
  OpenSSH, and AI-assisted workflow threats, assumptions, and residual risks.
- [OpenSSH Dependency Policy](../openssh-dependencies.md): OpenSSH, Python,
  package dependency, uninstall, and original-state ownership rules.
- [Enterprise Readiness Assessment](../enterprise-readiness.md): SOC 2, ISO
  27001, and NIST package-publishing gap assessment.
- [Codex and Enterprise Detached Workflows](../codex-enterprise-workflow.md):
  enterprise temporary access and detached job guidance.
- [AI-Assisted Temporary Server Access](../ai-temporary-access.md): security
  model for AI-assisted operations without installing AI daemons on target
  servers.

## Publishing Boundary

Use this wiki for package-publishing operations. Keep lower-level install
commands, platform details, and target matrix updates in the canonical project
docs above, then link to them here.

For install examples, download remote scripts to a temporary path and execute
the saved file. Do not document `curl ... | sh` or `curl ... | bash` patterns
for SSHFling package installs.
