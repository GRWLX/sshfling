#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
helper="$repo_root/native/sshfling-unix-identity"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fakebin="$tmp/bin"
minimalbin="$tmp/minimal-bin"
command_log="$tmp/commands.log"
mkdir -p "$fakebin" "$minimalbin"
: >"$command_log"

fail() {
  echo "native Unix identity validation failed: $*" >&2
  exit 1
}

expect_failure() {
  local label="$1"
  shift
  if "$@" >"$tmp/failure.out" 2>"$tmp/failure.err"; then
    fail "$label unexpectedly succeeded"
  fi
  if grep -q '^result' "$tmp/failure.out"; then
    fail "$label emitted a result record while failing"
  fi
}

cat >"$fakebin/uname" <<'SH'
#!/bin/sh
[ "${1:-}" = -s ] || exit 2
printf '%s\n' "${FAKE_UNAME:-Linux}"
SH
cp "$fakebin/uname" "$minimalbin/uname"

cat >"$fakebin/getent" <<'SH'
#!/bin/sh
set -eu
[ "${1:-}" = passwd ] && [ "$#" -eq 2 ] || exit 64
printf 'getent %s\n' "$2" >>"$FAKE_COMMAND_LOG"
case "${FAKE_GETENT_MODE:-present}" in
  present) printf '%s:x:1201:1202::/srv/%s:/bin/sh\n' "$2" "$2" ;;
  missing) exit 2 ;;
  empty) exit 0 ;;
  malformed) printf '%s:x:not-a-uid:1202::/srv/%s:/bin/sh\n' "$2" "$2" ;;
  mismatch) printf 'different:x:1201:1202::/srv/different:/bin/sh\n' ;;
  multiple)
    printf '%s:x:1201:1202::/srv/%s:/bin/sh\n' "$2" "$2"
    printf '%s:x:1203:1204::/other:/bin/sh\n' "$2"
    ;;
  error) exit 70 ;;
  *) exit 64 ;;
esac
SH

cat >"$fakebin/dscacheutil" <<'SH'
#!/bin/sh
set -eu
[ "$#" -eq 5 ] && [ "$1" = -q ] && [ "$2" = user ] && \
  [ "$3" = -a ] && [ "$4" = name ] || exit 64
username=$5
printf 'dscacheutil %s\n' "$username" >>"$FAKE_COMMAND_LOG"
case "${FAKE_DSCACHEUTIL_MODE:-present}" in
  present)
    printf 'name: %s\npassword: *\nuid: 501\ngid: 20\ndir: /Users/%s\nshell: /bin/zsh\n' \
      "$username" "$username"
    ;;
  missing) exit 0 ;;
  malformed) printf 'name: %s\nuid: 501\ndir: /Users/%s\n' "$username" "$username" ;;
  duplicate) printf 'name: %s\nname: %s\nuid: 501\ngid: 20\ndir: /Users/%s\n' "$username" "$username" "$username" ;;
  error) exit 75 ;;
  *) exit 64 ;;
esac
SH

cat >"$fakebin/dscl" <<'SH'
#!/bin/sh
set -eu
[ "${1:-}" = . ] || exit 64
case "${2:-}" in
  -list)
    [ "$#" -eq 3 ] && [ "$3" = /Users ] || exit 64
    printf 'dscl list\n' >>"$FAKE_COMMAND_LOG"
    case "${FAKE_DSCL_MODE:-present}" in
      present|malformed|read-error) printf 'daemon\n%s\nnobody\n' "$FAKE_DSCL_USER" ;;
      missing) printf 'daemon\nnobody\n' ;;
      list-error) exit 74 ;;
      *) exit 64 ;;
    esac
    ;;
  -read)
    [ "$#" -eq 7 ] || exit 64
    username=${3#/Users/}
    printf 'dscl read %s\n' "$username" >>"$FAKE_COMMAND_LOG"
    case "${FAKE_DSCL_MODE:-present}" in
      present)
        printf 'NFSHomeDirectory: /Users/%s\nPrimaryGroupID: 20\nRecordName: %s\nUniqueID: 502\n' \
          "$username" "$username"
        ;;
      malformed) printf 'RecordName: %s\nUniqueID: invalid\nPrimaryGroupID: 20\n' "$username" ;;
      read-error) exit 76 ;;
      *) exit 64 ;;
    esac
    ;;
  *) exit 64 ;;
