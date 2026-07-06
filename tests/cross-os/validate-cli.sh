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
assert payload["effective"]["max_time_seconds"] == 86400, payload
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

detached_dir="$tmp/detached"
"$cmd" --json detached start --name cross --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'import time; print("detached-ready", flush=True); time.sleep(30)' >"$tmp/detached-start.json"
"$cmd" --json detached list --detached-dir "$detached_dir" >"$tmp/detached-list.json"
python3 - "$tmp/detached-start.json" "$tmp/detached-list.json" <<'PY'
import json
import sys

start = json.load(open(sys.argv[1], encoding="utf-8"))
listing = json.load(open(sys.argv[2], encoding="utf-8"))
assert start["ok"] is True, start
job = start["job"]
assert job["name"] == "cross", job
assert job["status"] == "processing", job
assert isinstance(job["pid"], int) and job["pid"] > 0, job
assert isinstance(job["supervisor_pid"], int) and job["supervisor_pid"] > 0, job
assert job["seconds"] == 30, job
assert listing["ok"] is True and listing["count"] == 1, listing
assert listing["jobs"][0]["pid"] == job["pid"], listing
PY
"$cmd" --json detached kill --detached-dir "$detached_dir" cross >"$tmp/detached-kill.json"
python3 - "$tmp/detached-kill.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["ok"] is True, payload
assert payload["job"]["status"] == "killed", payload
assert payload["killed"] >= 1, payload
assert payload["pids"], payload
PY
"$cmd" detached start --name plain --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'import time; time.sleep(30)' >"$tmp/detached-plain-start.out"
"$cmd" detached kill --detached-dir "$detached_dir" plain >"$tmp/detached-plain-kill.out"
grep -Eq '^killed [1-9][0-9]* detached process\(es\)$' "$tmp/detached-plain-kill.out" || fail "plain detached kill output was not stable"
set +e
"$cmd" --json detached start --name start-fails --time 30s --cwd "$tmp/missing-cwd" --detached-dir "$detached_dir" -- python3 -c 'print("bad")' >"$tmp/detached-start-fails.out" 2>"$tmp/detached-start-fails.err"
start_fails_code="$?"
set -e
if [ "$start_fails_code" -eq 0 ]; then
  fail "detached start reported success for a command that never started"
fi
python3 - "$tmp/detached-start-fails.out" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
assert payload["ok"] is False, payload
message = payload["error"]["message"]
assert "Detached job failed to start" in message, payload
job = payload["error"]["details"]["job"]
assert job["name"] == "start-fails", job
assert job["status"] == "failed", job
assert job.get("pid") is None, job
assert "error" in job, job
PY
"$cmd" --json detached start --name replace-active --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'import time; time.sleep(30)' >"$tmp/detached-replace-active-start.json"
set +e
"$cmd" --json detached start --replace --name replace-active --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'print("bad")' >"$tmp/detached-replace-active.out" 2>"$tmp/detached-replace-active.err"
replace_active_code="$?"
set -e
if [ "$replace_active_code" -eq 0 ]; then
  "$cmd" --json detached kill --detached-dir "$detached_dir" replace-active >/dev/null 2>&1 || true
  fail "active detached job was replaced"
fi
grep -Fq "already active" "$tmp/detached-replace-active.out" || fail "active detached replace did not explain the active job"
"$cmd" --json detached kill --detached-dir "$detached_dir" replace-active >/dev/null
"$cmd" --json detached start --name replace-done --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'print("first", flush=True)' >"$tmp/detached-replace-done-start.json"
replace_done_seen=0
replace_done_attempts=0
while [ "$replace_done_attempts" -lt 10 ]; do
  "$cmd" --json detached list --name replace-done --detached-dir "$detached_dir" >"$tmp/detached-replace-done-list.json"
  if python3 - "$tmp/detached-replace-done-list.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
jobs = payload.get("jobs", [])
sys.exit(0 if jobs and jobs[0].get("status") == "completed" else 1)
PY
  then
    replace_done_seen=1
    break
  fi
  replace_done_attempts=$((replace_done_attempts + 1))
  sleep 1
