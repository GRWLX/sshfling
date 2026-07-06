# Security Best Practices Report

Date: 2026-07-06

Repository: `/workspace/project/tempSSh`

## Executive Summary

SSHFling is a temporary SSH access broker. The strongest current controls are
that password grants are the default production grant path, OpenSSH
certificates are explicit with `--certificate` for policy or platform-specific
cases, Docker sshd disables common forwarding paths, and the tracked repository
does not contain real private keys, cloud keys, or credentialed connection
strings.

The highest risks are in release/package trust, issuer and CA isolation, and the gap between "temporary access" and host-level process/account containment. Several findings are design or operational risks that become critical when the issuer, web console, or Docker harness is exposed beyond localhost, or when grants target `root` or a privileged deploy account.

Recommended first fixes:

1. Sign package repositories and remove `trusted=yes`, `gpgcheck=0`, and pipe-to-shell production install guidance.
2. Fix `sshfling serve` so the packaged systemd service can run unprivileged, then make `/etc/sshfling` read-only to the daemon.
3. Remove request-controlled `login_user` from the issuer API or bind it to a server-side principal/account map.
4. Add hard containment for sessions and detached jobs using cgroups/systemd scopes, not only child-process traversal.
5. Refuse password grants for existing Unix users by default.

## Fix Pass Summary

Status as of 2026-07-06 current worktree:

- Remediated the package install trust path for generated/default guidance: no `trusted=yes`, no `gpgcheck=0`, no pipe-to-shell install examples, strict `x.y.z` package version validation, direct package checksum verification, and optional signed APT/RPM repository metadata.
- Remediated the packaged issuer/service mismatch: `sshfling serve` can run unprivileged, refuses remote binds unless explicitly allowed, rejects placeholder/short tokens, uses constant-time token checks, caps request bodies, and rate-limits issuer POSTs.
- Remediated issuer `login_user` policy bypass: issuer requests cannot select another Unix login user and issued API certificates bind `login_user` to the principal.
- Remediated password-grant account takeover by default: existing Unix users are refused unless `--allow-existing-user` is explicitly used; expired break-glass existing-user grants are locked/expired instead of left as standing passwords; and generated usernames now use a larger random space.
- Partially remediated session escape risk: detached work is denied from forced-command sessions by default, can only be allowed by a trusted wrapper flag, is capped to remaining session time when allowed, and has an active-job cap. Full cgroup/systemd-scope containment remains residual work.
- Remediated Docker harness defaults: localhost host-port binding by default, expanded `.dockerignore`, read-only root filesystems, dropped capabilities, `no-new-privileges`, pids limits, tmpfs runtime paths, runtime host keys, and optional pinned host-key verification for the client.
- Remediated systemd hardening gaps: root-owned config/CA material with group read access, no daemon write access to `/etc/sshfling`, and additional unit sandboxing directives.

## Scope And Method

Reviewed tracked source, scripts, Dockerfiles, Compose files, systemd units, docs, packaging workflows, and tests. Generated local build outputs, binary packages, and bytecode were not inspected except where source workflows generate or publish them.

Four read-only sub-agents were used:

- Application Security Engineer
- Security Architect
- Senior SecOps Engineer
- Penetration Tester

The `security-best-practices` skill has no shell/Docker/systemd-specific reference file, so this report applies general secure operations practice plus the selected agent guidance.

## Positive Observations

- No committed real private key material, cloud key patterns, credentialed DB URLs, or obvious hardcoded production secrets were found in tracked source.
- `secrets/*` is ignored while `secrets/.gitkeep` remains tracked.
- Docker sshd disables password auth, root login, TCP forwarding, agent forwarding, X11 forwarding, and tunnels by default.
- The web console is localhost-only unless `--allow-remote` is explicitly used.

## Critical Findings

### SEC-001: Unsigned Package Install Path Enables Root Supply-Chain Execution

Severity: Critical

Status note (2026-07-06): Remediated in the current working tree for generated/default install paths. Public install guidance no longer uses `trusted=yes`, `gpgcheck=0`, or pipe-to-shell install commands; direct Linux package installs verify published SHA-256 files; optional APT/RPM repo signing support has been added for the public package site; package version inputs are validated before generation.