esac
SH
chmod 0755 "$fakebin"/* "$minimalbin/uname"
ln -s "$(command -v awk)" "$minimalbin/awk"

export FAKE_COMMAND_LOG="$command_log"
export FAKE_UNAME=Linux
export FAKE_GETENT_MODE=present
linux_identity="$(PATH="$fakebin:/usr/bin:/bin" "$helper" identity native)"
[[ "$linux_identity" == $'result\tstatus=present\tuser=native\tuid=1201\tgid=1202\thome=/srv/native' ]] \
  || fail "Linux identity output was not stable: $linux_identity"

export FAKE_GETENT_MODE=missing
[[ "$(PATH="$fakebin:/usr/bin:/bin" "$helper" identity absent)" == \
  $'result\tstatus=missing\tuser=absent' ]] || fail "Linux missing result was not stable"

for mode in empty malformed mismatch multiple error; do
  export FAKE_GETENT_MODE="$mode"
  expect_failure "Linux $mode backend" env PATH="$fakebin:/usr/bin:/bin" \
    "$helper" identity native
done
expect_failure "invalid username" env PATH="$fakebin:/usr/bin:/bin" \
  "$helper" identity 'Bad.User'
expect_failure "missing getent" env FAKE_UNAME=Linux PATH="$minimalbin" \
  "$helper" identity native

export FAKE_UNAME=Darwin
export FAKE_DSCACHEUTIL_MODE=present
darwin_identity="$(PATH="$fakebin:/usr/bin:/bin" "$helper" identity macuser)"
[[ "$darwin_identity" == $'result\tstatus=present\tuser=macuser\tuid=501\tgid=20\thome=/Users/macuser' ]] \
  || fail "Darwin dscacheutil output was not stable: $darwin_identity"

export FAKE_DSCACHEUTIL_MODE=missing
[[ "$(PATH="$fakebin:/usr/bin:/bin" "$helper" identity absent)" == \
  $'result\tstatus=missing\tuser=absent' ]] || fail "Darwin missing result was not stable"

for mode in malformed duplicate error; do
  export FAKE_DSCACHEUTIL_MODE="$mode"
  expect_failure "Darwin dscacheutil $mode backend" \
    env PATH="$fakebin:/usr/bin:/bin" "$helper" identity macuser
done

dsclbin="$tmp/dscl-bin"
mkdir -p "$dsclbin"
cp "$fakebin/uname" "$fakebin/dscl" "$dsclbin/"
chmod 0755 "$dsclbin"/*
export FAKE_DSCL_USER=directoryuser
export FAKE_DSCL_MODE=present
dscl_identity="$(PATH="$dsclbin:/usr/bin:/bin" "$helper" identity directoryuser)"
[[ "$dscl_identity" == $'result\tstatus=present\tuser=directoryuser\tuid=502\tgid=20\thome=/Users/directoryuser' ]] \
  || fail "Darwin dscl output was not stable: $dscl_identity"

export FAKE_DSCL_MODE=missing
[[ "$(PATH="$dsclbin:/usr/bin:/bin" "$helper" identity absent)" == \
  $'result\tstatus=missing\tuser=absent' ]] || fail "dscl missing result was not stable"
if grep -Fq 'dscl read absent' "$command_log"; then
  fail "dscl read ran for an account absent from the directory listing"
fi

for mode in malformed list-error read-error; do
  export FAKE_DSCL_MODE="$mode"
  expect_failure "Darwin dscl $mode backend" env PATH="$dsclbin:/usr/bin:/bin" \
    "$helper" identity directoryuser
done
expect_failure "missing Darwin identity tools" \
  env FAKE_UNAME=Darwin PATH="$minimalbin" "$helper" identity macuser
expect_failure "unsupported operating system" \
  env FAKE_UNAME=Plan9 PATH="$fakebin:/usr/bin:/bin" "$helper" identity native

echo "native Unix identity validation ok"
