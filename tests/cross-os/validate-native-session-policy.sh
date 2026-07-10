#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
wrapper="${1:-$repo_root/production/sshfling-session}"
tmp="$(mktemp -d)"
lock_root=""

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo -n "$@"
  fi
}

inode_number() {
  if stat -c %i "$1" 2>/dev/null; then
    return 0
  fi
  stat -f %i "$1"
}

cleanup() {
  if [[ -n "$lock_root" ]]; then
    as_root rm -rf -- "$lock_root" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

fail() {
  echo "native session policy validation failed: $*" >&2
  exit 1
}

case "$(uname -s)" in
  Darwin) lock_root="/private/var/db/sshfling/session-lock-test-$$" ;;
  FreeBSD|OpenBSD|NetBSD|DragonFly) lock_root="/var/db/sshfling/session-lock-test-$$" ;;
  *) lock_root="/var/lib/sshfling/session-lock-test-$$" ;;
esac
test_user="$(id -un)"
test_uid="$(id -u)"
as_root "$wrapper" --lock-root "$lock_root" --provision-locks "$test_user" >"$tmp/provision.out" \
  || fail "could not provision root-managed test locks"
grep -Fq $'status=provisioned\tuser=' "$tmp/provision.out" \
  || fail "lock provisioning did not return a stable result"
lock_file="$lock_root/$test_uid/session-1.lock"
[[ -f "$lock_file" && ! -L "$lock_file" ]] || fail "lock provisioning did not create slot 1"

[[ -x "$wrapper" ]] || fail "wrapper is not executable: $wrapper"
if grep -Eq 'python3|python' "$wrapper"; then
  fail "wrapper still invokes Python"
fi
if grep -Fq 'exec {' "$wrapper"; then
  fail "wrapper uses file-descriptor syntax unsupported by macOS Bash 3.2"
fi
if grep -Fq 'run_limited /bin/bash' "$wrapper"; then
  fail "wrapper hardcodes a non-portable Bash path"
fi

run_wrapper() {
  local policy_file="$1"
  local max_seconds="$2"
  local login_user="${3:-native-default}"
  local jq_bin="${4:-}"
  local marker="$tmp/ran"
  local -a wrapper_args=(
    --lock-root "$lock_root"
    --max-seconds "$max_seconds"
    --max-connections 1
    --username native-policy-test
    --login-user "$login_user"
    --policy-file "$policy_file"
  )

  rm -f "$marker"
  mkdir -p "$tmp/runtime" "$tmp/home"
  if [[ -n "$jq_bin" ]]; then
    wrapper_args+=(--jq-bin "$jq_bin")
  fi
  XDG_RUNTIME_DIR="$tmp/runtime" \
    HOME="$tmp/home" \
    SSH_ORIGINAL_COMMAND="printf '%s\\n' ran > $(printf '%q' "$marker")" \
    "$wrapper" "${wrapper_args[@]}" \
      >"$tmp/stdout" 2>"$tmp/stderr"
}

assert_allowed() {
  local policy_file="$1"
  local max_seconds="$2"
  local login_user="${3:-native-default}"

  if ! run_wrapper "$policy_file" "$max_seconds" "$login_user"; then
    fail "valid policy rejected: $(cat "$tmp/stderr")"
  fi
  [[ -f "$tmp/ran" ]] || fail "allowed session command did not run"
}

assert_rejected() {
  local policy_file="$1"
  local max_seconds="$2"
  local login_user="${3:-native-default}"

  if run_wrapper "$policy_file" "$max_seconds" "$login_user"; then
    fail "policy unexpectedly allowed a session: $policy_file"
  fi
  [[ ! -e "$tmp/ran" ]] || fail "rejected policy still ran the session command"
}

cat >"$tmp/normalized.json" <<'JSON'
{
  "default": {
    "max_time_seconds": 60,
    "max_connections": 3,
    "access_level": "operator"
  },
  "users": {
    "native-user": {
      "max_time_seconds": 30,
      "max_connections": 2,
      "access_level": "standard"
    },
    "inherits-time": {
      "max_connections": 1
    }
  },
  "version": 2
}
JSON
assert_allowed "$tmp/normalized.json" 60
assert_rejected "$tmp/normalized.json" 61
assert_allowed "$tmp/normalized.json" 30 native-user
assert_rejected "$tmp/normalized.json" 31 native-user
assert_allowed "$tmp/normalized.json" 60 inherits-time

