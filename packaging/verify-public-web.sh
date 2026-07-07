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
verify_gpg_home=""

cleanup_verify() {
  if [[ -n "$verify_gpg_home" && -d "$verify_gpg_home" ]]; then
    if command -v gpgconf >/dev/null 2>&1; then
      GNUPGHOME="$verify_gpg_home" gpgconf --kill all >/dev/null 2>&1 || true
    fi
    rm -rf "$verify_gpg_home"
  fi
}
trap cleanup_verify EXIT

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

setup_verify_gpg() {
  if [[ -n "$verify_gpg_home" ]]; then
    return 0
  fi
  if ! command -v gpg >/dev/null 2>&1; then
    echo "gpg is required to verify signed repository metadata." >&2
    missing=1
    return 1
  fi

  verify_gpg_home="$(mktemp -d)"
  chmod 700 "$verify_gpg_home"
  if ! GNUPGHOME="$verify_gpg_home" gpg --batch --import "$public_dir/sshfling-repo.asc" >/dev/null 2>&1; then
    echo "could not import repository signing key for verification" >&2
    missing=1
    return 1
  fi
}

verify_gpg_signature() {
  local label="$1"
  shift

  if ! setup_verify_gpg; then
    return
  fi
  if ! GNUPGHOME="$verify_gpg_home" gpg --batch --verify "$@" >/dev/null 2>&1; then
    echo "invalid repository signature: $label" >&2
    missing=1
  fi
}

verify_rpm_package_signatures() {
  local expected_key_id
  local rpmdb_dir
  local rpm_path
  local sig_info

  if [[ ! -f "$public_dir/sshfling-repo.asc" ]]; then
    return
  fi
  if ! command -v rpm >/dev/null 2>&1; then
    echo "rpm is required to verify signed RPM packages." >&2
    missing=1
    return
  fi

  expected_key_id="$(normalize_gpg_fingerprint "$(cat "$public_dir/sshfling-repo-fingerprint.txt" 2>/dev/null || true)")"
  expected_key_id="${expected_key_id: -16}"
  rpmdb_dir="$(mktemp -d)"
  if ! rpm --define "_dbpath $rpmdb_dir" --import "$public_dir/sshfling-repo.asc" >/dev/null 2>&1; then
    echo "could not import repository signing key into temporary RPM database" >&2
    missing=1
    rm -rf "$rpmdb_dir"
    return
  fi

  while IFS= read -r -d '' rpm_path; do
    sig_info="$(rpm -qp --qf '%{SIGPGP:pgpsig}\n%{SIGGPG:pgpsig}\n%{RSAHEADER:pgpsig}\n%{DSAHEADER:pgpsig}\n' "$rpm_path" 2>/dev/null || true)"
    sig_info="$(printf '%s\n' "$sig_info" | tr '[:lower:]' '[:upper:]')"
    if [[ -z "$expected_key_id" ]] || ! printf '%s\n' "$sig_info" | grep -Fq "KEY ID $expected_key_id"; then
      echo "missing RPM package signature: ${rpm_path#"$public_dir/"}" >&2
      missing=1
    elif ! rpm --define "_dbpath $rpmdb_dir" --checksig "$rpm_path" >/dev/null 2>&1; then
      echo "invalid RPM package signature: ${rpm_path#"$public_dir/"}" >&2
      missing=1
    fi
  done < <(find "$public_dir/rpm" -maxdepth 1 -type f -name '*.rpm' -print0 | sort -z)

  rm -rf "$rpmdb_dir"
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
  if is_truthy "$require_repo_signatures" && [[ -z "$expected" ]]; then
    echo "REQUIRE_REPO_SIGNATURES requires SSHFLING_REPO_GPG_FINGERPRINT as the approved trust anchor." >&2
    missing=1
  fi
  if [[ -n "$expected" && "$actual" != "$expected" ]]; then
    echo "repository signing fingerprint mismatch: expected $expected, found $actual" >&2
    missing=1
  fi
  if command -v gpg >/dev/null 2>&1 && [[ -f "$public_dir/sshfling-repo.asc" ]]; then
    if setup_verify_gpg; then
      key_actual="$(
        GNUPGHOME="$verify_gpg_home" gpg --batch --show-keys --with-colons "$public_dir/sshfling-repo.asc" |
          awk -F: '/^fpr:/ {print toupper($10); exit}'
      )"
    fi
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
  require_not_contains "install.sh" 'expected_repo_fingerprint=""'
  if [[ -f "$public_dir/sshfling-repo.asc" ]]; then
    if [[ -f "$public_dir/apt/InRelease" ]]; then
      verify_gpg_signature "apt/InRelease" "$public_dir/apt/InRelease"
    fi
    if [[ -f "$public_dir/apt/Release.gpg" && -f "$public_dir/apt/Release" ]]; then
      verify_gpg_signature "apt/Release.gpg" "$public_dir/apt/Release.gpg" "$public_dir/apt/Release"
    fi
    if [[ -f "$public_dir/rpm/repodata/repomd.xml.asc" && -f "$public_dir/rpm/repodata/repomd.xml" ]]; then
      verify_gpg_signature "rpm/repodata/repomd.xml.asc" "$public_dir/rpm/repodata/repomd.xml.asc" "$public_dir/rpm/repodata/repomd.xml"
    fi
    verify_rpm_package_signatures
  fi
}