done
if [ "$replace_done_seen" -ne 1 ]; then
  fail "detached replacement setup did not reach completed status"
fi
set +e
"$cmd" --json detached start --name replace-done --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'print("bad")' >"$tmp/detached-replace-done.out" 2>"$tmp/detached-replace-done.err"
replace_done_code="$?"
set -e
if [ "$replace_done_code" -eq 0 ]; then
  fail "inactive detached job was replaced without --replace"
fi
grep -Fq "Use --replace after it is inactive" "$tmp/detached-replace-done.out" || fail "inactive detached replace did not require --replace"
"$cmd" --json detached start --replace --name replace-done --time 30s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'import time; print("second", flush=True); time.sleep(30)' >"$tmp/detached-replace-done-replaced.json"
replace_done_log="$detached_dir/replace-done.out.log"
replace_second_seen=0
replace_second_attempts=0
while [ "$replace_second_attempts" -lt 5 ]; do
  if grep -Fq "second" "$replace_done_log" 2>/dev/null; then
    replace_second_seen=1
    break
  fi
  replace_second_attempts=$((replace_second_attempts + 1))
  sleep 1
done
if [ "$replace_second_seen" -ne 1 ]; then
  "$cmd" --json detached kill --detached-dir "$detached_dir" replace-done >/dev/null 2>&1 || true
  fail "detached --replace did not start the replacement job"
fi
if grep -Fq "first" "$replace_done_log" 2>/dev/null; then
  "$cmd" --json detached kill --detached-dir "$detached_dir" replace-done >/dev/null 2>&1 || true
  fail "detached --replace did not reset stdout log"
fi
"$cmd" --json detached kill --detached-dir "$detached_dir" replace-done >/dev/null
"$cmd" --json detached start --name timeout --time 1s --cwd "$tmp" --detached-dir "$detached_dir" -- python3 -c 'import time; time.sleep(10)' >"$tmp/detached-timeout-start.json"
timeout_seen=0
timeout_attempts=0
while [ "$timeout_attempts" -lt 12 ]; do
  "$cmd" --json detached list --name timeout --detached-dir "$detached_dir" >"$tmp/detached-timeout-list.json"
  if python3 - "$tmp/detached-timeout-list.json" <<'PY'
import json
import sys

payload = json.load(open(sys.argv[1], encoding="utf-8"))
jobs = payload.get("jobs", [])
sys.exit(0 if jobs and jobs[0].get("status") == "timed_out" else 1)
PY
  then
    timeout_seen=1
    break
  fi
  timeout_attempts=$((timeout_attempts + 1))
  sleep 1
done
if [ "$timeout_seen" -ne 1 ]; then
  "$cmd" --json detached kill --detached-dir "$detached_dir" timeout >/dev/null 2>&1 || true
  fail "detached timeout job did not reach timed_out status"
fi
set +e
"$cmd" --json detached start --name too-long --time 25h --detached-dir "$detached_dir" -- python3 -c 'print("no")' >"$tmp/detached-too-long.out" 2>"$tmp/detached-too-long.err"
detached_too_long_code="$?"
set -e
if [ "$detached_too_long_code" -eq 0 ]; then
  fail "expected detached --time 25h to be rejected"
fi
grep -Fq "cannot exceed 24 hours" "$tmp/detached-too-long.out" || fail "detached too-long JSON missing 24h error"
set +e
SSHFLING_FORCED_SESSION=1 "$cmd" --json detached start --name forced-denied --time 30s --detached-dir "$detached_dir" -- python3 -c 'print("no")' >"$tmp/detached-forced-denied.out" 2>"$tmp/detached-forced-denied.err"
forced_denied_code="$?"
set -e
if [ "$forced_denied_code" -eq 0 ]; then
  fail "detached start was allowed from forced-session environment"
fi
grep -Fq "forced-command session" "$tmp/detached-forced-denied.out" || fail "forced-session detached denial missing error"

