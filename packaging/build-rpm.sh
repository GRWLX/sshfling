#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=packaging/version.sh
source "$repo_root/packaging/version.sh"
version="$(assert_sshfling_version_matches_source "${SSHFLING_VERSION:-}" "$repo_root")"
dist_dir="$repo_root/dist"
topdir="$repo_root/build/rpm"
payload="$topdir/payload"

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

assert_rpm_payload_assets() {
  local actual
  local expected

  actual="$(mktemp)"
  expected="$(mktemp)"
  find "$payload" -type f -printf '%m %P\n' | sort -k2,2 >"$actual"
  cat >"$expected" <<'ASSETS'
644 etc/sshfling/policy.json
640 etc/sshfling/sshflingd.env
755 usr/bin/sshfling
755 usr/libexec/sshfling/sshfling-linux-account
755 usr/libexec/sshfling/sshfling-unix-identity
644 usr/lib/systemd/system/sshfling-prune.service
644 usr/lib/systemd/system/sshfling-prune.timer
644 usr/lib/systemd/system/sshflingd.service
644 usr/share/doc/sshfling/LICENSE
644 usr/share/doc/sshfling/README.md
644 usr/share/doc/sshfling/sshflingd.env.example
644 usr/share/sshfling/templates/.env.example
644 usr/share/sshfling/templates/LICENSE
644 usr/share/sshfling/templates/README.md
644 usr/share/sshfling/templates/compose.client.yml
644 usr/share/sshfling/templates/compose.server.yml
755 usr/share/sshfling/templates/native/sshfling-linux-account
755 usr/share/sshfling/templates/native/sshfling-unix-identity
755 usr/share/sshfling/templates/production/sshfling-login-shell
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
644 usr/share/sshfling/templates/systemd/sshfling-prune.service
644 usr/share/sshfling/templates/systemd/sshfling-prune.timer
644 usr/share/sshfling/templates/systemd/sshflingd.service
ASSETS
  sort -k2,2 "$expected" -o "$expected"
  if ! diff -u "$expected" "$actual" >&2; then
    echo "sshfling: RPM payload asset list changed unexpectedly" >&2
    rm -f "$actual" "$expected"
    exit 1
  fi
  rm -f "$actual" "$expected"
}

if ! command -v rpmbuild >/dev/null 2>&1; then
  echo "rpmbuild is required to build an RPM package." >&2
  exit 127
fi

rm -rf "$topdir"
install -d "$topdir/BUILD" "$topdir/RPMS" "$topdir/SOURCES" "$topdir/SPECS" "$topdir/SRPMS"
install -d -m 0750 "$payload/etc/sshfling"
  install -d "$payload/usr/bin" "$payload/usr/libexec/sshfling" "$payload/usr/share/sshfling/templates" "$payload/usr/share/doc/sshfling" "$payload/usr/lib/systemd/system"

install -m 0755 "$repo_root/bin/sshfling" "$payload/usr/bin/sshfling"
install -m 0755 "$repo_root/native/sshfling-linux-account" "$payload/usr/libexec/sshfling/sshfling-linux-account"
install -m 0755 "$repo_root/native/sshfling-unix-identity" "$payload/usr/libexec/sshfling/sshfling-unix-identity"
install -m 0644 "$repo_root/packaging/policy.json" "$payload/etc/sshfling/policy.json"
install -m 0640 "$repo_root/systemd/sshflingd.env.example" "$payload/etc/sshfling/sshflingd.env"

# shellcheck source=packaging/copy-templates.sh
source "$repo_root/packaging/copy-templates.sh"
copy_sshfling_templates "$repo_root" "$payload/usr/share/sshfling/templates"
install -m 0644 "$repo_root/README.md" "$payload/usr/share/doc/sshfling/README.md"
install -m 0644 "$repo_root/LICENSE" "$payload/usr/share/doc/sshfling/LICENSE"
install -m 0644 "$repo_root/systemd/sshflingd.env.example" "$payload/usr/share/doc/sshfling/sshflingd.env.example"
install -m 0644 "$repo_root/systemd/sshflingd.service" "$payload/usr/lib/systemd/system/sshflingd.service"
install -m 0644 "$repo_root/systemd/sshfling-prune.service" "$payload/usr/lib/systemd/system/sshfling-prune.service"
install -m 0644 "$repo_root/systemd/sshfling-prune.timer" "$payload/usr/lib/systemd/system/sshfling-prune.timer"

