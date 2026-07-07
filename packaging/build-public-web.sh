#!/usr/bin/env bash
set -euo pipefail

package_dist="${1:-package-dist}"
public_dir="${2:-public}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

export LC_ALL=C
export TZ=UTC
umask 022

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${VERSION:?VERSION is required}" "$repo_root")"
repository="${REPOSITORY:?REPOSITORY is required}"
owner="${OWNER:?OWNER is required}"
repo_name="${repository#*/}"
owner_pages="$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')"
base_host="${owner_pages}.github.io"
base_url="https://${base_host}/${repo_name}"
pkg_identifier="${SSHFLING_PKG_IDENTIFIER:-io.sshfling.cli}"
repo_signed=0
repo_signing_key=""
repo_signing_fingerprint=""
gpg_home=""
gpg_pass_file=""
build_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$build_epoch" ]]; then
  build_epoch="$(git -C "$repo_root" log -1 --format=%ct 2>/dev/null || date -u +%s)"
fi
if [[ ! "$build_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be Unix epoch seconds, got: $build_epoch" >&2
  exit 2
fi

cleanup_signing() {
  if [[ -n "$gpg_home" && -d "$gpg_home" ]] && command -v gpgconf >/dev/null 2>&1; then
    GNUPGHOME="$gpg_home" gpgconf --kill all >/dev/null 2>&1 || true
  fi
  if [[ -n "$gpg_pass_file" ]]; then
    rm -f "$gpg_pass_file"
  fi
  if [[ -n "$gpg_home" ]]; then
    rm -rf "$gpg_home"
  fi
}
trap cleanup_signing EXIT

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

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_gpg_fingerprint() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

normalize_public_file_mtimes() {
  find "$public_dir/apt" "$public_dir/rpm" "$public_dir/downloads" -type f -exec touch -d "@$build_epoch" {} +
}

setup_repo_signing() {
  local private_key="${SSHFLING_REPO_GPG_PRIVATE_KEY:-}"
  local requested_key="${SSHFLING_REPO_GPG_KEY_ID:-}"
  local expected_fingerprint
  local generate_key="${SSHFLING_GENERATE_REPO_SIGNING_KEY:-}"
  local generate_repo_key=0
  local require_signatures="${REQUIRE_REPO_SIGNATURES:-}"

  if is_truthy "$generate_key"; then
    generate_repo_key=1
  fi
  expected_fingerprint="$(normalize_gpg_fingerprint "${SSHFLING_REPO_GPG_FINGERPRINT:-}")"
  if is_truthy "$require_signatures"; then
    if [[ -z "$private_key" ]]; then
      echo "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_PRIVATE_KEY for stable repository signing." >&2
      exit 2
    fi
    if [[ -z "$expected_fingerprint" ]]; then
      echo "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_FINGERPRINT as the approved trust anchor." >&2
      exit 2
    fi
    if (( generate_repo_key )); then
      echo "REQUIRE_REPO_SIGNATURES does not allow generated test repository signing keys." >&2
      exit 2
    fi
  fi
  if [[ -z "$private_key" && -z "$requested_key" ]] && (( ! generate_repo_key )); then
    return 0
  fi
  if [[ -z "$private_key" && -n "$requested_key" ]] && (( ! generate_repo_key )); then
    if ! command -v gpg >/dev/null 2>&1 || ! gpg --batch --list-secret-keys "$requested_key" >/dev/null 2>&1; then
      echo "Repository signing key ID was provided without matching signing material; building an unsigned package site." >&2
      return 0
    fi
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required when repository signing is enabled." >&2
    exit 127
  fi

  if [[ -n "$private_key" ]] || (( generate_repo_key )); then
    gpg_home="$(mktemp -d)"
    chmod 700 "$gpg_home"
    export GNUPGHOME="$gpg_home"
  fi

  if [[ -n "$private_key" ]]; then
    printf '%s\n' "$private_key" | gpg --batch --import
  elif (( generate_repo_key )); then
    gpg --batch --passphrase '' --quick-generate-key "SSHFling package repository <packages@sshfling.local>" rsa3072 sign 1y
  fi

  if [[ -n "$requested_key" && ( -n "$private_key" || "$generate_repo_key" == "0" ) ]]; then
    repo_signing_key="$requested_key"
  else
    repo_signing_key="$(gpg --batch --list-secret-keys --with-colons | awk -F: '/^fpr:/ {print $10; exit}')"
  fi
  if [[ -z "$repo_signing_key" ]]; then
    echo "No repository signing key was found." >&2
    exit 2
  fi
  gpg --batch --list-secret-keys "$repo_signing_key" >/dev/null
  repo_signing_fingerprint="$(gpg --batch --with-colons --fingerprint "$repo_signing_key" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
  if [[ -z "$repo_signing_fingerprint" ]]; then
    echo "Could not determine repository signing key fingerprint." >&2
    exit 2
  fi
  if [[ -n "$expected_fingerprint" && "$repo_signing_fingerprint" != "$expected_fingerprint" ]]; then
    echo "Repository signing key fingerprint mismatch." >&2
    echo "Expected: $expected_fingerprint" >&2
    echo "Actual:   $repo_signing_fingerprint" >&2
    exit 2
  fi
  gpg --batch --yes --armor --export "$repo_signing_key" >"$public_dir/sshfling-repo.asc"
  gpg --batch --yes --export "$repo_signing_key" >"$public_dir/sshfling-repo.gpg"
  printf '%s\n' "$repo_signing_fingerprint" >"$public_dir/sshfling-repo-fingerprint.txt"
  repo_signed=1
}

gpg_sign() {
  local args=(--batch --yes --local-user "$repo_signing_key")
  if [[ -n "${SSHFLING_REPO_GPG_PASSPHRASE:-}" ]]; then
    if [[ -z "$gpg_pass_file" ]]; then
      gpg_pass_file="$(mktemp)"
      chmod 600 "$gpg_pass_file"
      printf '%s' "$SSHFLING_REPO_GPG_PASSPHRASE" >"$gpg_pass_file"
    fi
    args+=(--pinentry-mode loopback --passphrase-file "$gpg_pass_file")
  fi
  gpg "${args[@]}" "$@"
}

apt_checksum_section() {
  local title="$1"
  local tool="$2"
  shift 2
  local file checksum size

  echo "$title:"
  for file in "$@"; do
    checksum="$("$tool" "$file" | awk '{print $1}')"
    size="$(wc -c <"$file" | tr -d '[:space:]')"
    printf ' %s %16s %s\n' "$checksum" "$size" "$file"
  done
}

normalize_public_tree_timestamps() {
  find "$public_dir" -exec touch -h -d "@$build_epoch" {} +
}

normalize_chocolatey_package() {
  local package_path="$public_dir/chocolatey/sshfling.${version}.nupkg"
  local install_script="$public_dir/chocolatey/install.ps1"
  local package_sha

  if [[ ! -f "$package_path" ]]; then
    return
  fi

  python3 - "$public_dir/chocolatey" "$package_path" "$build_epoch" <<'PY'
import sys
import time
import zipfile
from pathlib import Path

root = Path(sys.argv[1])
output = Path(sys.argv[2])
epoch = max(int(sys.argv[3]), 315532800)
date_time = time.gmtime(epoch)[:6]

with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
    for relative in ["sshfling.nuspec", "tools/chocolateyinstall.ps1"]:
        data = (root / relative).read_bytes()
        info = zipfile.ZipInfo(relative, date_time=date_time)
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = (0o644 & 0xFFFF) << 16
        archive.writestr(info, data)
PY

  package_sha="$(sha256sum "$package_path" | awk '{print $1}')"
  python3 - "$install_script" "$package_sha" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
package_sha = sys.argv[2]
lines = path.read_text(encoding="utf-8").splitlines()
lines = [
    f'$expectedSha256 = "{package_sha}"' if line.startswith("$expectedSha256 = ") else line
    for line in lines
]
path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY
}

write_apt_release() {
  cat <<EOF
Origin: SSHFling
Label: SSHFling
Suite: stable
Codename: stable
Architectures: all
Components: main
Description: SSHFling package repository
Date: $(date -u -d "@${build_epoch}" -R)
EOF
  apt_checksum_section "MD5Sum" md5sum Packages Packages.gz SHA256SUMS
  apt_checksum_section "SHA1" sha1sum Packages Packages.gz SHA256SUMS
  apt_checksum_section "SHA256" sha256sum Packages Packages.gz SHA256SUMS
}

sign_rpm_packages() {
  local rpm_path gpg_cmd
  local rpm_defines

  if ! command -v rpmsign >/dev/null 2>&1; then
    echo "rpmsign is required when repository signing is enabled." >&2
    exit 127
  fi

  gpg_cmd="$(command -v gpg)"
  rpm_defines=(
    --define "_signature gpg"
    --define "__gpg $gpg_cmd"
    --define "_gpg_name $repo_signing_key"
    --define "_gpg_digest_algo sha256"
  )
  if [[ -n "${SSHFLING_REPO_GPG_PASSPHRASE:-}" ]]; then
    if [[ -z "$gpg_pass_file" ]]; then
      gpg_pass_file="$(mktemp)"
      chmod 600 "$gpg_pass_file"
      printf '%s' "$SSHFLING_REPO_GPG_PASSPHRASE" >"$gpg_pass_file"
    fi
    rpm_defines+=(--define "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback --passphrase-file $gpg_pass_file")
  else
    rpm_defines+=(--define "_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback")
  fi

  while IFS= read -r -d '' rpm_path; do
    rpmsign "${rpm_defines[@]}" --addsign "$rpm_path"
  done < <(find "$public_dir/rpm" -maxdepth 1 -type f -name '*.rpm' -print0 | sort -z)
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
normalize_public_file_mtimes

setup_repo_signing

(
  cd "$public_dir/apt"
  dpkg-scanpackages . /dev/null > Packages
  gzip -9cn Packages > Packages.gz
  sha256sum -- *.deb > SHA256SUMS
  write_apt_release > Release
  if (( repo_signed )); then
    gpg_sign --clearsign -o InRelease Release
    gpg_sign --detach-sign --armor -o Release.gpg Release
  fi
)

if (( repo_signed )); then
  sign_rpm_packages
fi
createrepo_c \
  --revision "$build_epoch" \
  --set-timestamp-to-revision \
  --simple-md-filenames \
  --no-database \
  --workers 1 \
  "$public_dir/rpm"
(
  cd "$public_dir/rpm"
  sha256sum -- *.rpm > SHA256SUMS
)
if (( repo_signed )); then
  gpg_sign --detach-sign --armor -o "$public_dir/rpm/repodata/repomd.xml.asc" "$public_dir/rpm/repodata/repomd.xml"
fi

source_tar="$(basename "$(first_file "$public_dir/downloads" "sshfling-*.tar.gz")")"
source_sha="$(sha256sum "$public_dir/downloads/$source_tar" | awk '{print $1}')"
first_file "$public_dir/apt" "sshfling_*_all.deb" >/dev/null
first_file "$public_dir/rpm" "sshfling-*.rpm" >/dev/null
cat >"$public_dir/homebrew/sshfling.rb" <<RUBY
class Sshfling < Formula
  desc "Temporary SSH access broker and CLI"
  homepage "$base_url"
  url "$base_url/downloads/$source_tar"
  sha256 "$source_sha"
  license :cannot_represent

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
expected_repo_fingerprint="__REPO_GPG_FINGERPRINT__"
base_host="${base_url#http://}"
base_host="${base_host#https://}"
base_host="${base_host%%/*}"
action="${1:-install}"
mode="${2:-auto}"

case "$action" in
  install|uninstall) ;;
  auto|apt|rpm|dnf|yum|brew|homebrew)
    mode="$action"
    action="install"
    ;;
  *)
    echo "Usage: install.sh [install|uninstall] [auto|apt|rpm|dnf|yum|brew]" >&2
    echo "       install.sh [auto|apt|rpm|dnf|yum|brew]" >&2
    exit 2
    ;;