Original evidence before the fix pass:

- `README.md:9` recommends `curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash`.
- `packaging/build-public-web.sh:104` writes an APT source with `trusted=yes`.
- `packaging/build-public-web.sh:133` writes an RPM repo with `gpgcheck=0`.
- `packaging/build-public-web.sh:295` and `packaging/build-public-web.sh:312` publish the same trust-disabled install snippets in generated web docs.
- The earlier public-web workflow force-published generated package web content with broad repository write access.

Current evidence after the fix pass:

- Generated install guidance downloads scripts to a temporary file before execution.
- Direct package installer paths verify published SHA-256 files before installing.
- Fleet APT examples use `signed-by=` and RPM examples use `gpgcheck=1` plus `repo_gpgcheck=1`.
- `packaging/verify-public-web.sh` rejects published `trusted=yes` and `gpgcheck=0` guidance.
- `.github/workflows/public-package-web.yml` deploys through GitHub Pages artifacts and requires a stable repository signing key for tag-based package publishing.

Impact: If the package site, release workflow, repository token, or publishing path is compromised, users can install attacker-controlled code as root/admin. That code can replace `sshfling`, alter templates/systemd files, or steal CA and policy material.

Remediation:

- Sign APT `Release`/`InRelease` metadata and use a published keyring with `signed-by=/usr/share/keyrings/sshfling.gpg`.
- Sign RPM packages/repository metadata and set `gpgcheck=1`; prefer `repo_gpgcheck=1` as well.
- Sign checksums with GPG, minisign, or cosign.
- Replace production pipe-to-shell guidance with download, verify, then run/install steps.
- Protect release tags and require a protected GitHub Pages environment for package-site publishing.

## High Findings

### SEC-002: Packaged Issuer Service Conflicts With Its Own Root Requirement

Severity: High

Status note (2026-07-06): Remediated in the current working tree. `sshfling serve` no longer requires root, `/etc/sshfling` is documented as root-owned and read-only to the daemon, CA/token read access is via the `sshflingd` group, and the systemd unit no longer grants broad write access to `/etc/sshfling`.

Evidence:

- `systemd/sshflingd.service:10` starts `sshfling serve`.
- `systemd/sshflingd.service:11` runs it as `User=sshflingd`.
- `bin/sshfling:2230` calls `require_root("serve")`.
- `systemd/sshflingd.service:19` grants daemon write access to `/etc/sshfling`.

Impact: The packaged service is likely to fail as written. Operators may respond by running the issuer as root or weakening the unit, putting CA material and policy under a larger blast radius.

Remediation:

- Remove the root requirement from `serve`; certificate signing only needs read access to the CA key and policy.
- Make `/etc/sshfling` root-owned and read-only to the service.
- Grant CA-key read access via a narrow group, `LoadCredential=`, or a signing helper.
- Move mutable runtime state to `StateDirectory=sshfling`.
- Remove broad `ReadWritePaths=/etc/sshfling`.
- Add `UMask=0077`, `PrivateDevices=true`, `ProtectKernelTunables=true`, `ProtectKernelModules=true`, `ProtectControlGroups=true`, `RestrictSUIDSGID=true`, and a suitable `SystemCallFilter=`.

### SEC-003: Exposed Issuer Can Become A Certificate-Minting Oracle

Severity: High

Status note (2026-07-06): Remediated for the direct issuer service in the current working tree. `serve` refuses non-loopback binds unless `--allow-remote` is set, rejects placeholder/short/whitespace bearer tokens at startup, uses constant-time bearer-token comparison, caps request bodies, and rate-limits issuer POSTs. Remote exposure still requires TLS/mTLS, VPN, or a hardened reverse proxy.

Evidence:

- Default issuer listen is local in `bin/sshfling:28` and `systemd/sshflingd.env.example:2`, but `serve --listen` accepts arbitrary host/port in `bin/sshfling:2241`.
- The HTTP server binds directly in `bin/sshfling:2252`.
- Auth is a bearer-token equality check in `bin/sshfling:2187`.
- Certificate issuance happens after token validation in `bin/sshfling:2207`.
- `README.md:245` shows a plain HTTP request to the issuer API.