require_file ".nojekyll"
require_file "index.html"
require_executable "install.sh"
require_file "community.html"
require_contains "install.sh" "signed-by=/usr/share/keyrings/sshfling-repo.gpg"
require_contains "install.sh" "repo_gpgcheck=1"
require_contains "install.sh" "verify_repo_key"
require_contains "install.sh" "apt-get remove -y sshfling"
require_contains "install.sh" "dnf --setopt=clean_requirements_on_remove=False remove -y sshfling"
require_contains "install.sh" "yum remove -y sshfling"
require_contains "install.sh" "/usr/share/keyrings/sshfling-repo.gpg"
require_not_contains "install.sh" "dnf remove -y sshfling"
require_not_contains "install.sh" "autoremove"
require_not_contains "install.sh" "autopurge"
require_not_contains "install.sh" "apt-get purge"
require_not_contains "install.sh" "dnf autoremove"
require_not_contains "install.sh" "yum autoremove"

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
require_contains "index.html" "sudo apt-get remove -y sshfling"
require_contains "index.html" "/usr/share/keyrings/sshfling-repo.gpg"
require_contains "index.html" "sudo dnf --setopt=clean_requirements_on_remove=False remove -y sshfling"
require_contains "index.html" "sudo yum remove -y sshfling"
require_contains "index.html" "brew uninstall sshfling"
require_contains "index.html" "sudo pkgutil --forget io.sshfling.cli"
require_contains "index.html" "Start-Process msiexec.exe -Wait -ArgumentList"
require_contains "index.html" "preserve host SSH configuration"
require_contains "index.html" "Python, OpenSSH, account-management tools, process tools, and util-linux"
require_not_contains "index.html" "bash \"\$tmp/install.sh\" uninstall"
require_not_contains "index.html" "uninstall-pkg.sh"
require_not_contains "index.html" "windows/uninstall.ps1"
require_not_contains "index.html" "apt-get purge"
require_not_contains "index.html" "dnf remove -y sshfling"
require_not_contains "index.html" "autoremove"
require_not_contains "index.html" "autopurge"
forbidden_patterns=(
  "trusted=""yes"
  "gpgcheck=""0"
  "repo_gpgcheck=""0"
  "--no-gpg-""checks"
  "--allow-un""trusted"
  "--no-check-""certificate"
  "curl -""k"
  "--in""secure"
  "--ignore-check""sums"
  "--allow-empty-check""sums"
  "--no-""verify"
  "SkipPublisher""Check"
)
for pattern in "${forbidden_patterns[@]}"; do
  require_tree_not_contains "$pattern"
done
require_contains "community.html" "FreeBSD"
require_contains "community.html" "OpenBSD"
require_contains "community.html" "pkgsrc"
require_contains "community.html" "proprietary commercial software"
require_contains "community.html" "Dependency ownership remains with the target operating system"
require_contains "community.html" "Trust model: review the generated manifest"
require_gzip_contains "apt/Packages.gz" "Version: ${version}"

require_contains "homebrew/sshfling.rb" "license :cannot_represent"
require_contains "arch/PKGBUILD" "LicenseRef-SSHFling-Commercial"
require_contains "nix/flake.nix" "license = licenses.unfree;"
require_contains "snap/snapcraft.yaml" "license: Proprietary"
require_contains "scoop/sshfling.json" '"identifier": "Proprietary"'
require_contains "chocolatey/sshfling.nuspec" "<requireLicenseAcceptance>true</requireLicenseAcceptance>"
require_contains "winget/manifests/g/${owner}/SSHFling/${version}/${owner}.SSHFling.locale.en-US.yaml" "License: SSHFling Commercial License"
require_contains "chocolatey/install.ps1" "Get-FileHash -Algorithm SHA256"
require_contains "appimage/AppImageBuilder.yml" "deb https://archive.ubuntu.com/ubuntu/ noble main universe"
require_not_contains "appimage/AppImageBuilder.yml" "deb http://archive.ubuntu.com/ubuntu/"

if [[ -f "$public_dir/sshfling-repo.gpg" || -f "$public_dir/sshfling-repo.asc" ]] || is_truthy "$require_repo_signatures"; then
  require_signed_repository
fi

if (( missing != 0 )); then
  echo "public package site verification failed" >&2
  exit 1
fi

echo "public package site includes all declared build targets"
