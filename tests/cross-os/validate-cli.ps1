param(
  [Parameter(Mandatory = $true)]
  [string]$CommandPath,

  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = "Stop"
$hasNativeCommandUseErrorActionPreference = Test-Path Variable:\PSNativeCommandUseErrorActionPreference
$previousNativeCommandUseErrorActionPreference = $null
if ($hasNativeCommandUseErrorActionPreference) {
  $previousNativeCommandUseErrorActionPreference = $PSNativeCommandUseErrorActionPreference
  $PSNativeCommandUseErrorActionPreference = $false
}

function Fail([string]$Message) {
  throw "cross validation failed: $Message"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sshfling-cross-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$activeMarker = Join-Path $tempRoot "replace-active.ready"
$env:SSHFLING_ACTIVE_MARKER = $activeMarker
$sleep30Command = @("python", "-c", "import os, pathlib, time; pathlib.Path(os.environ['SSHFLING_ACTIVE_MARKER']).write_text('ready'); time.sleep(30)")

try {
  $versionOutput = (& $CommandPath --version | Out-String).Trim()
  if ($versionOutput -ne "sshfling $Version") {
    Fail "unexpected version output: $versionOutput"
  }

  $helpOutput = (& $CommandPath --help | Out-String)
  if (-not $helpOutput.Contains("Grant or kill temporary SSH access.")) {
    Fail "help output missing expected description"
  }

  $env:SSHFLING_WEB_PASSWORD = "cross-test-password"
  $hashOutput = (& $CommandPath web-hash | Out-String).Trim()
  if (-not $hashOutput.StartsWith("pbkdf2_sha256`$")) {
    Fail "web-hash output did not use pbkdf2_sha256"
  }
  Remove-Item Env:\SSHFLING_WEB_PASSWORD -ErrorAction SilentlyContinue

  $policyPath = Join-Path $tempRoot "missing-policy.json"
  $policyJson = (& $CommandPath --json policy show --policy-file $policyPath | Out-String)
  $policy = $policyJson | ConvertFrom-Json
  if (-not $policy.ok) {
    Fail "policy show returned ok=false"
  }
  if ($policy.effective.max_time_seconds -ne 86400 -or $policy.effective.max_connections -ne 10) {
    Fail "policy defaults were not stable"
  }
  if ($policy.policy.version -ne 2) {
    Fail "policy schema version was not stable"
  }

  $env:SSHFLING_CONNECT_DRY_RUN = "1"
  $env:SSHFLING_SSH_BIN = "ssh"
  $connectOutput = (& $CommandPath -p 2222 s123@example.invalid whoami | Out-String).Trim()
  Remove-Item Env:\SSHFLING_CONNECT_DRY_RUN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SSH_BIN -ErrorAction SilentlyContinue
  foreach ($needle in @(
      "PreferredAuthentications=password,keyboard-interactive",
      "PubkeyAuthentication=no",
      "-p 2222",
      "s123@example.invalid",
      "whoami"
    )) {
    if (-not $connectOutput.Contains($needle)) {
      Fail "connect dry-run missing $needle"
    }
  }

  $detachedDir = Join-Path $tempRoot "detached"
  $detachedStartJson = (& $CommandPath --json detached start --name cross --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "import time; print('detached-ready', flush=True); time.sleep(30)" | Out-String)
  $detachedStart = $detachedStartJson | ConvertFrom-Json
  if (-not $detachedStart.ok -or $detachedStart.job.name -ne "cross" -or $detachedStart.job.status -ne "processing") {
    Fail "detached start did not return a processing job"
  }
  if ($detachedStart.job.pid -le 0 -or $detachedStart.job.supervisor_pid -le 0) {
    Fail "detached start did not report process and supervisor PIDs"
  }
  $detachedListJson = (& $CommandPath --json detached list --detached-dir $detachedDir | Out-String)
  $detachedList = $detachedListJson | ConvertFrom-Json
  if (-not $detachedList.ok -or $detachedList.count -ne 1 -or $detachedList.jobs[0].pid -ne $detachedStart.job.pid) {
    Fail "detached list did not report the started job"
  }
  $detachedKillJson = (& $CommandPath --json detached kill --detached-dir $detachedDir cross | Out-String)
  $detachedKill = $detachedKillJson | ConvertFrom-Json
  if (-not $detachedKill.ok -or $detachedKill.job.status -ne "killed" -or $detachedKill.killed -lt 1) {
    Fail "detached kill did not stop the started job: $($detachedKillJson.Trim())"
  }
  $null = (& $CommandPath detached start --name plain --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "import time; time.sleep(30)" | Out-String).Trim()
  $plainKillOutput = (& $CommandPath detached kill --detached-dir $detachedDir plain | Out-String).Trim()
  if (-not [regex]::IsMatch($plainKillOutput, "^killed [1-9][0-9]* detached process\(es\)$")) {
    Fail "plain detached kill output was not stable: $plainKillOutput"
  }
  $missingCwd = Join-Path $tempRoot "missing-cwd"
  $startFailsRaw = & $CommandPath --json detached start --name start-fails --time 30s --cwd $missingCwd --detached-dir $detachedDir -- python -c "print('bad')" 2>&1
  $startFailsCode = $LASTEXITCODE
  $startFailsJson = ($startFailsRaw | Out-String)
  if ($startFailsCode -eq 0) {
    Fail "detached start reported success for a command that never started: $($startFailsJson.Trim())"
  }
  $startFails = $startFailsJson | ConvertFrom-Json
  if ($startFails.ok -ne $false -or -not $startFails.error.message.Contains("Detached job failed to start")) {
    Fail "detached start failure JSON was not stable: $($startFailsJson.Trim())"
  }
  $startFailsJob = $startFails.error.details.job
  if ($startFailsJob.name -ne "start-fails" -or $startFailsJob.status -ne "failed" -or $null -ne $startFailsJob.pid -or -not $startFailsJob.error) {
    Fail "detached start failure job details were not stable: $($startFailsJson.Trim())"
  }
  $replaceActiveStartJson = (& $CommandPath --json detached start --name replace-active --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @sleep30Command | Out-String)
  $replaceActiveStart = $replaceActiveStartJson | ConvertFrom-Json
  if (-not $replaceActiveStart.ok -or $replaceActiveStart.job.status -ne "processing") {
    Fail "active detached replacement setup was not processing: $($replaceActiveStartJson.Trim())"
  }
  $replaceActiveReady = $false
  for ($attempt = 0; $attempt -lt 50; $attempt++) {
    if (Test-Path $activeMarker) {
      $replaceActiveReady = $true
      break
    }
    Start-Sleep -Milliseconds 200
  }
  if (-not $replaceActiveReady) {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-active | Out-String)
    Fail "active detached replacement setup did not start child command: $($replaceActiveStartJson.Trim())"
  }
  $replaceActiveListJson = (& $CommandPath --json detached list --name replace-active --detached-dir $detachedDir | Out-String)
  $replaceActiveList = $replaceActiveListJson | ConvertFrom-Json
  $replaceActiveJobs = @($replaceActiveList.jobs)
  if ($replaceActiveJobs.Count -ne 1 -or $replaceActiveJobs[0].status -ne "processing") {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-active | Out-String)
    Fail "active detached replacement setup was not still processing: $($replaceActiveListJson.Trim())"
  }
  $replaceActiveRaw = & $CommandPath --json detached start --replace --name replace-active --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "print('bad')" 2>&1
  $replaceActiveCode = $LASTEXITCODE
  $replaceActiveJson = ($replaceActiveRaw | Out-String)
  if ($replaceActiveCode -eq 0) {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-active | Out-String)
    Fail "active detached job was replaced: $($replaceActiveJson.Trim())"
  }
  if (-not $replaceActiveJson.Contains("already active")) {
    Fail "active detached replace did not explain the active job: $($replaceActiveJson.Trim())"
  }
  $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-active | Out-String)
  $null = (& $CommandPath --json detached start --name replace-done --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "print('first', flush=True)" | Out-String)
  $replaceDoneSeen = $false
  for ($attempt = 0; $attempt -lt 10; $attempt++) {
    $replaceDoneListJson = (& $CommandPath --json detached list --name replace-done --detached-dir $detachedDir | Out-String)
    $replaceDoneList = $replaceDoneListJson | ConvertFrom-Json
    $replaceDoneJobs = @($replaceDoneList.jobs)
    if ($replaceDoneJobs.Count -gt 0 -and $replaceDoneJobs[0].status -eq "completed") {
      $replaceDoneSeen = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $replaceDoneSeen) {
    Fail "detached replacement setup did not reach completed status"
  }
  $replaceDoneRaw = & $CommandPath --json detached start --name replace-done --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "print('bad')" 2>&1
  $replaceDoneCode = $LASTEXITCODE
  $replaceDoneJson = ($replaceDoneRaw | Out-String)
  if ($replaceDoneCode -eq 0) {
    Fail "inactive detached job was replaced without --replace: $($replaceDoneJson.Trim())"
  }
  if (-not $replaceDoneJson.Contains("Use --replace after it is inactive")) {
    Fail "inactive detached replace did not require --replace: $($replaceDoneJson.Trim())"
  }
  $null = (& $CommandPath --json detached start --replace --name replace-done --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "import time; print('second', flush=True); time.sleep(30)" | Out-String)
  $replaceDoneLog = Join-Path $detachedDir "replace-done.out.log"
  $replaceSecondSeen = $false
  for ($attempt = 0; $attempt -lt 5; $attempt++) {
    $replaceDoneContent = Get-Content -Raw -Path $replaceDoneLog -ErrorAction SilentlyContinue
    if ($replaceDoneContent -like "*second*") {
      $replaceSecondSeen = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $replaceSecondSeen) {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-done | Out-String)
    Fail "detached --replace did not start the replacement job"
  }
  if ((Get-Content -Raw -Path $replaceDoneLog) -like "*first*") {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-done | Out-String)
    Fail "detached --replace did not reset stdout log"
  }
  $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-done | Out-String)
  $tooLongRaw = & $CommandPath --json detached start --name too-long --time 25h --detached-dir $detachedDir -- python -c "print('no')" 2>&1
  $tooLongCode = $LASTEXITCODE
  $tooLongJson = ($tooLongRaw | Out-String)
  $tooLong = $tooLongJson | ConvertFrom-Json
  if ($tooLongCode -eq 0 -or $tooLong.ok -ne $false -or -not $tooLong.error.message.Contains("cannot exceed 24 hours")) {
    Fail "detached 25h start was not rejected with the 24h cap: $($tooLongJson.Trim())"
  }

  $importCheck = Join-Path $tempRoot "import-check.py"
  @'
