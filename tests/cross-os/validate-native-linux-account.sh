#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/native/sshfling-linux-account"
tmp="$(mktemp -d)"
mutable_target_parent=""
trap 'rm -rf "$tmp" "${mutable_target_parent:-}"' EXIT
fakebin="$tmp/bin"
passwd_db="$tmp/passwd"
command_log="$tmp/commands.log"
mkdir -p "$fakebin"
: >"$passwd_db"
: >"$command_log"

fail() {
  echo "native Linux account validation failed: $*" >&2
  exit 1
}

cat >"$fakebin/getent" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == passwd && "$#" -eq 2 ]] || exit 2
if [[ "${FAKE_GETENT_ERROR_USER:-}" == "$2" ]]; then exit "${FAKE_GETENT_ERROR_CODE:-70}"; fi
awk -F: -v user="$2" '$1 == user { print; found=1; exit } END { if (!found) exit 2 }' "$FAKE_PASSWD_DB"
SH
cat >"$fakebin/useradd" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'useradd' >>"$FAKE_COMMAND_LOG"
printf ' %q' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
username="${!#}"
shell_path=/bin/sh
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --shell)
      shell_path="$2"
      shift 2
      ;;
    *) shift ;;
  esac
done
shell_path="${FAKE_USERADD_SHELL_OVERRIDE:-$shell_path}"
if [[ "${FAKE_USERADD_INVISIBLE:-0}" == 1 ]]; then exit 0; fi
printf '%s:x:1200:1200::/home/%s:%s\n' "$username" "$username" "$shell_path" >>"$FAKE_PASSWD_DB"
SH
cat >"$fakebin/chpasswd" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
IFS= read -r value
printf '%s\n' "$value" >"$FAKE_PASSWORD_INPUT"
printf 'chpasswd\n' >>"$FAKE_COMMAND_LOG"
SH
cat >"$fakebin/usermod" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'usermod' >>"$FAKE_COMMAND_LOG"
printf ' %q' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
if [[ "${1:-}" == --lock && "${FAKE_USERMOD_LOCK_FAIL:-0}" == 1 ]]; then exit 1; fi
if [[ "${1:-}" == --unlock && "${FAKE_USERMOD_UNLOCK_FAIL:-0}" == 1 ]]; then exit 42; fi
SH
cat >"$fakebin/passwd" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'passwd' >>"$FAKE_COMMAND_LOG"
printf ' %q' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
SH
cat >"$fakebin/chage" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'chage' >>"$FAKE_COMMAND_LOG"
printf ' %q' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
if [[ "${FAKE_CHAGE_FAIL:-0}" == 1 ]]; then exit 43; fi
SH
cat >"$fakebin/userdel" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'userdel' >>"$FAKE_COMMAND_LOG"
printf ' %q' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
if [[ "${1:-}" == --remove && "${FAKE_USERDEL_REMOVE_FAIL:-0}" == 1 ]]; then exit 1; fi
username="${!#}"
if [[ "${FAKE_USERDEL_KEEP:-0}" == 1 ]]; then exit 0; fi
if [[ "${FAKE_USERDEL_REMOVE_AFTER_DELETE_FAIL:-0}" == 1 && "${1:-}" != --remove ]] \
  && ! awk -F: -v user="$username" '$1 == user { found=1 } END { exit(found ? 0 : 1) }' "$FAKE_PASSWD_DB"; then
  exit 6
fi
awk -F: -v user="$username" '$1 != user' "$FAKE_PASSWD_DB" >"$FAKE_PASSWD_DB.tmp"
mv "$FAKE_PASSWD_DB.tmp" "$FAKE_PASSWD_DB"
if [[ "${1:-}" == --remove && "${FAKE_USERDEL_REMOVE_AFTER_DELETE_FAIL:-0}" == 1 ]]; then exit 1; fi
SH
cat >"$fakebin/openssl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  rand)
    [[ "${FAKE_OPENSSL_RAND_FAIL:-0}" != 1 ]] || exit 1
    printf 'generated-secret\n'
    ;;
  passwd)
    IFS= read -r password
    [[ -n "$password" ]]
    if [[ "${FAKE_OPENSSL_PASSWD_EMPTY:-0}" == 1 ]]; then exit 0; fi
    printf '%s\n' '$6$native-test-hash'
    ;;
  *) exit 2 ;;
