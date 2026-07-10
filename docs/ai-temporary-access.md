# AI-Assisted Temporary Server Access

SSHFling is useful when an engineer wants help from an AI coding or operations tool, but the production server should not run an AI CLI, agent, SDK, or vendor-specific daemon.

The target host only needs standard OpenSSH, Linux account-management tools for the default password flow, and the small `sshfling-session` wrapper. The default flow grants access with a generated temporary Unix password, so the AI tool can work through the same SSH channel an operator would use. When the timer expires, the password grant stops being useful and any active session is cut off by the server-side wrapper.

## Why This Helps

AI tools are strongest when they can inspect logs, run diagnostics, check configuration, and apply tightly scoped fixes. The usual risk is that giving a tool server access can turn into a standing credential: a reusable SSH key, a shared password, a long-lived account, or a background agent installed on the host.

SSHFling avoids that pattern. It lets an administrator issue access for a narrow window, such as five or ten minutes, without installing the AI tool on the server. The server continues to trust OpenSSH, not the AI vendor. The operator remains in control of who can connect, which Unix principal is allowed, how long the session can live, and how many active sessions are permitted.

## Typical Flow

1. An operator starts a temporary grant with `sudo sshfling -t 10m --username ticket-1234`.
2. SSHFling creates a temporary Unix user and generated password, writes a tracked sshd `Match User` block, and prints `sshfling ticket-1234@host`.
3. The AI tool or human operator uses standard SSH from the workstation or automation environment and enters the generated password when prompted.
4. The server-side forced command enforces the wall-clock limit even if the connection is already open.
5. The operator can list or kill active sessions with `sudo sshfling list`, `sudo sshfling -k ticket-1234`, or `sudo sshfling shutdown`.

For file movement during that window, use the same temporary username with
native transfer wrappers:

```bash
sshfling scp ./diagnostics.sh ticket-1234@host.example.com:/tmp/diagnostics.sh
sshfling rsync --recursive --preserve ./patch/ ticket-1234@host.example.com:/tmp/patch/
```

These are normal temporary SSH sessions under the same timeout and connection
policy. `sshfling scp` uses OpenSSH scp and can preserve mode/mtime with
`--preserve`; it cannot preserve or set owner/group. `sshfling rsync` requires
rsync on both ends and can request `--mode`, `--chown`, or `--owner-group` only
when the receiving account has permission. Without preserve or explicit mode
controls, target umask and filesystem policy decide the final mode and mtime.

For longer enterprise workflows, SSHFling can issue access up to 24 hours. Active session JSON includes the wrapper PID and child process PID fields for operational tracking. If Codex or another tool needs to continue after the SSH connection closes, start it with `sshfling detached start` or hand it to a host supervisor such as systemd or tmux, then track that detached PID and logs. See [Codex and enterprise detached workflows](codex-enterprise-workflow.md).

For environments that require OpenSSH user certificates instead of generated local passwords, an operator can use explicit certificate mode:

```bash
sudo sshfling ca init --ca-key /etc/sshfling/ca_user_ed25519
sudo sshfling host install --user deploy --ca-pub /etc/sshfling/ca_user_ed25519.pub
sudo sshfling --certificate -t 10m --username ticket-1234
```

Certificate mode must be prepared with an existing CA keypair and `sshfling
host install`, which configures OpenSSH to trust that user certificate
authority. An explicit `--certificate` grant then issues a short-lived
certificate and prints a normal `ssh` command.

## Security Properties

- No AI CLI, agent, model runtime, or vendor daemon needs to be installed on the target server.
- No permanent private key is copied to the server for the AI tool.
- Password mode creates a real local Unix password, tracks the grant on the server, auto-expires access, and allows only one active session for that temporary username.
- Certificate mode is available with `--certificate` and does not require a shared password.
- Access is time-bound by OpenSSH certificate validity or password-grant expiry, and by a server-side timeout wrapper.
- Policy can cap maximum lifetime and concurrent sessions below SSHFling's hard limits.
- Each grant can use a meaningful temporary username, such as a ticket number, for cleaner operational review.
- Existing SSH logs, process accounting, shell history policy, endpoint monitoring, and package integrity controls remain usable.

## Access Levels And Roles

SSHFling policy has an `access_level` field for least-privilege review. It classifies the privilege level of the Unix or platform account receiving the grant; it does not add the account to sudoers, local administrators, groups, roles, or IAM bindings.

- `standard`: default for temporary users and ordinary accounts with no expected `sudo` or root-equivalent rights.
- `operator`: diagnostics or approved operational commands through an existing operator account, without broad sudo.
- `sudo-limited`: an account with a reviewed sudoers allowlist or equivalent constrained elevation.
- `admin`: root-equivalent or local administrator access where the platform supports it; use only for approved break-glass work.

Keep the policy at the lowest level that can complete the task. For example:

```bash
sudo sshfling policy install --user deploy --access-level sudo-limited --max-time 30m --max-connections 1
sudo sshfling --certificate --username ticket-1234 --login-user deploy --access-level sudo-limited -t 10m
```

Grant requests can ask for `--access-level` or `--role`. SSHFling rejects a
requested level above the effective policy level, treats `root`,
`Administrator`, and any account that resolves to UID 0 as admin-class access,
and accepts `root-equivalent` as an access-level alias rather than a special
username. Host controls such as Unix groups, sudoers, PAM, AD, MDM, and
service-manager policy remain the enforcement layer for the actual privileges.
Password mode refuses root-equivalent Unix users because it creates or resets
local passwords; use explicit certificate mode for approved admin/root-equivalent
break-glass access.

## Threat-Model Checkpoints

The enterprise threat model for this workflow is in [SSHFling threat model](threat-model.md). For AI-assisted operations, review these checkpoints before granting access:

- Treat the temporary username, detached job name, ticket ID, wrapper PID, child PID, stdout/stderr paths, and validation workflow links as required breadcrumbs for review and rollback.
- A named temporary account is attribution, not sandboxing. The AI tool receives the normal privileges of the Unix account it logs in as, including any `sudo`, scheduler, service-manager, filesystem, or network permissions that account already has.
- The session wrapper applies wall-clock expiry to the SSH session it launches,
  but the command runs as the same UID and can signal that monitor. Hard
  containment of the command and every descendant requires host controls such
  as a privileged supervisor, systemd scope, cgroup, and account policy.
- Expired password grants should be pruned by an operator or fleet job. `sshfling password prune --all --delete-users` removes expired SSHFling-created users after managed sshd config removal is verified; existing break-glass users are locked/expired, not deleted.
- Certificate mode depends on protecting the user CA private key and issuer token. Keep the issuer loopback-only unless it is behind approved TLS, mTLS, VPN, or equivalent access controls.
- Password mode refuses root-equivalent Unix users and refuses to reset any other existing Unix user by default; use `--allow-existing-user` only for a documented non-root break-glass case.
- Install SSHFling from signed package repositories for managed fleets, and record the package signing fingerprint, release workflow URL, and package-site evidence in the change ticket.

## Operational Guidance

Treat SSHFling as a controlled access broker, not as a replacement for change management. Use short durations, issue access per task, prefer named grants tied to tickets, and keep package and policy files managed by your normal configuration system. Use explicit certificate mode when policy forbids temporary local passwords or when the target platform is not a supported Linux password host.

For higher-security environments, publish SSHFling through signed packages, protect `/etc/sshfling/policy.json`, monitor the issuer service, alert on unexpected policy or package changes, and centralize SSHFling system logs plus detached job logs before granting long-running AI-assisted access.