python3 - "$cmd" <<'PY'
import importlib.machinery
import importlib.util
from pathlib import Path
import shutil
import sys
import tempfile

cmd = sys.argv[1]
if "/" not in cmd:
    cmd = shutil.which(cmd)
    assert cmd, "sshfling command not found on PATH"
command_path = Path(cmd)
candidates = []
wrapped_path = command_path.with_name(f".{command_path.name}-wrapped")
if wrapped_path.exists():
    candidates.append(wrapped_path)
candidates.append(command_path)

last_syntax_error = None
for candidate in candidates:
    loader = importlib.machinery.SourceFileLoader("sshfling_under_test", str(candidate))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    sshfling = importlib.util.module_from_spec(spec)
    try:
        loader.exec_module(sshfling)
        break
    except SyntaxError as exc:
        last_syntax_error = exc
else:
    raise last_syntax_error or AssertionError(f"could not load sshfling source from {candidates}")

class Result:
    returncode = 0
    stderr = ""
    stdout = """\
 100     1     0      9 /usr/local/libexec/sshfling-session --max-seconds 30 --username s123 --login-user root
 101   100     0      9 /bin/bash -lc sleep 30
 102   101     0      9 sleep 30
 200     1     0      9 unrelated
"""

sshfling.command_path = lambda name: "/bin/ps" if name == "ps" else None
sshfling.run = lambda *args, **kwargs: Result()
sshfling.os.getpid = lambda: 999

sessions = sshfling.find_sshfling_sessions()
assert len(sessions) == 1, sessions
session = sessions[0]
assert session["pid"] == 100, session
assert session["status"] == "processing", session
assert session["process_pid"] == 101, session
assert session["process_pids"] == [101, 102], session

with tempfile.TemporaryDirectory() as detached_dir:
    paths = sshfling.detached_paths(detached_dir, "active-race")
    now = sshfling.utc_timestamp()
    sshfling.write_json_atomic(paths["metadata"], {
        "version": 1,
        "managed_by": "sshfling",
        "name": "active-race",
        "status": "processing",
        "pid": 987654,
        "supervisor_pid": 987655,
        "command": ["python3", "-c", "print('replacement should not start')"],
        "cwd": detached_dir,
        "seconds": 300,
        "started_at": now,
        "started_at_utc": sshfling.utc_iso(now),
        "expires_at": now + 300,
        "expires_at_utc": sshfling.utc_iso(now + 300),
        "metadata_path": str(paths["metadata"]),
        "stdout_path": str(paths["stdout"]),
        "stderr_path": str(paths["stderr"]),
    })

    class Args:
        name = "active-race"
        time = 300
        seconds = None
        detached_dir = detached_dir
        cwd = detached_dir
        replace = True
        detached_args = ["--", "python3", "-c", "print('bad')"]
        json = True

    original_process_exists = sshfling.process_exists
    sshfling.process_exists = lambda pid: False
    try:
        try:
            sshfling.cmd_detached_start(Args)
        except sshfling.SSHFlingError as exc:
            assert "already active" in exc.message, exc.message
        else:
            raise AssertionError("active detached metadata was replaced after process_exists returned false")
    finally:
        sshfling.process_exists = original_process_exists

