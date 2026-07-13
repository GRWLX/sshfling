#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
debian_revision="${SSHFLING_DEBIAN_REVISION:-1}"
debian_version="${version}-${debian_revision}"
rpm_release="${SSHFLING_RPM_RELEASE:-1}"
packet_dir="${1:-${SSHFLING_OFFICIAL_SUBMISSION_DIR:-$repo_root/build/official-distro-submission}}"

fail() {
  echo "official distro submission packet validation failed: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [ -s "$packet_dir/$path" ] || fail "missing file: $path"
}

require_contains() {
  local path="$1"
  local expected="$2"
  grep -Fq "$expected" "$packet_dir/$path" || fail "$path does not contain: $expected"
}

require_not_contains() {
  local path="$1"
  local forbidden="$2"
  if grep -Fq "$forbidden" "$packet_dir/$path"; then
    fail "$path contains forbidden text: $forbidden"
  fi
}

require_tar_not_contains() {
  local path="$1"
  local forbidden="$2"
  if tar -tzf "$packet_dir/$path" | grep -Fq "$forbidden"; then
    fail "$path contains forbidden member: $forbidden"
  fi
}

[ -d "$packet_dir" ] || fail "missing packet directory: $packet_dir"
[ ! -d "$packet_dir/work" ] || fail "temporary work directory was not removed"

require_file "README.md"
require_file "SHA256SUMS"

require_file "debian/sshfling_${version}.orig.tar.gz"
require_file "debian/sshfling_${debian_version}.debian.tar.xz"
require_file "debian/sshfling_${debian_version}.dsc"
require_file "debian/sshfling_${debian_version}_source.buildinfo"
require_file "debian/sshfling_${debian_version}_source.changes"
require_file "debian/lintian-source.log"
require_file "debian/ITP.txt"
require_file "debian/RFS.txt"
require_file "debian/dput.cf.example"
require_file "debian/upload-commands.txt"

require_file "fedora/sshfling.spec"
require_file "fedora/sshfling.spec.expanded"
require_file "fedora/sshfling-${version}.tar.gz"
require_file "fedora/sshfling-${version}-${rpm_release}.src.rpm"
require_file "fedora/rpmlint-source.log"
require_file "fedora/package-review.md"
require_file "fedora/mock-command.txt"
require_file "fedora/fedora-review-command.txt"

(
  cd "$packet_dir"
  sha256sum -c SHA256SUMS >/dev/null
)

require_contains "README.md" "Version: $version"
require_contains "README.md" "Source commit:"
require_contains "README.md" "Release tag: v$version"
require_contains "README.md" "Release tag status:"
if [ "${SSHFLING_REQUIRE_RELEASE_TAG:-}" = "1" ]; then
  require_contains "README.md" "Release tag status: matches source commit"
fi
require_contains "debian/ITP.txt" "Package: wnpp"
require_contains "debian/ITP.txt" "* License         : Apache-2.0"
require_contains "debian/RFS.txt" "Package: sponsorship-requests"
require_contains "debian/RFS.txt" "Version          : $debian_version"
require_contains "debian/RFS.txt" "#ITP_BUG_NUMBER"
require_contains "debian/dput.cf.example" "[mentors]"
require_contains "debian/upload-commands.txt" "debsign sshfling_${debian_version}_source.changes"
require_contains "debian/upload-commands.txt" "dput mentors sshfling_${debian_version}_source.changes"
require_contains "debian/sshfling_${debian_version}.dsc" "Source: sshfling"
require_contains "debian/sshfling_${debian_version}_source.changes" "Distribution: unstable"

require_contains "fedora/sshfling.spec" "License:        Apache-2.0"
require_contains "fedora/package-review.md" "Spec URL:"
require_contains "fedora/package-review.md" "SRPM URL:"
require_contains "fedora/package-review.md" "License: Apache-2.0"
require_contains "fedora/package-review.md" "Upstream source URL: https://github.com/GRWLX/sshfling/archive/refs/tags/v$version/sshfling-$version.tar.gz"
require_contains "fedora/mock-command.txt" "sshfling-${version}-${rpm_release}.src.rpm"
require_contains "fedora/fedora-review-command.txt" "sshfling-${version}-${rpm_release}.src.rpm"
require_contains "fedora/rpmlint-source.log" "0 errors, 0 warnings"

if grep -Eq '^E:' "$packet_dir/debian/lintian-source.log"; then
  fail "debian/lintian-source.log contains lintian errors"
fi
require_not_contains "debian/lintian-source.log" "build-depends-on-essential-package-without-using-version"
require_not_contains "debian/lintian-source.log" "file-without-copyright-information"
require_not_contains "debian/lintian-source.log" "source-contains-prebuilt-java-object"

require_tar_not_contains "debian/sshfling_${version}.orig.tar.gz" "sshfling-${version}/debian/"
require_tar_not_contains "debian/sshfling_${version}.orig.tar.gz" "packaging/java/gradle/wrapper/gradle-wrapper.jar"
require_tar_not_contains "fedora/sshfling-${version}.tar.gz" "packaging/java/gradle/wrapper/gradle-wrapper.jar"

echo "official distro submission packet validation ok: $packet_dir"
