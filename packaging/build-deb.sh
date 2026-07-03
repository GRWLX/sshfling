#!/usr/bin/env bash
set -euo pipefail

version="${FLING_VERSION:-0.1.0}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
stage="$repo_root/build/deb/fling_${version}_all"

rm -rf "$stage"
install -d "$stage/DEBIAN" "$stage/etc/fling" "$stage/usr/bin" "$stage/usr/share/fling/templates" "$stage/usr/share/doc/fling" "$stage/lib/systemd/system"

install -m 0755 "$repo_root/bin/fling" "$stage/usr/bin/fling"
install -m 0644 "$repo_root/packaging/policy.json" "$stage/etc/fling/policy.json"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_fling_templates "$repo_root" "$stage/usr/share/fling/templates"

install -m 0644 "$repo_root/README.md" "$stage/usr/share/doc/fling/README.md"
install -m 0644 "$repo_root/LICENSE" "$stage/usr/share/doc/fling/LICENSE"
install -m 0644 "$repo_root/systemd/flingd.env.example" "$stage/usr/share/doc/fling/flingd.env.example"
install -m 0644 "$repo_root/systemd/flingd.service" "$stage/lib/systemd/system/flingd.service"

cat >"$stage/DEBIAN/control" <<CONTROL
Package: fling
Version: $version
Section: utils
Priority: optional
Architecture: all
Depends: python3, openssh-client, procps, util-linux
Suggests: openssh-server, docker.io | docker-ce | podman-docker
Maintainer: Fling Maintainers <root@localhost>
Description: Temporary SSH certificate issuer and access CLI
 Fling issues short-lived OpenSSH user certificates and installs a forced
 session wrapper so temporary SSH sessions are capped by a server-side
 wall-clock timeout. Docker Compose files are included as a test harness.
CONTROL

cat >"$stage/DEBIAN/conffiles" <<'CONFFILES'
/etc/fling/policy.json
CONFFILES

install -d "$dist_dir"
dpkg-deb --build --root-owner-group "$stage" "$dist_dir/fling_${version}_all.deb"
echo "$dist_dir/fling_${version}_all.deb"