original_ancestry = sshfling.process_ancestry
try:
    sshfling.process_ancestry = lambda: []
    with tempfile.TemporaryDirectory() as detached_dir:
        paths = sshfling.detached_paths(detached_dir, "cap-denied")
        now = sshfling.utc_timestamp()
        for index in range(sshfling.MAX_DETACHED_JOBS):
            name = f"active-{index}"
            active_paths = sshfling.detached_paths(detached_dir, name)
            sshfling.write_json_atomic(active_paths["metadata"], {
                "version": 1,
                "managed_by": "sshfling",
                "name": name,
                "status": "processing",
                "pid": 900000 + index,
                "supervisor_pid": 910000 + index,
                "command": ["python3", "-c", "print('active')"],
                "cwd": detached_dir,
                "seconds": 300,
                "started_at": now,
                "started_at_utc": sshfling.utc_iso(now),
                "expires_at": now + 300,
                "expires_at_utc": sshfling.utc_iso(now + 300),
                "metadata_path": str(active_paths["metadata"]),
                "stdout_path": str(active_paths["stdout"]),
                "stderr_path": str(active_paths["stderr"]),
            })

        class Args:
            name = "cap-denied"
            time = 300
            seconds = None
            detached_dir = detached_dir
            cwd = detached_dir
            replace = False
            detached_args = ["--", "python3", "-c", "print('bad')"]
            json = True

        try:
            sshfling.cmd_detached_start(Args)
        except sshfling.SSHFlingError as exc:
            assert "Maximum detached sshfling jobs reached" in exc.message, exc.message
            assert exc.code == 75, exc.code
        else:
            raise AssertionError("detached start ignored active job cap")

    now = sshfling.utc_timestamp()
    sshfling.process_ancestry = lambda: [{
        "pid": 12345,
        "ppid": 1,
        "argv": ["bash", "/usr/local/libexec/sshfling-session", "--max-seconds", "30"],
        "environ": {"SSHFLING_FORCED_SESSION_EXPIRES_AT": str(now + 30)},
    }]
    context = sshfling.sshfling_forced_session_context()
    assert context["forced"] is True, context
    assert context["allow_detached"] is False, context
    try:
        sshfling.cmd_detached_start(Args)
    except sshfling.SSHFlingError as exc:
        assert "forced-command session" in exc.message, exc.message
        assert exc.code == 75, exc.code
    else:
        raise AssertionError("detached start was allowed without wrapper override")

    sshfling.process_ancestry = lambda: [{
        "pid": 12346,
        "ppid": 1,
        "argv": ["bash", "/usr/local/libexec/sshfling-session", "--allow-detached-start", "--max-seconds", "30"],
        "environ": {"SSHFLING_FORCED_SESSION_EXPIRES_AT": str(now + 5)},
    }]
    context = sshfling.sshfling_forced_session_context()
    assert context["forced"] is True, context
    assert context["allow_detached"] is True, context
    assert context["remaining_seconds"] is not None and 0 <= context["remaining_seconds"] <= 5, context
finally:
    sshfling.process_ancestry = original_ancestry
PY

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
grep -Fq "SSHFLING_MAX_SECONDS=86400" "$project/systemd/sshflingd.env.example" || fail "systemd env did not default SSHFLING_MAX_SECONDS to 86400"
grep -Fq "max_allowed_seconds=86400" "$project/production/sshfling-session" || fail "production wrapper did not allow 24h sessions"
grep -Fq "max_allowed_seconds=86400" "$project/ssh-server/limited-session.sh" || fail "docker wrapper did not allow 24h sessions"

python3 - "$cmd" <<'PY'
import argparse
import importlib.machinery
import importlib.util
import json
import pathlib
import shutil
import sys
import tempfile
import time

cmd = sys.argv[1]
if "/" not in cmd:
    cmd = shutil.which(cmd)
    assert cmd, "sshfling command not found on PATH"
command_path = pathlib.Path(cmd)
candidates = []
wrapped_path = command_path.with_name(f".{command_path.name}-wrapped")
if wrapped_path.exists():
    candidates.append(wrapped_path)
candidates.append(command_path)

last_syntax_error = None
for candidate in candidates:
    loader = importlib.machinery.SourceFileLoader("sshfling_setup_under_test", str(candidate))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    sshfling = importlib.util.module_from_spec(spec)
    try:
        loader.exec_module(sshfling)
        break
    except SyntaxError as exc:
        last_syntax_error = exc
else:
    raise last_syntax_error or AssertionError(f"could not load sshfling source from {candidates}")

def setup_args(**overrides):
    values = {
        "password": False,
        "certificate": False,
        "ca_key": None,
        "ca_key_explicit": False,
        "login_user": None,
        "login_user_explicit": False,
        "public_key": None,
        "public_key_file": None,
        "out": None,
        "session_dir": None,
        "session_dir_explicit": False,
        "key_id": None,
        "source_address": None,
        "no_pty": False,
    }
    values.update(overrides)
    return argparse.Namespace(**values)

