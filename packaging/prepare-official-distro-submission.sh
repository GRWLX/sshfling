#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
debian_revision="${SSHFLING_DEBIAN_REVISION:-1}"
debian_version="${version}-${debian_revision}"
rpm_release="${SSHFLING_RPM_RELEASE:-1}"
maintainer="GRWLX <44076838+GRWLX@users.noreply.github.com>"
output_dir="${SSHFLING_OFFICIAL_SUBMISSION_DIR:-$repo_root/build/official-distro-submission}"

usage() {
  cat <<USAGE
Usage: SSHFLING_VERSION=$version packaging/prepare-official-distro-submission.sh

Build a local official-distro submission packet under:
  $output_dir

Environment:
  SSHFLING_VERSION                 Version to prepare. Defaults to packaging source version.
  SSHFLING_DEBIAN_REVISION         Debian revision. Defaults to 1.
  SSHFLING_RPM_RELEASE             Fedora RPM release. Defaults to 1.
  SSHFLING_OFFICIAL_SUBMISSION_DIR Output directory.
  SSHFLING_ALLOW_DIRTY             Set to 1 to allow a dirty worktree.
  SSHFLING_RUN_MOCK                Set to 1 to run mock against the Fedora SRPM.
  SSHFLING_RUN_FEDORA_REVIEW       Set to 1 to run fedora-review against the Fedora SRPM.
USAGE
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "$command_name is required to prepare official distro submission artifacts." >&2
    exit 127
  fi
}

require_clean_worktree() {
  if [ "${SSHFLING_ALLOW_DIRTY:-}" = "1" ]; then
    return
  fi
  if [ -n "$(git -C "$repo_root" status --porcelain)" ]; then
    echo "Refusing to prepare official submission artifacts from a dirty worktree." >&2
    echo "Commit or stash changes, or set SSHFLING_ALLOW_DIRTY=1 for a local rehearsal." >&2
    exit 1
  fi
}

copy_source_tree() {
  local destination="$1"
  local include_debian="$2"
  local exclude_debian=()
  if [ "$include_debian" != "1" ]; then
    exclude_debian=(--exclude='./debian')
  fi

  mkdir -p "$destination"
  (
    cd "$repo_root"
    tar \
      --exclude='./.git' \
      --exclude='./.codex' \
      --exclude='./.codex-*' \
      --exclude='./.env' \
      --exclude='./.env.*' \
      --exclude='./build' \
      --exclude='./dist' \
      --exclude='./public' \
      --exclude='./package-dist' \
      --exclude='./release-dist' \
      --exclude='./docs/release/enterprise-release-evidence' \
      --exclude='./packaging/dotnet/*/bin' \
      --exclude='./packaging/dotnet/*/obj' \
      --exclude='./packaging/java/gradle/wrapper/gradle-wrapper.jar' \
      --exclude='./packaging/java/*/target' \
      --exclude='./node_modules' \
      --exclude='./TODO.txt' \
      --exclude='./security_best_practices_report.md' \
      --exclude='*/__pycache__' \
      "${exclude_debian[@]}" \
      -cf - .
  ) | tar -C "$destination" --strip-components=1 -xf -
}

write_hash_manifest() {
  (
    cd "$output_dir"
    find . -type f \
      ! -name SHA256SUMS \
      ! -path './work/*' \
      -print0 \
      | sort -z \
      | xargs -0 sha256sum
  ) >"$output_dir/SHA256SUMS"
}

