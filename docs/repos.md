# Register Fling In Package Repos

The repo includes two GitHub Actions release paths:

- `Release packages without web` builds `.deb`, `.rpm`, `.msi`, `.pkg`, a source tarball, and release checksums.
- `Release packages with public web` builds the same package set and publishes a GitHub Pages package site with APT, RPM, Homebrew, macOS pkg, and Windows MSI install entry points.

For public installs, enable GitHub Pages for Actions in the repository settings and run the `Release packages with public web` workflow from a version tag such as `v0.1.0`.

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
echo "deb [trusted=yes] ${BASE_URL}/apt ./" | sudo tee /etc/apt/sources.list.d/fling.list
sudo tee /etc/apt/preferences.d/fling >/dev/null <<EOF
Package: fling
Pin: origin ${BASE_HOST}
Pin-Priority: 1001
EOF
sudo apt update
sudo apt install -y fling
```

## Public RHEL / Fedora / Rocky / Alma RPM

```bash
sudo tee /etc/yum.repos.d/fling.repo >/dev/null <<EOF
[fling]
name=Fling
baseurl=${BASE_URL}/rpm
enabled=1
gpgcheck=0
EOF

sudo dnf install -y fling
```

Use `sudo yum install -y fling` on older yum-based hosts.

## Public Homebrew

```bash
brew install "${BASE_URL}/homebrew/fling.rb"
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

The generated public APT and RPM repo examples use unsigned metadata (`trusted=yes` and `gpgcheck=0`) so the command is simple. For production fleets, sign the repository metadata and packages, publish the public key, and change these examples to use `signed-by=` on APT and `gpgcheck=1` on RPM.

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
cp dist/fling_*.deb repo/apt/
cd repo/apt
dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
```

Register it on a client:

```bash
echo "deb [trusted=yes] file:/absolute/path/to/repo/apt ./" | sudo tee /etc/apt/sources.list.d/fling.list
sudo apt update
sudo apt install fling
```

For production, sign the repo metadata with GPG and host it over HTTPS.

## RHEL / Fedora / Rocky / Alma RPM

Minimal local repo:

```bash
mkdir -p repo/rpm
cp dist/fling-*.rpm repo/rpm/
createrepo_c repo/rpm
```

Register it on a client:

```bash
sudo tee /etc/yum.repos.d/fling.repo >/dev/null <<'EOF'
[fling]
name=Fling
baseurl=file:///absolute/path/to/repo/rpm
enabled=1
gpgcheck=0
EOF

sudo dnf install fling
```

For production, sign RPMs and enable `gpgcheck=1`.

## macOS

For direct `.pkg` distribution:

```bash
sudo installer -pkg dist/fling-0.1.0.pkg -target /
```

For Homebrew distribution, publish a source tarball and add a formula to a tap:

```ruby
class Fling < Formula
  desc "Time-limited SSH Docker Compose deployment CLI"
  homepage "https://example.com/fling"
  url "https://example.com/fling-0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256"
  license "Apache-2.0"

  depends_on "python@3"
  depends_on "docker" => :recommended

  def install
    bin.install "bin/fling"
    pkgshare.install ".env.example", "LICENSE", "README.md", "compose.server.yml", "compose.client.yml"
    pkgshare.install "scripts", "secrets", "ssh-client", "ssh-server"
  end

  test do
    system "#{bin}/fling", "--version"
  end
end
```

Then users install with:

```bash
brew tap your-org/fling
brew install fling
```

For production `.pkg` distribution, sign and notarize the package.

## Windows MSI

MSI files are not installed from APT/YUM-style repos. Common registration paths:

- winget: publish a manifest that points to the signed MSI URL.
- Intune, SCCM, or Group Policy: upload the MSI as a managed app/package.
- Internal HTTPS share: publish the MSI and checksum.

Silent install:

```powershell
msiexec /i fling-0.1.0.msi /qn
```

For production, sign the MSI with an Authenticode certificate.