Impact: If the issuer is exposed and the token is weak, default, logged, or stolen, an attacker can mint temporary SSH certificates for allowed principals.

Remediation:

- Refuse non-loopback binds unless an explicit remote mode is enabled.
- Require TLS/mTLS or a Unix socket behind a hardened local reverse proxy for remote use.
- Reject placeholder and low-entropy tokens at startup.
- Use constant-time token comparison.
- Add request size caps, per-IP/token rate limits, source-address requirements where feasible, and issuance audit logs.

### SEC-004: Issuer API Lets Token Holders Bypass Per-User Policy With `login_user`

Severity: High

Status note (2026-07-06): Remediated in the current working tree. Issuer requests that set `login_user` to a different account are rejected, and API-issued certificates bind `login_user` to the allowed principal.

Evidence:

- The API authorizes `principal` in `bin/sshfling:2197`.
- It accepts request-controlled `login_user` in `bin/sshfling:2216`.
- Policy lookup uses `login_user or principal` in `bin/sshfling:641`.
- The forced command embeds `--login-user` in `bin/sshfling:656` and the wrapper trusts it for policy lookup in `production/sshfling-session:50`.

Impact: A bearer-token holder can request a certificate for an allowed principal but set `login_user` to an unrestricted/default-policy name. A user with a 30 minute cap can effectively receive the default cap, currently up to 24 hours.

Remediation:

- Remove `login_user` from the issuer API request body.
- Configure a server-side map of allowed principal to Unix login user.
- Have the wrapper derive the actual login user from `id -un` unless a root-only local command path explicitly needs metadata.
- Add a regression test where a restricted user policy cannot be bypassed through issuer input.

### SEC-005: Password Mode Can Turn An Existing Account Into A Standing Credential

Severity: High

Status note (2026-07-06): Remediated by default in the current working tree. Password grants now refuse existing Unix users unless `--allow-existing-user` is explicitly passed for a documented break-glass case, expired break-glass existing-user grants are locked/expired during prune, and random temporary usernames now use a larger six-digit space.

Evidence:

- Existing Unix users are reused in `bin/sshfling:939`.
- `set_user_password` resets/unlocks the password in `bin/sshfling:931`.
- Password grants call that path in `bin/sshfling:986`.
- The generated `Match User` block enables password auth in `bin/sshfling:951`.
- Prune locks/expires break-glass existing-user grants without deleting the
  account.

Impact: If an operator runs password mode against an existing account such as `deploy`, SSHFling resets that real account password and prints it. The forced command can expire the SSHFling grant, but the account password may remain changed and reusable in other auth paths.

Remediation:

- Refuse password grants for existing users by default.
- Add an explicit break-glass flag if existing-user password grants are intentionally needed.
- Always lock or expire password-grant users at expiry.
- Create a systemd timer/cron cleanup path when creating password grants.
- Expand random username entropy beyond the current `s000` to `s999` space in `bin/sshfling:838`.
- Keep docs and CLI output aligned on default password grants, with
  certificate mode explicit through `--certificate` where policy requires it.

### SEC-006: Time-Limited Sessions Are Process-Tree Based, Not Hard Containment

Severity: High

Status note (2026-07-06): Partially remediated. `sshfling detached start` is denied inside forced-command sessions by default, can only be allowed by a trusted wrapper argument, is capped to remaining session time when allowed, and has a 10-job active metadata cap. Full cgroup/systemd-scope containment remains open.

Evidence:

- The production wrapper launches commands through `/bin/bash -lc` or a login shell in `production/sshfling-session:178`.
- Timeout cleanup recursively kills current child PIDs in `production/sshfling-session:141` and `production/sshfling-session:160`.
- Detached commands can be started for up to 24 hours in `bin/sshfling:3007` and `bin/sshfling:1493`.
- The detached supervisor launches arbitrary commands in `bin/sshfling:1688`.

Impact: A temporary user can attempt to outlive the grant by re-parenting processes, scheduling work, using host supervisors, or using `sshfling detached start` if installed on the target. The risk depends heavily on the target account's privileges.

Remediation:

- Run each forced SSH session in a cgroup/systemd scope with `RuntimeMaxSec` and `KillMode=control-group`.
- Disable or restrict `sshfling detached` when `SSH_ORIGINAL_COMMAND`/forced-session context is present.
- Cap detached runtime to the remaining grant/policy.
- Deny `cron`, `at`, `systemd-run`, `sudo`, writable service-unit paths, and similar persistence paths for temp users.
- Add regression tests for `setsid`, `nohup`, `disown`, scheduler, and detached-job escape attempts.

### SEC-007: Temporary Identity Is Attribution, Not Isolation

Severity: High

Evidence:

- Certificate setup prints an SSH command for `login_user@server` in `bin/sshfling:1103`.
- Host install binds access to a real Unix account with `Match User` in `bin/sshfling:2064`.
- Production tests grant `--login-user root` and expect `whoami` to be root in `tests/docker/run-production-test.sh:191` and `tests/docker/run-production-test.sh:230`.

Impact: A "temporary" grant to `root` or a privileged deploy user gives that account's full filesystem, sudo, network, and persistence blast radius during the session.

Remediation:

- Make dedicated least-privilege temp accounts the default.
- Block root grants unless an explicit break-glass flag is used.
- Install per-account policy caps by default.
- Remove sudo and persistence-path write permissions for AI/tool accounts.
- Document that session names are not sandboxing boundaries.

### SEC-008: CA Private Key Compromise Defeats The Temporary-Access Model

Severity: High

Status note (2026-07-06): Partially remediated for packaged systemd deployment. The service setup now keeps CA/config material root-owned and only group-readable by `sshflingd`, and the daemon no longer owns or writes `/etc/sshfling`. Broader CA isolation such as HSM/constrained helper signing remains open.

Evidence:

- CA keys are generated unencrypted with `0600` permissions in `bin/sshfling:728`.
- README setup chowns CA material to the service user in `README.md:236`.
- Hosts trust the CA through `TrustedUserCAKeys` in `bin/sshfling:2060`.
- Host config does not add a host-side `ForceCommand`; timeout enforcement is embedded as a certificate critical option at signing time in `bin/sshfling:681`.

Impact: If the CA key is stolen, an attacker can sign certificates outside SSHFling, potentially without the forced command or with a longer validity.

Remediation:

- Use separate CAs per environment/account class.
- Keep CA keys root-owned and not writable by the issuer process.
- Consider a constrained signing helper or HSM-backed signing flow.
- Alert on CA-key reads, unexpected certificate serials, and non-SSHFling signing.
- Explore host-side validation that rejects certificates missing expected critical options.

### SEC-009: Unvalidated Version Inputs Reach Package Generation

Severity: High

Status note (2026-07-06): Remediated in the current working tree. `packaging/version.sh` enforces strict numeric `x.y.z` versions and is wired into Bash packaging scripts, public-web generation, public-web verification, Make package targets, and package-install/cross-OS workflow validation.

Evidence:

- `Makefile:33`, `Makefile:38`, and `Makefile:41` pass `VERSION` into package/test scripts.
- `packaging/build-deb.sh:7` uses the version in build paths.
- `packaging/build-rpm.sh:77` writes the version into an RPM spec.
- `packaging/build-community-manifests.sh:592` writes the version into generated package manifest filenames.

Impact: A crafted version containing path separators, whitespace, quotes, newlines, or package syntax can corrupt generated manifests, write outside intended directories, or inject package script content depending on the target ecosystem.

Remediation:

- Validate version at every public entrypoint with a strict package-safe regex adjusted to the supported release scheme. The current package path uses numeric `x.y.z`.
- Reject `/`, `\`, whitespace, quotes, shell metacharacters, XML/HTML metacharacters, and newlines.
- Normalize generated paths and assert they remain under the intended output directory.

### SEC-010: Docker Production Test Build Context Can Include Local Secrets

Severity: High

Status note (2026-07-06): Remediated for the current test/release context. `.dockerignore` now excludes environment files, common key/cert formats, cloud config directories, build/release outputs, logs, caches, editor metadata, and generated SSH host/client key names.

Evidence:

- `.dockerignore:1` through `.dockerignore:7` exclude only `.git`, build/dist, `secrets/*`, `__pycache__`, and `*.pyc`.
- `tests/docker/Dockerfile.production:19` copies the entire context with `COPY . /opt/sshfling`.

Impact: Local `.env` variants, logs, virtualenvs, temporary keys, release outputs, or other untracked files can be baked into test images.

Remediation:

- Extend `.dockerignore` with `.env`, `.env.*`, `*.log`, `.venv/`, `.pytest_cache/`, `.mypy_cache/`, `.coverage`, `htmlcov/`, `public/`, `package-dist/`, `release-dist/`, `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, and OS/editor metadata.
- Prefer a `git archive` or explicitly staged build context for release/test images.

## Medium Findings

### SEC-011: Web Console Lacks Brute-Force Protection And Secure Cookie Handling For Remote Mode

Severity: Medium

Status note (2026-07-06): Remediated for the identified controls. Web login POSTs are rate-limited per client address, request bodies are capped, and cookies are marked `Secure` when the console is intentionally bound to a non-loopback address.

Evidence:

- `/login` is handled without rate limiting in `bin/sshfling:2530`.
- Session cookies are `HttpOnly; SameSite=Strict` but not `Secure` in `bin/sshfling:2535`.
- Remote bind is allowed with `--allow-remote` in `bin/sshfling:2591`.
- The README example uses `SSHFLING_WEB_PASSWORD='change-me'` in `README.md:175`.

Impact: If exposed remotely, weak or reused admin passwords can be brute-forced, and cookies can be stolen over non-TLS HTTP.

Remediation:

- Keep web mode localhost-only unless behind SSH/VPN/TLS.
- Add per-IP login rate limits and lockouts.
- Set `Secure` on cookies whenever the console is not strictly loopback HTTP.
- Replace the weak example with a generated random password example.

### SEC-012: Client Container Trusts First Scanned SSH Host Key

Severity: Medium

Status note (2026-07-06): Partially remediated. The client supports pinned `SSH_KNOWN_HOSTS`, `SSH_KNOWN_HOSTS_FILE`, and `SSH_HOST_KEY_SHA256` verification. If no pin is supplied it still falls back to scan-on-first-use for the local Docker test harness.

Evidence:

- `ssh-client/entrypoint.sh:52` obtains host keys using `ssh-keyscan`.
- `ssh-client/entrypoint.sh:71` enables strict checking against the just-fetched `known_hosts` file.

Impact: The first connection can be man-in-the-middled. `StrictHostKeyChecking=yes` only protects after trusting the unauthenticated scan result.

Remediation:

- Require a pinned `known_hosts` Docker secret or expected host-key fingerprint for non-test use.
- Compare scanned keys to the expected fingerprint before connecting.
- Consider host CA trust for production-style client flows.

### SEC-013: Docker Harness Publishes SSH Broadly And Lacks Runtime Confinement

Severity: Medium

Status note (2026-07-06): Remediated for defaults. The server publishes on `127.0.0.1` by default via `SSH_BIND_ADDRESS`, both Compose services use `no-new-privileges`, dropped capabilities, pids limits, read-only filesystems, and tmpfs runtime paths, and the server generates host keys/config under `/run`.

Evidence:

- `compose.server.yml:13` publishes `${SSH_PORT_ON_HOST:-2222}:22`, binding all host interfaces by default.
- `ssh-server/sshd_config:2` listens on `0.0.0.0`.
- `compose.server.yml:4` and `compose.client.yml:4` do not set `read_only`, `cap_drop`, `security_opt`, `tmpfs`, or `pids_limit`.

Impact: Operators can unintentionally expose the test SSH container. If compromised, the container has default Docker runtime capabilities and a writable filesystem.

Remediation:

- Default the port mapping to `127.0.0.1:${SSH_PORT_ON_HOST:-2222}:22`.
- Add `SSH_BIND_ADDRESS` for explicit public exposure.
- Add `security_opt: ["no-new-privileges:true"]`, `cap_drop: ["ALL"]`, minimal `cap_add`, `read_only: true`, tmpfs mounts for `/run` and `/tmp`, and a `pids_limit`.

### SEC-014: Predictable Lock Files In `/tmp` Can Deny Or Weaken Session Limits

Severity: Medium

Status note (2026-07-06): Remediated in the production wrapper. Session locks now use a private user/runtime directory and no direct shared `/tmp` fallback.

Evidence:

- `production/sshfling-session:120` creates lock paths under `${TMPDIR:-/tmp}`.
- `production/sshfling-session:121` opens the path through shell redirection.

Impact: A local attacker can pre-place lock paths to deny sessions for a UID. On systems without strong symlink protections, shell redirection on predictable world-writable paths can be more dangerous.

Remediation:

- Use a root-owned private lock directory such as `/run/sshfling/locks`.
- Create locks with safe open flags or atomic `mkdir` lock directories.
- Avoid shell redirection on predictable paths in world-writable directories.

### SEC-015: Host Enforcement Relies On Certificates Carrying `force-command`

Severity: Medium

Evidence:

- `bin/sshfling:681` adds `force-command` when SSHFling signs a certificate.
- Host install writes CA/principal/auth settings in `bin/sshfling:2060` through `bin/sshfling:2070`, but no host-side `ForceCommand`.

Impact: If the CA key is used outside SSHFling, a host can accept certificates that do not run the timeout wrapper.

Remediation:

- Use narrowly scoped CAs and strict signer access controls.
- Consider `AuthorizedPrincipalsCommand` or equivalent host-side validation for required certificate critical options.
- Monitor SSH auth logs for certificates missing expected `key_id`/serial patterns.

### SEC-016: Audit Trail Is Too Thin For High-Trust Temporary Access

Severity: Medium

Evidence:

- Default `key_id` is generic in `bin/sshfling:652`.
- Certificate serial/key ID are returned in `bin/sshfling:710` but not written to an append-only audit sink.
- HTTP/web logging is basic request logging in `bin/sshfling:2225` and `bin/sshfling:2569`.

Impact: After misuse, it may be hard to prove who issued, used, killed, pruned, or changed a grant.

Remediation:

- Require ticket/operator identifiers for grants.
- Log grant issuance, password grant creation, issuer failures, policy changes, kills, and prunes to journald/syslog.
- Include principal, login user, key fingerprint, certificate serial, source IP, TTL, outcome, and actor.
- Do not log passwords, bearer tokens, cookies, or private keys.

### SEC-017: CI Lacks Security Gates

Severity: Medium

Evidence:

- `.github/workflows/container-image-tests.yml:32` runs functional container tests.
- `.github/workflows/release-packages.yml:87` runs `make test`.
- No tracked workflow references `gitleaks`, `trufflehog`, `semgrep`, `trivy`, `hadolint`, `shellcheck`, or `systemd-analyze security`.

Impact: Secret leaks, insecure shell patterns, vulnerable images, and service hardening regressions can ship without a blocking signal.

Remediation:

- Add CI jobs for secret scanning, SAST, shell linting, Dockerfile linting, filesystem/container vulnerability scanning, and systemd unit security review.
- Start as non-blocking if needed, then block on high-confidence critical/high findings.

## Low Findings

### SEC-018: Docker Harness Can Be Misread As A Production Boundary

Severity: Low

Status note (2026-07-06): Partially remediated. The default host bind is
localhost and Docker runtime settings are hardened, but the README should still
be treated as the source of truth that Docker is a test harness and production
hosts should use the default password grant path or explicit certificate mode
when policy requires it.

Evidence:

- `README.md:99` says Docker is only a test harness for production hosts.
- `compose.server.yml:13` still publishes SSH on the host by default.

Impact: Operators may reuse the harness as production and rely on a weak container boundary for SSH access.

Remediation:

- Add explicit "test harness only" comments to generated Compose files.
- Bind to localhost by default.
- Point production users to default password grants, explicit certificate mode
  where required, and least-privilege account setup.

## Residual Risk And Open Questions

- Severity rises if `sshflingd` or the web console is exposed off-host.
- Severity rises if grants are commonly issued to `root`, sudo-enabled users, or deployment accounts with write access to app/runtime paths.
- This review did not inspect generated `.deb`, `.rpm`, `.pkg`, `.msi`, `.zip`, local `build/`, local `dist/`, or Python bytecode artifacts.
- No live external scanning or exploitation was performed.
