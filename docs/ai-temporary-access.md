# AI-Assisted Temporary Server Access

SSHFling is useful when an engineer wants help from an AI coding or operations tool, but the production server should not run an AI CLI, agent, SDK, or vendor-specific daemon.

The target host only needs standard OpenSSH, Linux account-management tools for the default password flow, and the small `sshfling-session` wrapper. The default flow grants access with a generated temporary Unix password, so the AI tool can work through the same SSH channel an operator would use. When the timer expires, the password grant stops being useful and any active session is cut off by the server-side wrapper.

## Why This Helps

AI tools are strongest when they can inspect logs, run diagnostics, check configuration, and apply tightly scoped fixes. The usual risk is that giving a tool server access can turn into a standing credential: a reusable SSH key, a shared password, a long-lived account, or a background agent installed on the host.

SSHFling avoids that pattern. It lets an administrator issue access for a narrow window, such as five or ten minutes, without installing the AI tool on the server. The server continues to trust OpenSSH, not the AI vendor. The operator remains in control of who can connect, which Unix principal is allowed, how long the session can live, and how many active sessions are permitted.

## Typical Flow

1. An operator starts a temporary grant with `sudo sshfling -t 10m --username ticket-1234`.
2. SSHFling creates or updates the temporary Unix user password, writes a tracked sshd `Match User` block, and prints `sshfling ticket-1234@host`.
3. The AI tool or human operator uses standard SSH from the workstation or automation environment and enters the generated password when prompted.
4. The server-side forced command enforces the wall-clock limit even if the connection is already open.
5. The operator can list or kill active sessions with `sudo sshfling list`, `sudo sshfling -k ticket-1234`, or `sudo sshfling shutdown`.

For longer enterprise workflows, SSHFling can issue access up to 24 hours. Active session JSON includes the wrapper PID and child process PID fields for operational tracking. If Codex or another tool needs to continue after the SSH connection closes, start it with `sshfling detached start` or hand it to a host supervisor such as systemd or tmux, then track that detached PID and logs. See [Codex and enterprise detached workflows](codex-enterprise-workflow.md).

For environments that require OpenSSH user certificates instead of generated local passwords, an operator can use explicit certificate mode:

```bash
sudo sshfling --certificate -t 10m --username ticket-1234
```

Certificate mode can also be prepared once with `sshfling host install`, which configures OpenSSH to trust a local user certificate authority. It issues a short-lived certificate and prints a normal `ssh` command.

## Security Properties

- No AI CLI, agent, model runtime, or vendor daemon needs to be installed on the target server.
- No permanent private key is copied to the server for the AI tool.
- Password mode creates a real local Unix password, tracks the grant on the server, auto-expires access, and allows only one active session for that temporary username.
- Certificate mode is available with `--certificate` and does not require a shared password.
- Access is time-bound by OpenSSH certificate validity or password-grant expiry, and by a server-side timeout wrapper.
- Policy can cap maximum lifetime and concurrent sessions below SSHFling's hard limits.
- Each grant can use a meaningful temporary username, such as a ticket number, for cleaner operational review.
- Existing SSH logs, process accounting, shell history policy, endpoint monitoring, and package integrity controls remain usable.

## Operational Guidance

Treat SSHFling as a controlled access broker, not as a replacement for change management. Use short durations, issue access per task, prefer named grants tied to tickets, and keep package and policy files managed by your normal configuration system. Use explicit certificate mode when policy forbids temporary local passwords or when the target platform is not a supported Linux password host.

For higher-security environments, publish SSHFling through signed packages, protect `/etc/sshfling/policy.json`, monitor the issuer service, and alert on unexpected policy or package changes.
