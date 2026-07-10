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
cat >"$minimalbin/getent" <<'SH'
#!/bin/sh
exit 127
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
chmod 0755 "$fakebin"/* "$minimalbin/uname" "$minimalbin/getent"
ln -s "$(command -v awk)" "$minimalbin/awk"

export FAKE_COMMAND_LOG="$command_log"
export FAKE_UNAME=Linux
export FAKE_GETENT_MODE=present
poisonbin="$tmp/poison-bin"
mkdir -p "$poisonbin"
cat >"$poisonbin/uname" <<EOF
#!/bin/sh
printf '%s\n' poisoned >"$tmp/poisoned-uname"
exit 70
EOF
cat >"$poisonbin/getent" <<EOF
#!/bin/sh
printf '%s\n' poisoned >"$tmp/poisoned-getent"
exit 70
EOF
chmod 0755 "$poisonbin"/*
PATH="$poisonbin:/usr/bin:/bin" "$helper" identity root >/dev/null
[[ ! -e "$tmp/poisoned-uname" && ! -e "$tmp/poisoned-getent" ]] \
  || fail "caller PATH selected an identity backend tool"

relative_fakebin="${fakebin#/}"
set +e
SSHFLING_NATIVE_TOOL_DIR="$relative_fakebin" \
  "$helper" identity native >"$tmp/relative-tool.out" 2>"$tmp/relative-tool.err"
relative_tool_status="$?"
SSHFLING_NATIVE_TOOL_DIR="$tmp/b*" \
  "$helper" identity native >"$tmp/glob-tool.out" 2>"$tmp/glob-tool.err"
glob_tool_status="$?"
set -e
[[ "$relative_tool_status" -eq 77 ]] \
  || fail "relative native tool directory returned $relative_tool_status instead of 77"
[[ "$glob_tool_status" -eq 77 ]] \
  || fail "globbed native tool directory returned $glob_tool_status instead of 77"

short_mode_bin="$tmp/short-mode-bin"
mkdir -p "$short_mode_bin"
chmod 0075 "$short_mode_bin" # release-security: intentional-world-writable-fixture
set +e
SSHFLING_NATIVE_TOOL_DIR="$short_mode_bin" \
  "$helper" identity native >"$tmp/short-mode.out" 2>"$tmp/short-mode.err"
short_mode_status="$?"
set -e
[[ "$short_mode_status" -eq 77 ]] \
  || fail "short writable directory mode returned $short_mode_status instead of 77"

sticky_tool_bin="$tmp/sticky-tool-bin"
mkdir -p "$sticky_tool_bin"
chmod 1777 "$sticky_tool_bin" # release-security: intentional-world-writable-fixture
for unsafe_tool_path in \
  "$sticky_tool_bin/" \
  "${sticky_tool_bin%/*}//${sticky_tool_bin##*/}"; do
  set +e
  SSHFLING_NATIVE_TOOL_DIR="$unsafe_tool_path" \
    "$helper" identity native >"$tmp/noncanonical.out" 2>"$tmp/noncanonical.err"
  noncanonical_status="$?"
  set -e
  [[ "$noncanonical_status" -eq 77 ]] \
    || fail "non-canonical writable directory returned $noncanonical_status instead of 77: $unsafe_tool_path"
done

native_env=(SSHFLING_NATIVE_TOOL_DIR="$fakebin")
linux_identity="$(env "${native_env[@]}" "$helper" identity native)"
[[ "$linux_identity" == $'result\tstatus=present\tuser=native\tuid=1201\tgid=1202\thome=/srv/native' ]] \
  || fail "Linux identity output was not stable: $linux_identity"

extra_tool_bin="$tmp/extra-tool-bin"
mkdir -p "$extra_tool_bin"
linux_path_identity="$(SSHFLING_NATIVE_TOOL_PATH="$extra_tool_bin:$fakebin" \
  "$helper" identity native)"
[[ "$linux_path_identity" == "$linux_identity" ]] \
  || fail "native tool path changed or discarded identity arguments: $linux_path_identity"
expect_failure "empty native tool path entry" env \
  SSHFLING_NATIVE_TOOL_PATH="$fakebin::$extra_tool_bin" "$helper" identity native

