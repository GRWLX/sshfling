#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
launcher_template="${1:-$repo_root/production/sshfling-login-shell}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "native login shell validation failed: $*" >&2
  exit 1
}

mkdir -p "$tmp/untrusted-bin"
launcher="$tmp/sshfling-login-shell"
wrapper="$tmp/sshfling-session"
policy="$tmp/policy.json"
actual_user="$(id -un)"
sed \
  -e "s|^expected_wrapper=.*$|expected_wrapper='$wrapper'|" \
  -e "s|^expected_policy=.*$|expected_policy='$policy'|" \
  -e "s|^expected_bash=.*$|expected_bash='$(command -v bash)'|" \
  "$launcher_template" >"$launcher"
chmod 0755 "$launcher"
cat >"$wrapper" <<'EOF'
#!/bin/sh
printf '%s\n' "$SSH_ORIGINAL_COMMAND"
command -v bash
printf '%s\n' "$*"
EOF
chmod 0755 "$wrapper"
printf '{}\n' >"$policy"

cat >"$tmp/bash-env" <<EOF
printf '%s\n' injected >"$tmp/bash-env-ran"
EOF
cat >"$tmp/sh-env" <<EOF
printf '%s\n' injected >"$tmp/sh-env-ran"
EOF
cat >"$tmp/untrusted-bin/bash" <<EOF
#!/bin/sh
printf '%s\n' injected >"$tmp/path-ran"
exec /bin/bash "\$@"
EOF
chmod 0755 "$tmp/untrusted-bin/bash"

set +e
"$launcher" >"$tmp/direct.out" 2>"$tmp/direct.err"
direct_status="$?"
set -e
[[ "$direct_status" -eq 126 ]] || fail "direct invocation returned $direct_status instead of 126"
grep -Fq 'administrative forced command is required' "$tmp/direct.err" \
  || fail "direct invocation did not explain its rejection"

PATH="$tmp/untrusted-bin:/usr/bin:/bin" \
BASH_ENV="$tmp/bash-env" \
ENV="$tmp/sh-env" \
SSH_ORIGINAL_COMMAND='printf original-command' \
  "$launcher" -c "$wrapper --max-seconds 30 --username Test.Principal --login-user $actual_user --policy-file $policy" \
  >"$tmp/dispatch.out"

grep -Fxq 'printf original-command' "$tmp/dispatch.out" \
  || fail "SSH_ORIGINAL_COMMAND was not preserved"
grep -Fxq -- "--max-seconds 30 --username Test.Principal --login-user $actual_user --policy-file $policy" "$tmp/dispatch.out" \
  || fail "dispatcher changed the administrative forced-command arguments"
if grep -Fq "$tmp/untrusted-bin" "$tmp/dispatch.out"; then
  fail "dispatcher did not replace the untrusted PATH"
fi
[[ ! -e "$tmp/bash-env-ran" ]] || fail "BASH_ENV ran before the forced command"
[[ ! -e "$tmp/sh-env-ran" ]] || fail "ENV ran before the forced command"
[[ ! -e "$tmp/path-ran" ]] || fail "untrusted PATH selected the shell interpreter"

expect_rejected() {
  local label="$1"
  local command="$2"
  local status

  set +e
  "$launcher" -c "$command" >"$tmp/rejected.out" 2>"$tmp/rejected.err"
  status="$?"
  set -e
  [[ "$status" -eq 126 ]] || fail "$label returned $status instead of 126"
}

expect_rejected "arbitrary command" 'printf bypass'
expect_rejected "shell chaining" "$wrapper --max-seconds 30 --username p --login-user $actual_user --policy-file $policy; printf bypass"
expect_rejected "alternate wrapper" "/bin/sh --max-seconds 30 --username p --login-user $actual_user --policy-file $policy"
expect_rejected "alternate policy" "$wrapper --max-seconds 30 --username p --login-user $actual_user --policy-file $tmp/other.json"
expect_rejected "jq override" "$wrapper --max-seconds 30 --username p --login-user $actual_user --policy-file $policy --jq-bin $tmp/untrusted-bin/bash"
expect_rejected "detached override" "$wrapper --allow-detached-start --max-seconds 30 --username p --login-user $actual_user --policy-file $policy"
expect_rejected "excess lifetime" "$wrapper --max-seconds 86401 --username p --login-user $actual_user --policy-file $policy"

SSH_ORIGINAL_COMMAND='printf password-command' \
  "$launcher" -c "$wrapper --max-seconds 30 --max-connections 1 --username $actual_user --login-user $actual_user --policy-file $policy --expires-at 1999999999" \
  >"$tmp/password.out"
grep -Fxq 'printf password-command' "$tmp/password.out" \
  || fail "password forced-command shape was rejected"

echo "native login shell validation ok"