esac
SH
chmod 0755 "$fakebin"/*

poisonbin="$tmp/poison-bin"
mkdir -p "$poisonbin"
cat >"$poisonbin/bash" <<EOF
#!/bin/sh
printf '%s\n' poisoned >"$tmp/poisoned-bash"
exec /bin/bash "\$@"
EOF
cat >"$poisonbin/getent" <<EOF
#!/bin/sh
printf '%s\n' poisoned >"$tmp/poisoned-getent"
exit 70
EOF
chmod 0755 "$poisonbin"/*
PATH="$poisonbin:/usr/bin:/bin" SSHFLING_NATIVE_TOOL_DIR='' \
  "$helper" exists root >/dev/null
[[ ! -e "$tmp/poisoned-bash" ]] || fail "caller PATH selected the helper interpreter"
[[ ! -e "$tmp/poisoned-getent" ]] || fail "caller PATH selected an account backend tool"
cat >"$tmp/bash-env" <<EOF
printf '%s\n' injected >"$tmp/bash-env-ran"
EOF
BASH_ENV="$tmp/bash-env" "$helper" exists root >/dev/null
[[ ! -e "$tmp/bash-env-ran" ]] || fail "BASH_ENV executed before helper hardening"

sticky_tool_dir="$tmp/sticky-tool-dir"
mkdir -p "$sticky_tool_dir"
cp "$poisonbin/getent" "$sticky_tool_dir/getent"
chmod 0755 "$sticky_tool_dir/getent"
chmod 1777 "$sticky_tool_dir" # release-security: intentional-world-writable-fixture
set +e
SSHFLING_NATIVE_TOOL_DIR="$sticky_tool_dir" \
  "$helper" exists root >"$tmp/sticky-tool.out" 2>"$tmp/sticky-tool.err"
sticky_tool_status="$?"
set -e
[[ "$sticky_tool_status" -eq 77 ]] \
  || fail "sticky writable native tool directory returned $sticky_tool_status instead of 77"
[[ ! -e "$tmp/poisoned-getent" ]] \
  || fail "sticky writable native tool directory executed a backend tool"

for unsafe_tool_path in \
  "$sticky_tool_dir/" \
  "${sticky_tool_dir%/*}//${sticky_tool_dir##*/}"; do
  set +e
  SSHFLING_NATIVE_TOOL_DIR="$unsafe_tool_path" \
    "$helper" exists root >"$tmp/noncanonical-tool.out" 2>"$tmp/noncanonical-tool.err"
  noncanonical_tool_status="$?"
  set -e
  [[ "$noncanonical_tool_status" -eq 77 ]] \
    || fail "non-canonical writable tool directory returned $noncanonical_tool_status instead of 77: $unsafe_tool_path"
done
set +e
SSHFLING_NATIVE_TOOL_PATH="$fakebin:" \
  "$helper" exists root >"$tmp/empty-tool-path.out" 2>"$tmp/empty-tool-path.err"
empty_tool_path_status="$?"
set -e
[[ "$empty_tool_path_status" -eq 77 ]] \
  || fail "trailing empty native tool path entry returned $empty_tool_path_status instead of 77"

if (( EUID == 0 )); then
  mutable_target_parent="$(mktemp -d /tmp/sshfling-native-writable.XXXXXXXX)"
  mkdir -p "$mutable_target_parent/root-tools"
  cp "$poisonbin/getent" "$mutable_target_parent/root-tools/getent"
  chmod 0755 "$mutable_target_parent/root-tools" "$mutable_target_parent/root-tools/getent"
  chmod 0777 "$mutable_target_parent" # release-security: intentional-world-writable-fixture
  ln -s "$mutable_target_parent/root-tools" "$tmp/root-tool-link"
  set +e
  SSHFLING_NATIVE_TOOL_DIR="$tmp/root-tool-link" \
    "$helper" exists root >"$tmp/symlink-tool.out" 2>"$tmp/symlink-tool.err"
  symlink_tool_status="$?"
  set -e
  [[ "$symlink_tool_status" -eq 77 ]] \
    || fail "native tool symlink with writable target ancestry returned $symlink_tool_status instead of 77"
fi

export SSHFLING_NATIVE_TOOL_DIR="$fakebin"
export FAKE_PASSWD_DB="$passwd_db"
export FAKE_COMMAND_LOG="$command_log"
export FAKE_PASSWORD_INPUT="$tmp/password.input"

"$helper" identity missing | grep -Fq $'result\tstatus=missing\tuser=missing'
printf 'native:x:1201:1202::/srv/native:/bin/bash\n' >>"$passwd_db"
identity="$($helper identity native)"
[[ "$identity" == *$'status=present\tuser=native\tuid=1201\tgid=1202\thome=/srv/native'* ]] \
  || fail "identity output was not stable: $identity"
"$helper" exists native | grep -Fq $'status=present\tuser=native\texists=true'
if "$helper" exists absent >/dev/null; then fail "missing account reported as present"; fi
if "$helper" identity 'Bad.User' >/dev/null 2>&1; then fail "invalid username was accepted"; fi

set +e
FAKE_GETENT_ERROR_USER=backendfail "$helper" exists backendfail >"$tmp/getent-error.out" 2>"$tmp/getent-error.err"
getent_error_code="$?"
set -e
[[ "$getent_error_code" -eq 70 ]] || fail "getent error returned $getent_error_code instead of 70"
[[ ! -s "$tmp/getent-error.out" ]] || fail "getent error emitted a missing-account result"