printf '%s\n' '{"max_time_seconds":45,"max_connections":2}' >"$tmp/legacy.json"
assert_allowed "$tmp/legacy.json" 45
assert_rejected "$tmp/legacy.json" 46

cat >"$tmp/split-lines.json" <<'JSON'
{
  "default": {
    "max_time_seconds":
      20,
    "max_connections":
      1
  },
  "users": {}
}
JSON
assert_allowed "$tmp/split-lines.json" 20
assert_rejected "$tmp/split-lines.json" 21

invalid_policies=(
  empty
  malformed
  truncated
  root-array
  string-time
  zero-time
  negative-time
  fractional-time
  over-time
  string-connections
  zero-connections
  over-connections
  invalid-users
  invalid-other-user
  invalid-access-level
)
: >"$tmp/empty.json"
printf '%s\n' 'not-json' >"$tmp/malformed.json"
printf '%s\n' '{"default":{"max_time_seconds":60' >"$tmp/truncated.json"
printf '%s\n' '[]' >"$tmp/root-array.json"
printf '%s\n' '{"default":{"max_time_seconds":"60","max_connections":1}}' >"$tmp/string-time.json"
printf '%s\n' '{"default":{"max_time_seconds":0,"max_connections":1}}' >"$tmp/zero-time.json"
printf '%s\n' '{"default":{"max_time_seconds":-1,"max_connections":1}}' >"$tmp/negative-time.json"
printf '%s\n' '{"default":{"max_time_seconds":1.5,"max_connections":1}}' >"$tmp/fractional-time.json"
printf '%s\n' '{"default":{"max_time_seconds":86401,"max_connections":1}}' >"$tmp/over-time.json"
printf '%s\n' '{"default":{"max_time_seconds":60,"max_connections":"1"}}' >"$tmp/string-connections.json"
printf '%s\n' '{"default":{"max_time_seconds":60,"max_connections":0}}' >"$tmp/zero-connections.json"
printf '%s\n' '{"default":{"max_time_seconds":60,"max_connections":11}}' >"$tmp/over-connections.json"
printf '%s\n' '{"default":{"max_time_seconds":60,"max_connections":1},"users":[]}' >"$tmp/invalid-users.json"
printf '%s\n' '{"default":{"max_time_seconds":60,"max_connections":1},"users":{"other":{"max_time_seconds":0}}}' >"$tmp/invalid-other-user.json"
printf '%s\n' '{"default":{"max_time_seconds":60,"max_connections":1,"access_level":"superuser"}}' >"$tmp/invalid-access-level.json"

for name in "${invalid_policies[@]}"; do
  assert_rejected "$tmp/$name.json" 1
  grep -Fq "Invalid sshfling policy file" "$tmp/stderr" \
    || fail "$name did not report a stable invalid-policy error"
done

cat >"$tmp/jq-empty-success" <<'SH'
#!/bin/sh
exit 0
SH
chmod 0755 "$tmp/jq-empty-success"
set +e
run_wrapper "$tmp/normalized.json" 1 native-default "$tmp/jq-empty-success"
empty_success_code="$?"
set -e
[[ "$empty_success_code" -eq 2 ]] || fail "empty successful jq output returned $empty_success_code instead of 2"
grep -Fq "Invalid sshfling policy file" "$tmp/stderr" \
  || fail "empty successful jq output did not report a stable invalid-policy error"

assert_allowed "$tmp/missing.json" 5

set +e
run_wrapper "$tmp/normalized.json" 1 native-default sshfling-jq-missing
missing_jq_code="$?"
set -e
[[ "$missing_jq_code" -eq 127 ]] || fail "missing jq returned $missing_jq_code instead of 127"
[[ ! -e "$tmp/ran" ]] || fail "missing jq still ran the session command"
grep -Fq "jq is required" "$tmp/stderr" || fail "missing jq error was not actionable"