assert_rpm_payload_assets
normalize_tree_timestamps "$payload"

tar \
  --sort=name \
  --mtime="@$source_date_epoch" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --use-compress-program="gzip -n" \
  -C "$payload" \
  -cf "$topdir/SOURCES/sshfling-files-${version}.tar.gz" \
  .

cat >"$topdir/SPECS/sshfling.spec" <<SPEC
Name: sshfling
Version: $version
Release: 1%{?dist}
Summary: Temporary SSH access broker and CLI
License: Apache-2.0
BuildArch: noarch
Requires: python3
Requires: bash
Requires: openssh-clients
Requires: openssl
Recommends: openssh-server
Recommends: rsync
Requires: shadow-utils
Requires(pre): shadow-utils
Requires: procps-ng
Requires: util-linux
Requires: jq
Source0: sshfling-files-${version}.tar.gz

%description
SSHFling grants short-lived SSH access with default password grants, optional
OpenSSH user certificates, and a forced session wrapper so temporary SSH
sessions are capped by a server-side wall-clock timeout. Docker Compose files
are included as a test harness.

%prep

%build

%install
mkdir -p %{buildroot}
tar -C %{buildroot} -xzf %{SOURCE0}

%pre
set -e

state_root=/var/lib/sshfling
state_dir=\$state_root/package-state
state_file=\$state_dir/install-state

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
  dir_path=\$1
  dir_mode=\$2
  dir_owner=\$3
  dir_group=\$4

  if [ -L "\$dir_path" ] || { [ -e "\$dir_path" ] && [ ! -d "\$dir_path" ]; }; then
    echo "sshfling: refusing to manage unsafe package directory \$dir_path" >&2
    exit 1
  fi
  install -d -m "\$dir_mode" -o "\$dir_owner" -g "\$dir_group" "\$dir_path"
}

ensure_package_state_dir() {
  ensure_package_dir "\$state_root" 0750 root root
  ensure_package_dir "\$state_dir" 0700 root root
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
  if [ -e "\$state_file" ] || [ -L "\$state_file" ]; then
    if [ -f "\$state_file" ] && [ ! -L "\$state_file" ]; then
      state_owner="\$(stat -c %u "\$state_file" 2>/dev/null || echo unknown)"
      if [ "\$state_owner" != "0" ]; then
        echo "sshfling: refusing to use non-root-owned install state \$state_file" >&2
        exit 1
      fi
      if grep -Fqx 'group_preexisting=no' "\$state_file" \\
        && grep -Fqx 'user_preexisting=no' "\$state_file" \\
        && grep -Fqx 'var_dir_preexisting=no' "\$state_file"; then
        recorded_uid="\$(sed -n 's/^user_uid=//p' "\$state_file" | tail -n 1)"
        recorded_gid="\$(sed -n 's/^user_gid=//p' "\$state_file" | tail -n 1)"
        recorded_home="\$(sed -n 's/^user_home=//p' "\$state_file" | tail -n 1)"
        current_entry="\$(getent passwd sshflingd 2>/dev/null || grep '^sshflingd:' /etc/passwd || true)"
        current_uid="\$(printf '%s\n' "\$current_entry" | cut -d: -f3)"
        current_gid="\$(printf '%s\n' "\$current_entry" | cut -d: -f4)"
        current_home="\$(printf '%s\n' "\$current_entry" | cut -d: -f6)"
        if [ -n "\$recorded_uid" ] && [ "\$recorded_uid" = "\$current_uid" ] \\
          && [ -n "\$recorded_gid" ] && [ "\$recorded_gid" = "\$current_gid" ] \\
          && [ -n "\$recorded_home" ] && [ "\$recorded_home" = "\$current_home" ]; then
          group_preexisting=no
          user_preexisting=no
          var_dir_preexisting=no
          return 0
        fi
      fi
    else
      echo "sshfling: refusing to use unsafe install state \$state_file" >&2
      exit 1
    fi
  fi

  {
    echo "group_preexisting=\$group_preexisting"
    echo "user_preexisting=\$user_preexisting"
    echo "var_dir_preexisting=\$var_dir_preexisting"
  } > "\$state_file"
  chmod 0600 "\$state_file"
}