set +e
FAKE_GETENT_ERROR_USER=backendone FAKE_GETENT_ERROR_CODE=1 \
  "$helper" exists backendone >"$tmp/getent-one.out" 2>"$tmp/getent-one.err"
getent_one_code="$?"
set -e
[[ "$getent_one_code" -eq 70 ]] || fail "getent exit 1 collided with missing-account status"
[[ ! -s "$tmp/getent-one.out" ]] || fail "getent exit 1 emitted a missing-account result"

if (( EUID != 0 )); then
  if "$helper" create newuser /bin/sh >/dev/null 2>&1; then
    fail "non-root account mutation was accepted"
  fi
  echo "native Linux account validation ok (mutation tests require root)"
  exit 0
fi

unsafe_shell="$tmp/unsafe-shell"
printf '#!/bin/sh\nexit 0\n' >"$unsafe_shell"
chmod 0777 "$unsafe_shell" # release-security: intentional-world-writable-fixture
if "$helper" create unsafeshell "$unsafe_shell" >/dev/null 2>&1; then
  fail "group- or world-writable login shell was accepted"
fi
if grep -F 'useradd' "$command_log" | grep -Fq 'unsafeshell'; then
  fail "useradd ran before login-shell ownership validation"
fi
unsafe_parent="$tmp/unsafe-parent"
mkdir -p "$unsafe_parent"
printf '#!/bin/sh\nexit 0\n' >"$unsafe_parent/login-shell"
chmod 0777 "$unsafe_parent" # release-security: intentional-world-writable-fixture
chmod 0755 "$unsafe_parent/login-shell"
if "$helper" create unsafeparent "$unsafe_parent/login-shell" >/dev/null 2>&1; then
  fail "login shell under a writable parent directory was accepted"
fi
if grep -F 'useradd' "$command_log" | grep -Fq 'unsafeparent'; then
  fail "useradd ran before login-shell parent validation"
fi
if (( EUID == 0 )); then
  printf '#!/bin/sh\nexit 0\n' >"$mutable_target_parent/login-shell"
  chmod 0755 "$mutable_target_parent/login-shell"
  ln -s "$mutable_target_parent/login-shell" "$tmp/unsafe-shell-link"
  if "$helper" create unsafesymlink "$tmp/unsafe-shell-link" >/dev/null 2>&1; then
    fail "login-shell symlink with writable target ancestry was accepted"
  fi
  if grep -F 'useradd' "$command_log" | grep -Fq 'unsafesymlink'; then
    fail "useradd ran before resolved login-shell parent validation"
  fi
fi

"$helper" create native /bin/sh | grep -Fq $'status=present\tuser=native\tcreated=false'
"$helper" create-certificate-user native /bin/sh | grep -Fq $'status=present\tuser=native\tcreated=false'
"$helper" create newuser /bin/sh | grep -Fq $'status=created\tuser=newuser\tcreated=true\tshell=/bin/sh'
"$helper" identity newuser | grep -Fq $'status=present\tuser=newuser'
printf '%s\n' 'secret-value' | "$helper" set-password newuser | grep -Fq 'password_set=true'
grep -Fxq 'newuser:secret-value' "$tmp/password.input"
if grep -Fq 'secret-value' "$command_log"; then fail "password leaked into command arguments"; fi

if printf '%s\n' 'replacement' | FAKE_USERMOD_UNLOCK_FAIL=1 "$helper" set-password newuser >/dev/null 2>&1; then
  fail "password setup ignored a failed account unlock"
fi
if printf '%s\n' 'replacement' | FAKE_CHAGE_FAIL=1 "$helper" set-password newuser >/dev/null 2>&1; then
  fail "password setup ignored a failed expiry reset"
fi

FAKE_USERMOD_LOCK_FAIL=1 "$helper" lock newuser >"$tmp/lock.out"
grep -Fq $'attempt\taction=lock\ttool=usermod\treturncode=1' "$tmp/lock.out"
grep -Fq $'attempt\taction=lock\ttool=passwd\treturncode=0' "$tmp/lock.out"
grep -Fq $'result\tstatus=locked\tuser=newuser\tlocked=true\texpired=true' "$tmp/lock.out"

FAKE_USERDEL_REMOVE_FAIL=1 "$helper" delete newuser >"$tmp/delete.out"
grep -Fq $'attempt\taction=delete-home\ttool=userdel\treturncode=1' "$tmp/delete.out"
grep -Fq $'attempt\taction=delete\ttool=userdel\treturncode=0' "$tmp/delete.out"
grep -Fq $'result\tstatus=deleted\tuser=newuser\tdeleted=true' "$tmp/delete.out"
"$helper" identity newuser | grep -Fq $'status=missing\tuser=newuser'