routes = []
original_password = sshfling.cmd_setup_password
original_certificate = sshfling.cmd_setup_certificate
try:
    sshfling.cmd_setup_password = lambda args: routes.append("password") or 0
    sshfling.cmd_setup_certificate = lambda args: routes.append("certificate") or 0

    assert sshfling.cmd_setup(setup_args()) == 0
    assert routes[-1] == "password", routes
    assert sshfling.cmd_setup(setup_args(password=True)) == 0
    assert routes[-1] == "password", routes
    assert sshfling.cmd_setup(setup_args(ca_key="/tmp/default-ca", session_dir="/tmp/default-sessions")) == 0
    assert routes[-1] == "password", routes
    assert sshfling.cmd_setup(setup_args(certificate=True)) == 0
    assert routes[-1] == "certificate", routes

    for option_args, expected_option in [
        ({"public_key": "ssh-ed25519 AAAA test"}, "--public-key"),
        ({"public_key_file": "/tmp/client.pub"}, "--public-key-file"),
        ({"out": "/tmp/client-cert.pub"}, "--out"),
        ({"ca_key": "/tmp/sshfling-ca", "ca_key_explicit": True}, "--ca-key"),
        ({"login_user": "root", "login_user_explicit": True}, "--login-user"),
        ({"session_dir": "/tmp/sshfling-sessions", "session_dir_explicit": True}, "--session-dir"),
        ({"key_id": "setup-test"}, "--key-id"),
        ({"source_address": "192.0.2.0/24"}, "--source-address"),
        ({"no_pty": True}, "--no-pty"),
    ]:
        try:
            sshfling.cmd_setup(setup_args(**option_args))
        except sshfling.SSHFlingError as exc:
            assert "require --certificate" in exc.message, exc.message
            assert expected_option in exc.details["options"], exc.details
        else:
            raise AssertionError(f"{expected_option} was accepted without --certificate")

    try:
        sshfling.cmd_setup(setup_args(password=True, certificate=True))
    except sshfling.SSHFlingError as exc:
        assert "not both" in exc.message, exc.message
    else:
        raise AssertionError("--password and --certificate were accepted together")
finally:
    sshfling.cmd_setup_password = original_password
    sshfling.cmd_setup_certificate = original_certificate

