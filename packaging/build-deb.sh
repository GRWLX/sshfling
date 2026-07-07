#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
dist_dir="$repo_root/dist"
stage="$repo_root/build/deb/sshfling_${version}_all"

export LC_ALL=C
export TZ=UTC
umask 022

source_date_epoch="${SOURCE_DATE_EPOCH:-}"
if [[ -z "$source_date_epoch" ]]; then
  source_date_epoch="$(git -C "$repo_root" log -1 --format=%ct HEAD 2>/dev/null || printf '1700000000')"
fi
if [[ ! "$source_date_epoch" =~ ^[0-9]+$ ]]; then
  echo "SOURCE_DATE_EPOCH must be an integer Unix timestamp." >&2
  exit 2
fi
export SOURCE_DATE_EPOCH="$source_date_epoch"

normalize_tree_timestamps() {
  local path="$1"

  find "$path" -exec touch -h -d "@$source_date_epoch" {} +
}

assert_deb_payload_assets() {
  local actual
  local expected

  actual="$(mktemp)"
  expected="$(mktemp)"
  find "$stage" \
    -path "$stage/DEBIAN" -prune -o \
    -type f -printf '%m %P\n' |
    sort -k2,2 >"$actual"
  cat >"$expected" <<'ASSETS'
644 etc/sshfling/policy.json
640 etc/sshfling/sshflingd.env
644 lib/systemd/system/sshflingd.service
755 usr/bin/sshfling
644 usr/share/doc/sshfling/LICENSE
644 usr/share/doc/sshfling/README.md
644 usr/share/doc/sshfling/sshflingd.env.example
644 usr/share/sshfling/templates/.env.example
644 usr/share/sshfling/templates/LICENSE
644 usr/share/sshfling/templates/README.md
644 usr/share/sshfling/templates/compose.client.yml
644 usr/share/sshfling/templates/compose.server.yml
755 usr/share/sshfling/templates/production/sshfling-session
755 usr/share/sshfling/templates/scripts/create-network.sh
755 usr/share/sshfling/templates/scripts/generate-ssh-key.sh
755 usr/share/sshfling/templates/scripts/install-local.sh
755 usr/share/sshfling/templates/scripts/uninstall-local.sh
644 usr/share/sshfling/templates/secrets/.gitkeep
644 usr/share/sshfling/templates/ssh-client/Dockerfile
755 usr/share/sshfling/templates/ssh-client/entrypoint.sh
644 usr/share/sshfling/templates/ssh-server/Dockerfile
755 usr/share/sshfling/templates/ssh-server/entrypoint.sh
755 usr/share/sshfling/templates/ssh-server/limited-session.sh
644 usr/share/sshfling/templates/ssh-server/sshd_config
644 usr/share/sshfling/templates/systemd/sshflingd.env.example
644 usr/share/sshfling/templates/systemd/sshflingd.service
ASSETS
  sort -k2,2 "$expected" -o "$expected"
  if ! diff -u "$expected" "$actual" >&2; then
    echo "sshfling: DEB payload asset list changed unexpectedly" >&2
    rm -f "$actual" "$expected"
    exit 1
  fi
  rm -f "$actual" "$expected"
}

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

assert_deb_payload_assets

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

state_root=/var/lib/sshfling
state_dir=$state_root/package-state
state_file=$state_dir/install-state

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

ensure_package_dir() {
  dir_path=$1
  dir_mode=$2
  dir_owner=$3
  dir_group=$4

  if [ -L "$dir_path" ] || { [ -e "$dir_path" ] && [ ! -d "$dir_path" ]; }; then
    echo "sshfling: refusing to manage unsafe package directory $dir_path" >&2
    exit 1
  fi
  install -d -m "$dir_mode" -o "$dir_owner" -g "$dir_group" "$dir_path"
}

ensure_package_state_dir() {
  ensure_package_dir "$state_root" 0750 root root
  ensure_package_dir "$state_dir" 0700 root root
}