esac

normalize_fingerprint() {
  printf '%s' "${1:-}" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]'
}

fingerprint_key_file() {
  local key_file="$1"
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required to verify the SSHFling repository signing key fingerprint." >&2
    return 127
  fi
  gpg --batch --show-keys --with-colons "$key_file" | awk -F: '/^fpr:/ {print toupper($10); exit}'
}

verify_repo_key() {
  local key_file="$1"
  local expected actual

  expected="$(normalize_fingerprint "$expected_repo_fingerprint")"
  if [[ -z "$expected" ]]; then
    echo "This installer does not include a pinned repository signing key fingerprint." >&2
    return 2
  fi
  actual="$(fingerprint_key_file "$key_file")"
  if [[ -z "$actual" || "$actual" != "$expected" ]]; then
    echo "Repository signing key fingerprint mismatch." >&2
    echo "Expected: $expected" >&2
    echo "Actual:   ${actual:-UNKNOWN}" >&2
    return 2
  fi
}

install_apt() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "${base_url}/sshfling-repo.gpg" -o "$tmp/sshfling-repo.gpg" || {
    echo "This package site does not publish a repository signing key. Rebuild it with repository signing enabled for APT installs." >&2
    return 2
  }
  curl -fsSL "${base_url}/apt/InRelease" -o "$tmp/InRelease" || {
    echo "This package site does not publish signed APT metadata. Rebuild it with repository signing enabled for APT installs." >&2
    return 2
  }
  verify_repo_key "$tmp/sshfling-repo.gpg"
  sudo install -d -m 0755 /usr/share/keyrings
  sudo install -m 0644 "$tmp/sshfling-repo.gpg" /usr/share/keyrings/sshfling-repo.gpg
  printf 'deb [signed-by=/usr/share/keyrings/sshfling-repo.gpg] %s/apt ./\n' "$base_url" >"$tmp/sshfling.list"
  sudo install -m 0644 "$tmp/sshfling.list" /etc/apt/sources.list.d/sshfling.list
  sudo apt-get update
  sudo apt-get install -y sshfling
}