session_started="$tmp/session-started"
session_rejected="$tmp/session-rejected"
session_after="$tmp/session-after"
mkdir -p "$tmp/untrusted-bin"
cat >"$tmp/untrusted-bin/flock" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$tmp/untrusted-bin/date" <<'SH'
#!/bin/sh
printf '1\n'
SH
chmod 0755 "$tmp/untrusted-bin/flock" "$tmp/untrusted-bin/date"
untrusted_path="$tmp/untrusted-bin:/usr/local/bin:/usr/bin:/bin"
unlock_attack="flock -u 10 >/dev/null 2>&1 || true; if command -v lockf >/dev/null 2>&1; then lockf -s -t 0 10 >/dev/null 2>&1 || true; fi;"
if (( EUID != 0 )); then
  unlock_attack+=" rm -f $(printf '%q' "$lock_file") >/dev/null 2>&1 || true;"
fi

PATH="$untrusted_path" \
  SSH_ORIGINAL_COMMAND="$unlock_attack printf started > $(printf '%q' "$session_started"); sleep 2" \
  "$wrapper" \
    --lock-root "$lock_root" \
    --max-seconds 10 \
    --max-connections 1 \
    --username lock-policy-test \
    --login-user "$test_user" \
    --policy-file "$tmp/missing.json" \
    >"$tmp/session-first.out" 2>"$tmp/session-first.err" &
session_pid="$!"
for _ in {1..50}; do
  [[ -e "$session_started" ]] && break
  sleep 0.1
done
[[ -e "$session_started" ]] \
  || fail "root-managed connection-limit holder did not start: $(cat "$tmp/session-first.err")"
[[ -e "$lock_file" ]] || fail "session command unlinked its protected lock file"

inode_before="$(inode_number "$lock_file")"
as_root "$wrapper" --lock-root "$lock_root" --provision-locks "$test_user" >"$tmp/reprovision.out" \
  || fail "idempotent lock reprovisioning failed"
inode_after="$(inode_number "$lock_file")"
[[ "$inode_before" == "$inode_after" ]] || fail "lock reprovisioning replaced an active slot inode"

set +e
PATH="$untrusted_path" \
  SSH_ORIGINAL_COMMAND="printf rejected > $(printf '%q' "$session_rejected")" \
  "$wrapper" \
    --lock-root "$lock_root" \
    --max-seconds 10 \
    --max-connections 1 \
    --username lock-policy-test \
    --login-user "$test_user" \
    --policy-file "$tmp/missing.json" \
    >"$tmp/session-second.out" 2>"$tmp/session-second.err"
session_reject_code="$?"
set -e
[[ "$session_reject_code" -eq 75 ]] \
  || fail "root-managed connection limit returned $session_reject_code instead of 75"
[[ ! -e "$session_rejected" ]] || fail "root-managed connection limit allowed a second session"
grep -Fq "Maximum active sshfling sessions reached" "$tmp/session-second.err" \
  || fail "root-managed connection limit did not report the rejection"
wait "$session_pid" \
  || fail "root-managed connection-limit holder failed: $(cat "$tmp/session-first.err")"

SSH_ORIGINAL_COMMAND="printf after > $(printf '%q' "$session_after")" \
  "$wrapper" \
    --lock-root "$lock_root" \
    --max-seconds 10 \
    --max-connections 1 \
    --username lock-policy-test \
    --login-user "$test_user" \
    --policy-file "$tmp/missing.json" \
    >"$tmp/session-third.out" 2>"$tmp/session-third.err"
[[ -e "$session_after" ]] || fail "root-managed connection slot was not released"

as_root mv "$lock_file" "$lock_file.missing-test"
set +e
run_wrapper "$tmp/missing.json" 1 "$test_user"
missing_slot_code="$?"
set -e
[[ "$missing_slot_code" -eq 75 ]] || fail "missing slot returned $missing_slot_code instead of 75"
grep -Fq "Missing or unsafe sshfling session lock file" "$tmp/stderr" \
  || fail "missing slot did not fail closed with an actionable error"
as_root mv "$lock_file.missing-test" "$lock_file"

echo "native session policy validation ok"