with tempfile.TemporaryDirectory() as tmpdir:
    root = pathlib.Path(tmpdir)
    grant_dir = root / "grants"
    conf_dir = root / "sshd_config.d"
    grant_dir.mkdir()
    conf_dir.mkdir()
    now = int(time.time())

    active_conf = conf_dir / "91-sshfling-password-sshflingactive.conf"
    expired_conf = conf_dir / "91-sshfling-password-sshflingexpired.conf"
    existing_conf = conf_dir / "91-sshfling-password-sshflingexisting.conf"
    unmanaged_conf = conf_dir / "91-sshfling-password-sshflingunmanaged.conf"
    spoof_conf = conf_dir / "91-sshfling-password-root.conf"
    active_conf.write_text("# Managed by sshfling password grant for sshflingactive.\n", encoding="utf-8")
    expired_conf.write_text("# Managed by sshfling password grant for sshflingexpired.\n", encoding="utf-8")
    existing_conf.write_text("# Managed by sshfling password grant for sshflingexisting.\n", encoding="utf-8")
    unmanaged_conf.write_text("# Managed by sshfling password grant for sshflingunmanaged.\n", encoding="utf-8")
    spoof_conf.write_text("# Managed by sshfling password grant for root.\n", encoding="utf-8")

    (grant_dir / "sshflingactive.json").write_text(json.dumps({
        "username": "sshflingactive",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": True,
        "expires_at": now + 3600,
        "config_path": str(active_conf),
    }), encoding="utf-8")
    (grant_dir / "sshflingexpired.json").write_text(json.dumps({
        "username": "sshflingexpired",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": True,
        "expires_at": now - 60,
        "config_path": str(expired_conf),
    }), encoding="utf-8")
    (grant_dir / "sshflingexisting.json").write_text(json.dumps({
        "username": "sshflingexisting",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": False,
        "expires_at": now - 60,
        "config_path": str(existing_conf),
    }), encoding="utf-8")
    (grant_dir / "sshflingunmanaged.json").write_text(json.dumps({
        "username": "sshflingunmanaged",
        "created_user": True,
        "expires_at": now - 60,
        "config_path": str(unmanaged_conf),
    }), encoding="utf-8")
    (grant_dir / "sshflingmissingconfig.json").write_text(json.dumps({
        "username": "sshflingmissingconfig",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": True,
        "expires_at": now - 60,
    }), encoding="utf-8")
    (grant_dir / "sshflingspoof.json").write_text(json.dumps({
        "username": "root",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": True,
        "expires_at": now - 60,
        "config_path": str(spoof_conf),
    }), encoding="utf-8")

    class UserExists:
        returncode = 0
        stderr = ""
        stdout = ""

    original_run = sshfling.run
    sshfling.run = lambda *args, **kwargs: UserExists()
    try:
        results = sshfling.prune_password_grants(
            grant_dir,
            all_grants=True,
            delete_users=True,
            dry_run=True,
        )
    finally:
        sshfling.run = original_run

    by_user = {item["username"]: item for item in results}
    assert by_user["sshflingactive"]["status"] == "active", by_user
    expired = by_user["sshflingexpired"]
    assert expired["status"] == "pruned", by_user
    assert expired["config"]["would_remove"] is True, expired
    assert expired["metadata"]["would_remove"] is True, expired
    assert expired["user"]["would_delete"] is True, expired
    existing = by_user["sshflingexisting"]
    assert existing["status"] == "pruned", by_user
    assert existing["user"]["would_lock"] is True, existing
    assert existing["user"]["existing_user"] is True, existing
    assert existing["user"]["delete_skipped"] == "existing Unix user was not created by sshfling", existing
    unmanaged = by_user["sshflingunmanaged"]
    assert unmanaged["status"] == "skipped-unmanaged", unmanaged
    assert "config" not in unmanaged, unmanaged
    assert "metadata" not in unmanaged, unmanaged
    missing_config = by_user["sshflingmissingconfig"]
    assert missing_config["status"] == "pruned", missing_config
    assert missing_config["user"]["would_lock"] is True, missing_config
    assert missing_config["user"]["delete_skipped"], missing_config
    spoofed = by_user["root"]
    assert spoofed["status"] == "skipped-unmanaged", spoofed
    assert "config" not in spoofed, spoofed
    assert "user" not in spoofed, spoofed

    captured = {}
    originals = {
        "require_root": sshfling.require_root,
        "require_password_host_tools": sshfling.require_password_host_tools,
        "prune_password_grants": sshfling.prune_password_grants,
        "unix_user_exists": sshfling.unix_user_exists,
        "ensure_unix_user": sshfling.ensure_unix_user,
        "set_user_password": sshfling.set_user_password,
        "resource_file": sshfling.resource_file,
        "install_file": sshfling.install_file,
        "write_if_changed": sshfling.write_if_changed,
        "write_password_grant_metadata": sshfling.write_password_grant_metadata,
        "reload_sshd": sshfling.reload_sshd,
        "detect_server_host": sshfling.detect_server_host,
        "audit_log": sshfling.audit_log,
        "emit_json": sshfling.emit_json,
    }
    try:
        sshfling.require_root = lambda action: None
        sshfling.require_password_host_tools = lambda: None
        sshfling.unix_user_exists = lambda username: True
        sshfling.ensure_unix_user = lambda username: {"user": username, "created": False}
        sshfling.set_user_password = lambda username, password: None
        sshfling.resource_file = lambda relative: command_path
        sshfling.install_file = lambda *args, **kwargs: {"installed": True}
        sshfling.write_if_changed = lambda *args, **kwargs: {"changed": True}
        def capture_metadata(grant_dir, username, metadata, dry_run=False):
            captured["metadata"] = metadata
            return {"metadata": "captured"}
        sshfling.write_password_grant_metadata = capture_metadata
        sshfling.reload_sshd = lambda: {"reloaded": "sshd"}
        sshfling.detect_server_host = lambda: "127.0.0.1"
        sshfling.audit_log = lambda *args, **kwargs: None
        sshfling.emit_json = lambda payload: None
        prune_called = {"value": False}
        def record_prune(*args, **kwargs):
            prune_called["value"] = True
            return []
        sshfling.prune_password_grants = record_prune
        try:
            sshfling.cmd_setup_password(argparse.Namespace(
                username="sshflingexisting",
                password_grant_dir=str(grant_dir),
                password_sshd_config_dir=str(conf_dir),
                session_wrapper="/tmp/sshfling-session",
                policy_file=str(root / "policy.json"),
                time=60,
                seconds=None,
                dry_run=True,
                validate=False,
                allow_existing_user=False,
                json=True,
            ))
        except sshfling.SSHFlingError as exc:
            assert "existing Unix user" in exc.message, exc.message
        else:
            raise AssertionError("existing Unix user was accepted without --allow-existing-user")
        assert prune_called["value"] is False, prune_called

        sshfling.prune_password_grants = lambda *args, **kwargs: []
        sshfling.cmd_setup_password(argparse.Namespace(
            username="sshflingexisting",
            password_grant_dir=str(grant_dir),
            password_sshd_config_dir=str(conf_dir),
            session_wrapper="/tmp/sshfling-session",
            policy_file=str(root / "policy.json"),
            time=60,
            seconds=None,
            dry_run=False,
            validate=False,
            allow_existing_user=True,
            json=True,
        ))
    finally:
        for name, value in originals.items():
            setattr(sshfling, name, value)
    assert captured["metadata"]["created_user"] is False, captured

    host_root = root / "host"
    host_root.mkdir()
    ca_pub = host_root / "ca.pub"
    template = host_root / "sshfling-session"
    trusted_ca = host_root / "trusted_ca.pub"
    principals_dir = host_root / "principals"
    wrapper_path = host_root / "installed-session"
    sshd_config = host_root / "90-sshfling.conf"
    ca_pub.write_text("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest ca\n", encoding="utf-8")
    template.write_text("#!/bin/sh\n", encoding="utf-8")
    sshd_config.write_text("original sshd config\n", encoding="utf-8")

    originals = {
        "require_root": sshfling.require_root,
        "resource_file": sshfling.resource_file,
        "validate_sshd_effective": sshfling.validate_sshd_effective,
    }
    try:
        sshfling.require_root = lambda action: None
        sshfling.resource_file = lambda relative: template
        def fail_validation(*args, **kwargs):
            raise sshfling.SSHFlingError("forced validation failure", 2)
        sshfling.validate_sshd_effective = fail_validation
        try:
            sshfling.cmd_host_install(argparse.Namespace(
                ca_pub=str(ca_pub),
                trusted_ca=str(trusted_ca),
                principals_dir=str(principals_dir),
                user="deploy",
                principal=None,
                session_wrapper=str(wrapper_path),
                sshd_config=str(sshd_config),
                max_time=None,
                max_connections=None,
                policy_file=str(host_root / "policy.json"),
                create_user=False,
                dry_run=False,
                validate=True,
                reload=False,
                json=True,
            ))
        except sshfling.SSHFlingError as exc:
            assert "forced validation failure" in exc.message, exc.message
            assert exc.details.get("rollback"), exc.details
        else:
            raise AssertionError("host install validation failure did not abort")
    finally:
        for name, value in originals.items():
            setattr(sshfling, name, value)
    assert sshd_config.read_text(encoding="utf-8") == "original sshd config\n"
    assert not trusted_ca.exists(), trusted_ca
    assert not (principals_dir / "deploy").exists(), principals_dir / "deploy"
    assert not wrapper_path.exists(), wrapper_path
PY

echo "cross validation ok: $cmd $version"