uninstall_apt() {
  if dpkg -s sshfling >/dev/null 2>&1; then
    sudo apt-get remove -y sshfling
  fi
  sudo rm -f \
    /etc/apt/sources.list.d/sshfling.list \
    /etc/apt/preferences.d/sshfling \
    /usr/share/keyrings/sshfling-repo.gpg
  sudo apt-get update || true
}

install_rpm() {
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  curl -fsSL "${base_url}/sshfling-repo.asc" -o "$tmp/sshfling-repo.asc" || {
    echo "This package site does not publish a repository signing key. Rebuild it with repository signing enabled for RPM installs." >&2
    return 2
  }
  curl -fsSL "${base_url}/rpm/repodata/repomd.xml.asc" -o "$tmp/repomd.xml.asc" || {
    echo "This package site does not publish signed RPM metadata. Rebuild it with repository signing enabled for RPM installs." >&2
    return 2
  }
  verify_repo_key "$tmp/sshfling-repo.asc"
  sudo install -d -m 0755 /etc/pki/rpm-gpg
  sudo install -m 0644 "$tmp/sshfling-repo.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
  cat >"$tmp/sshfling.repo" <<EOF
[sshfling]
name=SSHFling
baseurl=${base_url}/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
EOF
  sudo install -m 0644 "$tmp/sshfling.repo" /etc/yum.repos.d/sshfling.repo
  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y sshfling
  else
    sudo yum install -y sshfling
  fi
}

