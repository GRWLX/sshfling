# SSHFling

`sshfling` grants temporary SSH access with standard OpenSSH. The server does not need an AI CLI, agent, SDK, or vendor daemon.

## Server / Service Side

Install from the signed APT repository after confirming the target release has
published package-site evidence, repository signing metadata, and a signing-key
fingerprint:

```bash
BASE_URL="https://grwlx.github.io/sshfling"
: "${APPROVED_REPO_FINGERPRINT:?set this from the approved release evidence}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$BASE_URL/sshfling-repo-fingerprint.txt" -o "$tmp/sshfling-repo-fingerprint.txt"
published_fingerprint="$(tr -d '[:space:]' <"$tmp/sshfling-repo-fingerprint.txt" | tr '[:lower:]' '[:upper:]')"
test "$published_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
curl -fsSL "$BASE_URL/sshfling-repo.gpg" -o "$tmp/sshfling-repo.gpg"
actual_fingerprint="$(gpg --batch --show-keys --with-colons "$tmp/sshfling-repo.gpg" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
test "$actual_fingerprint" = "$APPROVED_REPO_FINGERPRINT"
sudo install -d -m 0755 /usr/share/keyrings
sudo install -m 0644 "$tmp/sshfling-repo.gpg" /usr/share/keyrings/sshfling-repo.gpg
echo "deb [signed-by=/usr/share/keyrings/sshfling-repo.gpg] $BASE_URL/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list
sudo apt update
sudo apt install -y sshfling
```

Uninstall the package/CLI:

```bash
sudo apt remove -y sshfling
sudo rm -f \
  /etc/apt/sources.list.d/sshfling.list \
  /etc/apt/preferences.d/sshfling \
  /usr/share/keyrings/sshfling-repo.gpg
sudo apt update
```

