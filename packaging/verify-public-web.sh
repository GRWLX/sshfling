#!/usr/bin/env bash
set -euo pipefail

public_dir="${1:-public}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(validate_sshfling_version "${VERSION:?VERSION is required}")"
repository="${REPOSITORY:?REPOSITORY is required}"
owner="${OWNER:-${repository%%/*}}"
require_repo_signatures="${REQUIRE_REPO_SIGNATURES:-}"

missing=0

require_file() {
  local path="$1"
  if [[ ! -f "$public_dir/$path" ]]; then
    echo "missing: $path" >&2
    missing=1
  fi
}

require_executable() {
  local path="$1"
  require_file "$path"
  if [[ -f "$public_dir/$path" && ! -x "$public_dir/$path" ]]; then
    echo "not executable: $path" >&2
    missing=1
  fi
}

require_dir() {
  local path="$1"
  if [[ ! -d "$public_dir/$path" ]]; then
    echo "missing directory: $path" >&2
    missing=1
  fi
}

require_contains() {
  local path="$1"
  local pattern="$2"
  require_file "$path"
  if [[ -f "$public_dir/$path" ]] && ! grep -q -- "$pattern" "$public_dir/$path"; then
    echo "missing pattern in $path: $pattern" >&2
    missing=1
  fi
}

require_not_contains() {
  local path="$1"
  local pattern="$2"
  require_file "$path"
  if [[ -f "$public_dir/$path" ]] && grep -q -- "$pattern" "$public_dir/$path"; then
    echo "forbidden pattern in $path: $pattern" >&2
    missing=1
  fi
}

require_tree_not_contains() {
  local pattern="$1"
  local matches

  matches="$(grep -R -I -n -F -- "$pattern" "$public_dir" || true)"
  if [[ -n "$matches" ]]; then
    echo "forbidden pattern in public package site: $pattern" >&2
    printf '%s\n' "$matches" >&2
    missing=1
  fi
}

