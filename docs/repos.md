# Register SSHFling In Package Repos

The repo includes two GitHub Actions release paths:

- `Release packages without web` builds `.deb`, `.rpm`, `.msi`, `.pkg`, a source tarball, and release checksums.
- `Release packages with public web` builds the same package set and publishes a GitHub Pages package site with APT, RPM, Homebrew, macOS pkg, Windows MSI, and community package manifests for additional ecosystems.

For public installs, enable GitHub Pages for Actions in the repository settings and run the `Release packages with public web` workflow from a version tag such as `v0.1.6`.

Replace `OWNER` and `REPO` in the examples below with the GitHub organization/user and repository name.

```bash
BASE_URL="https://OWNER.github.io/REPO"
BASE_HOST="OWNER.github.io"
```

Automatic install on Linux or Homebrew hosts:

```bash
curl -fsSL "${BASE_URL}/install.sh" | bash
```

Force a specific installer path:

```bash
curl -fsSL "${BASE_URL}/install.sh" | bash -s -- apt
curl -fsSL "${BASE_URL}/install.sh" | bash -s -- dnf
curl -fsSL "${BASE_URL}/install.sh" | bash -s -- brew
```

## Public Debian / Ubuntu APT

```bash
sudo rm -f /etc/apt/sources.list.d/fling.list /etc/apt/preferences.d/fling
echo "deb [trusted=yes] ${BASE_URL}/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list
sudo tee /etc/apt/preferences.d/sshfling >/dev/null <<EOF
Package: sshfling
Pin: origin ${BASE_HOST}
Pin-Priority: 1001
EOF
sudo apt update
sudo apt install -y sshfling
```

## Public RHEL / Fedora / Rocky / Alma RPM

```bash
sudo rm -f /etc/yum.repos.d/fling.repo
sudo tee /etc/yum.repos.d/sshfling.repo >/dev/null <<EOF
[sshfling]
name=SSHFling
baseurl=${BASE_URL}/rpm
enabled=1
gpgcheck=0
EOF

sudo dnf install -y sshfling
```

Use `sudo yum install -y sshfling` on older yum-based hosts.

## Public Homebrew

```bash
brew install "${BASE_URL}/homebrew/sshfling.rb"
```

## Public macOS pkg

```bash
curl -fsSL "${BASE_URL}/macos/install-pkg.sh" | sudo bash
```

## Public Windows MSI

```powershell
$BaseUrl = "https://OWNER.github.io/REPO"
irm "$BaseUrl/windows/install.ps1" | iex
```

## Public Community Manifests

The Pages workflow also generates ready-to-use or ready-to-submit package definitions at `${BASE_URL}/community.html`:

- Arch / AUR: `arch/PKGBUILD` and `arch/.SRCINFO`
- Alpine: `alpine/APKBUILD`
- FreeBSD Ports: `freebsd/security/sshfling`
- OpenBSD Ports: `openbsd/security/sshfling`
- pkgsrc for NetBSD, DragonFly BSD, illumos, and SmartOS: `pkgsrc/security/sshfling`
- Nix: `nix/flake.nix`
- Guix: `guix/sshfling.scm`
- Void Linux: `void/template`
- Gentoo: `gentoo/app-admin/sshfling`
- Slackware: `slackware/sshfling.SlackBuild`
- openSUSE OBS: `opensuse/sshfling.spec`
- Snapcraft: `snap/snapcraft.yaml`
- Termux: `termux/packages/sshfling/build.sh`
- AppImage: `appimage/AppImageBuilder.yml`
- Scoop: `scoop/sshfling.json`
- winget: `winget/manifests/g/OWNER/SSHFling/VERSION`
- Chocolatey: `chocolatey/sshfling.VERSION.nupkg`

Some of these can be installed directly from the generated URL, while official/community repositories still require a maintainer account, review, signing, or a pull request into the upstream repository.

The generated public APT and RPM repo examples use unsigned metadata (`trusted=yes` and `gpgcheck=0`) so the command is simple. For production fleets, sign the repository metadata and packages, publish the public key, and change these examples to use `signed-by=` on APT and `gpgcheck=1` on RPM.

Client mode only needs Python and OpenSSH client tools. Server-side certificate grants need OpenSSH server tooling on the target host. Server-side password grants are Linux-oriented and need account-management tools such as `useradd`, `chpasswd`, `usermod`, and `chage`; the generated Linux package metadata includes the matching `passwd`, `shadow`, or `shadow-utils` dependency where that ecosystem uses one.

Build packages first:

```bash
./packaging/build-deb.sh
./packaging/build-rpm.sh
powershell -NoProfile -ExecutionPolicy Bypass -File packaging/build-msi.ps1
./packaging/build-pkg.sh
```

Outputs go to `dist/`.

## Debian / Ubuntu APT

Minimal local repo:

```bash
mkdir -p repo/apt
cp dist/sshfling_*.deb repo/apt/
cd repo/apt
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
```

Register it on a client:

```bash
echo "deb [trusted=yes] file:/absolute/path/to/repo/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list
sudo apt update
sudo apt install sshfling
```

For production, sign the repo metadata with GPG and host it over HTTPS.

## RHEL / Fedora / Rocky / Alma RPM

Minimal local repo:

```bash
mkdir -p repo/rpm
cp dist/sshfling-*.rpm repo/rpm/
createrepo_c repo/rpm
```

Register it on a client:

```bash
sudo tee /etc/yum.repos.d/sshfling.repo >/dev/null <<'EOF'
[sshfling]
name=SSHFling
baseurl=file:///absolute/path/to/repo/rpm
enabled=1
gpgcheck=0
EOF

sudo dnf install sshfling
```

For production, sign RPMs and enable `gpgcheck=1`.

## macOS

For direct `.pkg` distribution:

```bash
sudo installer -pkg dist/sshfling-0.1.6.pkg -target /
```

For Homebrew distribution, publish a source tarball and add a formula to a tap:

```ruby
class Sshfling < Formula
  desc "Time-limited SSH Docker Compose deployment CLI"
  homepage "https://example.com/sshfling"
  url "https://example.com/sshfling-0.1.6.tar.gz"
  sha256 "REPLACE_WITH_SHA256"
  license "Apache-2.0"

  depends_on "python@3"
  depends_on "docker" => :recommended

  def install
    bin.install "bin/sshfling"
    pkgshare.install ".env.example", "LICENSE", "README.md", "compose.server.yml", "compose.client.yml"
    pkgshare.install "scripts", "secrets", "ssh-client", "ssh-server", "production", "systemd"
  end

  test do
    system "#{bin}/sshfling", "--version"
  end
end
```

Then users install with:

```bash
brew tap your-org/sshfling
brew install sshfling
```

For production `.pkg` distribution, sign and notarize the package.

## Windows MSI

MSI files are not installed from APT/YUM-style repos. Common registration paths:

- winget: publish a manifest that points to the signed MSI URL.
- Intune, SCCM, or Group Policy: upload the MSI as a managed app/package.
- Internal HTTPS share: publish the MSI and checksum.

Silent install:

```powershell
msiexec /i sshfling-0.1.6.msi /qn
```

For production, sign the MSI with an Authenticode certificate.
