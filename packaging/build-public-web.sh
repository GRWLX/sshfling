#!/usr/bin/env bash
set -euo pipefail

package_dist="${1:-package-dist}"
public_dir="${2:-public}"

version="${VERSION:?VERSION is required}"
repository="${REPOSITORY:?REPOSITORY is required}"
owner="${OWNER:?OWNER is required}"
repo_name="${repository#*/}"
owner_pages="$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')"
base_host="${owner_pages}.github.io"
base_url="https://${base_host}/${repo_name}"

first_file() {
  local dir="$1"
  local pattern="$2"
  local found

  found="$(find "$dir" -maxdepth 1 -type f -name "$pattern" -print | sort | head -n 1)"
  if [[ -z "$found" ]]; then
    echo "Missing required package matching $pattern in $dir" >&2
    exit 1
  fi
  printf '%s\n' "$found"
}

rm -rf "$public_dir"
install -d \
  "$public_dir/apt" \
  "$public_dir/rpm" \
  "$public_dir/downloads" \
  "$public_dir/homebrew" \
  "$public_dir/macos" \
  "$public_dir/windows"
touch "$public_dir/.nojekyll"

cp "$package_dist"/*.deb "$public_dir/apt/"
cp "$package_dist"/*.rpm "$public_dir/rpm/"
cp "$package_dist"/*.tar.gz "$public_dir/downloads/"
cp "$package_dist"/*.pkg "$public_dir/downloads/"
cp "$package_dist"/*.msi "$public_dir/downloads/"
if compgen -G "$package_dist/*.zip" >/dev/null; then
  cp "$package_dist"/*.zip "$public_dir/downloads/"
fi

(
  cd "$public_dir/apt"
  dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
)

createrepo_c "$public_dir/rpm"

source_tar="$(basename "$(first_file "$public_dir/downloads" "sshfling-*.tar.gz")")"
source_sha="$(sha256sum "$public_dir/downloads/$source_tar" | awk '{print $1}')"
cat >"$public_dir/homebrew/sshfling.rb" <<RUBY
class Sshfling < Formula
  desc "Temporary SSH certificate issuer and access CLI"
  homepage "$base_url"
  url "$base_url/downloads/$source_tar"
  sha256 "$source_sha"
  license "Apache-2.0"

  depends_on "python@3"

  def install
    bin.install "bin/sshfling"
    (pkgshare/"templates").install ".env.example", "LICENSE", "README.md", "compose.server.yml", "compose.client.yml"
    (pkgshare/"templates").install "scripts", "secrets", "ssh-client", "ssh-server", "production", "systemd"
  end

  test do
    system "#{bin}/sshfling", "--version"
  end
end
RUBY

cat >"$public_dir/install.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

base_url="${SSHFLING_BASE_URL:-__BASE_URL__}"
base_host="${base_url#http://}"
base_host="${base_host#https://}"
base_host="${base_host%%/*}"
mode="${1:-auto}"

install_apt() {
  sudo rm -f /etc/apt/sources.list.d/fling.list /etc/apt/preferences.d/fling
  echo "deb [trusted=yes] ${base_url}/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list >/dev/null
  sudo tee /etc/apt/preferences.d/sshfling >/dev/null <<EOF
Package: sshfling
Pin: origin ${base_host}
Pin-Priority: 1001
EOF
  sudo apt-get update
  sudo apt-get install -y sshfling
}

install_rpm() {
  sudo rm -f /etc/yum.repos.d/fling.repo
  sudo tee /etc/yum.repos.d/sshfling.repo >/dev/null <<EOF
[sshfling]
name=SSHFling
baseurl=${base_url}/rpm
enabled=1
gpgcheck=0
EOF
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y sshfling
  else
    sudo yum install -y sshfling
  fi
}

install_brew() {
  brew install "${base_url}/homebrew/sshfling.rb"
}

case "$mode" in
  apt) install_apt ;;
  rpm|dnf|yum) install_rpm ;;
  brew|homebrew) install_brew ;;
  auto)
    if command -v apt-get >/dev/null 2>&1; then
      install_apt
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
      install_rpm
    elif command -v brew >/dev/null 2>&1; then
      install_brew
    else
      echo "No supported package manager found. Use ${base_url}/downloads/ directly." >&2
      exit 2
    fi
    ;;
  *)
    echo "Usage: install.sh [auto|apt|rpm|dnf|yum|brew]" >&2
    exit 2
    ;;
esac
SH
sed -i "s#__BASE_URL__#$base_url#g" "$public_dir/install.sh"
chmod 0755 "$public_dir/install.sh"

pkg_name="$(basename "$(first_file "$public_dir/downloads" "sshfling-*.pkg")")"
cat >"$public_dir/macos/install-pkg.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
curl -fsSL "$base_url/downloads/$pkg_name" -o "\$tmp/$pkg_name"
sudo installer -pkg "\$tmp/$pkg_name" -target /
SH
chmod 0755 "$public_dir/macos/install-pkg.sh"

msi_name="$(basename "$(first_file "$public_dir/downloads" "sshfling-*.msi")")"
cat >"$public_dir/windows/install.ps1" <<SH
\$ErrorActionPreference = "Stop"
\$installer = Join-Path \$env:TEMP "$msi_name"
Invoke-WebRequest -Uri "$base_url/downloads/$msi_name" -OutFile \$installer
Start-Process msiexec.exe -Wait -ArgumentList "/i", \$installer, "/qn"
SH

(
  cd "$public_dir/downloads"
  sha256sum -- * > SHA256SUMS
)

bash "$(dirname "${BASH_SOURCE[0]}")/build-community-manifests.sh" "$package_dist" "$public_dir" "$base_url" "$version" "$repository"

{
  echo '<!doctype html>'
  echo '<html lang="en">'
  echo '<head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">'
  echo "<title>SSHFling $version downloads</title></head>"
  echo '<body><h1>SSHFling downloads</h1><ul>'
  for file in "$public_dir"/downloads/*; do
    name="$(basename "$file")"
    echo "<li><a href=\"$name\">$name</a></li>"
  done
  echo '</ul></body></html>'
} >"$public_dir/downloads/index.html"

cat >"$public_dir/index.html" <<HTML
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>SSHFling $version packages</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 920px; margin: 40px auto; padding: 0 20px; line-height: 1.5; }
    code, pre { background: #f4f4f5; border-radius: 6px; }
    code { padding: 2px 5px; }
    pre { padding: 14px; overflow-x: auto; }
  </style>
</head>
<body>
  <h1>SSHFling $version packages</h1>
  <h2>Debian / Ubuntu</h2>
  <pre><code>sudo rm -f /etc/apt/sources.list.d/fling.list /etc/apt/preferences.d/fling
echo "deb [trusted=yes] $base_url/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list
sudo tee /etc/apt/preferences.d/sshfling &gt;/dev/null &lt;&lt;'EOF'
Package: sshfling
Pin: origin $base_host
Pin-Priority: 1001
EOF
sudo apt update
sudo apt install -y sshfling</code></pre>
  <h2>RHEL / Fedora / Rocky / Alma</h2>
  <pre><code>sudo rm -f /etc/yum.repos.d/fling.repo
sudo tee /etc/yum.repos.d/sshfling.repo &gt;/dev/null &lt;&lt;'EOF'
[sshfling]
name=SSHFling
baseurl=$base_url/rpm
enabled=1
gpgcheck=0
EOF
sudo dnf install -y sshfling</code></pre>
  <h2>Homebrew</h2>
  <pre><code>brew install $base_url/homebrew/sshfling.rb</code></pre>
  <h2>macOS pkg</h2>
  <pre><code>curl -fsSL $base_url/macos/install-pkg.sh | sudo bash</code></pre>
  <h2>Windows MSI</h2>
  <pre><code>irm $base_url/windows/install.ps1 | iex</code></pre>
  <h2>More ecosystems</h2>
  <p>Arch/AUR, Alpine, FreeBSD, OpenBSD, pkgsrc, Nix, Guix, Void, Gentoo, Slackware, openSUSE OBS, Snapcraft, Termux, AppImage, Scoop, winget, and Chocolatey manifests are under <a href="$base_url/community.html">community package manifests</a>.</p>
  <h2>Downloads</h2>
  <p>Raw packages and checksums are under <a href="$base_url/downloads/">downloads</a>.</p>
</body>
</html>
HTML
