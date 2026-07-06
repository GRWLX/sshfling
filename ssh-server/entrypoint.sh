#!/usr/bin/env bash
set -euo pipefail

session_seconds="${SSH_SESSION_SECONDS:-60}"
authorized_keys_file="${AUTHORIZED_KEYS_FILE:-/run/secrets/ssh_authorized_keys}"
authorized_keys="${SSH_AUTHORIZED_KEYS:-}"
sshd_config_template="${SSHD_CONFIG_TEMPLATE:-/usr/local/share/timed-ssh-server/sshd_config}"
sshd_runtime_config="${SSHD_RUNTIME_CONFIG:-/run/sshd_config}"
host_key_dir="${SSH_HOST_KEY_DIR:-/run/ssh-host-keys}"
session_limit_file="/etc/ssh/session_limit_seconds"

if [[ ! "$session_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "SSH_SESSION_SECONDS must be a positive integer." >&2
  exit 2
fi

if [[ ! -s "$authorized_keys_file" && -z "$authorized_keys" ]]; then
  echo "Provide authorized keys with $authorized_keys_file or SSH_AUTHORIZED_KEYS." >&2
  exit 1
fi

if [[ ! -r "$sshd_config_template" ]]; then
  echo "Cannot read sshd config template at $sshd_config_template." >&2
  exit 1
fi

install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
install -d -m 0755 /run/sshd
install -d -m 0700 "$host_key_dir"
install -d -m 0755 "$(dirname "$session_limit_file")"

if [[ -s "$authorized_keys_file" ]]; then
  install -m 0600 -o deploy -g deploy "$authorized_keys_file" /home/deploy/.ssh/authorized_keys
else
  printf '%s\n' "$authorized_keys" >/home/deploy/.ssh/authorized_keys
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 0600 /home/deploy/.ssh/authorized_keys
fi

generate_host_key() {
  local type="$1"
  local key_path="$2"
  shift 2

  if [[ ! -s "$key_path" ]]; then
    ssh-keygen -q -t "$type" "$@" -N "" -f "$key_path"
  fi
  chmod 0600 "$key_path"
}

generate_host_key ed25519 "$host_key_dir/ssh_host_ed25519_key"
generate_host_key rsa "$host_key_dir/ssh_host_rsa_key" -b 3072

printf '%s\n' "$session_seconds" >"$session_limit_file"
chmod 0644 "$session_limit_file"

awk -v host_key_dir="$host_key_dir" '
  /^[[:space:]]*HostKey[[:space:]]/ { next }
  /^[[:space:]]*PidFile[[:space:]]/ { next }
  { print }
  END {
    print "HostKey " host_key_dir "/ssh_host_ed25519_key"
    print "HostKey " host_key_dir "/ssh_host_rsa_key"
    print "PidFile /run/sshd.pid"
  }
' "$sshd_config_template" >"$sshd_runtime_config"
chmod 0644 "$sshd_runtime_config"

exec /usr/sbin/sshd -D -e -f "$sshd_runtime_config"