record_created_identity() {
  if [ ! -f "\$state_file" ] || [ -L "\$state_file" ]; then
    return 0
  fi
  if [ "\${group_preexisting:-yes}" = "no" ] && group_exists && ! grep -q '^group_gid=' "\$state_file"; then
    group_entry="\$(getent group sshflingd 2>/dev/null || grep '^sshflingd:' /etc/group || true)"
    group_gid="\$(printf '%s\n' "\$group_entry" | cut -d: -f3)"
    if [ -n "\$group_gid" ]; then
      echo "group_gid=\$group_gid" >>"\$state_file"
    fi
  fi
  if [ "\${user_preexisting:-yes}" = "no" ] && user_exists && ! grep -q '^user_uid=' "\$state_file"; then
    user_entry="\$(getent passwd sshflingd 2>/dev/null || grep '^sshflingd:' /etc/passwd || true)"
    user_uid="\$(printf '%s\n' "\$user_entry" | cut -d: -f3)"
    user_gid="\$(printf '%s\n' "\$user_entry" | cut -d: -f4)"
    user_home="\$(printf '%s\n' "\$user_entry" | cut -d: -f6)"
    if [ -n "\$user_uid" ] && [ -n "\$user_gid" ] && [ -n "\$user_home" ]; then
      {
        echo "user_uid=\$user_uid"
        echo "user_gid=\$user_gid"
        echo "user_home=\$user_home"
      } >>"\$state_file"
    fi
  fi
}

record_install_state

if ! group_exists; then
  groupadd --system sshflingd 2>/dev/null || groupadd -r sshflingd
fi

if ! user_exists; then
  nologin=/usr/sbin/nologin
  if [ ! -x "\$nologin" ] && [ -x /sbin/nologin ]; then
    nologin=/sbin/nologin
  fi
  useradd --system --gid sshflingd --home-dir /var/lib/sshflingd --shell "\$nologin" --no-create-home sshflingd 2>/dev/null \
    || useradd -r -g sshflingd -d /var/lib/sshflingd -s "\$nologin" -M sshflingd
fi

record_created_identity

exit 0

%post
set -e

ensure_package_dir() {
  dir_path=\$1
  dir_mode=\$2
  dir_owner=\$3
  dir_group=\$4

  if [ -L "\$dir_path" ] || { [ -e "\$dir_path" ] && [ ! -d "\$dir_path" ]; }; then
    echo "sshfling: refusing to manage unsafe package directory \$dir_path" >&2
    exit 1
  fi
  install -d -m "\$dir_mode" -o "\$dir_owner" -g "\$dir_group" "\$dir_path"
}

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
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable --now sshfling-prune.timer >/dev/null 2>&1 || true
fi

exit 0

%preun
set -e

state_root=/var/lib/sshfling
preserve_dir=\$state_root/rpm-preserve-config

ensure_package_state_root() {
  if [ -L "\$state_root" ] || { [ -e "\$state_root" ] && [ ! -d "\$state_root" ]; }; then
    echo "sshfling: refusing to manage unsafe package state root \$state_root" >&2
    exit 1
  fi
  install -d -m 0750 -o root -g root "\$state_root"
}

if [ "\$1" -eq 0 ]; then
  preserved_config=no
  ensure_package_state_root
  if [ -L "\$preserve_dir" ]; then
    rm -f "\$preserve_dir"
  else
    rm -rf "\$preserve_dir"
  fi
  install -d -m 0700 -o root -g root "\$preserve_dir"
  for path in /etc/sshfling/policy.json /etc/sshfling/sshflingd.env; do
    if [ -f "\$path" ] && [ ! -L "\$path" ]; then
      cp -p "\$path" "\$preserve_dir/\$(basename "\$path")"
      preserved_config=yes
    fi
  done
  if [ "\$preserved_config" != "yes" ]; then
    rmdir "\$preserve_dir" 2>/dev/null || true
  fi
fi

if [ "\$1" -eq 0 ] && command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl disable --now sshfling-prune.timer >/dev/null 2>&1 || true
  systemctl disable --now sshflingd.service >/dev/null 2>&1 || true
fi

exit 0

%postun
set -e

state_root=/var/lib/sshfling
preserve_dir=\$state_root/rpm-preserve-config
state_dir=\$state_root/package-state
state_file=\$state_dir/install-state

