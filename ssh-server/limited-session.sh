#!/usr/bin/env bash
set -euo pipefail

limit_file="/etc/ssh/session_limit_seconds"
session_seconds="$(tr -d '[:space:]' <"$limit_file" 2>/dev/null || true)"
max_allowed_seconds=86400

if [[ ! "$session_seconds" =~ ^[1-9][0-9]*$ ]]; then
  session_seconds=60
fi

if (( session_seconds > max_allowed_seconds )); then
  session_seconds="$max_allowed_seconds"
fi

status=0
timed_out=0
watchdog_pid=""
timeout_marker=""
session_deadline=$(( $(date +%s) + session_seconds ))
export SSHFLING_SESSION_ACTIVE=1
export SSHFLING_SESSION_EXPIRES_AT="$session_deadline"

kill_tree() {
  local pid="$1"
  local signal="$2"
  local children

  children="$(pgrep -P "$pid" 2>/dev/null || true)"
  for child in $children; do
    kill_tree "$child" "$signal"
  done

  kill "-$signal" "$pid" 2>/dev/null || true
}

run_limited() {
  timeout_marker="$(mktemp)"
  rm -f "$timeout_marker"

  "$@" &
  local command_pid="$!"

  (
    sleep "$session_seconds"
    if kill -0 "$command_pid" 2>/dev/null; then
      : >"$timeout_marker"
      kill_tree "$command_pid" TERM
      sleep 5
      kill_tree "$command_pid" KILL
    fi
  ) &
  watchdog_pid="$!"

  wait "$command_pid" || status=$?

  if [[ -e "$timeout_marker" ]]; then
    timed_out=1
    status=124
    if kill -0 "$watchdog_pid" 2>/dev/null; then
      kill "$watchdog_pid" 2>/dev/null || true
    fi
    wait "$watchdog_pid" 2>/dev/null || true
  elif kill -0 "$watchdog_pid" 2>/dev/null; then
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true
  fi

  rm -f "$timeout_marker"
}

if [[ -n "${SSH_ORIGINAL_COMMAND:-}" ]]; then
  run_limited /bin/bash -lc "$SSH_ORIGINAL_COMMAND"
else
  echo "SSH session is limited to ${session_seconds} seconds." >&2
  run_limited /bin/bash -l
fi

if [[ "$timed_out" -eq 1 ]]; then
  echo "SSH session time limit reached after ${session_seconds} seconds." >&2
fi

exit "$status"
