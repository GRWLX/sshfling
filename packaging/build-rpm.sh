#!/usr/bin/env bash
set -euo pipefail

version="${SSHFLING_VERSION:-0.1.7}"
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
install -d "$payload/etc/sshfling" "$payload/usr/bin" "$payload/usr/share/sshfling/templates" "$payload/usr/share/doc/sshfling" "$payload/usr/lib/systemd/system"

install -m 0755 "$repo_root/bin/sshfling" "$payload/usr/bin/sshfling"
install -m 0644 "$repo_root/packaging/policy.json" "$payload/etc/sshfling/policy.json"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_sshfling_templates "$repo_root" "$payload/usr/share/sshfling/templates"
install -m 0644 "$repo_root/README.md" "$payload/usr/share/doc/sshfling/README.md"
install -m 0644 "$repo_root/LICENSE" "$payload/usr/share/doc/sshfling/LICENSE"
install -m 0644 "$repo_root/systemd/sshflingd.env.example" "$payload/usr/share/doc/sshfling/sshflingd.env.example"
install -m 0644 "$repo_root/systemd/sshflingd.service" "$payload/usr/lib/systemd/system/sshflingd.service"

tar -C "$payload" -czf "$topdir/SOURCES/sshfling-files-${version}.tar.gz" .

cat >"$topdir/SPECS/sshfling.spec" <<SPEC
Name: sshfling
Version: $version
Release: 1%{?dist}
Summary: Temporary SSH certificate issuer and access CLI
License: Apache-2.0
BuildArch: noarch
Requires: python3
Requires: openssh-clients
Requires: shadow-utils
Requires: procps-ng
Requires: util-linux
Source0: sshfling-files-${version}.tar.gz

%description
SSHFling issues short-lived OpenSSH user certificates and installs a forced
session wrapper so temporary SSH sessions are capped by a server-side
wall-clock timeout. Docker Compose files are included as a test harness.

%prep

%build

%install
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%files
%config(noreplace) /etc/sshfling/policy.json
%attr(0755,root,root) /usr/bin/sshfling
/usr/share/sshfling/templates
/usr/share/doc/sshfling/README.md
/usr/share/doc/sshfling/LICENSE
/usr/share/doc/sshfling/sshflingd.env.example
/usr/lib/systemd/system/sshflingd.service

%changelog
* Fri Jul 03 2026 SSHFling Maintainers <root@localhost> - ${version}-1
- Initial package
SPEC

rpmbuild --define "_topdir $topdir" -bb "$topdir/SPECS/sshfling.spec"

install -d "$dist_dir"
find "$topdir/RPMS" -type f -name "sshfling-${version}-*.rpm" -exec cp {} "$dist_dir/" \;
find "$dist_dir" -type f -name "sshfling-${version}-*.rpm" -print
