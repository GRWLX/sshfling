# Codex and Enterprise Detached Workflows

SSHFling grants temporary SSH access. It does not install Codex, an AI agent, or a vendor daemon on the target host. For enterprise use, keep that boundary clear: use SSHFling for access, then use the host's normal process supervisor when work needs to continue after the SSH connection closes.

## 24-Hour Grant

Issue a named 24-hour grant for a tracked change, ticket, or incident:

```bash
sudo sshfling -t 24h --username ticket-1234
```

To make 24 hours the installed policy cap for a host:

```bash
sudo sshfling policy install --max-time 24h --max-connections 10
```

Policies can still set shorter per-user caps:

```bash
sudo sshfling policy install --user deploy --max-time 2h --max-connections 3
```

## Connected Process PID

For active SSHFling sessions, use:

```bash
sudo sshfling --json list
```

Each session includes:

- `pid`: the `sshfling-session` wrapper PID.
- `status`: `processing` while the wrapper is active.
- `process_pid`: the immediate child process launched by the wrapper.
- `process_pids`: the child process tree under the wrapper.

Use `pid` when calling `sshfling shutdown` or `sshfling -k`. Use `process_pid` or `process_pids` for operational visibility into the command currently doing work.

## Detached Work

Do not rely on raw `nohup`, shell backgrounding, or `disown` for enterprise work. Those patterns make ownership, logs, and shutdown policy harder to audit. Prefer a supervisor that records the main PID and can enforce a runtime limit.

On systemd hosts:

```bash
sudo systemd-run \
  --unit=codex-ticket-1234 \
  --working-directory=/srv/app \
  --property=RuntimeMaxSec=24h \
  --property=KillMode=control-group \
  bash -lc 'codex'
```

Then inspect the detached process:

```bash
sudo systemctl show codex-ticket-1234.service -p ActiveState -p MainPID
sudo journalctl -u codex-ticket-1234.service -f
```

On hosts without systemd, use `tmux` with an explicit timeout:

```bash
tmux new-session -d -s codex-ticket-1234 'cd /srv/app && timeout 24h codex'
tmux list-panes -t codex-ticket-1234 -F '#{pane_pid}'
```

Detached jobs are no longer children of the `sshfling-session` wrapper after the SSH command exits, so `sshfling list` tracks connected SSHFling sessions, not completed handoffs to systemd or tmux. Use the supervisor PID and logs for detached work.

## Release Validation

The local and cross-OS validation scripts check that:

- The default policy cap is 86,400 seconds.
- Installed templates carry the 24-hour wrapper and issuer defaults.
- Active session JSON exposes `status`, `process_pid`, and `process_pids`.

Run local validation before publishing:

```bash
make test
```

For release candidates, run the documented GitHub workflows in [build-targets.md](build-targets.md), ending with `Package install tests` and `Cross OS validation`.