restore_config() {
  src="\$1"
  dst="\$2"
  mode="\$3"
  owner="\$4"
  group="\$5"

  if [ ! -f "\$src" ]; then
    return 0
  fi

  rpmsave="\$dst.rpmsave"
  if [ -f "\$rpmsave" ]; then
    if [ "\$(cksum <"\$rpmsave")" = "\$(cksum <"\$src")" ]; then
      rm -f "\$rpmsave"
    else
      echo "sshfling: preserving existing \$rpmsave" >&2
    fi
  fi

  if getent group "\$group" >/dev/null 2>&1; then
    install -m "\$mode" -o "\$owner" -g "\$group" "\$src" "\$dst" 2>/dev/null \
      || cp -p "\$src" "\$dst"
  else
    install -m "\$mode" -o "\$owner" -g root "\$src" "\$dst" 2>/dev/null \
      || cp -p "\$src" "\$dst"
  fi
}

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
  if [ -L "\$state_root" ] || [ -L "\$state_dir" ]; then
    echo "sshfling: ignoring symlinked package state directory" >&2
    return 0
  fi

  if [ ! -f "\$state_file" ] || [ -L "\$state_file" ]; then
    return 0
  fi

  state_owner="\$(stat -c %u "\$state_file" 2>/dev/null || echo unknown)"
  if [ "\$state_owner" != "0" ]; then
    echo "sshfling: ignoring non-root-owned install state \$state_file" >&2
    return 0
  fi

  while IFS='=' read -r key value; do
    case "\$key" in
      group_preexisting)
        if [ "\$value" = "yes" ] || [ "\$value" = "no" ]; then
          group_preexisting="\$value"
        fi
        ;;
      user_preexisting)
        if [ "\$value" = "yes" ] || [ "\$value" = "no" ]; then
          user_preexisting="\$value"
        fi
        ;;
      var_dir_preexisting)
        if [ "\$value" = "yes" ] || [ "\$value" = "no" ]; then
          var_dir_preexisting="\$value"
        fi
        ;;
      group_gid)
        group_gid="\$value"
        ;;
      user_uid)
        user_uid="\$value"
        ;;
      user_gid)
        user_gid="\$value"
        ;;
      user_home)
        user_home="\$value"
        ;;
    esac
  done < "\$state_file"
}

service_user_matches_state() {
  if [ -z "\${user_uid:-}" ] || [ -z "\${user_gid:-}" ] || [ -z "\${user_home:-}" ]; then
    return 1
  fi
  user_entry="\$(getent passwd sshflingd 2>/dev/null || grep '^sshflingd:' /etc/passwd || true)"
  current_uid="\$(printf '%s\n' "\$user_entry" | cut -d: -f3)"
  current_gid="\$(printf '%s\n' "\$user_entry" | cut -d: -f4)"
  current_home="\$(printf '%s\n' "\$user_entry" | cut -d: -f6)"
  [ "\$current_uid" = "\$user_uid" ] && [ "\$current_gid" = "\$user_gid" ] && [ "\$current_home" = "\$user_home" ]
}

service_group_matches_state() {
  if [ -z "\${group_gid:-}" ]; then
    return 1
  fi
  group_entry="\$(getent group sshflingd 2>/dev/null || grep '^sshflingd:' /etc/group || true)"
  current_gid="\$(printf '%s\n' "\$group_entry" | cut -d: -f3)"
  [ "\$current_gid" = "\$group_gid" ]
}

remove_package_state() {
  if [ -L "\$state_root" ]; then
    echo "sshfling: not removing symlinked package state root \$state_root" >&2
    return 0
  fi
  if [ -L "\$state_dir" ]; then
    rm -f "\$state_dir"
  else
    rm -rf "\$state_dir"
  fi
  if [ -L "\$preserve_dir" ]; then
    rm -f "\$preserve_dir"
  else
    rm -rf "\$preserve_dir"
  fi
  rmdir "\$state_root" 2>/dev/null || true
}

remove_preserve_state() {
  if [ -L "\$preserve_dir" ]; then
    rm -f "\$preserve_dir"
  else
    rm -rf "\$preserve_dir"
  fi
  rmdir "\$state_root" 2>/dev/null || true
}

