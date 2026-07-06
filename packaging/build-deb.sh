#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
dist_dir="$repo_root/dist"
stage="$repo_root/build/deb/sshfling_${version}_all"

rm -rf "$stage"
install -d "$stage/DEBIAN" "$stage/usr/bin" "$stage/usr/share/sshfling/templates" "$stage/usr/share/doc/sshfling" "$stage/lib/systemd/system"
install -d -m 0750 "$stage/etc/sshfling"

install -m 0755 "$repo_root/bin/sshfling" "$stage/usr/bin/sshfling"
install -m 0644 "$repo_root/packaging/policy.json" "$stage/etc/sshfling/policy.json"
install -m 0640 "$repo_root/systemd/sshflingd.env.example" "$stage/etc/sshfling/sshflingd.env"

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
Depends: python3, openssh-client, passwd, procps, util-linux
Suggests: openssh-server, docker.io | docker-ce | podman-docker
Maintainer: SSHFling Maintainers <root@localhost>
Description: Temporary SSH access broker and CLI
 SSHFling grants short-lived SSH access with default password grants, optional
 OpenSSH user certificates, and a forced session wrapper so temporary SSH
 sessions are capped by a server-side wall-clock timeout. Docker Compose files
 are included as a test harness.
CONTROL

cat >"$stage/DEBIAN/conffiles" <<'CONFFILES'
/etc/sshfling/policy.json
/etc/sshfling/sshflingd.env
CONFFILES

cat >"$stage/DEBIAN/postinst" <<'POSTINST'
#!/bin/sh
set -e

group_exists() {
  if command -v getent >/dev/null 2>&1; then
    getent group sshflingd >/dev/null 2>&1
  else
    grep -q '^sshflingd:' /etc/group
  fi
}

user_exists() {
  if command -v getent >/dev/null 2>&1; then
    getent passwd sshflingd >/dev/null 2>&1
  else
    grep -q '^sshflingd:' /etc/passwd
  fi
}

ensure_account() {
  if ! group_exists; then
    if command -v groupadd >/dev/null 2>&1; then
      groupadd --system sshflingd 2>/dev/null || groupadd -r sshflingd
    elif command -v addgroup >/dev/null 2>&1; then
      addgroup --system sshflingd
    else
      echo "sshfling: cannot create sshflingd group; groupadd or addgroup is required" >&2
      exit 1
    fi
  fi

  if ! user_exists; then
    nologin=/usr/sbin/nologin
    if [ ! -x "$nologin" ] && [ -x /sbin/nologin ]; then
      nologin=/sbin/nologin
    fi

    if command -v useradd >/dev/null 2>&1; then
      useradd --system --gid sshflingd --home-dir /var/lib/sshflingd --shell "$nologin" --no-create-home sshflingd 2>/dev/null \
        || useradd -r -g sshflingd -d /var/lib/sshflingd -s "$nologin" -M sshflingd
    elif command -v adduser >/dev/null 2>&1; then
      adduser --system --ingroup sshflingd --home /var/lib/sshflingd --no-create-home --shell "$nologin" sshflingd
    else
      echo "sshfling: cannot create sshflingd user; useradd or adduser is required" >&2
      exit 1
    fi
  fi
}

reload_systemd() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

case "$1" in
  configure)
    ensure_account
    install -d -m 0750 -o root -g sshflingd /etc/sshfling
    install -d -m 0750 -o sshflingd -g sshflingd /var/lib/sshflingd
    if [ -f /etc/sshfling/policy.json ] && [ ! -L /etc/sshfling/policy.json ]; then
      chown root:root /etc/sshfling/policy.json
      chmod 0644 /etc/sshfling/policy.json
    fi
    if [ -f /etc/sshfling/sshflingd.env ] && [ ! -L /etc/sshfling/sshflingd.env ]; then
      chown root:sshflingd /etc/sshfling/sshflingd.env
      chmod 0640 /etc/sshfling/sshflingd.env
    fi
    reload_systemd
    if [ -n "${2:-}" ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      if systemctl is-active --quiet sshflingd.service; then
        systemctl try-restart sshflingd.service >/dev/null 2>&1 || true
      fi
    fi
    ;;
esac

exit 0
POSTINST

cat >"$stage/DEBIAN/prerm" <<'PRERM'
#!/bin/sh
set -e

case "$1" in
  remove|deconfigure)
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      systemctl disable --now sshflingd.service >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
PRERM

cat >"$stage/DEBIAN/postrm" <<'POSTRM'
#!/bin/sh
set -e

case "$1" in
  remove|purge|abort-install|abort-upgrade|disappear)
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    ;;
esac

exit 0
POSTRM

chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"

install -d "$dist_dir"
dpkg-deb --build --root-owner-group "$stage" "$dist_dir/sshfling_${version}_all.deb"
echo "$dist_dir/sshfling_${version}_all.deb"
