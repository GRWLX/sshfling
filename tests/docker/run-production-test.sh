#!/usr/bin/env bash
set -euo pipefail

cd /opt/sshfling

log() {
  printf '\n[sshfling-test] %s\n' "$*"
}

fail() {
  echo "FAILED: $*" >&2
  exit 1
}

if [[ "${SSHFLING_ALLOW_HOST_MUTATION_TESTS:-}" != "1" ]]; then
  if [[ ! -f /.dockerenv ]] && ! grep -qaE '(docker|kubepods|containerd|podman)' /proc/1/cgroup 2>/dev/null; then
    fail "refusing to run destructive production tests outside a container; set SSHFLING_ALLOW_HOST_MUTATION_TESTS=1 to override"
  fi
fi

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
python3 -m py_compile bin/sshfling
bash -n \
  native/sshfling-linux-account \
  scripts/install-local.sh \
  scripts/uninstall-local.sh \
  scripts/create-network.sh \
  scripts/generate-ssh-key.sh \
  ssh-client/entrypoint.sh \
  ssh-server/entrypoint.sh \
  ssh-server/limited-session.sh \
  production/sshfling-session \
  packaging/copy-templates.sh \
  packaging/build-deb.sh \
  packaging/build-rpm.sh \
  packaging/build-pkg.sh
sh -n native/sshfling-unix-identity
bin/sshfling -h >"$work/help.out"
grep -q -- "-t TIME, --time TIME" "$work/help.out"
grep -q -- "-k \\[USERNAME\\], --kill \\[USERNAME\\]" "$work/help.out"
grep -q -- "s123" "$work/help.out"
grep -q -- "list" "$work/help.out"
grep -q -- "web" "$work/help.out"
SSHFLING_CONNECT_DRY_RUN=1 bin/sshfling -p 2222 -o StrictHostKeyChecking=no s234@1.0.0.1 whoami >"$work/connect-dry-run.out"
grep -q -- "PreferredAuthentications=password,keyboard-interactive" "$work/connect-dry-run.out"
grep -q -- "PubkeyAuthentication=no" "$work/connect-dry-run.out"
grep -q -- "ForwardAgent=no" "$work/connect-dry-run.out"
grep -q -- "ClearAllForwardings=yes" "$work/connect-dry-run.out"
grep -q -- "-p 2222" "$work/connect-dry-run.out"
grep -q -- "s234@1.0.0.1 whoami" "$work/connect-dry-run.out"

log "issuer security helper checks"
python3 - "$work/rootless-policy.json" <<'PY'
import argparse
import importlib.machinery
import importlib.util
import os
import sys

loader = importlib.machinery.SourceFileLoader("sshfling_module", "bin/sshfling")
spec = importlib.util.spec_from_loader(loader.name, loader)
sshfling = importlib.util.module_from_spec(spec)
loader.exec_module(sshfling)

valid_token = "".join(["01234567", "89abcdef", "01234567", "89abcdef"])
for token in ["short-token", "replace-with-a-long-random-token", "your-token-goes-here-0123456789abcdef"]:
    try:
        sshfling.validate_bearer_token(token, "SSHFLING_ISSUER_TOKEN")
    except sshfling.SSHFlingError:
        pass
    else:
        raise AssertionError(f"weak issuer token accepted: {token}")

assert sshfling.validate_bearer_token(valid_token, "SSHFLING_ISSUER_TOKEN") == valid_token
assert sshfling.bearer_token_matches("Bearer " + valid_token, valid_token)
assert not sshfling.bearer_token_matches("Bearer " + valid_token[:-1] + "x", valid_token)

class FakeHTTPServer:
    def __init__(self, address, handler):
        self.address = address
        self.handler = handler
    def serve_forever(self):
        return None

sshfling.is_admin = lambda: False
sshfling.http.server.ThreadingHTTPServer = FakeHTTPServer
args = argparse.Namespace(
    policy_file=os.path.abspath(sys.argv[1]),
    token=valid_token,
    token_env="SSHFLING_ISSUER_TOKEN",
    max_seconds=60,
    default_seconds=30,
    listen="127.0.0.1:0",
    allow_remote=False,
    allowed_principal=["deploy"],
    ca_key="/tmp/nonroot-ca",
    session_wrapper=sshfling.DEFAULT_SESSION_WRAPPER,
)
assert sshfling.cmd_serve(args) == 0
PY

log "install user-specific policy caps root connections at two"
bin/sshfling policy install --user root --max-time 1h --max-connections 2 --access-level admin >"$work/policy.out"
grep -q "user: root" "$work/policy.out"
grep -q "max-connections: 2" "$work/policy.out"
grep -q "access-level: admin" "$work/policy.out"

log "web console login can update user-specific policy"
SSHFLING_WEB_PASSWORD=web-pass SSHFLING_WEB_SESSION_SECRET=test-secret bin/sshfling web \
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
import importlib.machinery
import importlib.util
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

policy_path = sys.argv[1]
loader = importlib.machinery.SourceFileLoader("sshfling_module", "bin/sshfling")
spec = importlib.util.spec_from_loader(loader.name, loader)
sshfling = importlib.util.module_from_spec(spec)
loader.exec_module(sshfling)
jar = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
base = "http://127.0.0.1:8899"

def post(path, data):
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(base + path, data=encoded, method="POST")
    return opener.open(req, timeout=5).read().decode()

