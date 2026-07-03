#!/usr/bin/env bash
set -euo pipefail

version="${FLING_VERSION:-0.1.0}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
topdir="$repo_root/build/rpm"
payload="$topdir/payload"

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "rpmbuild is required to build an RPM package." >&2
  exit 127
fi

rm -rf "$topdir"
install -d "$topdir/BUILD" "$topdir/RPMS" "$topdir/SOURCES" "$topdir/SPECS" "$topdir/SRPMS"
install -d "$payload/etc/fling" "$payload/usr/bin" "$payload/usr/share/fling/templates" "$payload/usr/share/doc/fling" "$payload/usr/lib/systemd/system"

install -m 0755 "$repo_root/bin/fling" "$payload/usr/bin/fling"
install -m 0644 "$repo_root/packaging/policy.json" "$payload/etc/fling/policy.json"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_fling_templates "$repo_root" "$payload/usr/share/fling/templates"
install -m 0644 "$repo_root/README.md" "$payload/usr/share/doc/fling/README.md"
install -m 0644 "$repo_root/LICENSE" "$payload/usr/share/doc/fling/LICENSE"
install -m 0644 "$repo_root/systemd/flingd.env.example" "$payload/usr/share/doc/fling/flingd.env.example"
install -m 0644 "$repo_root/systemd/flingd.service" "$payload/usr/lib/systemd/system/flingd.service"

tar -C "$payload" -czf "$topdir/SOURCES/fling-files-${version}.tar.gz" .

cat >"$topdir/SPECS/fling.spec" <<SPEC
Name: fling
Version: $version
Release: 1%{?dist}
Summary: Temporary SSH certificate issuer and access CLI
License: Apache-2.0
BuildArch: noarch
Requires: python3
Requires: openssh-clients
Requires: procps-ng
Requires: util-linux
Source0: fling-files-${version}.tar.gz

%description
Fling issues short-lived OpenSSH user certificates and installs a forced
session wrapper so temporary SSH sessions are capped by a server-side
wall-clock timeout. Docker Compose files are included as a test harness.

%prep

%build

%install
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%config(noreplace) /etc/fling/policy.json
%attr(0755,root,root) /usr/bin/fling
/usr/share/fling/templates
/usr/share/doc/fling/README.md
/usr/share/doc/fling/LICENSE
/usr/share/doc/fling/flingd.env.example
/usr/lib/systemd/system/flingd.service

%changelog
* Fri Jul 03 2026 Fling Maintainers <root@localhost> - ${version}-1
- Initial package
SPEC

rpmbuild --define "_topdir $topdir" -bb "$topdir/SPECS/fling.spec"

install -d "$dist_dir"
find "$topdir/RPMS" -type f -name "fling-${version}-*.rpm" -exec cp {} "$dist_dir/" \;
find "$dist_dir" -type f -name "fling-${version}-*.rpm" -print