if FAKE_USERADD_SHELL_OVERRIDE=/bin/bash "$helper" create wrongshell /bin/sh >/dev/null 2>&1; then
  fail "account creation accepted an unexpected login shell"
fi
"$helper" identity wrongshell | grep -Fq $'status=missing\tuser=wrongshell'
grep -Fq 'userdel --remove wrongshell' "$command_log"

set +e
FAKE_USERADD_SHELL_OVERRIDE=/bin/bash FAKE_USERDEL_KEEP=1 \
  "$helper" create stuckshell /bin/sh >"$tmp/stuck-shell.out" 2>"$tmp/stuck-shell.err"
stuck_shell_status="$?"
set -e
[[ "$stuck_shell_status" -ne 0 ]] || fail "account cleanup failure was reported as success"
grep -Fq $'result\tstatus=cleanup-failed\tuser=stuckshell\tcreated=true\tcleanup_confirmed=false' \
  "$tmp/stuck-shell.out"
"$helper" exists stuckshell >/dev/null
"$helper" delete stuckshell >/dev/null

"$helper" create keepuser /bin/sh >/dev/null
if FAKE_USERDEL_KEEP=1 "$helper" delete keepuser >/dev/null 2>&1; then
  fail "delete succeeded while the account remained visible"
fi
"$helper" exists keepuser >/dev/null
"$helper" delete keepuser >/dev/null

"$helper" create partialdelete /bin/sh >/dev/null
FAKE_USERDEL_REMOVE_AFTER_DELETE_FAIL=1 "$helper" delete partialdelete >"$tmp/partial-delete.out"
grep -Fq $'attempt\taction=delete-home\ttool=userdel\treturncode=1' "$tmp/partial-delete.out"
grep -Fq $'result\tstatus=deleted\tuser=partialdelete\tdeleted=true' "$tmp/partial-delete.out"

printf 'root:x:0:0::/root:/bin/bash\n' >>"$passwd_db"
if "$helper" lock root >/dev/null 2>&1; then fail "root-equivalent account mutation was accepted"; fi
printf 'leadingzero:x:00:1200::/home/leadingzero:/bin/sh\n' >>"$passwd_db"
if printf '%s\n' replacement | "$helper" set-password leadingzero >/dev/null 2>&1; then
  fail "a leading-zero uid bypassed canonical identity validation"
fi

certificate_output="$("$helper" create-certificate-user certuser /bin/sh)"
[[ "$certificate_output" == *$'status=created\tuser=certuser\tcreated=true\tunlocked=true'* ]] \
  || fail "certificate-user output was not stable: $certificate_output"
[[ "$certificate_output" == *$'shell=/bin/sh'* ]] \
  || fail "certificate-user output omitted its verified shell: $certificate_output"
grep -Fq 'useradd --create-home --shell /bin/sh --password' "$command_log"
if grep -Fq 'generated-secret' "$command_log"; then fail "generated certificate-user password leaked"; fi

set +e
FAKE_USERADD_SHELL_OVERRIDE=/bin/bash FAKE_USERDEL_KEEP=1 \
  "$helper" create-certificate-user certstuck /bin/sh \
  >"$tmp/cert-stuck.out" 2>"$tmp/cert-stuck.err"
cert_stuck_status="$?"
set -e
[[ "$cert_stuck_status" -ne 0 ]] || fail "certificate account cleanup failure was reported as success"
grep -Fq $'result\tstatus=cleanup-failed\tuser=certstuck\tcreated=true\tcleanup_confirmed=false' \
  "$tmp/cert-stuck.out"
"$helper" exists certstuck >/dev/null
"$helper" delete certstuck >/dev/null

if FAKE_OPENSSL_RAND_FAIL=1 "$helper" create-certificate-user hashfail /bin/sh >/dev/null 2>&1; then
  fail "certificate user was created without a password hash"
fi
"$helper" identity hashfail | grep -Fq $'status=missing\tuser=hashfail'
if grep -F 'useradd' "$command_log" | grep -Fq 'hashfail'; then
  fail "useradd ran before password hash generation completed"
fi

if FAKE_OPENSSL_PASSWD_EMPTY=1 "$helper" create-certificate-user emptyhash /bin/sh >/dev/null 2>&1; then
  fail "certificate user was created with an empty password hash"
fi
if grep -F 'useradd' "$command_log" | grep -Fq 'emptyhash'; then
  fail "useradd ran with an empty certificate-user password hash"
fi

if FAKE_USERADD_INVISIBLE=1 "$helper" create-certificate-user invisible /bin/sh >/dev/null 2>&1; then
  fail "certificate user creation accepted an invisible postcondition"
fi
grep -Fq 'userdel --remove invisible' "$command_log"

echo "native Linux account validation ok"