def post_status(path, data):
    encoded = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(base + path, data=encoded, method="POST")
    try:
        with opener.open(req, timeout=5) as response:
            response.read()
            return response.status
    except urllib.error.HTTPError as exc:
        exc.read()
        return exc.code

login_page = opener.open(base + "/login", timeout=5).read().decode()
assert "Login" in login_page
post("/login", {"username": "admin", "password": "web-pass"})
dashboard = opener.open(base + "/", timeout=5).read().decode()
csrf = re.search(r'name="csrf" value="([^"]+)"', dashboard).group(1)
post("/policy", {"csrf": csrf, "user": "deploy", "max_time": "25s", "max_connections": "2"})
policy = json.load(open(policy_path))
assert policy["users"]["deploy"]["max_time_seconds"] == 25
assert policy["users"]["deploy"]["max_connections"] == 2
dashboard = opener.open(base + "/", timeout=5).read().decode()
assert "deploy" in dashboard
assert "25s" in dashboard
post("/logout", {"csrf": csrf})

oversized = b"username=admin&password=" + b"x" * (sshfling.MAX_HTTP_BODY_BYTES + 1)
req = urllib.request.Request(base + "/login", data=oversized, method="POST")
try:
    opener.open(req, timeout=5).read()
except urllib.error.HTTPError as exc:
    assert exc.code == 413, exc.code
else:
    raise AssertionError("oversized login body was accepted")

for index in range(sshfling.WEB_LOGIN_RATE_LIMIT + 1):
    status = post_status("/login", {"username": "admin", "password": "wrong"})
    if index < sshfling.WEB_LOGIN_RATE_LIMIT:
        assert status == 401, (index, status)
    else:
        assert status == 429, status
PY
kill "$web_pid" 2>/dev/null || true
wait "$web_pid" 2>/dev/null || true
web_pid=""

log "non-root access grant is rejected"
install -d -m 0755 "$work/nonroot"
ssh-keygen -q -t ed25519 -N "" -C "nonroot-test" -f "$work/nonroot/client"
set +e
su nobody -s /bin/sh -c "cd /opt/sshfling && bin/sshfling --certificate -t 1m --ca-key '$work/nonroot/ca' --username denied --public-key-file '$work/nonroot/client.pub'" >"$work/nonroot.out" 2>"$work/nonroot.err"
nonroot_code="$?"
set -e
if [[ "$nonroot_code" -ne 77 ]]; then
  cat "$work/nonroot.out" >&2
  cat "$work/nonroot.err" >&2
  fail "expected non-root setup to exit 77, got $nonroot_code"
fi

log "create CA and configure host for an existing remote user"
bin/sshfling ca init --ca-key "$work/ca_user_ed25519" >/dev/null
bin/sshfling host install \
  --ca-pub "$work/ca_user_ed25519.pub" \
  --username root \
  --principal temp-remote \
  --principal s101 \
  --principal s102 \
  --principal s103 \
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
bin/sshfling \
  --certificate \
  --ca-key "$work/ca_user_ed25519" \
  --username too-long \
  -t 25h >"$work/too-long.out" 2>"$work/too-long.err"
too_long_code="$?"
set -e
if [[ "$too_long_code" -eq 0 ]]; then
  fail "expected --time 25h to be rejected"
fi
grep -q "cannot exceed 24 hours" "$work/too-long.err"

bin/sshfling --json --certificate -t 8s \
  --ca-key "$work/ca_user_ed25519" \
  --username temp-remote \
  --login-user root >"$work/setup.json"

python3 - "$work/setup.json" "$work/setup.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["username"] == "temp-remote"
assert payload["seconds"] == 8
assert payload["server"]
assert payload["server"] != "SERVER_IP"
assert f"root@{payload['server']}" in payload["ssh_command"]
assert payload["generated_key"] is True
with open(sys.argv[2], "w") as out:
    out.write(f"CLIENT_KEY={payload['private_key']}\n")
    out.write(f"CLIENT_CERT={payload['out']}\n")
PY
# shellcheck source=/dev/null
source "$work/setup.env"

ssh-keygen -L -f "$CLIENT_CERT" >"$work/cert.txt"
grep -q "temp-remote" "$work/cert.txt"
grep -q "force-command /usr/local/libexec/sshfling-session --max-seconds 8 --username temp-remote --login-user root --policy-file /etc/sshfling/policy.json" "$work/cert.txt"

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

log "expired certificate cannot authenticate after valid-before"
sleep 10
set +e
"${ssh_base[@]}" 'whoami' >"$work/cert-expired.out" 2>"$work/cert-expired.err"
cert_expired_code="$?"
set -e
if [[ "$cert_expired_code" -eq 0 ]]; then
  fail "expired certificate authenticated after valid-before"
fi
if grep -q '^root$' "$work/cert-expired.out"; then
  fail "expired certificate produced a successful whoami result"
fi
cert_material_dir="$(dirname "$CLIENT_KEY")"
cert_metadata="$cert_material_dir/sshfling-cert.json"
test -f "$cert_metadata"

