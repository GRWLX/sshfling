# Security and Compliance

This guide summarizes package-publishing controls and operational evidence for
enterprise SSHFling releases.

## Compliance Scope

This guide supports control evidence for SOC 2, ISO 27001:2022, and NIST SP
800-53 Rev. 5 programs. It is not legal advice, does not assert certification,
and does not prove compliance by itself. Treat it as an evidence map for release
operators and auditors.

Detailed framework mapping, CIS-style hardening expectations, and caveats are
maintained in [Compliance Mapping](../compliance-mapping.md). The repository
threat assumptions and residual risks are maintained in
[SSHFling Threat Model](../threat-model.md).

| Control area | SOC 2 | ISO 27001:2022 | NIST SP 800-53 Rev. 5 |
| --- | --- | --- | --- |
| Release authorization and change traceability | CC8.1 | A.8.32 | CM-3, CM-5 |
| Build, package, and validation integrity | CC7.1, CC8.1 | A.8.25, A.8.29 | SI-2, SA-10, CM-6 |
| Signing keys and secret custody | CC6.1, CC6.6 | A.5.15, A.5.18, A.8.24 | AC-6, IA-5, SC-12 |
| Audit logging and evidence retention | CC7.2, CC7.3 | A.8.15, A.8.16 | AU-2, AU-6, AU-12 |
| Rollback and recovery | CC7.4, CC7.5 | A.5.30, A.8.13 | CP-10, IR-4 |

## Trust Model

SSHFling uses standard OpenSSH on target hosts. It does not require an AI CLI,
agent, SDK, model runtime, or vendor daemon on the server.

SSHFling does not vendor, fork, pin, upgrade, or remove OpenSSH. Dependency
ownership, version selection, uninstall behavior, and original-state evidence
are documented in [OpenSSH Dependency Policy](../openssh-dependencies.md).

Package publishing must preserve that trust model:

- Publish native packages from reviewed source commits.
- Use signed repository metadata for fleet Linux installs.
- Verify package checksums for direct package downloads.
- Keep host policy, SSH configuration, CA keys, and issuer tokens under normal
  configuration-management and secret-management controls.

## Package Integrity Controls

Required controls for production package publishing:

- Git tags identify release commits.
- GitHub Actions builds package artifacts from the release commit.
- `packaging/verify-public-web.sh` verifies the public package-site structure
  before publishing.
- APT repository metadata is signed when repository signing is enabled.
- RPM packages and RPM repository metadata are signed when repository signing is
  enabled.
- Raw downloads include `downloads/SHA256SUMS`.
- Generated community manifests include checksums where the ecosystem supports
  them.

Avoid these patterns:

- `curl ... | sh` or `curl ... | bash` install instructions.
- APT `trusted=yes` sources.
- RPM `gpgcheck=0` or `repo_gpgcheck=0` for fleet repositories.
- Production clients trusting an ephemeral package-site signing key.
- Replacing a published package with different content under the same version
  after external consumption begins.

## Signing Material

Store signing material as GitHub Actions secrets:

| Secret | Purpose |
| --- | --- |
| `SSHFLING_REPO_GPG_PRIVATE_KEY` | Private key for APT and RPM repository signing. |
| `SSHFLING_REPO_GPG_FINGERPRINT` | Approved public fingerprint for the production repository signing key. |
| `SSHFLING_REPO_GPG_KEY_ID` | Optional key selector for the imported keyring. |
| `SSHFLING_REPO_GPG_PASSPHRASE` | Optional passphrase for the private key. |

Operational requirements:

- Limit secret access to release maintainers.
- Rotate keys through a planned fleet update.
- Record the public fingerprint in release evidence.
- Never paste private keys into docs, tickets, logs, or package artifacts.
- Use a non-production generated key only for local tests or disposable package
  sites.

## License and Redistribution

SSHFling is licensed under the Apache License, Version 2.0. Enterprise
publishing must confirm:

- The release artifacts include the project `LICENSE` file.
- Third-party package submissions use Apache-2.0-compatible metadata for the
  target ecosystem.
- Generated manifests preserve any required notices and checksum evidence.
- License acceptance flags are disabled unless the target ecosystem requires a
  separate explicit prompt.

## Host Security Controls

For production hosts:

- Treat password grants as the default access path and manage them with short
  explicit lifetimes, named temporary users, prune automation, and host audit
  controls.
