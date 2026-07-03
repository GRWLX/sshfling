#!/usr/bin/env bash
set -euo pipefail

session_seconds="${SSH_SESSION_SECONDS:-60}"
authorized_keys_file="${AUTHORIZED_KEYS_FILE:-/run/secrets/ssh_authorized_keys}"
authorized_keys="${SSH_AUTHORIZED_KEYS:-}"

if [[ ! "$session_seconds" =~ ^[1-9][0-9]*$ ]]; then
  echo "SSH_SESSION_SECONDS must be a positive integer." >&2
  exit 2
fi

if [[ ! -s "$authorized_keys_file" && -z "$authorized_keys" ]]; then
  echo "Provide authorized keys with $authorized_keys_file or SSH_AUTHORIZED_KEYS." >&2
  exit 1
fi

install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh

if [[ -s "$authorized_keys_file" ]]; then
  install -m 0600 -o deploy -g deploy "$authorized_keys_file" /home/deploy/.ssh/authorized_keys
else
  printf '%s\n' "$authorized_keys" >/home/deploy/.ssh/authorized_keys
  chown deploy:deploy /home/deploy/.ssh/authorized_keys
  chmod 0600 /home/deploy/.ssh/authorized_keys
fi

printf '%s\n' "$session_seconds" >/etc/ssh/session_limit_seconds
chmod 0644 /etc/ssh/session_limit_seconds

ssh-keygen -A >/dev/null

exec /usr/sbin/sshd -D -e