log "cert prune removes expired generated certificate material"
bin/sshfling --json cert prune --username temp-remote --session-dir /var/lib/sshfling/sessions >"$work/cert-prune.json"
python3 - "$work/cert-prune.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["count"] == 1
result = payload["results"][0]
assert result["username"] == "temp-remote", result
assert result["status"] == "pruned", result
assert result["private_key"]["removed"] is True, result
assert result["public_key"]["removed"] is True, result
assert result["certificate"]["removed"] is True, result
assert result["metadata"]["removed"] is True, result
assert result["directory"]["removed"] is True, result
PY
test ! -e "$CLIENT_KEY"
test ! -e "${CLIENT_KEY}.pub"
test ! -e "$CLIENT_CERT"
test ! -e "$cert_metadata"
test ! -e "$cert_material_dir"

log "default password grant prints sshfling connect command and accepts password login"
bin/sshfling --json -t 20s \
  --username s234 >"$work/password-setup.json"
python3 - "$work/password-setup.json" "$work/password.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["auth"] == "password"
assert payload["username"] == "s234"
assert payload["seconds"] == 20
assert payload["server"]
assert payload["server"] != "SERVER_IP"
assert payload["ssh_command"] == f"sshfling s234@{payload['server']}"
assert payload["password"]
for key in ["certificate", "private_key", "public_key", "ca", "generated_key", "out", "serial", "valid_before", "principal"]:
    assert key not in payload, (key, payload)
with open(sys.argv[2], "w") as out:
    out.write(f"SSHPASS={payload['password']}\n")
PY
# shellcheck source=/dev/null
source "$work/password.env"

bin/sshfling --json --password --dry-run -t 20s \
  --username s235compat >"$work/password-compat.json"
python3 - "$work/password-compat.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["auth"] == "password"
assert payload["username"] == "s235compat"
assert payload["seconds"] == 20
assert payload["password"]
PY

log "operator and sudo-limited access levels create classified password grants without sudo groups"
for access_case in "operator:s241operator" "sudo-limited:s242sudo"; do
  access_level="${access_case%%:*}"
  access_user="${access_case##*:}"
  bin/sshfling policy install \
    --user "$access_user" \
    --max-time 2m \
    --max-connections 1 \
    --access-level "$access_level" >"$work/$access_user-policy.out"
  grep -q "user: $access_user" "$work/$access_user-policy.out"
  grep -q "access-level: $access_level" "$work/$access_user-policy.out"

  bin/sshfling --json -t 4s \
    --username "$access_user" \
    --access-level "$access_level" >"$work/$access_user-setup.json"
  python3 - "$work/$access_user-setup.json" "$access_level" "$access_user" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
expected_level = sys.argv[2]
expected_user = sys.argv[3]
assert payload["ok"] is True, payload
assert payload["auth"] == "password", payload
assert payload["username"] == expected_user, payload
assert payload["access_level"] == expected_level, payload
assert payload["policy"]["access_level"] == expected_level, payload
PY
  python3 - "$access_level" "$access_user" <<'PY'
import json
import sys
from pathlib import Path
expected_level = sys.argv[1]
expected_user = sys.argv[2]
metadata = json.loads(Path(f"/var/lib/sshfling/password-grants/{expected_user}.json").read_text())
assert metadata["username"] == expected_user, metadata
assert metadata["access_level"] == expected_level, metadata
assert metadata["created_user"] is True, metadata
PY
  id -u "$access_user" >/dev/null
  if id -nG "$access_user" | grep -Eq '(^| )(sudo|wheel|admin)( |$)'; then
    fail "$access_level user $access_user was unexpectedly added to a sudo/admin group"
  fi
done
sleep 5
for access_user in s241operator s242sudo; do
  bin/sshfling --json password prune --username "$access_user" --delete-users >"$work/$access_user-prune.json"
  python3 - "$work/$access_user-prune.json" "$access_user" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
expected_user = sys.argv[2]
assert payload["ok"] is True, payload
assert payload["count"] == 1, payload
result = payload["results"][0]
assert result["username"] == expected_user, result
assert result["status"] == "pruned", result
assert result["config"]["removed"] is True, result
assert result["metadata"]["removed"] is True, result
assert result["user"]["deleted"] is True, result
PY
  if id -u "$access_user" >/dev/null 2>&1; then
    fail "expired classified access user $access_user was not deleted"
  fi
done
sshd -t

grep -q "Match User s234" /etc/ssh/sshd_config.d/91-sshfling-password-s234.conf
grep -q "ForceCommand /usr/local/libexec/sshfling-session --max-seconds 20 --max-connections 1 --username s234 --login-user s234 --policy-file /etc/sshfling/policy.json --expires-at" /etc/ssh/sshd_config.d/91-sshfling-password-s234.conf
test -f /var/lib/sshfling/password-grants/s234.json
grep -q '"created_user": true' /var/lib/sshfling/password-grants/s234.json
grep -q '"user_uid":' /var/lib/sshfling/password-grants/s234.json
grep -q '"user_gid":' /var/lib/sshfling/password-grants/s234.json

sshd -t
kill "$sshd_pid"
wait "$sshd_pid" 2>/dev/null || true
/usr/sbin/sshd -D -e -p 2222 >"$work/sshd-password.log" 2>&1 &
sshd_pid="$!"
sleep 0.5

SSHPASS="$SSHPASS" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s234@127.0.0.1 \
  'whoami' >"$work/password-whoami.out"
grep -q '^s234$' "$work/password-whoami.out"