uninstall_rpm() {
  if command -v rpm >/dev/null 2>&1 && rpm -q sshfling >/dev/null 2>&1; then
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf --setopt=clean_requirements_on_remove=False remove -y sshfling
    else
      sudo yum remove -y sshfling
    fi
  fi
  sudo rm -f \
    /etc/yum.repos.d/sshfling.repo \
    /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
}

install_brew() {
  brew install "${base_url}/homebrew/sshfling.rb"
}

uninstall_brew() {
  if brew list --formula sshfling >/dev/null 2>&1; then
    brew uninstall sshfling
  fi
}

run_for_mode() {
  local selected="$1"
  case "$selected" in
    apt) "${action}_apt" ;;
    rpm|dnf|yum) "${action}_rpm" ;;
    brew|homebrew) "${action}_brew" ;;
    *)
      echo "Usage: install.sh [install|uninstall] [auto|apt|rpm|dnf|yum|brew]" >&2
      echo "       install.sh [auto|apt|rpm|dnf|yum|brew]" >&2
      exit 2
      ;;
  esac
}

case "$mode" in
  auto)
    if command -v apt-get >/dev/null 2>&1; then
      run_for_mode apt
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
      run_for_mode rpm
    elif command -v brew >/dev/null 2>&1; then
      run_for_mode brew
    else
      echo "No supported package manager found. Use ${base_url}/downloads/ directly." >&2
      exit 2
    fi
    ;;
  apt|rpm|dnf|yum|brew|homebrew) run_for_mode "$mode" ;;
  *) run_for_mode "$mode" ;;
