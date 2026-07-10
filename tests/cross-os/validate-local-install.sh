#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
prefix="$tmp/prefix"

fail() {
  echo "local install validation failed: $*" >&2
  exit 1
}

PREFIX="$prefix" bash "$repo_root/scripts/install-local.sh" >/dev/null

for path in \
  bin/sshfling \
  libexec/sshfling/sshfling-linux-account \
  libexec/sshfling/sshfling-unix-identity \
  share/sshfling/templates/native/sshfling-linux-account \
  share/sshfling/templates/native/sshfling-unix-identity \
  share/sshfling/templates/production/sshfling-login-shell \
  share/sshfling/templates/systemd/sshfling-prune.service \
  share/sshfling/templates/systemd/sshfling-prune.timer
do
  [[ -e "$prefix/$path" ]] || fail "install omitted $path"
done

"$prefix/libexec/sshfling/sshfling-unix-identity" identity root \
  | grep -Fq $'status=present\tuser=root\tuid=0'

PREFIX="$prefix" bash "$repo_root/scripts/uninstall-local.sh" >/dev/null

for path in \
  bin/sshfling \
  libexec/sshfling/sshfling-linux-account \
  libexec/sshfling/sshfling-unix-identity \
  share/sshfling/templates/native/sshfling-linux-account \
  share/sshfling/templates/native/sshfling-unix-identity \
  share/sshfling/templates/production/sshfling-login-shell \
  share/sshfling/templates/systemd/sshfling-prune.service \
  share/sshfling/templates/systemd/sshfling-prune.timer
do
  [[ ! -e "$prefix/$path" ]] || fail "uninstall left $path"
done

echo "local install validation ok"