for _ in $(seq 1 50); do
  if bin/sshfling --json list --username s234 | grep -Eq '"count"[[:space:]]*:[[:space:]]*0'; then
    break
  fi
  sleep 0.1
done
bin/sshfling --json list --username s234 | grep -Eq '"count"[[:space:]]*:[[:space:]]*0'

SSHPASS="$SSHPASS" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s234@127.0.0.1 \
  'echo password-hold; sleep 5' >"$work/password-hold.out" 2>"$work/password-hold.err" &
password_hold_pid="$!"
for _ in $(seq 1 50); do
  if grep -q '^password-hold$' "$work/password-hold.out" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
if ! grep -q '^password-hold$' "$work/password-hold.out"; then
  fail "password hold session did not start"
fi

set +e
SSHPASS="$SSHPASS" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s234@127.0.0.1 \
  'whoami' >"$work/password-second.out" 2>"$work/password-second.err"
password_second_code="$?"
set -e
if [[ "$password_second_code" -eq 0 ]]; then
  fail "expected second concurrent password session to be rejected"
fi
grep -q "Maximum active sshfling sessions reached" "$work/password-second.err"
wait "$password_hold_pid" || true

sleep 21
set +e
SSHPASS="$SSHPASS" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s234@127.0.0.1 \
  'whoami' >"$work/password-expired.out" 2>"$work/password-expired.err"
password_expired_code="$?"
set -e
if [[ "$password_expired_code" -eq 0 ]]; then
  fail "expected expired password grant to reject ssh login"
fi
grep -q "Temporary SSH access expired" "$work/password-expired.err"

log "prune expired password grant removes config and locks the temporary user"
bin/sshfling --json password prune --username s234 >"$work/password-prune.json"
python3 - "$work/password-prune.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["count"] == 1
result = payload["results"][0]
assert result["status"] == "pruned"
assert result["config"]["removed"] is True
assert result["metadata"]["removed"] is True
assert result["user"]["locked"] is True
PY
test ! -e /etc/ssh/sshd_config.d/91-sshfling-password-s234.conf
test ! -e /var/lib/sshfling/password-grants/s234.json
grep -Eq '^s234:!' /etc/shadow
sshd -t

log "password prune --all --delete-users removes only expired managed users"
bin/sshfling --json -t 90s \
  --username s235active >"$work/password-active.json"
bin/sshfling --json -t 1s \
  --username s236expired >"$work/password-expired-grant.json"
bin/sshfling --json -t 1s \
  --username s237guard >"$work/password-guard-grant.json"
rm -f /etc/ssh/sshd_config.d/91-sshfling-password-s237guard.conf
bin/sshfling --json -t 1s \
  --username s239named >"$work/password-named-expired-grant.json"
useradd --create-home --shell /bin/sh s238existing
bin/sshfling --json -t 1s \
  --username s238existing \
  --allow-existing-user >"$work/password-existing-grant.json"
python3 - "$work/password-active.json" "$work/password-expired-grant.json" "$work/password-named-expired-grant.json" "$work/password-prune-users.env" <<'PY'
import json
import sys

active = json.load(open(sys.argv[1]))
expired = json.load(open(sys.argv[2]))
named = json.load(open(sys.argv[3]))
with open(sys.argv[4], "w") as out:
    out.write(f"SSHPASS_ACTIVE={active['password']}\n")
    out.write(f"SSHPASS_EXPIRED={expired['password']}\n")
    out.write(f"SSHPASS_NAMED={named['password']}\n")
PY
# shellcheck source=/dev/null
source "$work/password-prune-users.env"

set +e
bin/sshfling --json password prune --delete-users >"$work/password-prune-ambiguous.json"
password_prune_ambiguous_code="$?"
set -e
if [[ "$password_prune_ambiguous_code" -eq 0 ]]; then
  fail "password prune --delete-users without --username or --all unexpectedly succeeded"
fi
grep -q "exactly one" "$work/password-prune-ambiguous.json"

log "password prune --username --delete-users protects active managed users"
bin/sshfling --json password prune --username s235active --delete-users >"$work/password-prune-active-user.json"
python3 - "$work/password-prune-active-user.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["count"] == 1
result = payload["results"][0]
assert result["username"] == "s235active", result
assert result["status"] == "active", result
assert "user" not in result, result
assert "config" not in result, result
assert "metadata" not in result, result
PY
id -u s235active >/dev/null
test -e /etc/ssh/sshd_config.d/91-sshfling-password-s235active.conf
test -e /var/lib/sshfling/password-grants/s235active.json

sleep 2
log "password prune --username --delete-users removes expired managed users"
bin/sshfling --json password prune --username s239named --delete-users >"$work/password-prune-named-expired.json"
python3 - "$work/password-prune-named-expired.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["count"] == 1
result = payload["results"][0]
assert result["username"] == "s239named", result
assert result["status"] == "pruned", result
assert result["config"]["removed"] is True, result
assert result["metadata"]["removed"] is True, result
assert result["user"]["deleted"] is True, result
PY
if id -u s239named >/dev/null 2>&1; then
  fail "expired password prune --username did not delete s239named"
fi
if getent group s239named >/dev/null 2>&1; then
  fail "expired password prune --username did not remove s239named primary group"
fi
test ! -e /etc/ssh/sshd_config.d/91-sshfling-password-s239named.conf
test ! -e /var/lib/sshfling/password-grants/s239named.json
sshd -t

