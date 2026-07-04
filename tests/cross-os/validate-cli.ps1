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
  $null = (& $CommandPath --json detached start --name replace-active --time 30s --cwd $tempRoot --detached-dir $detachedDir -- python -c "import time; time.sleep(30)" | Out-String)
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
    if ((Test-Path $replaceDoneLog) -and (Get-Content -Raw -Path $replaceDoneLog).Contains("second")) {
      $replaceSecondSeen = $true
      break
    }
    Start-Sleep -Seconds 1
  }
  if (-not $replaceSecondSeen) {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-done | Out-String)
    Fail "detached --replace did not start the replacement job"
  }
  if ((Get-Content -Raw -Path $replaceDoneLog).Contains("first")) {
    $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-done | Out-String)
    Fail "detached --replace did not reset stdout log"
  }
  $null = (& $CommandPath --json detached kill --detached-dir $detachedDir replace-done | Out-String)
  $tooLongJson = (& $CommandPath --json detached start --name too-long --time 25h --detached-dir $detachedDir -- python -c "print('no')" | Out-String)
  $tooLong = $tooLongJson | ConvertFrom-Json
  if ($tooLong.ok -ne $false -or -not $tooLong.error.message.Contains("cannot exceed 24 hours")) {
    Fail "detached 25h start was not rejected with the 24h cap"
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
  if ($hasNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $previousNativeCommandUseErrorActionPreference
  }
}