esac
SH
sed -i "s#__BASE_URL__#$base_url#g" "$public_dir/install.sh"
sed -i "s#__REPO_GPG_FINGERPRINT__#$repo_signing_fingerprint#g" "$public_dir/install.sh"
chmod 0755 "$public_dir/install.sh"

pkg_name="$(basename "$(first_file "$public_dir/downloads" "sshfling-*.pkg")")"
pkg_sha="$(sha256sum "$public_dir/downloads/$pkg_name" | awk '{print $1}')"
cat >"$public_dir/macos/install-pkg.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
curl -fsSL "$base_url/downloads/$pkg_name" -o "\$tmp/$pkg_name"
(cd "\$tmp" && printf '%s  %s\n' "$pkg_sha" "$pkg_name" | shasum -a 256 -c -)
pkgutil --check-signature "\$tmp/$pkg_name" >/dev/null
xcrun stapler validate "\$tmp/$pkg_name" >/dev/null
spctl -a -vv -t install "\$tmp/$pkg_name" >/dev/null
sudo installer -pkg "\$tmp/$pkg_name" -target /
SH
chmod 0755 "$public_dir/macos/install-pkg.sh"

cat >"$public_dir/macos/uninstall-pkg.sh" <<SH
#!/usr/bin/env bash
set -euo pipefail

sudo rm -f /usr/local/bin/sshfling
sudo rm -rf /usr/local/share/sshfling
sudo pkgutil --forget "$pkg_identifier" >/dev/null 2>&1 || true

echo "Removed SSHFling package files."
echo "Left /etc/sshfling in place for local policy or CA material."
SH
chmod 0755 "$public_dir/macos/uninstall-pkg.sh"

msi_name="$(basename "$(first_file "$public_dir/downloads" "sshfling-*.msi")")"
msi_sha="$(sha256sum "$public_dir/downloads/$msi_name" | awk '{print $1}')"
cat >"$public_dir/windows/install.ps1" <<SH
\$ErrorActionPreference = "Stop"
\$installer = Join-Path \$env:TEMP "$msi_name"
Invoke-WebRequest -Uri "$base_url/downloads/$msi_name" -OutFile \$installer
\$expectedSha256 = "$msi_sha"
\$actualSha256 = (Get-FileHash -Algorithm SHA256 -Path \$installer).Hash.ToLowerInvariant()
if (\$actualSha256 -ne \$expectedSha256) {
  throw "SHA-256 mismatch for $msi_name"
}
\$signature = Get-AuthenticodeSignature -FilePath \$installer
if (\$signature.Status -ne "Valid") {
  throw "MSI Authenticode signature is not valid: \$(\$signature.Status)"
}
\$proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/i", \$installer, "/qn", "/norestart")
if (\$proc.ExitCode -notin @(0, 3010, 1641)) {
  throw "msiexec install failed with exit code \$(\$proc.ExitCode)"
}
SH

cat >"$public_dir/windows/uninstall.ps1" <<'SH'
$ErrorActionPreference = "Stop"

$uninstallRoots = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$products = Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
  Where-Object {
	    $_.DisplayName -eq "SSHFling" -and
	    $_.Publisher -eq "SSHFling Maintainers" -and
	    $_.DisplayVersion -eq "__VERSION__" -and
	    $_.WindowsInstaller -eq 1 -and
	    $_.URLInfoAbout -eq "https://github.com/GRWLX/sshfling"
	  }