log "targeted deleted password user cannot authenticate with old password"
set +e
SSHPASS="$SSHPASS_NAMED" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s239named@127.0.0.1 \
  'whoami' >"$work/password-named-deleted-auth.out" 2>"$work/password-named-deleted-auth.err"
password_named_deleted_code="$?"
set -e
if [[ "$password_named_deleted_code" -eq 0 ]]; then
  fail "targeted deleted expired password user authenticated with old password"
fi
if grep -q '^s239named$' "$work/password-named-deleted-auth.out"; then
  fail "targeted deleted expired password user produced a successful whoami result"
fi

log "password prune --username --delete-users refuses mismatched reused user identity"
bin/sshfling --json -t 1s \
  --username s240reuse >"$work/password-reuse-grant.json"
python3 - <<'PY'
import json
from pathlib import Path

path = Path("/var/lib/sshfling/password-grants/s240reuse.json")
metadata = json.loads(path.read_text())
metadata["user_uid"] = int(metadata.get("user_uid", 0)) + 100000
metadata["user_gid"] = int(metadata.get("user_gid", 0)) + 100000
metadata["user_home"] = "/home/s240reuse-recreated"
path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
PY
sleep 2
bin/sshfling --json password prune --username s240reuse --delete-users >"$work/password-prune-reuse.json"
python3 - "$work/password-prune-reuse.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert payload["count"] == 1
result = payload["results"][0]
assert result["status"] == "skipped-user-mismatch", result
assert "config" not in result, result
assert "metadata" not in result, result
assert result["user"]["status"] == "skipped-user-mismatch", result
PY
id -u s240reuse >/dev/null
test -e /etc/ssh/sshd_config.d/91-sshfling-password-s240reuse.conf
test -e /var/lib/sshfling/password-grants/s240reuse.json
userdel --remove s240reuse >/dev/null 2>&1 || userdel s240reuse >/dev/null 2>&1 || true
sshd -t

bin/sshfling --json password prune --all --delete-users >"$work/password-prune-all.json"
python3 - "$work/password-prune-all.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
by_user = {item.get("username"): item for item in payload["results"] if item.get("username")}
assert by_user["s235active"]["status"] == "active", by_user
expired = by_user["s236expired"]
assert expired["status"] == "pruned", by_user
assert expired["config"]["removed"] is True, expired
assert expired["metadata"]["removed"] is True, expired
assert expired["user"]["deleted"] is True, expired
guard = by_user["s237guard"]
assert guard["status"] == "pruned", by_user
assert guard["config"]["status"] == "missing", guard
assert guard["metadata"]["removed"] is True, guard
assert guard["user"]["deleted"] is True, guard
existing = by_user["s238existing"]
assert existing["status"] == "pruned", by_user
assert existing["config"]["removed"] is True, existing
assert existing["metadata"]["removed"] is True, existing
assert existing["user"]["locked"] is True, existing
assert existing["user"]["existing_user"] is True, existing
assert existing["user"]["delete_skipped"] == "existing Unix user was not created by sshfling", existing
reuse = by_user["s240reuse"]
assert reuse["status"] == "pruned", by_user
assert reuse["config"]["removed"] is True, reuse
assert reuse["metadata"]["removed"] is True, reuse
assert reuse["user"]["status"] == "missing", reuse
PY
id -u s235active >/dev/null
if id -u s236expired >/dev/null 2>&1; then
  fail "expired password prune did not delete s236expired"
fi
if getent group s236expired >/dev/null 2>&1; then
  fail "expired password prune did not remove s236expired primary group"
fi
if id -u s237guard >/dev/null 2>&1; then
  fail "expired password prune with missing config did not delete s237guard"
fi
if getent group s237guard >/dev/null 2>&1; then
  fail "expired password prune with missing config did not remove s237guard primary group"
fi
id -u s238existing >/dev/null
test ! -e /etc/ssh/sshd_config.d/91-sshfling-password-s240reuse.conf
test ! -e /var/lib/sshfling/password-grants/s240reuse.json
test -e /etc/ssh/sshd_config.d/91-sshfling-password-s235active.conf
test ! -e /etc/ssh/sshd_config.d/91-sshfling-password-s236expired.conf
test ! -e /etc/ssh/sshd_config.d/91-sshfling-password-s237guard.conf
test ! -e /etc/ssh/sshd_config.d/91-sshfling-password-s238existing.conf
test -e /var/lib/sshfling/password-grants/s235active.json
test ! -e /var/lib/sshfling/password-grants/s236expired.json
test ! -e /var/lib/sshfling/password-grants/s237guard.json
test ! -e /var/lib/sshfling/password-grants/s238existing.json
grep -Eq '^s238existing:!' /etc/shadow
sshd -t

log "active password grant still authenticates after delete-users prune"
SSHPASS="$SSHPASS_ACTIVE" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s235active@127.0.0.1 \
  'whoami' >"$work/password-active-after-prune.out"
grep -q '^s235active$' "$work/password-active-after-prune.out"

log "deleted expired password user cannot authenticate with old password"
set +e
SSHPASS="$SSHPASS_EXPIRED" sshpass -e bin/sshfling \
  -p 2222 \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  s236expired@127.0.0.1 \
  'whoami' >"$work/password-deleted-auth.out" 2>"$work/password-deleted-auth.err"