record_install_state() {
  group_preexisting=no
  user_preexisting=no
  var_dir_preexisting=no
  if group_exists; then
    group_preexisting=yes
  fi
  if user_exists; then
    user_preexisting=yes
  fi
  if [ -e /var/lib/sshflingd ]; then
    var_dir_preexisting=yes
  fi

  ensure_package_state_dir
  if [ -e "$state_file" ] || [ -L "$state_file" ]; then
    if [ -f "$state_file" ] && [ ! -L "$state_file" ]; then
      state_owner="$(stat -c %u "$state_file" 2>/dev/null || echo unknown)"
      if [ "$state_owner" != "0" ]; then
        echo "sshfling: refusing to use non-root-owned install state $state_file" >&2
        exit 1
      fi
      if grep -Fqx 'group_preexisting=no' "$state_file" \
        && grep -Fqx 'user_preexisting=no' "$state_file" \
        && grep -Fqx 'var_dir_preexisting=no' "$state_file"; then
        recorded_uid="$(sed -n 's/^user_uid=//p' "$state_file" | tail -n 1)"
        recorded_gid="$(sed -n 's/^user_gid=//p' "$state_file" | tail -n 1)"
        recorded_home="$(sed -n 's/^user_home=//p' "$state_file" | tail -n 1)"
        current_entry="$(getent passwd sshflingd 2>/dev/null || grep '^sshflingd:' /etc/passwd || true)"
        current_uid="$(printf '%s\n' "$current_entry" | cut -d: -f3)"
        current_gid="$(printf '%s\n' "$current_entry" | cut -d: -f4)"
        current_home="$(printf '%s\n' "$current_entry" | cut -d: -f6)"
        if [ -n "$recorded_uid" ] && [ "$recorded_uid" = "$current_uid" ] \
          && [ -n "$recorded_gid" ] && [ "$recorded_gid" = "$current_gid" ] \
          && [ -n "$recorded_home" ] && [ "$recorded_home" = "$current_home" ]; then
          group_preexisting=no
          user_preexisting=no
          var_dir_preexisting=no
          return 0
        fi
      fi
    else
      echo "sshfling: refusing to use unsafe install state $state_file" >&2
      exit 1
    fi
  fi

  {
    echo "group_preexisting=$group_preexisting"
    echo "user_preexisting=$user_preexisting"
    echo "var_dir_preexisting=$var_dir_preexisting"
  } >"$state_file"
  chmod 0600 "$state_file"
}

record_created_identity() {
  if [ ! -f "$state_file" ] || [ -L "$state_file" ]; then
    return 0
  fi
  if [ "${group_preexisting:-yes}" = "no" ] && group_exists && ! grep -q '^group_gid=' "$state_file"; then
    group_entry="$(getent group sshflingd 2>/dev/null || grep '^sshflingd:' /etc/group || true)"
    group_gid="$(printf '%s\n' "$group_entry" | cut -d: -f3)"
    if [ -n "$group_gid" ]; then
      echo "group_gid=$group_gid" >>"$state_file"
    fi
  fi
  if [ "${user_preexisting:-yes}" = "no" ] && user_exists && ! grep -q '^user_uid=' "$state_file"; then
    user_entry="$(getent passwd sshflingd 2>/dev/null || grep '^sshflingd:' /etc/passwd || true)"
    user_uid="$(printf '%s\n' "$user_entry" | cut -d: -f3)"
    user_gid="$(printf '%s\n' "$user_entry" | cut -d: -f4)"
    user_home="$(printf '%s\n' "$user_entry" | cut -d: -f6)"
    if [ -n "$user_uid" ] && [ -n "$user_gid" ] && [ -n "$user_home" ]; then
      {
        echo "user_uid=$user_uid"
        echo "user_gid=$user_gid"
        echo "user_home=$user_home"
      } >>"$state_file"
    fi
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
    record_install_state
    ensure_account
    record_created_identity
    ensure_package_dir /etc/sshfling 0750 root sshflingd
    ensure_package_dir /var/lib/sshflingd 0750 sshflingd sshflingd
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

state_root=/var/lib/sshfling
state_dir=$state_root/package-state
state_file=$state_dir/install-state

user_exists() {
  if command -v getent >/dev/null 2>&1; then
    getent passwd sshflingd >/dev/null 2>&1
  else
    grep -q '^sshflingd:' /etc/passwd
  fi
}

group_exists() {
  if command -v getent >/dev/null 2>&1; then
    getent group sshflingd >/dev/null 2>&1
  else
    grep -q '^sshflingd:' /etc/group
  fi
}

var_lib_is_empty() {
  if [ ! -d /var/lib/sshflingd ]; then
    return 0
  fi
  if find /var/lib/sshflingd -mindepth 1 -maxdepth 1 | grep -q .; then
    return 1
  fi
  return 0
}

read_install_state() {
  if [ -L "$state_root" ] || [ -L "$state_dir" ]; then
    echo "sshfling: ignoring symlinked package state directory" >&2
    return 0
  fi

  if [ ! -f "$state_file" ] || [ -L "$state_file" ]; then
    return 0
  fi

  state_owner="$(stat -c %u "$state_file" 2>/dev/null || echo unknown)"
  if [ "$state_owner" != "0" ]; then
    echo "sshfling: ignoring non-root-owned install state $state_file" >&2
    return 0
  fi

  while IFS='=' read -r key value; do
    case "$key" in
      group_preexisting)
        if [ "$value" = "yes" ] || [ "$value" = "no" ]; then
          group_preexisting="$value"
        fi
        ;;
      user_preexisting)
        if [ "$value" = "yes" ] || [ "$value" = "no" ]; then
          user_preexisting="$value"
        fi
        ;;
      var_dir_preexisting)
        if [ "$value" = "yes" ] || [ "$value" = "no" ]; then
          var_dir_preexisting="$value"
        fi
        ;;
      group_gid)
        group_gid="$value"
        ;;
      user_uid)
        user_uid="$value"
        ;;
      user_gid)
        user_gid="$value"
        ;;
      user_home)
        user_home="$value"
        ;;
    esac
  done < "$state_file"
}

