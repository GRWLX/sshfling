# Fling

`fling` is a production temporary SSH access tool. Normal use is intentionally small:

```bash
sudo fling
sudo fling -t 5m
sudo fling -t 5m --username temp-name
sudo fling list
sudo fling -k f432
sudo fling web
sudo fling shutdown
sudo fling -k
```

If `--username` is omitted, `fling` creates a random temporary username like `f123`.

Rules:

- `fling`, `fling -t`, `fling shutdown`, and `fling -k` require root/admin.
- The maximum time is 1 hour.
- `fling` with no `-t` uses the maximum: 1 hour.
- Up to 10 active fling SSH sessions are allowed, depending on install policy.
- If no SSH public key is provided, `fling` creates a temporary keypair automatically.

Under the hood, it uses OpenSSH user certificates and a host-side timeout wrapper.

Fling also fits AI-assisted operations where the target server should not run an AI CLI, agent, SDK, or vendor daemon. An operator can grant a short-lived standard SSH session to a human or AI tool from a workstation, while the server continues to rely on OpenSSH certificates, local policy, and a forced command wrapper for timeout enforcement. See [AI-assisted temporary server access](docs/ai-temporary-access.md).

It also includes a Docker Compose test harness with two projects:

- server: an SSH container that accepts only public-key auth for `deploy`
- client: a container that connects to the server over the shared Docker network

Every SSH session is capped by `SSH_SESSION_SECONDS`.

For production hosts, Docker is only a test harness. The production mode uses OpenSSH user certificates:

- `fling ca init` creates an SSH user CA keypair.
- `fling host install` configures a target host to trust the CA for one Unix user.
- `fling cert issue` signs a user's public key for a short lifetime.
- `fling serve` runs a small authenticated certificate issuer service.

The issued certificate includes an OpenSSH `force-command` option that runs `fling-session` on the target host. That wrapper enforces the session wall-clock limit, so an already-connected SSH session is killed when its allowed time is reached.

## Production Quick Start

The normal command is:

```bash
sudo fling
```

That creates or reuses the CA key, creates a temporary username, creates a temporary keypair/certificate, and prints the SSH command. Use `-t` to choose a shorter time.

Optional username:

```bash
sudo fling -t 10m --username ticket-1234
```

Kill active fling SSH sessions:

```bash
sudo fling shutdown
sudo fling -k f432
```

List active sessions:

```bash
sudo fling list
```

Install per-user policy limits:

```bash
sudo fling policy install --user deploy --max-time 30m --max-connections 3
```

Run the local web console:

```bash
export FLING_WEB_PASSWORD_HASH="$(FLING_WEB_PASSWORD='change-me' fling web-hash)"
sudo --preserve-env=FLING_WEB_PASSWORD_HASH fling web
```

Open `http://127.0.0.1:8790` and log in as `admin`.

The policy is stored at `/etc/fling/policy.json`. Fling has hard caps of 1 hour and 10 active sessions. Policy can set lower default limits and lower per-user limits, not higher ones.

Root can always replace binaries or edit local files. To make policy changes controlled in production, manage `/etc/fling/policy.json` through signed packages/config management and alert on package verification or file integrity changes.

On the issuer machine:

```bash
fling ca init --ca-key /etc/fling/ca_user_ed25519
```

Copy `/etc/fling/ca_user_ed25519.pub` to each target host, then on each target host:

```bash
sudo fling host install \
  --ca-pub ./ca_user_ed25519.pub \
  --username temp-remote \
  --create-user \
  --reload
```

Issue a temporary certificate for a client public key:

```bash
fling cert issue \
  --ca-key /etc/fling/ca_user_ed25519 \
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
export FLING_ISSUER_TOKEN="$(openssl rand -hex 32)"
fling serve --ca-key /etc/fling/ca_user_ed25519 --allowed-principal deploy
```

Run it with systemd after installing a package:

```bash
sudo useradd --system --home /var/lib/flingd --shell /usr/sbin/nologin flingd
sudo install -d -m 0750 -o flingd -g flingd /etc/fling
sudo fling ca init --ca-key /etc/fling/ca_user_ed25519
sudo chown flingd:flingd /etc/fling/ca_user_ed25519 /etc/fling/ca_user_ed25519.pub
sudo install -m 0600 -o root -g root /usr/share/doc/fling/flingd.env.example /etc/fling/flingd.env
sudo sed -i "s/replace-with-a-long-random-token/$(openssl rand -hex 32)/" /etc/fling/flingd.env
sudo systemctl enable --now flingd
```

Request a certificate from the service:

```bash
curl -sS \
  -H "Authorization: Bearer $FLING_ISSUER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"public_key":"ssh-ed25519 AAAA... user@host","principal":"deploy","seconds":300}' \
  http://127.0.0.1:8787/v1/certificates
```

## Docker Test Harness

```bash
./scripts/install-local.sh
fling init ./my-fling --with-key --session-seconds 60
cd ./my-fling
fling network create
fling server up --build
fling client run 'whoami && hostname && date -u'
```

Timeout test:

```bash
fling test-timeout --seconds 5 --sleep 20
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

GitHub Actions workflows are included for public distribution:

- `Release packages without web` builds release artifacts only.
- `Release packages with public web` publishes a GitHub Pages package site for commands such as `sudo apt install -y fling`, `sudo dnf install -y fling`, Homebrew, macOS `.pkg`, and Windows MSI installs.

## Package Ecosystem Choice

For this tool, native packages are the right default for deployment fleets because the command wraps Docker, writes deployment files, and is likely to be installed by admins.

NPM would be good for developer-first distribution, especially `npm install -g fling`, but it would add a Node runtime expectation. NuGet is only a good fit if this becomes a .NET global tool. Homebrew is the best macOS developer path, winget/Intune are better Windows distribution paths, and APT/YUM are best for Linux fleets.

## Common Commands

```bash
fling doctor
fling init ./deploy --with-key
fling network create
fling server up --build
fling server logs --tail 100
fling client run 'uname -a'
fling server down
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
