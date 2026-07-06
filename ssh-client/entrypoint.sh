#!/usr/bin/env bash
set -euo pipefail

ssh_host="${SSH_HOST:-ssh-server}"
ssh_port="${SSH_PORT:-22}"
ssh_user="${SSH_USER:-deploy}"
private_key="${SSH_PRIVATE_KEY:-/run/secrets/ssh_private_key}"
private_key_b64="${SSH_PRIVATE_KEY_B64:-}"
known_hosts_input="${SSH_KNOWN_HOSTS:-}"
known_hosts_file="${SSH_KNOWN_HOSTS_FILE:-}"
host_key_sha256="${SSH_HOST_KEY_SHA256:-}"
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

if [[ -n "$known_hosts_file" && ! -r "$known_hosts_file" ]]; then
  echo "Cannot read SSH_KNOWN_HOSTS_FILE at $known_hosts_file." >&2
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

if [[ -n "$known_hosts_input" ]]; then
  printf '%s\n' "$known_hosts_input" >"$known_hosts"
elif [[ -n "$known_hosts_file" ]]; then
  install -m 0644 "$known_hosts_file" "$known_hosts"
else
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
fi

if [[ ! -s "$known_hosts" ]]; then
  echo "Known hosts data is empty." >&2
  exit 1
fi

if [[ -n "$host_key_sha256" ]]; then
  expected_fingerprints="${host_key_sha256//,/ }"
  matched_known_hosts="$runtime_dir/known_hosts.match"
  : >"$matched_known_hosts"
  lookup_hosts=("$ssh_host")
  if [[ "$ssh_port" != "22" ]]; then
    lookup_hosts=("[${ssh_host}]:${ssh_port}")
  else
    lookup_hosts+=("[${ssh_host}]:${ssh_port}")
  fi

  for lookup_host in "${lookup_hosts[@]}"; do
    ssh-keygen -F "$lookup_host" -f "$known_hosts" 2>/dev/null \
      | awk 'NF >= 3 && $1 !~ /^#/ { print }' >>"$matched_known_hosts"
  done

  if [[ ! -s "$matched_known_hosts" ]]; then
    echo "Known hosts data does not contain an entry for $ssh_host:$ssh_port." >&2
    exit 1
  fi

  fingerprint_match=0
  while read -r _ fingerprint _; do
    for expected in $expected_fingerprints; do
      if [[ "$fingerprint" == "$expected" || "$fingerprint" == "SHA256:$expected" ]]; then
        fingerprint_match=1
      fi
    done
  done < <(ssh-keygen -l -E sha256 -f "$matched_known_hosts")

  if [[ "$fingerprint_match" -ne 1 ]]; then
    echo "SSH host key fingerprint for $ssh_host:$ssh_port did not match SSH_HOST_KEY_SHA256." >&2
    exit 1
  fi
fi

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
