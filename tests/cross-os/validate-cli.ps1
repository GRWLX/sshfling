param(
  [Parameter(Mandatory = $true)]
  [string]$CommandPath,

  [Parameter(Mandatory = $true)]
  [string]$Version
)

$ErrorActionPreference = "Stop"

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
}