if (-not $products) {
  Write-Output "SSHFling is not installed."
  exit 0
}

foreach ($product in $products) {
  $productCode = $product.PSChildName
  if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') {
    throw "Could not determine MSI product code for SSHFling."
  }
  $proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/x", $productCode, "/qn", "/norestart")
  if ($proc.ExitCode -notin @(0, 3010, 1605, 1614, 1641)) {
    throw "msiexec uninstall failed with exit code $($proc.ExitCode)"
  }
}

Write-Output "Removed SSHFling."
SH
sed -i "s#__VERSION__#$version#g" "$public_dir/windows/uninstall.ps1"

(
  cd "$public_dir/downloads"
  sha256sum -- * > SHA256SUMS
)

bash "$(dirname "${BASH_SOURCE[0]}")/build-community-manifests.sh" "$package_dist" "$public_dir" "$base_url" "$version" "$repository"
normalize_chocolatey_package

signed_repo_html=""
if (( repo_signed )); then
  signed_repo_html="$(cat <<HTML
  <p>Repository signing key fingerprint: <code>$repo_signing_fingerprint</code>. Verify this fingerprint against the approved release record before trusting keys downloaded from this site.</p>
  <h2>Signed APT Repository</h2>
  <pre><code>expected_fingerprint="$repo_signing_fingerprint"
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
curl -fsSL $base_url/sshfling-repo.gpg -o "\$tmp/sshfling-repo.gpg"
actual_fingerprint="\$(gpg --batch --show-keys --with-colons "\$tmp/sshfling-repo.gpg" | awk -F: '/^fpr:/ {print toupper(\$10); exit}')"
test "\$actual_fingerprint" = "\$expected_fingerprint"
sudo install -d -m 0755 /usr/share/keyrings
sudo install -m 0644 "\$tmp/sshfling-repo.gpg" /usr/share/keyrings/sshfling-repo.gpg
echo "deb [signed-by=/usr/share/keyrings/sshfling-repo.gpg] $base_url/apt ./" | sudo tee /etc/apt/sources.list.d/sshfling.list
sudo apt update
sudo apt install -y sshfling</code></pre>
  <h2>Signed RPM Repository</h2>
  <pre><code>expected_fingerprint="$repo_signing_fingerprint"
tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT
curl -fsSL $base_url/sshfling-repo.asc -o "\$tmp/sshfling-repo.asc"
actual_fingerprint="\$(gpg --batch --show-keys --with-colons "\$tmp/sshfling-repo.asc" | awk -F: '/^fpr:/ {print toupper(\$10); exit}')"
test "\$actual_fingerprint" = "\$expected_fingerprint"
sudo install -d -m 0755 /etc/pki/rpm-gpg
sudo install -m 0644 "\$tmp/sshfling-repo.asc" /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
sudo tee /etc/yum.repos.d/sshfling.repo &gt;/dev/null &lt;&lt;'EOF'
[sshfling]
name=SSHFling
baseurl=$base_url/rpm
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling
EOF
sudo dnf install -y sshfling</code></pre>
HTML
)"
else
  signed_repo_html="$(cat <<'HTML'
  <h2>Linux Repositories</h2>
  <p>This package site was built without signed APT/RPM repository metadata. Use the direct package installer above, or rebuild the package site with a repository signing key for fleet repository registration.</p>
HTML
)"
fi

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
  <p>SSHFling is proprietary commercial software. Installing, running, or redistributing these packages requires the rights described in the project LICENSE or a separate written agreement from GRWLX.</p>
$signed_repo_html
  <h2>Convenience Linux Installer</h2>
  <p>The saved installer script uses the signed APT/RPM repository paths above when repository signing is enabled. Enterprise fleets should prefer the explicit signed repository commands and treat mutable installer scripts as convenience wrappers.</p>
  <pre><code>tmp="\$(mktemp -d)"
