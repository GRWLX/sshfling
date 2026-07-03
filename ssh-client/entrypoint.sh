#!/usr/bin/env bash
set -euo pipefail

ssh_host="${SSH_HOST:-ssh-server}"
ssh_port="${SSH_PORT:-22}"
ssh_user="${SSH_USER:-deploy}"
private_key="${SSH_PRIVATE_KEY:-/run/secrets/ssh_private_key}"
private_key_b64="${SSH_PRIVATE_KEY_B64:-}"
connect_timeout="${SSH_CONNECT_TIMEOUT:-5}"
wait_retries="${SSH_WAIT_RETRIES:-30}"
remote_command="${SSH_COMMAND:-whoami && hostname && date -u}"

if [[ ! "$ssh_port" =~ ^[0-9]+$ ]]; then
  echo "SSH_PORT must be an integer." >&2
  exit 2
fi

if [[ ! "$connect_timeout" =~ ^[0-9]+$ || "$connect_timeout" -lt 1 ]]; then
  echo "SSH_CONNECT_TIMEOUT must be a positive integer." >&2
  exit 2
fi

if [[ ! "$wait_retries" =~ ^[0-9]+$ || "$wait_retries" -lt 1 ]]; then
  echo "SSH_WAIT_RETRIES must be a positive integer." >&2
  exit 2
fi

if [[ ! -r "$private_key" && -z "$private_key_b64" ]]; then
  echo "Provide a private key with $private_key or SSH_PRIVATE_KEY_B64." >&2
  exit 1
fi

runtime_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$runtime_dir"
}
trap cleanup EXIT

key_copy="$runtime_dir/client_key"
known_hosts="$runtime_dir/known_hosts"

if [[ -n "$private_key_b64" ]]; then
  if ! printf '%s' "$private_key_b64" | base64 -d >"$key_copy"; then
    echo "SSH_PRIVATE_KEY_B64 is not valid base64." >&2
    exit 1
  fi
  chmod 0600 "$key_copy"
else
  install -m 0600 "$private_key" "$key_copy"
fi

for attempt in $(seq 1 "$wait_retries"); do
  if ssh-keyscan -p "$ssh_port" -T "$connect_timeout" "$ssh_host" >"$known_hosts" 2>/dev/null; then
    break
  fi

  if [[ "$attempt" -eq "$wait_retries" ]]; then
    echo "Could not discover SSH host key for $ssh_host:$ssh_port." >&2
    exit 1
  fi

  sleep 1
done

ssh_base=(
  ssh
  -i "$key_copy"
  -p "$ssh_port"
  -o "BatchMode=yes"
  -o "ConnectTimeout=$connect_timeout"
  -o "StrictHostKeyChecking=yes"
  -o "UserKnownHostsFile=$known_hosts"
  "$ssh_user@$ssh_host"
)

if [[ "$#" -gt 0 ]]; then
  exec "${ssh_base[@]}" "$@"
fi

exec "${ssh_base[@]}" "$remote_command"
