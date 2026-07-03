#!/usr/bin/env bash
set -euo pipefail

key_path="${1:-secrets/client_ed25519}"
key_dir="$(dirname "$key_path")"

mkdir -p "$key_dir"

if [[ -e "$key_path" || -e "$key_path.pub" ]]; then
  echo "Key already exists at $key_path"
  echo "Remove it first if you want to rotate the deployment key."
  exit 1
fi

ssh-keygen -t ed25519 -N "" -C "timed-ssh-client" -f "$key_path" >/dev/null
chmod 600 "$key_path"
chmod 644 "$key_path.pub"

echo "Created SSH keypair:"
echo "  private: $key_path"
echo "  public:  $key_path.pub"
