#!/usr/bin/env bash
set -euo pipefail

public_dir="${1:-public}"
version="${VERSION:?VERSION is required}"
repository="${REPOSITORY:?REPOSITORY is required}"
owner="${OWNER:-${repository%%/*}}"

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

require_gzip_contains() {
  local path="$1"
  local pattern="$2"
  require_file "$path"
  if [[ -f "$public_dir/$path" ]] && ! gunzip -c "$public_dir/$path" | grep -q -- "$pattern"; then
    echo "missing compressed pattern in $path: $pattern" >&2
    missing=1
  fi
}

require_file ".nojekyll"
require_file "index.html"
require_executable "install.sh"
require_file "community.html"

require_file "apt/Packages.gz"
require_file "apt/sshfling_${version}_all.deb"
require_file "rpm/sshfling-${version}-1.noarch.rpm"
require_file "rpm/repodata/repomd.xml"
require_file "homebrew/sshfling.rb"
require_file "macos/install-pkg.sh"
require_file "windows/install.ps1"
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
require_contains "community.html" "FreeBSD"
require_contains "community.html" "OpenBSD"
require_contains "community.html" "pkgsrc"
require_gzip_contains "apt/Packages.gz" "Version: ${version}"

if (( missing != 0 )); then
  echo "public package site verification failed" >&2
  exit 1
fi

echo "public package site includes all declared build targets"
