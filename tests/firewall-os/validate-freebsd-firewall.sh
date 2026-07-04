#!/usr/bin/env sh
set -eu

cmd="${1:?sshfling command path is required}"
version="${2:?expected version is required}"
platform="${3:-freebsd-firewall}"

fail() {
  echo "firewall OS validation failed: $*" >&2
  exit 1
}

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
"$script_dir/cross-os/validate-cli.sh" "$cmd" "$version"

tmp="${TMPDIR:-/tmp}/sshfling-firewall-$$"
rm -rf "$tmp"
mkdir -p "$tmp/sshd_config.d" "$tmp/principals"
trap 'rm -rf "$tmp"' EXIT INT TERM

ca_pub="$tmp/ca.pub"
cat >"$ca_pub" <<'EOF'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJpWrMtN5B+xY5CTW2Tay4c1Mbe0z0H5tY2NmwM1yNcj sshfling-firewall-test
EOF

"$cmd" --json host install \
  --dry-run \
  --no-validate \
  --ca-pub "$ca_pub" \
  --user sshflingtest \
  --principal sshflingtest \
  --trusted-ca "$tmp/trusted_user_ca_keys.pem" \
  --principals-dir "$tmp/authorized_principals" \
  --session-wrapper "$tmp/sshfling-session" \
  --sshd-config "$tmp/sshd_config.d/90-sshfling.conf" \
  --policy-file "$tmp/policy.json" \
  >"$tmp/host-install.json"

python3 - "$tmp/host-install.json" "$platform" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
platform = sys.argv[2]
assert payload["ok"] is True, payload
results = payload["results"]
assert any(item.get("dry_run") and item.get("path", "").endswith("sshfling-session") for item in results), payload
assert any(item.get("dry_run") and item.get("path", "").endswith("trusted_user_ca_keys.pem") for item in results), payload
assert any(item.get("dry_run") and item.get("path", "").endswith("90-sshfling.conf") for item in results), payload
print(f"certificate host dry-run ok: {platform}")
PY

if [ "$(id -u)" = "0" ]; then
  set +e
  "$cmd" --password --dry-run --username sshflingtest -t 60s 2>"$tmp/password.err" >"$tmp/password.out"
  rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    fail "password mode unexpectedly succeeded on $platform"
  fi
  grep -Fq "Password grant setup requires Linux account tools" "$tmp/password.err" || {
    cat "$tmp/password.err" >&2
    fail "password mode did not fail with the expected Linux-tooling boundary"
  }
fi

echo "firewall OS validation ok: $platform $version"