curl -fsSL $base_url/install.sh -o "\$tmp/install.sh"
bash "\$tmp/install.sh" apt
bash "\$tmp/install.sh" dnf</code></pre>
  <p>Uninstall with the host package manager rather than downloading a fresh mutable helper script. These commands remove SSHFling package and repository trust files only; they preserve host SSH configuration, grant state, CA material, local policy, Python, OpenSSH, account-management tools, process tools, and util-linux.</p>
  <pre><code>sudo apt-get remove -y sshfling
sudo rm -f /etc/apt/sources.list.d/sshfling.list /etc/apt/preferences.d/sshfling /usr/share/keyrings/sshfling-repo.gpg
sudo apt-get update || true

sudo dnf --setopt=clean_requirements_on_remove=False remove -y sshfling
sudo rm -f /etc/yum.repos.d/sshfling.repo /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling

sudo yum remove -y sshfling
sudo rm -f /etc/yum.repos.d/sshfling.repo /etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling</code></pre>
  <h2>Homebrew</h2>
  <pre><code>brew install $base_url/homebrew/sshfling.rb</code></pre>
  <p>Uninstall:</p>
  <pre><code>brew uninstall sshfling</code></pre>
  <h2>macOS pkg</h2>
  <p>Enterprise macOS distribution should use signed and notarized packages. This helper is a convenience wrapper around the published package artifact.</p>
  <pre><code>tmp="\$(mktemp -d)"
curl -fsSL $base_url/macos/install-pkg.sh -o "\$tmp/install-pkg.sh"
sudo bash "\$tmp/install-pkg.sh"</code></pre>
  <p>Uninstall:</p>
  <pre><code>sudo rm -f /usr/local/bin/sshfling
sudo rm -rf /usr/local/share/sshfling
sudo pkgutil --forget $pkg_identifier >/dev/null 2>&amp;1 || true</code></pre>
  <p>The macOS uninstall commands preserve /etc/sshfling, host SSH configuration, CA material, grant state, Python, and OpenSSH for separate fleet policy.</p>
  <h2>Windows MSI</h2>
  <p>Enterprise Windows distribution should use Authenticode-signed installers and verify signatures before deployment. This helper is a convenience wrapper around the published MSI artifact.</p>
  <pre><code>\$installer = Join-Path \$env:TEMP "sshfling-install.ps1"
Invoke-WebRequest -Uri "$base_url/windows/install.ps1" -OutFile \$installer
&amp; \$installer</code></pre>
  <p>Uninstall:</p>
  <pre><code>\$uninstallRoots = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
\$products = Get-ItemProperty -Path \$uninstallRoots -ErrorAction SilentlyContinue |
  Where-Object {
	    \$_.DisplayName -eq "SSHFling" -and
	    \$_.Publisher -eq "SSHFling Maintainers" -and
	    \$_.DisplayVersion -eq "$version" -and
	    \$_.WindowsInstaller -eq 1 -and
	    \$_.URLInfoAbout -eq "https://github.com/GRWLX/sshfling"
	  }
foreach (\$product in \$products) {
  \$productCode = \$product.PSChildName
  if (\$productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { throw "Could not determine MSI product code for SSHFling." }
  \$proc = Start-Process msiexec.exe -Wait -PassThru -ArgumentList @("/x", \$productCode, "/qn", "/norestart")
  if (\$proc.ExitCode -notin @(0, 3010, 1605, 1614, 1641)) { throw "msiexec uninstall failed with exit code \$(\$proc.ExitCode)" }
}</code></pre>
  <p>MSI uninstall removes installer-managed files and PATH state only. Python, OpenSSH, Windows OpenSSH Server, host SSH configuration, CA material, grant state, and external policy remain under fleet ownership.</p>
  <h2>More ecosystems</h2>
  <p>Arch/AUR, Alpine, FreeBSD, OpenBSD, pkgsrc, Nix, Guix, Void, Gentoo, Slackware, openSUSE OBS, Snapcraft, Termux, AppImage, Scoop, winget, and Chocolatey manifests are under <a href="$base_url/community.html">community package manifests</a>.</p>
  <h2>Downloads</h2>
  <p>Raw packages and checksums are under <a href="$base_url/downloads/">downloads</a>.</p>
</body>
</html>
HTML

normalize_public_tree_timestamps
