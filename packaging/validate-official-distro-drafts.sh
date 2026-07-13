#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required to validate official distro packaging drafts." >&2
    exit 127
  fi
}

cleanup_outputs() {
  (
    cd "$repo_root"
    debian/rules clean >/dev/null 2>&1 || true
    rm -rf build/fedora-draft-validation
    rm -f \
      "../sshfling_${version}-1_all.deb" \
      "../sshfling_${version}-1_amd64.buildinfo" \
      "../sshfling_${version}-1_amd64.changes"
    find . -type d -name __pycache__ -prune -exec rm -rf {} +
  )
}

trap cleanup_outputs EXIT

require_command dpkg-buildpackage
require_command dpkg-checkbuilddeps
require_command rpmbuild
require_command rpmspec

cd "$repo_root"

python3 tools/official_distro_readiness.py --check

sh -n \
  debian/sshfling.postinst \
  debian/sshfling.prerm \
  debian/sshfling.postrm \
  debian/tests/smoke

dpkg-checkbuilddeps
dpkg-buildpackage -us -uc -b
test -s "../sshfling_${version}-1_all.deb"
dpkg-deb -I "../sshfling_${version}-1_all.deb" >/dev/null
dpkg-deb -c "../sshfling_${version}-1_all.deb" >/dev/null

fedora_topdir="$repo_root/build/fedora-draft-validation"
install -d \
  "$fedora_topdir/BUILD" \
  "$fedora_topdir/BUILDROOT" \
  "$fedora_topdir/RPMS" \
  "$fedora_topdir/SOURCES" \
  "$fedora_topdir/SPECS" \
  "$fedora_topdir/SRPMS"

git -C "$repo_root" archive \
  --format=tar.gz \
  --prefix="sshfling-$version/" \
  HEAD >"$fedora_topdir/SOURCES/sshfling-$version.tar.gz"

rpmspec -P packaging/fedora/sshfling.spec >"$fedora_topdir/sshfling.spec.expanded"
if grep -Eq '%\{|systemd_|_unitdir' "$fedora_topdir/sshfling.spec.expanded"; then
  echo "Fedora spec expansion left unresolved macros." >&2
  exit 1
fi

rpmbuild --nodeps --define "_topdir $fedora_topdir" -ba packaging/fedora/sshfling.spec
test -s "$fedora_topdir/SRPMS/sshfling-$version-1.src.rpm"
test -s "$fedora_topdir/RPMS/noarch/sshfling-$version-1.noarch.rpm"
rpm -qip "$fedora_topdir/RPMS/noarch/sshfling-$version-1.noarch.rpm" >/dev/null
rpm -qlp "$fedora_topdir/RPMS/noarch/sshfling-$version-1.noarch.rpm" >/dev/null

echo "official distro draft validation ok: $version"
