#!/usr/bin/env sh
set -eu

cmd="${1:?sshfling command path is required}"
version="${2:?expected version is required}"

fail() {
  echo "cross validation failed: $*" >&2
  exit 1
}

tmp="${TMPDIR:-/tmp}/sshfling-cross-$$"
rm -rf "$tmp"
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT INT TERM

version_output="$("$cmd" --version)"
test "$version_output" = "sshfling $version" || fail "unexpected version output: $version_output"

help_output="$("$cmd" --help)"
printf '%s\n' "$help_output" | grep -Fq "Grant or kill temporary SSH access." || fail "help output missing expected description"

SSHFLING_WEB_PASSWORD="cross-test-password" "$cmd" web-hash >"$tmp/hash.out"
hash_output="$(cat "$tmp/hash.out")"
case "$hash_output" in
  pbkdf2_sha256\$*) ;;
  *) fail "web-hash output did not use pbkdf2_sha256" ;;
esac

"$cmd" --json policy show --policy-file "$tmp/missing-policy.json" >"$tmp/policy.json"
python3 - "$tmp/policy.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["ok"] is True, payload
assert payload["effective"]["max_time_seconds"] == 3600, payload
assert payload["effective"]["max_connections"] == 10, payload
assert payload["policy"]["version"] == 2, payload
PY

SSHFLING_CONNECT_DRY_RUN=1 SSHFLING_SSH_BIN=ssh "$cmd" -p 2222 s123@example.invalid whoami >"$tmp/connect.out"
connect_output="$(cat "$tmp/connect.out")"
printf '%s\n' "$connect_output" | grep -Fq "PreferredAuthentications=password,keyboard-interactive" || fail "connect dry-run missing password auth option"
printf '%s\n' "$connect_output" | grep -Fq "PubkeyAuthentication=no" || fail "connect dry-run missing pubkey disable option"
printf '%s\n' "$connect_output" | grep -Fq -- "-p 2222" || fail "connect dry-run missing forwarded port flag"
printf '%s\n' "$connect_output" | grep -Fq "s123@example.invalid" || fail "connect dry-run missing target"
printf '%s\n' "$connect_output" | grep -Fq "whoami" || fail "connect dry-run missing remote command"

project="$tmp/project"
"$cmd" --json init "$project" --session-seconds 60 --host-port 2222 >"$tmp/init.json"
python3 - "$tmp/init.json" "$project" <<'PY'
import json
import pathlib
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
project = pathlib.Path(sys.argv[2]).resolve()
assert payload["ok"] is True, payload
assert pathlib.Path(payload["project_dir"]).resolve() == project, payload
assert "template_dir" in payload and payload["template_dir"], payload
PY

for rel in \
  .env \
  .env.example \
  README.md \
  LICENSE \
  compose.server.yml \
  compose.client.yml \
  scripts/install-local.sh \
  scripts/uninstall-local.sh \
  scripts/create-network.sh \
  scripts/generate-ssh-key.sh \
  secrets/.gitkeep \
  ssh-client/Dockerfile \
  ssh-client/entrypoint.sh \
  ssh-server/Dockerfile \
  ssh-server/entrypoint.sh \
  ssh-server/limited-session.sh \
  ssh-server/sshd_config \
  production/sshfling-session \
  systemd/sshflingd.service \
  systemd/sshflingd.env.example
do
  test -e "$project/$rel" || fail "init did not create $rel"
done

grep -Fq "SSH_SESSION_SECONDS=60" "$project/.env" || fail "init did not write SSH_SESSION_SECONDS"
grep -Fq "SSH_PORT_ON_HOST=2222" "$project/.env" || fail "init did not write SSH_PORT_ON_HOST"

echo "cross validation ok: $cmd $version"