remove_created_account_if_safe() {
  group_preexisting=yes
  user_preexisting=yes
  var_dir_preexisting=yes
  var_dir_blocks_cleanup=no

  read_install_state

  if [ -d /var/lib/sshflingd ]; then
    if [ "\${var_dir_preexisting:-yes}" = "no" ] && var_lib_is_empty; then
      if user_exists && ! service_user_matches_state; then
        echo "sshfling: preserving /var/lib/sshflingd because package ownership identity does not match" >&2
        remove_preserve_state
        return 0
      fi
    else
      var_dir_blocks_cleanup=yes
    fi
  fi

  if [ -d /etc/sshfling ] || [ "\$var_dir_blocks_cleanup" = "yes" ]; then
    if [ "\${user_preexisting:-yes}" = "yes" ] && [ "\${group_preexisting:-yes}" = "yes" ] && [ "\${var_dir_preexisting:-yes}" = "yes" ]; then
      remove_package_state
    else
      remove_preserve_state
    fi
    return 0
  fi

  if [ "\${user_preexisting:-yes}" = "no" ] && user_exists; then
    if service_user_matches_state; then
      userdel sshflingd >/dev/null 2>&1 || true
    else
      echo "sshfling: preserving sshflingd account because package ownership identity does not match" >&2
    fi
  fi

  if [ "\${var_dir_preexisting:-yes}" = "no" ] && var_lib_is_empty; then
    rmdir /var/lib/sshflingd 2>/dev/null || true
  fi

  if [ "\${group_preexisting:-yes}" = "no" ] && group_exists && ! user_exists; then
    if service_group_matches_state; then
      groupdel sshflingd >/dev/null 2>&1 || true
    else
      echo "sshfling: preserving sshflingd group because package ownership identity does not match" >&2
    fi
  fi

  remove_package_state
}

if [ "\$1" -eq 0 ] && [ ! -L "\$state_root" ] && [ ! -L "\$preserve_dir" ] && [ -d "\$preserve_dir" ]; then
  install -d -m 0750 /etc/sshfling
  if getent group sshflingd >/dev/null 2>&1; then
    chown root:sshflingd /etc/sshfling 2>/dev/null || true
  else
    chown root:root /etc/sshfling 2>/dev/null || true
  fi
  restore_config "\$preserve_dir/policy.json" /etc/sshfling/policy.json 0644 root root
  restore_config "\$preserve_dir/sshflingd.env" /etc/sshfling/sshflingd.env 0640 root sshflingd
  rm -rf "\$preserve_dir"
  rmdir "\$state_root" 2>/dev/null || true
fi

if [ "\$1" -eq 0 ]; then
  remove_created_account_if_safe
fi

if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  systemctl daemon-reload >/dev/null 2>&1 || true
  if [ "\$1" -ge 1 ] && systemctl is-active --quiet sshflingd.service; then
    systemctl try-restart sshflingd.service >/dev/null 2>&1 || true
  fi
fi

exit 0

%files
%dir %attr(0750,root,sshflingd) /etc/sshfling
%config(missingok,noreplace) %attr(0644,root,root) /etc/sshfling/policy.json
%config(missingok,noreplace) %attr(0640,root,sshflingd) /etc/sshfling/sshflingd.env
%attr(0755,root,root) /usr/bin/sshfling
%attr(0755,root,root) /usr/libexec/sshfling/sshfling-linux-account
%attr(0755,root,root) /usr/libexec/sshfling/sshfling-unix-identity
/usr/share/sshfling/templates
/usr/share/doc/sshfling/README.md
/usr/share/doc/sshfling/LICENSE
/usr/share/doc/sshfling/sshflingd.env.example
/usr/lib/systemd/system/sshfling-prune.service
/usr/lib/systemd/system/sshfling-prune.timer
/usr/lib/systemd/system/sshflingd.service

%changelog
* Fri Jul 03 2026 GRWLX <44076838+GRWLX@users.noreply.github.com> - ${version}-1
- Initial package
SPEC

rpmbuild \
  --define "_topdir $topdir" \
  --define "_build_id_links none" \
  --define "_buildhost sshfling-build.local" \
  --define "use_source_date_epoch_as_buildtime 1" \
  --define "clamp_mtime_to_source_date_epoch 1" \
  -bb "$topdir/SPECS/sshfling.spec"

install -d "$dist_dir"
mapfile -t built_rpms < <(find "$topdir/RPMS" -type f -name "sshfling-${version}-*.rpm" | sort)
if ((${#built_rpms[@]} != 1)); then
  printf 'Expected exactly one built RPM for version %s, found %s.\n' "$version" "${#built_rpms[@]}" >&2
  printf '%s\n' "${built_rpms[@]}" >&2
  exit 1
fi
rpm_name="$(basename "${built_rpms[0]}")"
rm -f "$dist_dir"/sshfling-"$version"-*.rpm
cp "${built_rpms[0]}" "$dist_dir/$rpm_name"
printf '%s\n' "$dist_dir/$rpm_name"