See [Install and uninstall runbook](docs/install-uninstall.md) for DEB/RPM,
public repository, macOS, Windows, BSD/community, container, dependency, and
original-state instructions. See [Repository and package registration](docs/repos.md)
for package publishing details, [OpenSSH dependency policy](docs/openssh-dependencies.md)
for dependency ownership, version, install, uninstall, and original-state
expectations, and [Uninstall and cleanup](#uninstall-and-cleanup) for host SSH
configuration and local state removal.

Password access:

```bash
sudo sshfling -t 10m
```

Shorter password access:

```bash
sudo sshfling -t 1m
```

Certificate access after the user CA exists and the target host trusts it:

```bash
sudo sshfling --certificate -t 10m
```

The server prints the temporary username, expiry, and the client command. Password access also prints a generated password. Certificate access prints or writes the generated key and certificate material. Access expires automatically.

See active sessions or cut them off:

```bash
sudo sshfling list
sudo sshfling -k s234
sudo sshfling shutdown
```

## Client Side

Use the command printed by the server.

Password access:

Install `sshfling` on the client with the signed package repository shown
above, or use the platform-specific package registration examples in
[docs/repos.md](docs/repos.md).

Run the server-printed command:

```bash
sshfling s234@1.0.0.1
```

Then type the generated password when OpenSSH prompts for it. Client mode does not require root.

Certificate access:

```bash
ssh -i /path/to/generated/key user@1.0.0.1
```

On the server side, `-p` is short for `--password`; password access is already the default, so the flag is kept for compatibility. Use `--certificate` to create certificate access. On the client side, `sshfling -p 2222 user@host` is passed through to OpenSSH as the SSH port option.

Certificate setup options such as `--ca-key`, `--public-key-file`, `--out`, `--login-user`, `--source-address`, and `--no-pty` require `--certificate`. Without `--certificate`, the server-side setup path creates a password grant or fails before creating certificate material.

The server-side grant prints the detected server address in the client command. If a host has multiple addresses and you need to override that detection, set `SSHFLING_SERVER_HOST` for the grant command.

Rules:

- Server-side grant, shutdown, and kill commands require root/admin.
- Temporary access setup requires an explicit `-t/--time` lifetime.
- The maximum grant time is 24 hours.
- Up to 10 active sshfling SSH sessions are allowed, depending on install policy.
- Password mode is the default. It creates a real Unix account password, tracks the grant, auto-expires access, and allows only one active session for that temporary username.
- Certificate mode is opt-in with `--certificate`. Run `sudo sshfling ca init` and configure target host trust with `sshfling host install` before issuing certificate grants. If no SSH public key is provided, certificate mode creates a temporary client keypair automatically.
- SSHFling discloses use in system logs through `logger` with the `sshfling` and `sshfling-session` tags. Audit records include grant/session metadata such as user, principal, lifetime, serial, and outcome, but not passwords, bearer tokens, cookies, private keys, public key material, or raw remote commands.

Under the hood, password mode writes a temporary sshd `Match User` block that forces the timeout wrapper. Certificate mode uses OpenSSH user certificates and the same host-side timeout wrapper.

SSHFling also fits AI-assisted operations where the target server should not run an AI CLI, agent, SDK, or vendor daemon. An operator can grant a short-lived standard SSH session to a human or AI tool from a workstation, while the server continues to rely on OpenSSH, local policy, and a forced command wrapper for timeout enforcement. See [AI-assisted temporary server access](docs/ai-temporary-access.md) and [Codex and enterprise detached workflows](docs/codex-enterprise-workflow.md).

It also includes a Docker Compose test harness with two projects:

- server: an SSH container that accepts only public-key auth for `deploy`
- client: a container that connects to the server over the shared Docker network

Every SSH session is capped by `SSH_SESSION_SECONDS`.

For production hosts, Docker is only a test harness. The normal production grant is a temporary password grant:

- `sudo sshfling -t 10m` creates a tracked temporary Unix password grant.
- `sudo sshfling -t 10m --username ticket-1234` creates a shorter named password grant.
- `sudo sshfling password prune --all` removes expired tracked password grants.

OpenSSH user certificates are available explicitly:

- `sudo sshfling ca init` creates an SSH user CA keypair.
- `sshfling host install` configures a target host to trust the CA for one Unix user.
- `sudo sshfling --certificate -t 10m` creates a temporary certificate grant after the CA keypair exists.
- `sudo sshfling cert issue --certificate -t 10m` signs a user's public key for a short lifetime.
- `sshfling serve` runs a small authenticated certificate issuer service.

Do not run `sshfling ca init --force` unless you are intentionally rotating the
user CA. It replaces the existing CA keypair; hosts that trust the old public
key and clients with certificates from the old CA need a planned trust update
and certificate reissue.

The issued certificate includes an OpenSSH `force-command` option that runs `sshfling-session` on the target host. That wrapper enforces the session wall-clock limit, so an already-connected SSH session is killed when its allowed time is reached.

## Production Quick Start

The normal command is:

```bash
sudo sshfling -t 10m
```

That creates a temporary Unix password grant, prints a generated password, and prints the `sshfling user@host` client command. Choose the shortest approved lifetime.

Optional username:

```bash
sudo sshfling -t 10m --username ticket-1234
```

Explicit certificate temporary access:

```bash
sudo sshfling --certificate -t 10m --username ticket-1234
```

Explicit password flag:

```bash
sudo sshfling -p -t 10m --username s234
```

That is equivalent to the default password grant and prints this client command:

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
Use a unique job name for each tracked change. To reuse a name after the previous job has completed, failed, timed out, or been killed, pass `--replace`; active jobs are never replaced in place.

Install per-user policy limits:

```bash
sudo sshfling policy install --user deploy --max-time 30m --max-connections 3
```

Policy also records an access-level classification for least-privilege review:

```bash
sudo sshfling policy install --user deploy --access-level sudo-limited --max-time 30m --max-connections 1
sudo sshfling --certificate --username ticket-1234 --login-user deploy --access-level sudo-limited -t 10m
```

Access levels are policy metadata and audit evidence; they do not add the
account to sudoers, local administrators, groups, roles, or IAM bindings. The
supported levels are `standard`, `operator`, `sudo-limited`, and
`admin/root-equivalent`. `standard` is the default for temporary users,
`operator` is for approved operational accounts without broad sudo,
`sudo-limited` is for reviewed constrained elevation, and `admin` is for
root-equivalent or break-glass access. Grant requests can pass `--access-level`
or `--role`; SSHFling rejects a requested level above the effective policy
level and treats `root` or `Administrator` logins as admin-class access. Host
controls such as Unix groups, sudoers, PAM, AD, MDM, and service-manager policy
remain the enforcement layer for actual privileges.

Password-mode grants create or reset local Unix passwords and therefore refuse
root-equivalent Unix users such as `root`. Use explicit certificate mode with an
admin/root-equivalent access level for approved break-glass access.

Run the local web console:

```bash
web_password="$(openssl rand -base64 24)"
export SSHFLING_WEB_PASSWORD_HASH="$(SSHFLING_WEB_PASSWORD="$web_password" sshfling web-hash)"
printf 'temporary web password: %s\n' "$web_password"
unset web_password
sudo --preserve-env=SSHFLING_WEB_PASSWORD_HASH sshfling web
```

Open `http://127.0.0.1:8790` and log in as `admin`.

The policy is stored at `/etc/sshfling/policy.json`. SSHFling has hard caps of 24 hours and 10 active sessions. Policy can set lower default limits and lower per-user limits, not higher ones.

Root can always replace binaries or edit local files. To make policy changes controlled in production, manage `/etc/sshfling/policy.json` through signed packages/config management and alert on package verification or file integrity changes.

On the issuer machine:

```bash
sudo sshfling ca init --ca-key /etc/sshfling/ca_user_ed25519
```

Use `--force` only for a planned CA rotation. Replacing this keypair changes
the trust anchor for hosts configured with `sshfling host install`; update the
trusted CA public key on those hosts and reissue affected certificates.

Copy `/etc/sshfling/ca_user_ed25519.pub` to each target host, then on each target host:

```bash
sudo sshfling host install \
  --ca-pub ./ca_user_ed25519.pub \
  --username temp-remote \
  --create-user
```

Remove the host SSH configuration:

```bash
sudo sshfling host uninstall --username temp-remote --reload
```

Issue a temporary certificate for a client public key:

```bash
sudo sshfling cert issue --certificate \
  --ca-key /etc/sshfling/ca_user_ed25519 \
  --public-key-file ~/.ssh/id_ed25519.pub \
  --username temp-remote \
  --time 5m \
  --out ~/.ssh/id_ed25519-cert.pub
```

Connect before the certificate expires:

```bash
ssh -i ~/.ssh/id_ed25519 temp-remote@host.example.com
```

Run the issuer API service:

```bash
export SSHFLING_ISSUER_TOKEN="$(openssl rand -hex 32)"
sshfling serve --ca-key /etc/sshfling/ca_user_ed25519 --allowed-principal deploy
```

Run it with systemd after installing a package:

```bash
sudo groupadd --system sshflingd
sudo useradd --system --gid sshflingd --home /var/lib/sshflingd --shell /usr/sbin/nologin sshflingd
sudo install -d -m 0750 -o root -g sshflingd /etc/sshfling
sudo sshfling ca init --ca-key /etc/sshfling/ca_user_ed25519
sudo chown root:sshflingd /etc/sshfling/ca_user_ed25519
sudo chmod 0640 /etc/sshfling/ca_user_ed25519
sudo chown root:root /etc/sshfling/ca_user_ed25519.pub
sudo chmod 0644 /etc/sshfling/ca_user_ed25519.pub
sudo install -m 0640 -o root -g sshflingd /usr/share/doc/sshfling/sshflingd.env.example /etc/sshfling/sshflingd.env
sudo sed -i "s/replace-with-a-long-random-token/$(openssl rand -hex 32)/" /etc/sshfling/sshflingd.env
sudo chown root:sshflingd /etc/sshfling/sshflingd.env
sudo chmod 0640 /etc/sshfling/sshflingd.env
sudo systemctl enable --now sshflingd
```

Keep `/etc/sshfling` root-owned and only group-readable by `sshflingd`. The daemon should not own or write the CA key, token file, or policy file; use the `sshflingd` group for read access, or a local systemd credential drop-in if you prefer `LoadCredential=` for CA/token material.

The packaged service listens on `127.0.0.1:8787` by default. If an approved
private-network deployment needs `SSHFLING_LISTEN` to use a non-loopback
address, set `SSHFLING_ALLOW_REMOTE=1` in
`/etc/sshfling/sshflingd.env` and protect the issuer behind TLS, mTLS, a VPN,
or equivalent network controls.

Request a certificate from the service:

```bash
curl -sS \
  -H "Authorization: Bearer $SSHFLING_ISSUER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"public_key":"ssh-ed25519 AAAA... user@host","principal":"deploy","seconds":300}' \
  http://127.0.0.1:8787/v1/certificates
```

## Uninstall and Cleanup

Package-channel-specific uninstall commands are in
[Install and uninstall runbook](docs/install-uninstall.md).

Package uninstall removes SSHFling-managed package files for the selected
install path. It does not remove host SSH configuration that was created with
`sshfling host install`, temporary password grant state, local CA keys, or
`/etc/sshfling` policy/config files. Dependency packages such as Python,
OpenSSH client/server packages, account-management tools, `procps`, or
`util-linux` are controlled by the host package manager and fleet policy;
uninstall does not guarantee that dependency state is restored to the exact
preinstall state. Do not include `apt autoremove`, `apt autopurge`,
`dnf autoremove`, or `yum autoremove` in SSHFling uninstall runbooks unless
dependency cleanup is a separate reviewed fleet action. On DNF hosts, use
`dnf --setopt=clean_requirements_on_remove=False remove sshfling` when removing
only SSHFling. Linux packages store their own service-account install-state
record under root-owned `/var/lib/sshfling/package-state` and remove that
package state during uninstall/purge handling. Record original dependency and
host configuration state in MDM, configuration management, or backups if exact
revert is required.

The detailed cross-platform dependency policy is in
[OpenSSH dependency policy](docs/openssh-dependencies.md).

For managed hosts, use the direct package-manager uninstall commands in
[Install and uninstall runbook](docs/install-uninstall.md). Avoid downloading a
mutable helper script at uninstall time.

Convenience wrapper with a specific uninstall path:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL https://grwlx.github.io/sshfling/install.sh -o "$tmp/install.sh"
bash "$tmp/install.sh" uninstall apt
bash "$tmp/install.sh" uninstall dnf
bash "$tmp/install.sh" uninstall brew
```

macOS pkg:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -fsSL https://grwlx.github.io/sshfling/macos/uninstall-pkg.sh -o "$tmp/uninstall-pkg.sh"
sudo bash "$tmp/uninstall-pkg.sh"
```

The macOS pkg uninstall helper removes `/usr/local/bin/sshfling` and `/usr/local/share/sshfling`, then forgets the pkg receipt. It intentionally preserves `/etc/sshfling` because that directory can contain local policy, CA material, or operator-managed configuration.

Windows MSI:

```powershell
$Uninstaller = Join-Path $env:TEMP "sshfling-uninstall.ps1"
Invoke-WebRequest -Uri "https://grwlx.github.io/sshfling/windows/uninstall.ps1" -OutFile $Uninstaller
& $Uninstaller
```

MSI uninstall removes the installed SSHFling product directory and the PATH entry added by the MSI. It does not uninstall Python, OpenSSH, Windows OpenSSH Server, host SSH configuration, temporary grant state, CA material, or policy/configuration stored outside the install directory. For the portable Windows zip, delete the extracted directory and remove only PATH entries you added yourself.

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

Only use `--delete-user` for Unix accounts created by `sshfling host install
--create-user`. SSHFling requires its host-user marker before deleting the Unix
account:

```bash
sudo sshfling host uninstall --username temp-remote --delete-user --reload
```

Clean up temporary password grants:

```bash
sudo sshfling password prune --all
sudo sshfling password prune --all --delete-users
sudo sshfling password prune --username s234 --delete-users
```

Prune requires exactly one selector: `--all` to scan the tracked grant store or
`--username USER` for targeted cleanup. It only removes expired grants and leaves
active grants in place. By default, expired SSHFling-created Unix users are
locked and expired; `--delete-users` deletes expired SSHFling-created users only
when SSHFling has recorded matching UID/GID/home identity evidence. Existing
users that were explicitly allowed with `--allow-existing-user` are locked and
expired but are never deleted by `--delete-users`. Root-equivalent users are
never deleted from password-grant metadata or host-user markers. Identity
mismatches preserve managed config and metadata for investigation.

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
powershell -NoProfile -File packaging/build-msi.ps1
./packaging/build-pkg.sh
```

Package outputs go to `dist/`.

- `.deb` needs `dpkg-deb`.
- `.rpm` needs `rpmbuild`.
- `.msi` needs Windows PowerShell and WiX Toolset v3.
- `.pkg` needs macOS `pkgbuild` and `productbuild`.

Repo registration instructions are in [docs/repos.md](docs/repos.md).
Package-channel install and uninstall instructions are in
[docs/install-uninstall.md](docs/install-uninstall.md).
The current OS/package target matrix is in [docs/build-targets.md](docs/build-targets.md).
OpenSSH and runtime dependency ownership policy is in
[docs/openssh-dependencies.md](docs/openssh-dependencies.md).
Enterprise publishing guidance is in [docs/release-checklist.md](docs/release-checklist.md),
[docs/release-evidence.md](docs/release-evidence.md),
[docs/enterprise-readiness.md](docs/enterprise-readiness.md), and the
[docs/wiki](docs/wiki/Home.md) pages.

GitHub Actions workflows are included for public distribution:

- `Container image tests` builds packages into Docker-based install targets and runs the SSHFling server/client image smoke tests through `make test-containers`.
- `Release packages without web` builds release artifacts only.
- `Release packages with public web` verifies a GitHub Pages package site for commands such as `sudo apt install -y sshfling`, `sudo dnf install -y sshfling`, Homebrew, macOS `.pkg`, Windows MSI installs, and community package manifests for BSDs, Arch/AUR, Alpine, Nix, Guix, Void, Gentoo, Slackware, openSUSE OBS, Snapcraft, Termux, AppImage, Scoop, winget, and Chocolatey. Manual runs are dry-run verification unless `publish=true`; tag runs publish only when stable repository signing secrets are present and the configured Pages environment permits deployment.
- `Package install tests` installs from the published package site and verifies the requested `sshfling` version across Linux package repos and community package manifests.
- `Cross OS validation` installs or builds those outputs across Linux, BSD,
  macOS, and Windows and checks the explicit grant lifetime requirement,
  24-hour cap, copied service templates, active-session PID fields, and
  detached job PID lifecycle.

### v0.1.14 Release Readiness

`v0.1.14` is the current fixed-forward release-prep candidate. It includes
additional prune safety, CA/certificate gating, OpenSSH dependency checks,
DEB/RPM service-account identity preservation, macOS/Windows package trust
gates, and release-evidence updates after the published `v0.1.13` release.
The previous published release is `v0.1.13` at commit
`065b03c16a81e9167120e9f41afd4c5e81a79a4a`.

`v0.1.12` shipped enterprise package publishing preparation: package builders,
public package-site verification, repository registration docs, community
manifest generation, release checklist/evidence templates, cross-OS/package
install validation, release matrix tooling, and enterprise operations docs.

Do not treat `v0.1.14` as enterprise-ready or published until release evidence
is attached for the final commit: release approval, protected tag or equivalent
change-control evidence, workflow run URLs, artifact checksums, repository
signing fingerprint, Pages deployment ID where package-site publishing is in
scope, runtime behavior evidence for password, certificate, access-level,
prune, and uninstall behavior, and macOS/Windows signing or notarization
evidence where applicable.

Release evidence generation and validation commands:

```bash
git status --short --branch
make clean
make test
make test-containers
make release-security-scan-strict VERSION=0.1.14
make release-security-evidence-validate RELEASE_MATRIX_VALIDATE_FLAGS=--require-pass
make package VERSION=0.1.14
make release-assets-evidence VERSION=0.1.14
make release-matrix-validate \
  RELEASE_MATRIX=docs/release/enterprise-release-evidence/generated/release-assets-matrix.csv \
  RELEASE_MANIFEST=docs/release/enterprise-release-evidence/generated/release-assets-manifest.json \
  RELEASE_MATRIX_VALIDATE_FLAGS=--require-pass
```

Link the completed release workflows listed above with the same version input.
Do not make enterprise readiness claims from generated test signing keys,
unsigned macOS/Windows artifacts, or unreviewed exception records.

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