service_user_matches_state() {
  if [ -z "${user_uid:-}" ] || [ -z "${user_gid:-}" ] || [ -z "${user_home:-}" ]; then
    return 1
  fi
  user_entry="$(getent passwd sshflingd 2>/dev/null || grep '^sshflingd:' /etc/passwd || true)"
  current_uid="$(printf '%s\n' "$user_entry" | cut -d: -f3)"
  current_gid="$(printf '%s\n' "$user_entry" | cut -d: -f4)"
  current_home="$(printf '%s\n' "$user_entry" | cut -d: -f6)"
  [ "$current_uid" = "$user_uid" ] && [ "$current_gid" = "$user_gid" ] && [ "$current_home" = "$user_home" ]
}

service_group_matches_state() {
  if [ -z "${group_gid:-}" ]; then
    return 1
  fi
  group_entry="$(getent group sshflingd 2>/dev/null || grep '^sshflingd:' /etc/group || true)"
  current_gid="$(printf '%s\n' "$group_entry" | cut -d: -f3)"
  [ "$current_gid" = "$group_gid" ]
}

remove_package_state() {
  if [ -L "$state_root" ]; then
    echo "sshfling: not removing symlinked package state root $state_root" >&2
    return 0
  fi
  if [ -L "$state_dir" ]; then
    rm -f "$state_dir"
  else
    rm -rf "$state_dir"
  fi
  rmdir "$state_root" 2>/dev/null || true
}

remove_created_account_if_safe() {
  group_preexisting=yes
  user_preexisting=yes
  var_dir_preexisting=yes
  var_dir_blocks_cleanup=no

  read_install_state

  if [ -d /var/lib/sshflingd ]; then
    if [ "${var_dir_preexisting:-yes}" = "no" ] && var_lib_is_empty; then
      if user_exists && ! service_user_matches_state; then
        echo "sshfling: preserving /var/lib/sshflingd because package ownership identity does not match" >&2
        return 0
      fi
    else
      var_dir_blocks_cleanup=yes
    fi
  fi

  if [ -d /etc/sshfling ] || [ "$var_dir_blocks_cleanup" = "yes" ]; then
    if [ "${user_preexisting:-yes}" = "yes" ] && [ "${group_preexisting:-yes}" = "yes" ] && [ "${var_dir_preexisting:-yes}" = "yes" ]; then
      remove_package_state
    fi
    return 0
  fi

  if [ "${user_preexisting:-yes}" = "no" ] && user_exists; then
    if service_user_matches_state; then
      if command -v userdel >/dev/null 2>&1; then
        userdel sshflingd >/dev/null 2>&1 || true
      elif command -v deluser >/dev/null 2>&1; then
        deluser --system sshflingd >/dev/null 2>&1 || deluser sshflingd >/dev/null 2>&1 || true
      fi
    else
      echo "sshfling: preserving sshflingd account because package ownership identity does not match" >&2
    fi
  fi

  if [ "${var_dir_preexisting:-yes}" = "no" ] && var_lib_is_empty; then
    rmdir /var/lib/sshflingd 2>/dev/null || true
  fi

  if [ "${group_preexisting:-yes}" = "no" ] && group_exists && ! user_exists; then
    if service_group_matches_state; then
      if command -v groupdel >/dev/null 2>&1; then
        groupdel sshflingd >/dev/null 2>&1 || true
      elif command -v delgroup >/dev/null 2>&1; then
        delgroup --system sshflingd >/dev/null 2>&1 || delgroup sshflingd >/dev/null 2>&1 || true
      fi
    else
      echo "sshfling: preserving sshflingd group because package ownership identity does not match" >&2
    fi
  fi

  remove_package_state
}

case "$1" in
  remove|purge|abort-install|abort-upgrade|disappear)
    if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
      systemctl daemon-reload >/dev/null 2>&1 || true
    fi
    ;;
esac

case "$1" in
  purge)
    rm -f /etc/sshfling/policy.json /etc/sshfling/sshflingd.env
    rmdir /etc/sshfling 2>/dev/null || true
    remove_created_account_if_safe
    ;;
esac

exit 0
POSTRM

chmod 0755 "$stage/DEBIAN/postinst" "$stage/DEBIAN/prerm" "$stage/DEBIAN/postrm"

normalize_tree_timestamps "$stage"

install -d "$dist_dir"
dpkg-deb --build --root-owner-group "$stage" "$dist_dir/sshfling_${version}_all.deb"
echo "$dist_dir/sshfling_${version}_all.deb"