- Use certificate mode explicitly when policy forbids temporary local passwords
  or when the target platform is not a validated Linux password host.
- Treat certificate-specific setup options as certificate-only. The CLI rejects
  options such as `--ca-key`, `--public-key-file`, `--out`, `--login-user`, and
  `--source-address` unless `--certificate` is present.
  Certificate setup also requires an existing CA keypair from `sshfling ca init`
  and host trust from `sshfling host install`.
- Treat `access_level` as a policy classification for least-privilege review,
  not as privilege assignment. Host IAM, sudoers, PAM, AD, MDM, groups, local
  administrator membership, and service-manager policy remain the enforcement
  layer for actual account privileges.
- Treat `sshfling password prune --all` and
  `sshfling password prune --username USER` as expired-grant cleanup, not as
  broad user deletion commands. Prune requires exactly one of those selectors.
  It skips active grants, skips unmanaged records, locks expired
  SSHFling-created users by default, deletes those users only with
  `--delete-users` when matching UID/GID/home identity evidence is recorded,
  preserves config and metadata on identity mismatch, locks/expires existing
  users explicitly allowed with `--allow-existing-user` without deleting them,
  and never mutates root-equivalent users from password-grant metadata or
  host-user markers.
- Treat package uninstall as package cleanup only. It removes SSHFling-managed
  package files and repository entries, but preserves host SSH state, password
  grant state, CA material, and `/etc/sshfling` configuration for separate host
  cleanup. Dependency packages remain under host package-manager and fleet
  policy control.
- Set policy limits below SSHFling hard caps when the environment requires
  shorter sessions or fewer concurrent connections.
- Manage `/etc/sshfling/policy.json` through signed packages or configuration
  management.
- Keep `/etc/sshfling` root-owned.
- Give the `sshflingd` service read access only to the CA key and token material
  it needs.
- Monitor package verification, policy changes, service changes, and unexpected
  SSH configuration changes.

Password mode is the default setup path and is Linux-oriented because it
requires account-management tools such as `useradd`, `chpasswd`, `usermod`, and
`chage`. Do not use the default password flow on pfSense or OPNsense firewall
appliances; use explicit certificate mode with an existing SSH-authorized user.

## Audit Expectations

SSHFling logs operational events through system logging with `sshfling` and
`sshfling-session` tags. Audit records include grant and session metadata such
as user, principal, lifetime, serial, and outcome.

Audit records must not include:

- Passwords.
- Bearer tokens.
- Cookies.
- Private keys.
- Public key material.
- Raw remote commands.

Release evidence should include:

- Version and tag.
- Source commit SHA.
- Workflow run URLs.
- Package-site URL.
- Checksums URL.
- Repository signing key fingerprint.
- Validation workflow results.
- Runtime behavior evidence for password default, explicit certificate mode,
  access-level classification, prune limits, and uninstall limits.
- Known exceptions and approvals.

## Issuer Service Controls

When running `sshfling serve` as a systemd service:

- Store the issuer token in `/etc/sshfling/sshflingd.env` or a systemd
  credential mechanism approved by the platform owner.
- Keep the CA private key root-owned and only group-readable by `sshflingd` when
  service access is required.
- Use `sshfling ca init --force` only for a planned CA rotation. It replaces
  the existing CA keypair, so trusted host CA files and issued certificates must
  be updated or reissued under the rotation plan.
- Do not allow the daemon to own or rewrite the CA key, token file, or policy
  file.
- Restrict network exposure to the intended local or internal interface.
- Keep the issuer loopback-only unless an approved deployment sets
  `SSHFLING_ALLOW_REMOTE=1` behind TLS, mTLS, a VPN, or equivalent network
  controls.
- Rotate issuer tokens after suspected exposure.

## Compliance Review Questions

Use these questions in release review:

- Does this release use a stable repository signing key?
- Are package manager trust settings strict?
- Are Apple and Windows signing requirements satisfied or explicitly waived?
- Are license and redistribution approvals recorded?
- Are release artifacts traceable to a reviewed commit?
- Are threat-model assumptions, OpenSSH dependency ownership, and platform
  coverage claims still accurate for this release?
- Are install and uninstall docs current?
- Are package-site verification and cross-OS validation results attached?
- Are host policy and issuer secrets managed outside ad hoc manual edits?