write_debian_request_text() {
  local debian_dir="$1"
  local source_changes="$2"
  local source_changes_name
  source_changes_name="$(basename "$source_changes")"

  cat >"$debian_dir/ITP.txt" <<ITP
Package: wnpp
Severity: wishlist
Owner: $maintainer
X-Debbugs-Cc: debian-devel@lists.debian.org

* Package name    : sshfling
  Version         : $version
  Upstream Author : GRWLX
* URL             : https://github.com/GRWLX/sshfling
* License         : Apache-2.0
  Programming Lang: Python, shell
  Description     : temporary SSH access broker and CLI

SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout.

This package is intended for the admin section.
ITP

  cat >"$debian_dir/RFS.txt" <<RFS
Package: sponsorship-requests
Severity: wishlist

Dear mentors,

I am looking for a sponsor for my package "sshfling":

 * Package name     : sshfling
   Version          : $debian_version
   Upstream contact : GRWLX <44076838+GRWLX@users.noreply.github.com>
 * URL              : https://github.com/GRWLX/sshfling
 * License          : Apache-2.0
 * Vcs              : https://github.com/GRWLX/sshfling.git
   Section          : admin

The source builds the following binary package:

  sshfling - temporary SSH access broker and CLI

To access further information about this package, please visit the following URL:

  https://github.com/GRWLX/sshfling

The package can be built with:

  dget -x <MENTORS_DSC_URL>

Changes for the initial upload:

 sshfling ($debian_version) unstable; urgency=medium
 .
   * Initial release. (Closes: #ITP_BUG_NUMBER)

Regards,
GRWLX
RFS

  cat >"$debian_dir/dput.cf.example" <<DPUT
[mentors]
fqdn = mentors.debian.net
incoming = /upload
method = https
allow_unsigned_uploads = 0
progress_indicator = 2
allowed_distributions = .*
DPUT

  cat >"$debian_dir/upload-commands.txt" <<UPLOAD
# Sign on the maintainer machine after reviewing all artifacts:
debsign $source_changes_name

# Upload to mentors.debian.net after configuring ~/.dput.cf:
dput mentors $source_changes_name

# Then replace #ITP_BUG_NUMBER in RFS.txt and submit the RFS bug.
UPLOAD
}

write_fedora_request_text() {
  local fedora_dir="$1"
  local srpm="$2"
  local spec="$3"
  local srpm_name spec_name
  srpm_name="$(basename "$srpm")"
  spec_name="$(basename "$spec")"

  cat >"$fedora_dir/package-review.md" <<FEDORA
# Fedora Package Review Draft: sshfling

Package: sshfling
Version: $version
License: Apache-2.0
URL: https://github.com/GRWLX/sshfling
Summary: Temporary SSH access broker and CLI

## Review Request Fields

- Spec URL: <PUBLIC_URL_TO_$spec_name>
- SRPM URL: <PUBLIC_URL_TO_$srpm_name>
- Description: SSHFling grants short-lived SSH access with default password
  grants, optional OpenSSH user certificates, and a forced session wrapper so
  temporary SSH sessions are capped by a server-side wall-clock timeout.
- Koji scratch build: <KOJI_SCRATCH_BUILD_URL>
- rpmlint: see rpmlint-source.log in this packet.
- mock: run the command in mock-command.txt and attach the result.
- fedora-review: run the command in fedora-review-command.txt and attach the result.

## EPEL Follow-up

Request EPEL branches only after Fedora package review and Fedora dist-git
import are accepted, unless a Fedora/EPEL sponsor requests an EPEL-only path.
FEDORA

  cat >"$fedora_dir/mock-command.txt" <<MOCK
mock -r fedora-rawhide-x86_64 --rebuild $srpm_name
MOCK

  cat >"$fedora_dir/fedora-review-command.txt" <<REVIEW
fedora-review -n sshfling --rpm-spec $spec_name --srpm $srpm_name
REVIEW
}

require_command dpkg-buildpackage
require_command lintian
require_command rpmbuild
require_command rpmlint
require_command rpmspec
require_command sha256sum
require_command tar

require_clean_worktree

cd "$repo_root"
python3 tools/official_distro_readiness.py --check --fail-on-blocked

rm -rf "$output_dir"
install -d "$output_dir/debian" "$output_dir/fedora" "$output_dir/work"

debian_parent="$output_dir/work/debian"
debian_source_dir="$debian_parent/sshfling-$version"
orig_stage="$output_dir/work/orig/sshfling-$version"
install -d "$debian_source_dir" "$orig_stage"
copy_source_tree "$debian_source_dir" 1
copy_source_tree "$orig_stage" 0
tar -C "$output_dir/work/orig" -czf "$debian_parent/sshfling_${version}.orig.tar.gz" "sshfling-$version"

(
  cd "$debian_source_dir"
  dpkg-buildpackage -S -us -uc
)

cp "$debian_parent"/sshfling_"$version".orig.tar.gz "$output_dir/debian/"
cp "$debian_parent"/sshfling_"$debian_version".debian.tar.* "$output_dir/debian/"
cp "$debian_parent"/sshfling_"$debian_version".dsc "$output_dir/debian/"
cp "$debian_parent"/sshfling_"$debian_version"_source.buildinfo "$output_dir/debian/"
cp "$debian_parent"/sshfling_"$debian_version"_source.changes "$output_dir/debian/"

debian_changes="$output_dir/debian/sshfling_${debian_version}_source.changes"
set +e
lintian --profile debian --pedantic "$debian_changes" >"$output_dir/debian/lintian-source.log" 2>&1
lintian_status=$?
set -e
if grep -Eq '^E:' "$output_dir/debian/lintian-source.log"; then
  cat "$output_dir/debian/lintian-source.log" >&2
  exit 1
fi
if [ "$lintian_status" -ne 0 ]; then
  echo "lintian reported source-package review warnings; keeping log as packet evidence." >&2
fi
write_debian_request_text "$output_dir/debian" "$debian_changes"

fedora_topdir="$output_dir/work/fedora-rpmbuild"
install -d "$fedora_topdir/BUILD" "$fedora_topdir/BUILDROOT" "$fedora_topdir/RPMS" "$fedora_topdir/SOURCES" "$fedora_topdir/SPECS" "$fedora_topdir/SRPMS"
fedora_source_stage="$output_dir/work/fedora-source/sshfling-$version"
install -d "$fedora_source_stage"
copy_source_tree "$fedora_source_stage" 1
tar -C "$output_dir/work/fedora-source" -czf "$fedora_topdir/SOURCES/sshfling-$version.tar.gz" "sshfling-$version"
cp packaging/fedora/sshfling.spec "$output_dir/fedora/sshfling.spec"
rpmspec -P "$output_dir/fedora/sshfling.spec" >"$output_dir/fedora/sshfling.spec.expanded"
rpmbuild --nodeps --define "_topdir $fedora_topdir" -bs "$output_dir/fedora/sshfling.spec"
cp "$fedora_topdir/SOURCES/sshfling-$version.tar.gz" "$output_dir/fedora/"
cp "$fedora_topdir/SRPMS/sshfling-$version-${rpm_release}.src.rpm" "$output_dir/fedora/"

fedora_srpm="$output_dir/fedora/sshfling-$version-${rpm_release}.src.rpm"
set +e
rpmlint -c packaging/fedora/rpmlint.toml "$fedora_srpm" >"$output_dir/fedora/rpmlint-source.log" 2>&1
rpmlint_status=$?
set -e
if [ "$rpmlint_status" -ne 0 ]; then
  cat "$output_dir/fedora/rpmlint-source.log" >&2
  exit "$rpmlint_status"
fi
write_fedora_request_text "$output_dir/fedora" "$fedora_srpm" "$output_dir/fedora/sshfling.spec"

if [ "${SSHFLING_RUN_MOCK:-}" = "1" ]; then
  require_command mock
  (cd "$output_dir/fedora" && mock -r fedora-rawhide-x86_64 --rebuild "$(basename "$fedora_srpm")") \
    >"$output_dir/fedora/mock.log" 2>&1
fi

if [ "${SSHFLING_RUN_FEDORA_REVIEW:-}" = "1" ]; then
  require_command fedora-review
  (
    cd "$output_dir/fedora"
    fedora-review -n sshfling --rpm-spec sshfling.spec --srpm "$(basename "$fedora_srpm")"
  ) >"$output_dir/fedora/fedora-review.log" 2>&1
fi

cat >"$output_dir/README.md" <<README
# SSHFling Official Distro Submission Packet

Version: $version
Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
Source commit: $(git -C "$repo_root" rev-parse HEAD)

## Debian/Ubuntu

- debian/sshfling_${debian_version}.dsc
- debian/sshfling_${version}.orig.tar.gz
- debian/sshfling_${debian_version}.debian.tar.*
- debian/sshfling_${debian_version}_source.changes
- debian/lintian-source.log
- debian/ITP.txt
- debian/RFS.txt
- debian/dput.cf.example
- debian/upload-commands.txt

Sign the source changes file on the maintainer machine, upload it to
mentors.debian.net, file the WNPP/ITP bug, then file the RFS bug after the
mentors package page is available.

## Fedora/EPEL

- fedora/sshfling.spec
- fedora/sshfling.spec.expanded
- fedora/sshfling-$version-${rpm_release}.src.rpm
- fedora/sshfling-$version.tar.gz
- fedora/rpmlint-source.log
- fedora/package-review.md
- fedora/mock-command.txt
- fedora/fedora-review-command.txt

Attach or publish the spec and SRPM for Fedora package review. Request EPEL
branches only after Fedora acceptance unless a Fedora/EPEL sponsor asks for an
EPEL-only review path.
README

write_hash_manifest

rm -rf "$output_dir/work"
echo "official distro submission packet ready: $output_dir"