password_deleted_code="$?"
set -e
if [[ "$password_deleted_code" -eq 0 ]]; then
  fail "deleted expired password user authenticated with old password"
fi
if grep -q '^s236expired$' "$work/password-deleted-auth.out"; then
  fail "deleted expired password user produced a successful whoami result"
fi

log "list and kill named sessions with max connections policy"
for name in s101 s102 s103; do
  bin/sshfling --json --certificate -t 30s \
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
    for name in ["s101", "s102", "s103"]:
        payload = json.load(open(work / f"{name}.json"))
        out.write(f"{name.upper()}_KEY={payload['private_key']}\n")
        out.write(f"{name.upper()}_CERT={payload['out']}\n")
PY
# shellcheck source=/dev/null
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

ssh_cert "$S101_KEY" "$S101_CERT" 'echo s101; sleep 30' >"$work/s101-session.out" 2>"$work/s101-session.err" &
s101_pid="$!"
for _ in $(seq 1 30); do
  if grep -q '^s101$' "$work/s101-session.out" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

ssh_cert "$S102_KEY" "$S102_CERT" 'echo s102; sleep 30' >"$work/s102-session.out" 2>"$work/s102-session.err" &
s102_pid="$!"
for _ in $(seq 1 30); do
  if grep -q '^s102$' "$work/s102-session.out" 2>/dev/null; then
    break
  fi
  sleep 0.1
done

set +e
ssh_cert "$S103_KEY" "$S103_CERT" 'echo s103' >"$work/s103-session.out" 2>"$work/s103-session.err"
s103_code="$?"
set -e
if [[ "$s103_code" -eq 0 ]]; then
  fail "expected third concurrent session to be rejected"
fi
grep -q "Maximum active sshfling sessions reached" "$work/s103-session.err"

bin/sshfling --json list --login-user root >"$work/list-two.json"
python3 - "$work/list-two.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
names = {session["username"] for session in payload["sessions"]}
assert {"s101", "s102"}.issubset(names), names
PY

bin/sshfling -k s101 >"$work/kill-s101.out"
grep -q "killed 1 active sshfling session" "$work/kill-s101.out"
set +e
wait "$s101_pid"
s101_code="$?"
set -e
if [[ "$s101_code" -eq 0 ]]; then
  fail "expected sshfling -k s101 to terminate only s101"
fi

bin/sshfling --json list --login-user root >"$work/list-one.json"
python3 - "$work/list-one.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
names = {session["username"] for session in payload["sessions"]}
assert "s101" not in names, names
assert "s102" in names, names
PY

bin/sshfling shutdown s102 >"$work/kill-s102.out"
grep -q "killed 1 active sshfling session" "$work/kill-s102.out"
set +e
wait "$s102_pid"
s102_code="$?"
set -e
if [[ "$s102_code" -eq 0 ]]; then
  fail "expected sshfling shutdown s102 to terminate s102"
fi

log "forced session timeout kills long command"
bin/sshfling --json --certificate -t 8s \
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
# shellcheck source=/dev/null
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
issuer_token="$(printf '%s%s%s%s' "01234567" "89abcdef" "01234567" "89abcdef")"
SSHFLING_ISSUER_TOKEN="$issuer_token" bin/sshfling serve \
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

python3 - "$work/api-client.pub" "$work/api-response.json" "$issuer_token" <<'PY'
import importlib.machinery
import importlib.util
import json
import sys
import urllib.error
import urllib.request

loader = importlib.machinery.SourceFileLoader("sshfling_module", "bin/sshfling")
spec = importlib.util.spec_from_loader(loader.name, loader)
sshfling = importlib.util.module_from_spec(spec)
loader.exec_module(sshfling)

public_key = open(sys.argv[1]).read().strip()
token = sys.argv[3]
url = "http://127.0.0.1:8877/v1/certificates"

