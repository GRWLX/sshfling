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

create_source_tarball() {
  local destination="$1"
  local tmpdir
  tmpdir="$(mktemp -d)"
  (
    set -euo pipefail
    trap 'rm -rf "$tmpdir"' EXIT
    mkdir -p "$tmpdir/sshfling-$version"
    tar \
      --exclude='./.git' \
      --exclude='./build' \
      --exclude='./dist' \
      --exclude='./debian/.debhelper' \
      --exclude='./debian/sshfling' \
      --exclude='./debian/debhelper-build-stamp' \
      --exclude='./debian/files' \
      --exclude='./debian/*.debhelper' \
      --exclude='./debian/*.substvars' \
      -cf - . \
      | tar -C "$tmpdir/sshfling-$version" --strip-components=1 -xf -
    tar -C "$tmpdir" -czf "$destination" "sshfling-$version"
  )
}

cleanup_outputs() {
  (
    cd "$repo_root"
    debian/rules clean >/dev/null 2>&1 || true
    rm -rf build/fedora-draft-validation
    rm -rf build/official-distro-draft-validation
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
require_command lintian
require_command rpmbuild
require_command rpmlint
require_command rpmspec
require_command tar

cd "$repo_root"
validation_dir="$repo_root/build/official-distro-draft-validation"
install -d "$validation_dir"

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
install -d "$validation_dir"
set +e
lintian --profile debian --pedantic "../sshfling_${version}-1_amd64.changes" >"$validation_dir/lintian.log" 2>&1
lintian_status=$?
set -e
python3 tools/validate_official_distro_lint.py lintian \
  "$validation_dir/lintian.log" \
  --exit-code "$lintian_status"

if [ -n "${SSHFLING_AUTOPKGTEST_BACKEND:-}" ]; then
  require_command autopkgtest
  read -r -a autopkgtest_backend <<<"$SSHFLING_AUTOPKGTEST_BACKEND"
  set +e
  autopkgtest \
    --summary-file "$validation_dir/autopkgtest.summary" \
    --log-file "$validation_dir/autopkgtest.log" \
    "../sshfling_${version}-1_all.deb" \
    -- "${autopkgtest_backend[@]}"
  autopkgtest_status=$?
  set -e
  python3 tools/validate_official_distro_lint.py autopkgtest \
    "$validation_dir/autopkgtest.summary" \
    --exit-code "$autopkgtest_status"
fi

fedora_topdir="$repo_root/build/fedora-draft-validation"
install -d \
  "$fedora_topdir/BUILD" \
  "$fedora_topdir/BUILDROOT" \
  "$fedora_topdir/RPMS" \
  "$fedora_topdir/SOURCES" \
  "$fedora_topdir/SPECS" \
  "$fedora_topdir/SRPMS"

create_source_tarball "$fedora_topdir/SOURCES/sshfling-$version.tar.gz"

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
rpmlint \
  -c packaging/fedora/rpmlint.toml \
  "$fedora_topdir/SRPMS/sshfling-$version-1.src.rpm" \
  "$fedora_topdir/RPMS/noarch/sshfling-$version-1.noarch.rpm"

echo "official distro draft validation ok: $version"
