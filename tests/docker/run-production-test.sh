#!/usr/bin/env bash
set -euo pipefail

cd /opt/fling

log() {
  printf '\n[fling-test] %s\n' "$*"
}

fail() {
  echo "FAILED: $*" >&2
  exit 1
}

work="$(mktemp -d)"
sshd_pid=""
web_pid=""

cleanup() {
  if [[ -n "$web_pid" ]]; then
    kill "$web_pid" 2>/dev/null || true
    wait "$web_pid" 2>/dev/null || true
  fi
  if [[ -n "$sshd_pid" ]]; then
    kill "$sshd_pid" 2>/dev/null || true
    wait "$sshd_pid" 2>/dev/null || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT

log "syntax checks"
python3 -m py_compile bin/fling
bash -n \
  scripts/install-local.sh \
  scripts/create-network.sh \
  scripts/generate-ssh-key.sh \
  ssh-client/entrypoint.sh \
  ssh-server/entrypoint.sh \
  ssh-server/limited-session.sh \
  production/fling-session \
  packaging/copy-templates.sh \
  packaging/build-deb.sh \
  packaging/build-rpm.sh \
  packaging/build-pkg.sh
bin/fling -h >"$work/help.out"
grep -q -- "-t TIME, --time TIME" "$work/help.out"
grep -q -- "-k \\[USERNAME\\], --kill \\[USERNAME\\]" "$work/help.out"
grep -q -- "f123" "$work/help.out"
grep -q -- "list" "$work/help.out"
grep -q -- "web" "$work/help.out"

log "install user-specific policy caps root connections at two"
bin/fling policy install --user root --max-time 1h --max-connections 2 >"$work/policy.out"
grep -q "user: root" "$work/policy.out"
grep -q "max-connections: 2" "$work/policy.out"

log "web console login can update user-specific policy"
FLING_WEB_PASSWORD=web-pass FLING_WEB_SESSION_SECRET=test-secret bin/fling web \
  --listen 127.0.0.1:8899 \
  --policy-file "$work/web-policy.json" >"$work/web.out" 2>"$work/web.err" &
web_pid="$!"
for _ in $(seq 1 50); do
  if curl -fsS http://127.0.0.1:8899/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done
python3 - "$work/web-policy.json" <<'PY'
import http.cookiejar
import json
import re
import sys
import urllib.parse
import urllib.request

policy_path = sys.argv[1]
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
base = "http://127.0.0.1:8899"

def post(path, data):
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(base + path, data=encoded, method="POST")
    return opener.open(req, timeout=5).read().decode()

login_page = opener.open(base + "/login", timeout=5).read().decode()
assert "Login" in login_page
post("/login", {"username": "admin", "password": "web-pass"})
dashboard = opener.open(base + "/", timeout=5).read().decode()
csrf = re.search(r'name="csrf" value="([^"]+)"', dashboard).group(1)
post("/policy", {"csrf": csrf, "user": "root", "max_time": "25s", "max_connections": "2"})
policy = json.load(open(policy_path))
assert policy["users"]["root"]["max_time_seconds"] == 25
assert policy["users"]["root"]["max_connections"] == 2
dashboard = opener.open(base + "/", timeout=5).read().decode()
assert "root" in dashboard
assert "25s" in dashboard
PY
kill "$web_pid" 2>/dev/null || true
wait "$web_pid" 2>/dev/null || true
web_pid=""

log "non-root access grant is rejected"
install -d -m 0755 "$work/nonroot"
ssh-keygen -q -t ed25519 -N "" -C "nonroot-test" -f "$work/nonroot/client"
set +e
su nobody -s /bin/sh -c "cd /opt/fling && bin/fling -t 1m --ca-key '$work/nonroot/ca' --username denied --public-key-file '$work/nonroot/client.pub'" >"$work/nonroot.out" 2>"$work/nonroot.err"
nonroot_code="$?"
set -e
if [[ "$nonroot_code" -ne 77 ]]; then
  cat "$work/nonroot.out" >&2
  cat "$work/nonroot.err" >&2
  fail "expected non-root setup to exit 77, got $nonroot_code"
fi

log "create CA and configure host for an existing remote user"
bin/fling ca init --ca-key "$work/ca_user_ed25519" >/dev/null
bin/fling host install \
  --ca-pub "$work/ca_user_ed25519.pub" \
  --username root \
  --principal temp-remote \
  --principal f101 \
  --principal f102 \
  --principal f103 \
  --no-validate

sshd -t
ssh-keygen -A >/dev/null
/usr/sbin/sshd -D -e -p 2222 >"$work/sshd.log" 2>&1 &
sshd_pid="$!"

for _ in $(seq 1 50); do
  if ssh-keyscan -p 2222 -T 1 127.0.0.1 >"$work/known_hosts" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

if [[ ! -s "$work/known_hosts" ]]; then
  cat "$work/sshd.log" >&2 || true
  fail "sshd did not start"
fi

log "issue temp cert with --username and -t"
set +e
bin/fling \
  --ca-key "$work/ca_user_ed25519" \
  --username too-long \
  -t 2h >"$work/too-long.out" 2>"$work/too-long.err"
too_long_code="$?"
set -e
if [[ "$too_long_code" -eq 0 ]]; then
  fail "expected --time 2h to be rejected"
fi
grep -q "cannot exceed 1 hour" "$work/too-long.err"

bin/fling --json -t 8s \
  --ca-key "$work/ca_user_ed25519" \
  --username temp-remote \
  --login-user root \
  --remote 127.0.0.1 >"$work/setup.json"

python3 - "$work/setup.json" "$work/setup.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["username"] == "temp-remote"
assert payload["seconds"] == 8
assert "root@127.0.0.1" in payload["ssh_command"]
assert payload["generated_key"] is True
with open(sys.argv[2], "w") as out:
    out.write(f"CLIENT_KEY={payload['private_key']}\n")
    out.write(f"CLIENT_CERT={payload['out']}\n")
PY
source "$work/setup.env"

ssh-keygen -L -f "$CLIENT_CERT" >"$work/cert.txt"
grep -q "temp-remote" "$work/cert.txt"
grep -q "force-command /usr/local/libexec/fling-session --max-seconds 8 --username temp-remote --login-user root --policy-file /etc/fling/policy.json" "$work/cert.txt"

ssh_base=(
  ssh
  -i "$CLIENT_KEY"
  -o "CertificateFile=$CLIENT_CERT"
  -o "BatchMode=yes"
  -o "StrictHostKeyChecking=yes"
  -o "UserKnownHostsFile=$work/known_hosts"
  -p 2222
  root@127.0.0.1
)

log "ssh login succeeds before expiry"
"${ssh_base[@]}" 'whoami' >"$work/whoami.out"
grep -q '^root$' "$work/whoami.out"

log "list and kill named sessions with max connections policy"
for name in f101 f102 f103; do
  bin/fling --json -t 30s \
    --ca-key "$work/ca_user_ed25519" \
    --username "$name" \
    --login-user root >"$work/$name.json"
done
python3 - "$work" "$work/multi.env" <<'PY'
import json
import sys
from pathlib import Path
work = Path(sys.argv[1])
with open(sys.argv[2], "w") as out:
    for name in ["f101", "f102", "f103"]:
        payload = json.load(open(work / f"{name}.json"))
        out.write(f"{name.upper()}_KEY={payload['private_key']}\n")
        out.write(f"{name.upper()}_CERT={payload['out']}\n")
PY
source "$work/multi.env"

ssh_cert() {
  local key="$1"
  local cert="$2"
  shift 2
  ssh \
    -i "$key" \
    -o "CertificateFile=$cert" \
    -o "BatchMode=yes" \
    -o "StrictHostKeyChecking=yes" \
    -o "UserKnownHostsFile=$work/known_hosts" \
    -p 2222 \
    root@127.0.0.1 \
    "$@"
}

ssh_cert "$F101_KEY" "$F101_CERT" 'echo f101; sleep 30' >"$work/f101-session.out" 2>"$work/f101-session.err" &
f101_pid="$!"
for _ in $(seq 1 30); do
  if grep -q '^f101$' "$work/f101-session.out" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

ssh_cert "$F102_KEY" "$F102_CERT" 'echo f102; sleep 30' >"$work/f102-session.out" 2>"$work/f102-session.err" &
f102_pid="$!"
for _ in $(seq 1 30); do
  if grep -q '^f102$' "$work/f102-session.out" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

set +e
ssh_cert "$F103_KEY" "$F103_CERT" 'echo f103' >"$work/f103-session.out" 2>"$work/f103-session.err"
f103_code="$?"
set -e
if [[ "$f103_code" -eq 0 ]]; then
  fail "expected third concurrent session to be rejected"
fi
grep -q "Maximum active fling sessions reached" "$work/f103-session.err"

bin/fling --json list --login-user root >"$work/list-two.json"
python3 - "$work/list-two.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
names = {session["username"] for session in payload["sessions"]}
assert {"f101", "f102"}.issubset(names), names
PY

bin/fling -k f101 >"$work/kill-f101.out"
grep -q "killed 1 active fling session" "$work/kill-f101.out"
set +e
wait "$f101_pid"
f101_code="$?"
set -e
if [[ "$f101_code" -eq 0 ]]; then
  fail "expected fling -k f101 to terminate only f101"
fi

bin/fling --json list --login-user root >"$work/list-one.json"
python3 - "$work/list-one.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
names = {session["username"] for session in payload["sessions"]}
assert "f101" not in names, names
assert "f102" in names, names
PY

bin/fling shutdown f102 >"$work/kill-f102.out"
grep -q "killed 1 active fling session" "$work/kill-f102.out"
set +e
wait "$f102_pid"
f102_code="$?"
set -e
if [[ "$f102_code" -eq 0 ]]; then
  fail "expected fling shutdown f102 to terminate f102"
fi

log "forced session timeout kills long command"
bin/fling --json -t 8s \
  --ca-key "$work/ca_user_ed25519" \
  --username temp-remote \
  --login-user root >"$work/timeout-setup.json"
python3 - "$work/timeout-setup.json" "$work/timeout.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as out:
    out.write(f"TIMEOUT_KEY={payload['private_key']}\n")
    out.write(f"TIMEOUT_CERT={payload['out']}\n")
PY
source "$work/timeout.env"
ssh_timeout_base=(
  ssh
  -i "$TIMEOUT_KEY"
  -o "CertificateFile=$TIMEOUT_CERT"
  -o "BatchMode=yes"
  -o "StrictHostKeyChecking=yes"
  -o "UserKnownHostsFile=$work/known_hosts"
  -p 2222
  root@127.0.0.1
)
set +e
"${ssh_timeout_base[@]}" 'echo start; sleep 20; echo should-not-print' >"$work/timeout.out" 2>"$work/timeout.err"
timeout_code="$?"
set -e
if [[ "$timeout_code" -ne 124 ]]; then
  cat "$work/timeout.out" >&2
  cat "$work/timeout.err" >&2
  fail "expected timeout exit 124, got $timeout_code"
fi
grep -q '^start$' "$work/timeout.out"
if grep -q 'should-not-print' "$work/timeout.out"; then
  fail "long command was not killed"
fi
grep -q 'time limit reached after 8 seconds' "$work/timeout.err"

log "issuer API returns a temp certificate"
ssh-keygen -q -t ed25519 -N "" -C "api-client" -f "$work/api-client"
FLING_ISSUER_TOKEN=test-token bin/fling serve \
  --listen 127.0.0.1:8877 \
  --ca-key "$work/ca_user_ed25519" \
  --allowed-principal temp-api \
  --default-seconds 30 \
  --max-seconds 60 >"$work/issuer.out" 2>"$work/issuer.err" &
issuer_pid="$!"
trap 'kill "$issuer_pid" 2>/dev/null || true; cleanup' EXIT

for _ in $(seq 1 50); do
  if curl -fsS http://127.0.0.1:8877/healthz >/dev/null 2>&1; then
    break
  fi
  sleep 0.1
done

python3 - "$work/api-client.pub" "$work/api-response.json" <<'PY'
import json
import sys
import urllib.request
public_key = open(sys.argv[1]).read().strip()
body = json.dumps({"public_key": public_key, "principal": "temp-api", "seconds": 30}).encode()
req = urllib.request.Request(
    "http://127.0.0.1:8877/v1/certificates",
    data=body,
    headers={"Authorization": "Bearer test-token", "Content-Type": "application/json"},
    method="POST",
)
payload = urllib.request.urlopen(req, timeout=5).read().decode()
open(sys.argv[2], "w").write(payload)
PY

python3 - "$work/api-response.json" "$work/api-client-cert.pub" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["username"] == "temp-api"
assert payload["seconds"] == 30
open(sys.argv[2], "w").write(payload["certificate"] + "\n")
PY
ssh-keygen -L -f "$work/api-client-cert.pub" | grep -q "temp-api"
kill "$issuer_pid" 2>/dev/null || true
wait "$issuer_pid" 2>/dev/null || true
trap cleanup EXIT

log "setup can generate a random username by default"
bin/fling --json -t 20s \
  --ca-key "$work/ca_user_ed25519" \
  >"$work/random-setup.json"
python3 - "$work/random-setup.json" <<'PY'
import json
import re
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert re.fullmatch(r"f[0-9]{3}", payload["username"]), payload["username"]
assert payload["generated_key"] is True
assert payload["private_key"]
assert payload["out"]
PY

log "bare fling defaults to one hour with a short random username"
bin/fling --json \
  --ca-key "$work/ca_user_ed25519" \
  >"$work/default-setup.json"
python3 - "$work/default-setup.json" <<'PY'
import json
import re
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["seconds"] == 3600
assert re.fullmatch(r"f[0-9]{3}", payload["username"]), payload["username"]
PY

log "custom user-specific install policy caps default and requested time"
bin/fling policy install --policy-file "$work/short-policy.json" --user root --max-time 45s --max-connections 2 >/dev/null
set +e
bin/fling --policy-file "$work/short-policy.json" \
  --ca-key "$work/ca_user_ed25519" \
  --username f201 \
  --login-user root \
  -t 46s >"$work/short-too-long.out" 2>"$work/short-too-long.err"
short_too_long_code="$?"
set -e
if [[ "$short_too_long_code" -eq 0 ]]; then
  fail "expected policy max-time 45s to reject 46s"
fi
grep -q "cannot exceed 45s" "$work/short-too-long.err"
bin/fling --json \
  --policy-file "$work/short-policy.json" \
  --login-user root \
  --ca-key "$work/ca_user_ed25519" >"$work/short-default.json"
python3 - "$work/short-default.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["seconds"] == 45
PY

log "create-user path unlocks generated account for certificate ssh"
bin/fling host install \
  --ca-pub "$work/ca_user_ed25519.pub" \
  --username flingtmp \
  --principal flingtmp \
  --create-user \
  --no-validate

sshd -t
kill "$sshd_pid"
wait "$sshd_pid" 2>/dev/null || true
/usr/sbin/sshd -D -e -p 2222 >"$work/sshd2.log" 2>&1 &
sshd_pid="$!"
sleep 0.5

bin/fling --json -t 20s \
  --ca-key "$work/ca_user_ed25519" \
  --username flingtmp >"$work/created-setup.json"
python3 - "$work/created-setup.json" "$work/created.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as out:
    out.write(f"CREATED_KEY={payload['private_key']}\n")
    out.write(f"CREATED_CERT={payload['out']}\n")
PY
source "$work/created.env"

ssh \
  -i "$CREATED_KEY" \
  -o "CertificateFile=$CREATED_CERT" \
  -o "BatchMode=yes" \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  -p 2222 \
  flingtmp@127.0.0.1 'whoami' >"$work/created-whoami.out"
grep -q '^flingtmp$' "$work/created-whoami.out"

log "all docker integration checks passed"
