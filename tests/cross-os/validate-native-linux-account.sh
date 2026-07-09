#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/native/sshfling-linux-account"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
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
if [[ "${FAKE_GETENT_ERROR_USER:-}" == "$2" ]]; then exit 70; fi
awk -F: -v user="$2" '$1 == user { print; found=1; exit } END { if (!found) exit 2 }' "$FAKE_PASSWD_DB"
SH
cat >"$fakebin/useradd" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'useradd' >>"$FAKE_COMMAND_LOG"
printf ' %q' "$@" >>"$FAKE_COMMAND_LOG"
printf '\n' >>"$FAKE_COMMAND_LOG"
username="${!#}"
if [[ "${FAKE_USERADD_INVISIBLE:-0}" == 1 ]]; then exit 0; fi
printf '%s:x:1200:1200::/home/%s:/bin/sh\n' "$username" "$username" >>"$FAKE_PASSWD_DB"
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

export PATH="$fakebin:$PATH"
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

if (( EUID != 0 )); then
  if "$helper" create newuser /bin/sh >/dev/null 2>&1; then
    fail "non-root account mutation was accepted"
  fi
  echo "native Linux account validation ok (mutation tests require root)"
  exit 0
fi

"$helper" create native /bin/sh | grep -Fq $'status=present\tuser=native\tcreated=false'
"$helper" create-certificate-user native /bin/sh | grep -Fq $'status=present\tuser=native\tcreated=false'
"$helper" create newuser /bin/sh | grep -Fq $'status=created\tuser=newuser\tcreated=true'
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

certificate_output="$("$helper" create-certificate-user certuser /bin/sh)"
[[ "$certificate_output" == *$'status=created\tuser=certuser\tcreated=true\tunlocked=true'* ]] \
  || fail "certificate-user output was not stable: $certificate_output"
grep -Fq 'useradd --create-home --shell /bin/sh --password' "$command_log"
if grep -Fq 'generated-secret' "$command_log"; then fail "generated certificate-user password leaked"; fi

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