export FAKE_GETENT_MODE=missing
[[ "$(env "${native_env[@]}" "$helper" identity absent)" == \
  $'result\tstatus=missing\tuser=absent' ]] || fail "Linux missing result was not stable"

for mode in empty malformed mismatch multiple error; do
  export FAKE_GETENT_MODE="$mode"
  expect_failure "Linux $mode backend" env "${native_env[@]}" \
    "$helper" identity native
done
expect_failure "invalid username" env "${native_env[@]}" \
  "$helper" identity 'Bad.User'
expect_failure "missing getent" env FAKE_UNAME=Linux SSHFLING_NATIVE_TOOL_DIR="$minimalbin" \
  "$helper" identity native

# Exercise the file backend directly because the host running this test normally
# provides getent. The production dispatcher reaches this function only when
# getent is absent from its fixed trusted PATH.
helper_library="$tmp/sshfling-unix-identity-library"
awk '/^if \[ "\$#" -ne 2 \]/{ exit } { print }' "$helper" >"$helper_library"
passwd_identity="$(sh -c '. "$1"; lookup_passwd_file root' sh "$helper_library")"
[[ "$passwd_identity" == $'result\tstatus=present\tuser=root\tuid=0\t'* ]] \
  || fail "passwd file identity output was not stable: $passwd_identity"
passwd_missing="$(sh -c '. "$1"; lookup_passwd_file sshflingmissingidentity' sh "$helper_library")"
[[ "$passwd_missing" == $'result\tstatus=missing\tuser=sshflingmissingidentity' ]] \
  || fail "passwd file missing result was not stable: $passwd_missing"

export FAKE_UNAME=Darwin
export FAKE_DSCACHEUTIL_MODE=present
darwin_identity="$(env "${native_env[@]}" "$helper" identity macuser)"
[[ "$darwin_identity" == $'result\tstatus=present\tuser=macuser\tuid=501\tgid=20\thome=/Users/macuser' ]] \
  || fail "Darwin dscacheutil output was not stable: $darwin_identity"

export FAKE_DSCACHEUTIL_MODE=missing
[[ "$(env "${native_env[@]}" "$helper" identity absent)" == \
  $'result\tstatus=missing\tuser=absent' ]] || fail "Darwin missing result was not stable"

for mode in malformed duplicate error; do
  export FAKE_DSCACHEUTIL_MODE="$mode"
  expect_failure "Darwin dscacheutil $mode backend" \
    env "${native_env[@]}" "$helper" identity macuser
done

dsclbin="$tmp/dscl-bin"
mkdir -p "$dsclbin"
cp "$fakebin/uname" "$fakebin/dscl" "$dsclbin/"
chmod 0755 "$dsclbin"/*
export FAKE_DSCL_USER=directoryuser
export FAKE_DSCL_MODE=present
dscl_identity="$(SSHFLING_NATIVE_TOOL_DIR="$dsclbin" "$helper" identity directoryuser)"
[[ "$dscl_identity" == $'result\tstatus=present\tuser=directoryuser\tuid=502\tgid=20\thome=/Users/directoryuser' ]] \
  || fail "Darwin dscl output was not stable: $dscl_identity"

export FAKE_DSCL_MODE=missing
[[ "$(SSHFLING_NATIVE_TOOL_DIR="$dsclbin" "$helper" identity absent)" == \
  $'result\tstatus=missing\tuser=absent' ]] || fail "dscl missing result was not stable"
if grep -Fq 'dscl read absent' "$command_log"; then
  fail "dscl read ran for an account absent from the directory listing"
fi

for mode in malformed list-error read-error; do
  export FAKE_DSCL_MODE="$mode"
  expect_failure "Darwin dscl $mode backend" env SSHFLING_NATIVE_TOOL_DIR="$dsclbin" \
    "$helper" identity directoryuser
done
expect_failure "missing Darwin identity tools" \
  env FAKE_UNAME=Darwin SSHFLING_NATIVE_TOOL_DIR="$minimalbin" "$helper" identity macuser
expect_failure "unsupported operating system" \
  env FAKE_UNAME=Plan9 "${native_env[@]}" "$helper" identity native

echo "native Unix identity validation ok"