import importlib.machinery
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import sys
import tempfile
import time

command_path = Path(sys.argv[1])
candidates = [
    command_path,
    command_path.with_suffix(".py"),
    command_path.parent / "sshfling.py",
]
last_syntax_error = None
for candidate in candidates:
    if not candidate.exists():
        continue
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
    return SimpleNamespace(**values)

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
    root = Path(tmpdir)
    grant_dir = root / "grants"
    conf_dir = root / "sshd_config.d"
    grant_dir.mkdir()
    conf_dir.mkdir()
    now = int(time.time())

    fixtures = [
        ("sshflingactive", True, now + 3600, {"managed_by": "sshfling", "auth": "password"}),
        ("sshflingexpired", True, now - 60, {"managed_by": "sshfling", "auth": "password"}),
        ("sshflingexisting", False, now - 60, {"managed_by": "sshfling", "auth": "password"}),
        ("sshflingunmanaged", True, now - 60, {}),
        ("sshflingmissingconfig", True, now - 60, {"managed_by": "sshfling", "auth": "password", "config_path": None}),
    ]
    for username, created_user, expires_at, extra in fixtures:
        conf = conf_dir / f"91-sshfling-password-{username}.conf"
        conf.write_text(f"# Managed by sshfling password grant for {username}.\n", encoding="utf-8")
        metadata = {
            "username": username,
            "created_user": created_user,
            "expires_at": expires_at,
            "config_path": str(conf),
        }
        metadata.update(extra)
        if metadata.get("config_path") is None:
            metadata.pop("config_path", None)
        (grant_dir / f"{username}.json").write_text(json.dumps(metadata), encoding="utf-8")
    spoof_conf = conf_dir / "91-sshfling-password-root.conf"
    spoof_conf.write_text("# Managed by sshfling password grant for root.\n", encoding="utf-8")
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
            sshfling.cmd_setup_password(SimpleNamespace(
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
        sshfling.cmd_setup_password(SimpleNamespace(
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
            sshfling.cmd_host_install(SimpleNamespace(
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
'@ | Set-Content -Encoding ASCII $importCheck
  & python $importCheck $CommandPath
  if ($LASTEXITCODE -ne 0) {
    Fail "Python import-level CLI contract checks failed"
  }

  $project = Join-Path $tempRoot "project"
  $initJson = (& $CommandPath --json init $project --session-seconds 60 --host-port 2222 | Out-String)
  $init = $initJson | ConvertFrom-Json
  if (-not $init.ok) {
    Fail "init returned ok=false"
  }
  if (-not $init.template_dir) {
    Fail "init did not report a template directory"
  }

  foreach ($relative in @(
      ".env",
      ".env.example",
      "README.md",
      "LICENSE",
      "compose.server.yml",
      "compose.client.yml",
      "scripts\install-local.sh",
      "scripts\uninstall-local.sh",
      "scripts\create-network.sh",
      "scripts\generate-ssh-key.sh",
      "secrets\.gitkeep",
      "ssh-client\Dockerfile",
      "ssh-client\entrypoint.sh",
      "ssh-server\Dockerfile",
      "ssh-server\entrypoint.sh",
      "ssh-server\limited-session.sh",
      "ssh-server\sshd_config",
      "production\sshfling-session",
      "systemd\sshflingd.service",
      "systemd\sshflingd.env.example"
    )) {
    $path = Join-Path $project $relative
    if (-not (Test-Path $path)) {
      Fail "init did not create $relative"
    }
  }

  $envContent = (Get-Content -Raw -Path (Join-Path $project ".env"))
  if (-not $envContent.Contains("SSH_SESSION_SECONDS=60")) {
    Fail "init did not write SSH_SESSION_SECONDS"
  }
  if (-not $envContent.Contains("SSH_PORT_ON_HOST=2222")) {
    Fail "init did not write SSH_PORT_ON_HOST"
  }
  $systemdEnv = Get-Content -Raw -Path (Join-Path $project "systemd\sshflingd.env.example")
  if (-not $systemdEnv.Contains("SSHFLING_MAX_SECONDS=86400")) {
    Fail "systemd env did not default SSHFLING_MAX_SECONDS to 86400"
  }
  $productionWrapper = Get-Content -Raw -Path (Join-Path $project "production\sshfling-session")
  if (-not $productionWrapper.Contains("max_allowed_seconds=86400")) {
    Fail "production wrapper did not allow 24h sessions"
  }
  $dockerWrapper = Get-Content -Raw -Path (Join-Path $project "ssh-server\limited-session.sh")
  if (-not $dockerWrapper.Contains("max_allowed_seconds=86400")) {
    Fail "docker wrapper did not allow 24h sessions"
  }

  Write-Output "cross validation ok: $CommandPath $Version"
}
finally {
  Remove-Item -Recurse -Force $tempRoot -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_WEB_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_CONNECT_DRY_RUN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SSH_BIN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_ACTIVE_MARKER -ErrorAction SilentlyContinue
  if ($hasNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $previousNativeCommandUseErrorActionPreference
  }
}