require_gzip_contains() {
  local path="$1"
  local pattern="$2"
  require_file "$path"
  if [[ -f "$public_dir/$path" ]] && ! gunzip -c "$public_dir/$path" | grep -q -- "$pattern"; then
    echo "missing compressed pattern in $path: $pattern" >&2
    missing=1
  fi
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

verify_repo_fingerprint_file() {
  local expected actual key_actual

  require_file "sshfling-repo-fingerprint.txt"
  if [[ ! -f "$public_dir/sshfling-repo-fingerprint.txt" ]]; then
    return
  fi
  actual="$(normalize_gpg_fingerprint "$(cat "$public_dir/sshfling-repo-fingerprint.txt")")"
  if [[ ! "$actual" =~ ^[A-F0-9]{40,64}$ ]]; then
    echo "invalid repository signing fingerprint: ${actual:-EMPTY}" >&2
    missing=1
    return
  fi
  expected="$(normalize_gpg_fingerprint "${SSHFLING_REPO_GPG_FINGERPRINT:-}")"
  if [[ -n "$expected" && "$actual" != "$expected" ]]; then
    echo "repository signing fingerprint mismatch: expected $expected, found $actual" >&2
    missing=1
  fi
  if command -v gpg >/dev/null 2>&1 && [[ -f "$public_dir/sshfling-repo.asc" ]]; then
    key_actual="$(gpg --batch --show-keys --with-colons "$public_dir/sshfling-repo.asc" | awk -F: '/^fpr:/ {print toupper($10); exit}')"
    if [[ "$key_actual" != "$actual" ]]; then
      echo "repository signing key fingerprint does not match sshfling-repo-fingerprint.txt" >&2
      echo "key:  ${key_actual:-UNKNOWN}" >&2
      echo "file: $actual" >&2
      missing=1
    fi
  fi
}

require_signed_repository() {
  require_file "sshfling-repo.gpg"
  require_file "sshfling-repo.asc"
  verify_repo_fingerprint_file
  require_file "apt/InRelease"
  require_file "apt/Release.gpg"
  require_file "rpm/repodata/repomd.xml.asc"
  require_contains "index.html" "signed-by=/usr/share/keyrings/sshfling-repo.gpg"
  require_contains "index.html" "repo_gpgcheck=1"
  require_contains "install.sh" "expected_repo_fingerprint="
  require_contains "install.sh" "verify_repo_key"
  require_contains "install.sh" "gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-sshfling"
}

require_file ".nojekyll"
require_file "index.html"
require_executable "install.sh"
require_file "community.html"
require_contains "install.sh" "signed-by=/usr/share/keyrings/sshfling-repo.gpg"
require_contains "install.sh" "repo_gpgcheck=1"
require_contains "install.sh" "verify_repo_key"

require_file "apt/Packages.gz"
require_file "apt/Packages"
require_file "apt/Release"
require_file "apt/SHA256SUMS"
require_file "apt/sshfling_${version}_all.deb"
require_file "rpm/sshfling-${version}-1.noarch.rpm"
require_file "rpm/repodata/repomd.xml"
require_file "rpm/SHA256SUMS"
require_file "homebrew/sshfling.rb"
require_file "macos/install-pkg.sh"
require_file "macos/uninstall-pkg.sh"
require_file "windows/install.ps1"
require_file "windows/uninstall.ps1"
require_contains "macos/install-pkg.sh" "shasum -a 256 -c -"
require_contains "windows/install.ps1" "Get-FileHash -Algorithm SHA256"
require_file "downloads/SHA256SUMS"
require_file "downloads/index.html"
require_file "downloads/sshfling-${version}.tar.gz"
require_file "downloads/sshfling-${version}.pkg"
require_file "downloads/sshfling-${version}.msi"
require_file "downloads/sshfling-${version}-windows.zip"

require_file "arch/PKGBUILD"
require_file "arch/.SRCINFO"
require_file "alpine/APKBUILD"
require_file "freebsd/security/sshfling/Makefile"
require_file "freebsd/security/sshfling/distinfo"
require_file "freebsd/security/sshfling/pkg-descr"
require_file "openbsd/security/sshfling/Makefile"
require_file "openbsd/security/sshfling/distinfo"
require_file "openbsd/security/sshfling/pkg/DESCR"
require_file "pkgsrc/security/sshfling/Makefile"
require_file "pkgsrc/security/sshfling/DESCR"
require_file "pkgsrc/security/sshfling/PLIST"
require_file "pkgsrc/security/sshfling/distinfo"
require_file "nix/flake.nix"
require_file "guix/sshfling.scm"
require_file "void/template"
require_file "gentoo/app-admin/sshfling/sshfling-${version}.ebuild"
require_file "slackware/sshfling.SlackBuild"
require_file "slackware/slack-desc"
require_file "opensuse/sshfling.spec"
require_file "snap/snapcraft.yaml"
require_file "termux/packages/sshfling/build.sh"
require_file "appimage/AppImageBuilder.yml"
require_file "scoop/sshfling.json"
require_dir "winget/manifests/g/${owner}/SSHFling/${version}"
require_file "winget/manifests/g/${owner}/SSHFling/${version}/${owner}.SSHFling.yaml"
require_file "winget/manifests/g/${owner}/SSHFling/${version}/${owner}.SSHFling.locale.en-US.yaml"
require_file "winget/manifests/g/${owner}/SSHFling/${version}/${owner}.SSHFling.installer.yaml"
require_file "chocolatey/sshfling.nuspec"
require_file "chocolatey/tools/chocolateyinstall.ps1"
require_file "chocolatey/sshfling.${version}.nupkg"
require_file "chocolatey/install.ps1"

require_contains "index.html" "SSHFling ${version} packages"
require_contains "index.html" "uninstall"
require_contains "index.html" "proprietary commercial software"
forbidden_patterns=(
  "trusted=""yes"
  "gpgcheck=""0"
  "repo_gpgcheck=""0"
  "--no-gpg-""checks"
  "--allow-un""trusted"
  "--no-check-""certificate"
  "curl -""k"
  "--in""secure"
)
for pattern in "${forbidden_patterns[@]}"; do
  require_tree_not_contains "$pattern"
done
require_contains "community.html" "FreeBSD"
require_contains "community.html" "OpenBSD"
require_contains "community.html" "pkgsrc"
require_contains "community.html" "proprietary commercial software"
require_gzip_contains "apt/Packages.gz" "Version: ${version}"

require_contains "homebrew/sshfling.rb" "license :cannot_represent"
require_contains "arch/PKGBUILD" "LicenseRef-SSHFling-Commercial"
require_contains "nix/flake.nix" "license = licenses.unfree;"
require_contains "snap/snapcraft.yaml" "license: Proprietary"
require_contains "scoop/sshfling.json" '"identifier": "Proprietary"'
require_contains "chocolatey/sshfling.nuspec" "<requireLicenseAcceptance>true</requireLicenseAcceptance>"
require_contains "winget/manifests/g/${owner}/SSHFling/${version}/${owner}.SSHFling.locale.en-US.yaml" "License: SSHFling Commercial License"

if [[ -f "$public_dir/sshfling-repo.gpg" || -f "$public_dir/sshfling-repo.asc" ]] || is_truthy "$require_repo_signatures"; then
  require_signed_repository
fi

if (( missing != 0 )); then
  echo "public package site verification failed" >&2
  exit 1
fi

echo "public package site includes all declared build targets"
