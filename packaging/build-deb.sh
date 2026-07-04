#!/usr/bin/env bash
set -euo pipefail

version="${SSHFLING_VERSION:-0.1.4}"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dist_dir="$repo_root/dist"
stage="$repo_root/build/deb/sshfling_${version}_all"

rm -rf "$stage"
install -d "$stage/DEBIAN" "$stage/etc/sshfling" "$stage/usr/bin" "$stage/usr/share/sshfling/templates" "$stage/usr/share/doc/sshfling" "$stage/lib/systemd/system"

install -m 0755 "$repo_root/bin/sshfling" "$stage/usr/bin/sshfling"
install -m 0644 "$repo_root/packaging/policy.json" "$stage/etc/sshfling/policy.json"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_sshfling_templates "$repo_root" "$stage/usr/share/sshfling/templates"

install -m 0644 "$repo_root/README.md" "$stage/usr/share/doc/sshfling/README.md"
install -m 0644 "$repo_root/LICENSE" "$stage/usr/share/doc/sshfling/LICENSE"
install -m 0644 "$repo_root/systemd/sshflingd.env.example" "$stage/usr/share/doc/sshfling/sshflingd.env.example"
install -m 0644 "$repo_root/systemd/sshflingd.service" "$stage/lib/systemd/system/sshflingd.service"

cat >"$stage/DEBIAN/control" <<CONTROL
Package: sshfling
Version: $version
Section: utils
Priority: optional
Architecture: all
Depends: python3, openssh-client, procps, util-linux
Suggests: openssh-server, docker.io | docker-ce | podman-docker
Maintainer: SSHFling Maintainers <root@localhost>
Description: Temporary SSH certificate issuer and access CLI
 SSHFling issues short-lived OpenSSH user certificates and installs a forced
 session wrapper so temporary SSH sessions are capped by a server-side
 wall-clock timeout. Docker Compose files are included as a test harness.
CONTROL

cat >"$stage/DEBIAN/conffiles" <<'CONFFILES'
/etc/sshfling/policy.json
CONFFILES

install -d "$dist_dir"
dpkg-deb --build --root-owner-group "$stage" "$dist_dir/sshfling_${version}_all.deb"
echo "$dist_dir/sshfling_${version}_all.deb"
