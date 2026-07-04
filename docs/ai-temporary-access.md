# AI-Assisted Temporary Server Access

SSHFling is useful when an engineer wants help from an AI coding or operations tool, but the production server should not run an AI CLI, agent, SDK, or vendor-specific daemon.

The target host only needs standard OpenSSH and the small `sshfling-session` wrapper. The default flow grants access with short-lived OpenSSH user certificates, so the AI tool can work through the same SSH channel an operator would use. When the timer expires, the certificate stops being useful and any active session is cut off by the server-side wrapper.

## Why This Helps

AI tools are strongest when they can inspect logs, run diagnostics, check configuration, and apply tightly scoped fixes. The usual risk is that giving a tool server access can turn into a standing credential: a reusable SSH key, a shared password, a long-lived account, or a background agent installed on the host.

SSHFling avoids that pattern. It lets an administrator issue access for a narrow window, such as five or ten minutes, without installing the AI tool on the server. The server continues to trust OpenSSH, not the AI vendor. The operator remains in control of who can connect, which Unix principal is allowed, how long the session can live, and how many active sessions are permitted.

## Typical Flow

1. The server is prepared once with `sshfling host install`, which configures OpenSSH to trust a local user certificate authority.
2. An operator starts a temporary grant with `sudo sshfling -t 10m --username ticket-1234`.
3. SSHFling issues a short-lived certificate and prints a normal `ssh` command.
4. The AI tool or human operator uses standard SSH from the workstation or automation environment.
5. The server-side forced command enforces the wall-clock limit even if the connection is already open.
6. The operator can list or kill active sessions with `sudo sshfling list`, `sudo sshfling -k ticket-1234`, or `sudo sshfling shutdown`.

For clients that cannot receive or use an SSH key/certificate, an operator can use password fallback:

```bash
sudo sshfling -p -t 10m --username s234
```

That creates a tracked temporary Unix password grant and prints `sshfling s234@1.0.0.1`. The client still uses normal OpenSSH; `sshfling` only sets password-preferred SSH options and lets OpenSSH prompt for the generated password.

## Security Properties

- No AI CLI, agent, model runtime, or vendor daemon needs to be installed on the target server.
- No permanent private key is copied to the server for the AI tool.
- Certificate mode does not require a shared password.
- Password fallback creates a real local Unix password, tracks the grant on the server, auto-expires access, and allows only one active session for that temporary username.
- Access is time-bound by OpenSSH certificate validity or password-grant expiry, and by a server-side timeout wrapper.
- Policy can cap maximum lifetime and concurrent sessions below SSHFling's hard limits.
- Each grant can use a meaningful temporary username, such as a ticket number, for cleaner operational review.
- Existing SSH logs, process accounting, shell history policy, endpoint monitoring, and package integrity controls remain usable.

## Operational Guidance

Treat SSHFling as a controlled access broker, not as a replacement for change management. Use short durations, issue access per task, prefer named grants tied to tickets, and keep package and policy files managed by your normal configuration system. Prefer certificate mode when possible; use password fallback only when the client environment cannot handle SSH keys or certificates.

For higher-security environments, publish SSHFling through signed packages, protect `/etc/sshfling/policy.json`, monitor the issuer service, and alert on unexpected policy or package changes.
