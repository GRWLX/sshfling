# SSHFling

`sshfling` grants temporary SSH access with standard OpenSSH. The server does not need an AI CLI, agent, SDK, or vendor daemon.

## Server / Service Side

Install:

```bash
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash
```

Uninstall the package/CLI:

```bash
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash -s -- uninstall
```

See [Uninstall and cleanup](#uninstall-and-cleanup) for host SSH configuration and local state removal.

Certificate access:

```bash
sudo sshfling
```

Shorter certificate access:

```bash
sudo sshfling -t 10m
```

Or password access:

```bash
sudo sshfling -p -t 10m
```

The server prints the temporary username, generated password when using `-p`, expiry, and the client command. Access expires automatically.

See active sessions or cut them off:

```bash
sudo sshfling list
sudo sshfling -k s234
sudo sshfling shutdown
```

## Client Side

Use the command printed by the server.

Certificate access:

```bash
ssh -i /path/to/generated/key user@1.0.0.1
```

Or password access:

Install `sshfling` on the client:

```bash
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash
```

Run the server-printed command:

```bash
sshfling s234@1.0.0.1
```

Then type the generated password when OpenSSH prompts for it. Client mode does not require root.

On the server side, `-p` is short for `--password`. On the client side, `sshfling -p 2222 user@host` is passed through to OpenSSH as the SSH port option.

The server-side grant prints the detected server address in the client command. If a host has multiple addresses and you need to override that detection, set `SSHFLING_SERVER_HOST` for the grant command.

Rules:

- Server-side grant, shutdown, and kill commands require root/admin.
- The maximum grant time is 24 hours.
- `sshfling` with no `-t` uses the maximum: 24 hours.
- Up to 10 active sshfling SSH sessions are allowed, depending on install policy.
- If no SSH public key is provided, certificate mode creates a temporary keypair automatically.
- Password mode creates a real Unix account password, tracks the grant, auto-expires access, and allows only one active session for that temporary username.

Under the hood, certificate mode uses OpenSSH user certificates and a host-side timeout wrapper. Password mode writes a temporary sshd `Match User` block that forces the same timeout wrapper.

SSHFling also fits AI-assisted operations where the target server should not run an AI CLI, agent, SDK, or vendor daemon. An operator can grant a short-lived standard SSH session to a human or AI tool from a workstation, while the server continues to rely on OpenSSH certificates, local policy, and a forced command wrapper for timeout enforcement. See [AI-assisted temporary server access](docs/ai-temporary-access.md) and [Codex and enterprise detached workflows](docs/codex-enterprise-workflow.md).

It also includes a Docker Compose test harness with two projects:

- server: an SSH container that accepts only public-key auth for `deploy`
- client: a container that connects to the server over the shared Docker network

Every SSH session is capped by `SSH_SESSION_SECONDS`.

For production hosts, Docker is only a test harness. The production mode uses OpenSSH user certificates:

- `sshfling ca init` creates an SSH user CA keypair.
- `sshfling host install` configures a target host to trust the CA for one Unix user.
- `sshfling cert issue` signs a user's public key for a short lifetime.
- `sshfling serve` runs a small authenticated certificate issuer service.

The issued certificate includes an OpenSSH `force-command` option that runs `sshfling-session` on the target host. That wrapper enforces the session wall-clock limit, so an already-connected SSH session is killed when its allowed time is reached.

## Production Quick Start

The normal command is:

```bash
sudo sshfling
```

That creates or reuses the CA key, creates a temporary username, creates a temporary keypair/certificate, and prints the SSH command. Use `-t` to choose a shorter time.

Optional username:

```bash
sudo sshfling -t 10m --username ticket-1234
```

Password-based temporary access:

```bash
sudo sshfling -p -t 10m --username s234
```

That prints a one-time grant with a generated password and this client command:

```bash
sshfling s234@1.0.0.1
```

On the client side, run the command, press Enter, then type the printed password when OpenSSH prompts for it. `sshfling s234@1.0.0.1` is a small wrapper around `ssh` that prefers password authentication and lets OpenSSH handle the password prompt.

Password mode is intended for Linux SSH servers with `useradd`, `chpasswd`, and OpenSSH server tools installed. It creates a real local Unix password for the temporary user, writes a tracked sshd config snippet, and blocks expired logins automatically through `ForceCommand`.

Kill active sshfling SSH sessions:

```bash
sudo sshfling shutdown
sudo sshfling -k s432
```

List active sessions:

```bash
sudo sshfling list
```

The list output includes the `sshfling-session` wrapper PID and the active child process PID. JSON output also includes `status`, `process_pid`, and `process_pids` for automation.

Start work that should continue after the SSH connection closes:

```bash
sshfling detached start --name ticket-1234 --time 24h --cwd /srv/app -- codex
sshfling detached list
sshfling detached kill ticket-1234
```

Detached jobs report a command `pid`, a `supervisor_pid`, stdout/stderr log paths, and enforce the same 24-hour runtime ceiling.

Install per-user policy limits:

```bash
sudo sshfling policy install --user deploy --max-time 30m --max-connections 3
```

Run the local web console:

```bash
export SSHFLING_WEB_PASSWORD_HASH="$(SSHFLING_WEB_PASSWORD='change-me' sshfling web-hash)"
sudo --preserve-env=SSHFLING_WEB_PASSWORD_HASH sshfling web
```

Open `http://127.0.0.1:8790` and log in as `admin`.

The policy is stored at `/etc/sshfling/policy.json`. SSHFling has hard caps of 24 hours and 10 active sessions. Policy can set lower default limits and lower per-user limits, not higher ones.

Root can always replace binaries or edit local files. To make policy changes controlled in production, manage `/etc/sshfling/policy.json` through signed packages/config management and alert on package verification or file integrity changes.

On the issuer machine:

```bash
sshfling ca init --ca-key /etc/sshfling/ca_user_ed25519
```

Copy `/etc/sshfling/ca_user_ed25519.pub` to each target host, then on each target host:

```bash
sudo sshfling host install \
  --ca-pub ./ca_user_ed25519.pub \
  --username temp-remote \
  --create-user \
```

Remove the host SSH configuration:

```bash
sudo sshfling host uninstall --username temp-remote --reload
```

Issue a temporary certificate for a client public key:

```bash
sshfling cert issue \
  --ca-key /etc/sshfling/ca_user_ed25519 \
  --public-key-file ~/.ssh/id_ed25519.pub \
  --username temp-remote \
  --time 5m \
  --out ~/.ssh/id_ed25519-cert.pub
```

Connect before the certificate expires:

```bash
ssh -i ~/.ssh/id_ed25519 deploy@host.example.com
```

Run the issuer API service:

```bash
export SSHFLING_ISSUER_TOKEN="$(openssl rand -hex 32)"
sshfling serve --ca-key /etc/sshfling/ca_user_ed25519 --allowed-principal deploy
```

Run it with systemd after installing a package:

```bash
sudo useradd --system --home /var/lib/sshflingd --shell /usr/sbin/nologin sshflingd
sudo install -d -m 0750 -o sshflingd -g sshflingd /etc/sshfling
sudo sshfling ca init --ca-key /etc/sshfling/ca_user_ed25519
sudo chown sshflingd:sshflingd /etc/sshfling/ca_user_ed25519 /etc/sshfling/ca_user_ed25519.pub
sudo install -m 0600 -o root -g root /usr/share/doc/sshfling/sshflingd.env.example /etc/sshfling/sshflingd.env
sudo sed -i "s/replace-with-a-long-random-token/$(openssl rand -hex 32)/" /etc/sshfling/sshflingd.env
sudo systemctl enable --now sshflingd
```

Request a certificate from the service:

```bash
curl -sS \
  -H "Authorization: Bearer $SSHFLING_ISSUER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"public_key":"ssh-ed25519 AAAA... user@host","principal":"deploy","seconds":300}' \
  http://127.0.0.1:8787/v1/certificates
```

## Uninstall and Cleanup

Package uninstall removes the `sshfling` command and packaged templates. It does not remove host SSH configuration that was created with `sshfling host install`, temporary password grant state, local CA keys, or `/etc/sshfling` policy/config files.

Linux and Homebrew:

```bash
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash -s -- uninstall
```

Force a specific uninstall path:

```bash
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash -s -- uninstall apt
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash -s -- uninstall dnf
curl -fsSL https://grwlx.github.io/sshfling/install.sh | bash -s -- uninstall brew
```

macOS pkg:

```bash
curl -fsSL https://grwlx.github.io/sshfling/macos/uninstall-pkg.sh | sudo bash
```

Windows MSI:

```powershell
irm https://grwlx.github.io/sshfling/windows/uninstall.ps1 | iex
```

Remove host SSH configuration created by `sshfling host install`:

```bash
sudo sshfling host uninstall --username temp-remote --dry-run
sudo sshfling host uninstall --username temp-remote --reload
```

By default, host uninstall removes the managed sshd snippet and that user's authorized-principals file. Shared files are opt-in:

```bash
sudo sshfling host uninstall \
  --username temp-remote \
  --remove-ca \
  --remove-wrapper \
  --remove-policy-user \
  --reload
```

Only use `--delete-user` for Unix accounts created solely for SSHFling:

```bash
sudo sshfling host uninstall --username temp-remote --delete-user --reload
```

Clean up temporary password grants:

```bash
sudo sshfling password prune --all
sudo sshfling password prune --all --delete-users
```

If you installed from a source checkout with `./scripts/install-local.sh`, remove that local install with:

```bash
./scripts/uninstall-local.sh
```

If you ran the issuer service with systemd, stop it before removing package files:

```bash
sudo systemctl disable --now sshflingd
```

## Docker Test Harness

```bash
./scripts/install-local.sh
sshfling init ./my-sshfling --with-key --session-seconds 60
cd ./my-sshfling
sshfling network create
sshfling server up --build
sshfling client run 'whoami && hostname && date -u'
```

Timeout test:

```bash
sshfling test-timeout --seconds 5 --sleep 20
```

## Packages

Build packages from this source checkout:

```bash
./packaging/build-deb.sh
./packaging/build-rpm.sh
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/build-msi.ps1
./packaging/build-pkg.sh
```

Package outputs go to `dist/`.

- `.deb` needs `dpkg-deb`.
- `.rpm` needs `rpmbuild`.
- `.msi` needs Windows PowerShell and WiX Toolset v3.
- `.pkg` needs macOS `pkgbuild` and `productbuild`.

Repo registration instructions are in [docs/repos.md](docs/repos.md).
The current OS/package target matrix is in [docs/build-targets.md](docs/build-targets.md).

GitHub Actions workflows are included for public distribution:

- `Release packages without web` builds release artifacts only.
- `Release packages with public web` publishes a GitHub Pages package site for commands such as `sudo apt install -y sshfling`, `sudo dnf install -y sshfling`, Homebrew, macOS `.pkg`, Windows MSI installs, and community package manifests for BSDs, Arch/AUR, Alpine, Nix, Guix, Void, Gentoo, Slackware, openSUSE OBS, Snapcraft, Termux, AppImage, Scoop, winget, and Chocolatey.
- `Cross OS validation` installs or builds those outputs across Linux, BSD, macOS, and Windows and checks the 24-hour policy default, copied service templates, active-session PID fields, and detached job PID lifecycle.

Nix users can also run from the repository:

```bash
NIXPKGS_ALLOW_UNFREE=1 nix run --impure github:GRWLX/sshfling
```

## Package Ecosystem Choice

For this tool, native packages are the right default for deployment fleets because the command wraps Docker, writes deployment files, and is likely to be installed by admins.

NPM would be good for developer-first distribution, especially `npm install -g sshfling`, but it would add a Node runtime expectation. NuGet is only a good fit if this becomes a .NET global tool. Homebrew is the best macOS developer path, winget/Intune are better Windows distribution paths, and APT/YUM are best for Linux fleets.

## License

SSHFling is proprietary software owned by GRWLX. Use requires a separate
written commercial license and payment of any royalties or fees required by
that agreement. See [LICENSE](LICENSE).

## Common Commands

```bash
sshfling doctor
sshfling init ./deploy --with-key
sshfling network create
sshfling server up --build
sshfling server logs --tail 100
sshfling client run 'uname -a'
sshfling server down
```

## Direct Compose

```bash
cp .env.example .env
./scripts/generate-ssh-key.sh
./scripts/create-network.sh
docker compose -f compose.server.yml up -d --build
docker compose -f compose.client.yml run --rm ssh-client
```

## Configuration

| Variable | Default | Purpose |
| --- | --- | --- |
| `SSH_SESSION_SECONDS` | `60` | Maximum wall-clock seconds per SSH session. |
| `SSH_PORT_ON_HOST` | `2222` | Optional host port mapped to server port `22`. |
| `SSH_HOST` | `ssh-server` | Docker network hostname of the server. |
| `SSH_PORT` | `22` | Server SSH port on the Docker network. |
| `SSH_USER` | `deploy` | SSH login user. |
| `SSH_COMMAND` | `whoami && hostname && date -u` | Default remote command. |

The generated private key is written to `secrets/client_ed25519` and ignored by git.