def post_body(body, bearer_token=token):
    req = urllib.request.Request(
        url,
        data=body,
        headers={"Authorization": f"Bearer {bearer_token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, response.read().decode()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read().decode()

def post_json(payload, bearer_token=token):
    return post_body(json.dumps(payload).encode(), bearer_token)

status, _ = post_json({"public_key": public_key, "principal": "temp-api", "seconds": 30, "login_user": "root"})
assert status == 400, status

oversized = b'{"public_key":"' + (b"x" * (sshfling.MAX_HTTP_BODY_BYTES + 1)) + b'","principal":"temp-api"}'
status, _ = post_body(oversized)
assert status == 413, status

status, payload = post_json({"public_key": public_key, "principal": "temp-api", "seconds": 30})
assert status == 200, (status, payload)
open(sys.argv[2], "w").write(payload)

seen_rate_limit = False
wrong_token = "".join(["fedcba98", "76543210", "fedcba98", "76543210"])
for _ in range(sshfling.ISSUER_POST_RATE_LIMIT + 2):
    status, _ = post_json({"public_key": public_key, "principal": "temp-api", "seconds": 30}, wrong_token)
    if status == 429:
        seen_rate_limit = True
        break
assert seen_rate_limit, "issuer POST rate limit did not trigger"
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

log "certificate setup can generate a random username"
bin/sshfling --json --certificate -t 20s \
  --ca-key "$work/ca_user_ed25519" \
  >"$work/random-setup.json"
python3 - "$work/random-setup.json" <<'PY'
import json
import re
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
assert re.fullmatch(r"s[0-9]{6}", payload["username"]), payload["username"]
assert payload["generated_key"] is True
assert payload["private_key"]
assert payload["out"]
PY

log "certificate setup requires an explicit lifetime"
set +e
bin/sshfling --json --certificate \
  --ca-key "$work/ca_user_ed25519" \
  >"$work/default-setup.json"
default_setup_code="$?"
set -e
if [[ "$default_setup_code" -eq 0 ]]; then
  fail "expected certificate setup without -t to fail"
fi
grep -q "explicit -t/--time" "$work/default-setup.json"

set +e
bin/sshfling --json --certificate --dry-run -t 20s \
  --ca-key "$work/ca_user_ed25519" \
  --session-dir "$work/cert-dry-run-sessions" \
  >"$work/cert-dry-run.json"
cert_dry_run_code="$?"
set -e
if [[ "$cert_dry_run_code" -eq 0 ]]; then
  fail "expected certificate dry-run to fail without writing key material"
fi
grep -q "does not support --dry-run" "$work/cert-dry-run.json"
test ! -e "$work/cert-dry-run-sessions"

set +e
bin/sshfling --json --certificate -t 20s \
  --ca-key "$work/missing-ca-user" \
  >"$work/cert-missing-ca.json"
cert_missing_ca_code="$?"
set -e
if [[ "$cert_missing_ca_code" -eq 0 ]]; then
  fail "expected certificate setup with missing CA to fail"
fi
grep -q "CA keypair does not exist" "$work/cert-missing-ca.json"

log "bare sshfling requires explicit lifetime"
set +e
bin/sshfling --json --dry-run >"$work/default-password-setup.json"
default_password_setup_code="$?"
set -e
if [[ "$default_password_setup_code" -eq 0 ]]; then
  fail "expected bare password setup without -t to fail"
fi
python3 - "$work/default-password-setup.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is False
assert "explicit -t/--time" in payload["error"]["message"], payload
PY

log "custom user-specific install policy caps default and requested time"
bin/sshfling policy install --policy-file "$work/short-policy.json" --user root --max-time 45s --max-connections 2 --access-level admin >/dev/null
set +e
bin/sshfling --policy-file "$work/short-policy.json" \
  --certificate \
  --ca-key "$work/ca_user_ed25519" \
  --username s201 \
  --login-user root \
  -t 46s >"$work/short-too-long.out" 2>"$work/short-too-long.err"
short_too_long_code="$?"
set -e
if [[ "$short_too_long_code" -eq 0 ]]; then
  fail "expected policy max-time 45s to reject 46s"
fi
grep -q "cannot exceed 45s" "$work/short-too-long.err"
bin/sshfling --json --certificate \
  --policy-file "$work/short-policy.json" \
  --login-user root \
  -t 45s \
  --ca-key "$work/ca_user_ed25519" >"$work/short-default.json"
python3 - "$work/short-default.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["seconds"] == 45
PY

log "create-user path unlocks generated account for certificate ssh"
bin/sshfling host install \
  --ca-pub "$work/ca_user_ed25519.pub" \
  --username sshflingtmp \
  --principal sshflingtmp \
  --create-user \
  --no-validate

sshd -t
kill "$sshd_pid"
wait "$sshd_pid" 2>/dev/null || true
/usr/sbin/sshd -D -e -p 2222 >"$work/sshd2.log" 2>&1 &
sshd_pid="$!"
sleep 0.5

bin/sshfling --json --certificate -t 20s \
  --ca-key "$work/ca_user_ed25519" \
  --username sshflingtmp >"$work/created-setup.json"
python3 - "$work/created-setup.json" "$work/created.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as out:
    out.write(f"CREATED_KEY={payload['private_key']}\n")
    out.write(f"CREATED_CERT={payload['out']}\n")
PY
# shellcheck source=/dev/null
source "$work/created.env"

ssh \
  -i "$CREATED_KEY" \
  -o "CertificateFile=$CREATED_CERT" \
  -o "BatchMode=yes" \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  -p 2222 \
  sshflingtmp@127.0.0.1 'whoami' >"$work/created-whoami.out"
grep -q '^sshflingtmp$' "$work/created-whoami.out"

log "host uninstall removes managed certificate host config"
bin/sshfling --json host uninstall \
  --username sshflingtmp \
  --principal sshflingtmp \
  --no-validate >"$work/host-uninstall.json"
python3 - "$work/host-uninstall.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
paths = {item.get("path"): item for item in payload["results"] if "path" in item}
assert paths["/etc/ssh/sshd_config.d/90-sshfling-temp-access.conf"]["removed"] is True
assert paths["/etc/ssh/auth_principals/sshflingtmp"]["removed"] is True
PY
test ! -e /etc/ssh/sshd_config.d/90-sshfling-temp-access.conf
test ! -e /etc/ssh/auth_principals/sshflingtmp
test -e /etc/ssh/sshfling_user_ca.pub
test -e /usr/local/libexec/sshfling-session
sshd -t

log "removed certificate host config denies the old certificate"
kill "$sshd_pid"
wait "$sshd_pid" 2>/dev/null || true
/usr/sbin/sshd -D -e -p 2222 >"$work/sshd-uninstalled.log" 2>&1 &
sshd_pid="$!"
sleep 0.5
set +e
ssh \
  -i "$CREATED_KEY" \
  -o "CertificateFile=$CREATED_CERT" \
  -o "BatchMode=yes" \
  -o "PreferredAuthentications=publickey" \
  -o "PasswordAuthentication=no" \
  -o "NumberOfPasswordPrompts=0" \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  -p 2222 \
  sshflingtmp@127.0.0.1 'whoami' >"$work/uninstalled-auth.out" 2>"$work/uninstalled-auth.err"
uninstalled_auth_code="$?"
set -e
if [[ "$uninstalled_auth_code" -eq 0 ]]; then
  fail "certificate login succeeded after host uninstall removed managed config"
fi
if grep -q '^sshflingtmp$' "$work/uninstalled-auth.out"; then
  fail "uninstalled certificate host config produced a successful whoami result"
fi

log "failed certificate host reinstall rolls back files and created user"
printf 'original host config\n' >"$work/revert-unincluded.conf"
set +e
bin/sshfling --json host install \
  --ca-pub "$work/ca_user_ed25519.pub" \
  --trusted-ca "$work/revert-ca.pub" \
  --principals-dir "$work/revert-principals" \
  --session-wrapper "$work/revert-wrapper" \
  --sshd-config "$work/revert-unincluded.conf" \
  --policy-file "$work/revert-policy.json" \
  --username sshflingrevert \
  --principal sshflingrevert \
  --max-time 30s \
  --create-user >"$work/host-revert.json" 2>"$work/host-revert.err"
host_revert_code="$?"
set -e
if [[ "$host_revert_code" -eq 0 ]]; then
  fail "expected host install validation failure to trigger rollback"
fi
python3 - "$work/host-revert.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is False, payload
error = payload["error"]
assert "not active" in error["message"], error
rollback = error["details"].get("rollback")
assert rollback, error
paths = {item.get("path"): item for item in rollback if "path" in item}
assert paths, rollback
PY
grep -Fxq "original host config" "$work/revert-unincluded.conf"
test ! -e "$work/revert-ca.pub"
test ! -e "$work/revert-principals/sshflingrevert"
test ! -e "$work/revert-wrapper"
test ! -e "$work/revert-policy.json"
if id -u sshflingrevert >/dev/null 2>&1; then
  fail "host install rollback did not delete created sshflingrevert user"
fi
sshd -t

log "certificate host config can be reinstalled after uninstall"
bin/sshfling host install \
  --ca-pub "$work/ca_user_ed25519.pub" \
  --username sshflingtmp \
  --principal sshflingtmp \
  --create-user \
  --no-validate
sshd -t
kill "$sshd_pid"
wait "$sshd_pid" 2>/dev/null || true
/usr/sbin/sshd -D -e -p 2222 >"$work/sshd-reinstalled.log" 2>&1 &
sshd_pid="$!"
sleep 0.5

bin/sshfling --json --certificate -t 20s \
  --ca-key "$work/ca_user_ed25519" \
  --username sshflingtmp >"$work/reinstalled-setup.json"
python3 - "$work/reinstalled-setup.json" "$work/reinstalled.env" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
with open(sys.argv[2], "w") as out:
    out.write(f"REINSTALLED_KEY={payload['private_key']}\n")
    out.write(f"REINSTALLED_CERT={payload['out']}\n")
PY
# shellcheck source=/dev/null
source "$work/reinstalled.env"

ssh \
  -i "$REINSTALLED_KEY" \
  -o "CertificateFile=$REINSTALLED_CERT" \
  -o "BatchMode=yes" \
  -o "StrictHostKeyChecking=yes" \
  -o "UserKnownHostsFile=$work/known_hosts" \
  -p 2222 \
  sshflingtmp@127.0.0.1 'whoami' >"$work/reinstalled-whoami.out"
grep -q '^sshflingtmp$' "$work/reinstalled-whoami.out"

log "host uninstall can remove shared certificate assets and generated user"
bin/sshfling --json host uninstall \
  --username sshflingtmp \
  --principal sshflingtmp \
  --remove-ca \
  --remove-wrapper \
  --delete-user \
  --no-validate >"$work/host-final-uninstall.json"
python3 - "$work/host-final-uninstall.json" <<'PY'
import json
import sys
payload = json.load(open(sys.argv[1]))
assert payload["ok"] is True
paths = {item.get("path"): item for item in payload["results"] if "path" in item}
assert paths["/etc/ssh/sshd_config.d/90-sshfling-temp-access.conf"]["removed"] is True
assert paths["/etc/ssh/auth_principals/sshflingtmp"]["removed"] is True
assert paths["/etc/ssh/sshfling_user_ca.pub"]["removed"] is True
assert paths["/usr/local/libexec/sshfling-session"]["removed"] is True
users = {item.get("user"): item for item in payload["results"] if "user" in item}
assert users["sshflingtmp"]["deleted"] is True
PY
test ! -e /etc/ssh/sshd_config.d/90-sshfling-temp-access.conf
test ! -e /etc/ssh/auth_principals/sshflingtmp
test ! -e /etc/ssh/sshfling_user_ca.pub
test ! -e /usr/local/libexec/sshfling-session
if id -u sshflingtmp >/dev/null 2>&1; then
  fail "host uninstall --delete-user did not delete sshflingtmp"
fi
sshd -t

log "all docker integration checks passed"
