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

function Test-PathUnderRoot([string]$Path, [string]$Root) {
  if (-not $Path -or -not $Root) {
    return $false
  }
  try {
    $separators = [char[]]@("\", "/")
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd($separators)
    $fullRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd($separators)
  }
  catch {
    return $false
  }
  if ($fullPath.Equals($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }
  return $fullPath.StartsWith($fullRoot + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-SameFilesystemPath([string]$Left, [string]$Right) {
  if (-not $Left -or -not $Right) {
    return $false
  }
  try {
    $separators = [char[]]@("\", "/")
    $fullLeft = [System.IO.Path]::GetFullPath($Left).TrimEnd($separators)
    $fullRight = [System.IO.Path]::GetFullPath($Right).TrimEnd($separators)
  }
  catch {
    return $false
  }
  return $fullLeft.Equals($fullRight, [System.StringComparison]::OrdinalIgnoreCase)
}

function Test-PathListContainsPath([string]$PathList, [string]$ExpectedPath) {
  if (-not $PathList -or -not $ExpectedPath) {
    return $false
  }
  foreach ($entry in ($PathList -split ";")) {
    $candidate = $entry.Trim().Trim([char]'"')
    if ($candidate -and (Test-SameFilesystemPath $candidate $ExpectedPath)) {
      return $true
    }
  }
  return $false
}

function Test-CommandFromProgramFiles([string]$Path) {
  $programRoots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }
  foreach ($root in $programRoots) {
    if (Test-PathUnderRoot $Path $root) {
      return $true
    }
  }
  return $false
}

function Assert-WindowsMsiMetadata([string]$Path, [string]$ExpectedVersion) {
  if (-not (Test-CommandFromProgramFiles $Path)) {
    return
  }

  $uninstallRoots = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $products = @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -eq "SSHFling" -and $_.DisplayVersion -eq $ExpectedVersion })
  if ($products.Count -lt 1) {
    Fail "Windows MSI metadata was not registered for SSHFling $ExpectedVersion"
  }

  $product = $products[0]
  if ($product.Publisher -ne "SSHFling Maintainers") {
    Fail "Windows MSI publisher metadata was not stable: $($product.Publisher)"
  }
  if (-not ([string]$product.Comments).Contains("Uninstall removes package files and PATH entry only")) {
    Fail "Windows MSI uninstall scope metadata was missing"
  }
  if ($product.URLInfoAbout -ne "https://github.com/GRWLX/sshfling") {
    Fail "Windows MSI about URL metadata was not stable: $($product.URLInfoAbout)"
  }
  if ([int]$product.NoModify -ne 1 -or [int]$product.NoRepair -ne 1) {
    Fail "Windows MSI modify/repair metadata was not disabled"
  }

  $packageMetadataRoots = @(
    "HKLM:\Software\SSHFling",
    "HKLM:\Software\WOW6432Node\SSHFling"
  )
  $packageMetadata = @(Get-ItemProperty -Path $packageMetadataRoots -ErrorAction SilentlyContinue | Select-Object -First 1)
  if (-not $packageMetadata -or $packageMetadata.Version -ne $ExpectedVersion) {
    Fail "Windows MSI package registry metadata did not record version $ExpectedVersion"
  }
  if (-not ([string]$packageMetadata.UninstallScope).Contains("host SSH state")) {
    Fail "Windows MSI package registry metadata did not record uninstall scope"
  }
  if (-not ([string]$packageMetadata.DependencyScope).Contains("does not bundle or remove Python")) {
    Fail "Windows MSI package registry metadata did not record dependency scope"
  }
  $installDir = [string]$packageMetadata.InstallDir
  if (-not $installDir -or -not (Test-PathUnderRoot $Path $installDir)) {
    Fail "Windows MSI package registry metadata did not match installed command path: $installDir"
  }
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if (-not (Test-PathListContainsPath $machinePath $installDir)) {
    Fail "Windows MSI did not add install directory to the machine PATH: $installDir"
  }
  $windowsStateScope = [string]$packageMetadata.WindowsStateScope
  if ($windowsStateScope -and -not $windowsStateScope.Contains("does not create Windows services")) {
    Fail "Windows MSI package registry metadata did not record Windows service/task scope"
  }
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("sshfling-cross-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
$activeMarker = Join-Path $tempRoot "replace-active.ready"
$env:SSHFLING_ACTIVE_MARKER = $activeMarker
$nativePowerShell = (Get-Command pwsh -ErrorAction SilentlyContinue)
if (-not $nativePowerShell) {
  $nativePowerShell = Get-Command powershell -ErrorAction Stop
}

function New-NativePowerShellCommand([string]$Script) {
  return @($nativePowerShell.Source, "-NoProfile", "-Command", $Script)
}

$sleep30Command = New-NativePowerShellCommand "[System.IO.File]::WriteAllText(`$env:SSHFLING_ACTIVE_MARKER, 'ready'); Start-Sleep -Seconds 30"

try {
  Assert-WindowsMsiMetadata $CommandPath $Version

  $versionOutput = (& $CommandPath --version | Out-String).Trim()
  if ($versionOutput -ne "sshfling $Version") {
    Fail "unexpected version output: $versionOutput"
  }
  Write-Output "platform OS: $([System.Environment]::OSVersion.VersionString)"
  Write-Output "platform architecture: $([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
  Write-Output "powershell version: $($PSVersionTable.PSVersion)"
  $pythonVersion = (& python --version 2>&1 | Out-String).Trim()
  Write-Output "python version: $pythonVersion"
  foreach ($tool in @("ssh", "ssh-keygen", "ssh-keyscan")) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
      Fail "missing OpenSSH client tool: $tool"
    }
  }
  $sshOutput = & ssh -V 2>&1
  $sshCode = $LASTEXITCODE
  $sshVersion = ($sshOutput | Out-String).Trim()
  if ($sshCode -ne 0 -or -not $sshVersion) {
    Fail "ssh -V failed or produced no version output"
  }
  Write-Output "ssh version: $sshVersion"
  if (Get-Command sshd -ErrorAction SilentlyContinue) {
    $sshdOutput = & sshd -V 2>&1
    $sshdCode = $LASTEXITCODE
    $sshdVersion = ($sshdOutput | Out-String).Trim()
    if ($sshdCode -ne 0 -or -not $sshdVersion) {
      Fail "sshd -V failed or produced no version output"
    }
    Write-Output "sshd version: $sshdVersion"
  }
  else {
    Write-Output "sshd version: unavailable"
  }

  $helpOutput = (& $CommandPath --help | Out-String)
  if (-not $helpOutput.Contains("Grant or kill temporary SSH access.")) {
    Fail "help output missing expected description"
  }

  $clientDepsJson = (& $CommandPath --json doctor --dependencies --mode client | Out-String)
  if ($LASTEXITCODE -ne 0) {
    Fail "client dependency inventory unexpectedly failed"
  }
  $clientDeps = $clientDepsJson | ConvertFrom-Json
  if (-not $clientDeps.ok -or $clientDeps.dependency_ownership -ne "platform-managed") {
    Fail "client dependency inventory did not report platform-managed ownership"
  }
  $clientRequired = @($clientDeps.dependencies | Where-Object { $_.required } | ForEach-Object { $_.name })
  foreach ($requiredTool in @("ssh", "ssh-keygen", "ssh-keyscan")) {
    if ($clientRequired -notcontains $requiredTool) {
      Fail "client dependency inventory missing required tool $requiredTool"
    }
  }

  $passwordDepsJson = (& $CommandPath --json doctor --dependencies --mode password-server 2>$null | Out-String)
  $passwordDepsCode = $LASTEXITCODE
  $passwordDeps = $passwordDepsJson | ConvertFrom-Json
  $passwordRequired = @($passwordDeps.dependencies | Where-Object { $_.required } | ForEach-Object { $_.name })
  foreach ($requiredTool in @(
      "sshd",
      "jq",
      "sshfling-unix-identity",
      "sshfling-linux-account",
      "useradd",
      "userdel",
      "chpasswd",
      "usermod",
      "chage",
      "flock-or-lockf"
    )) {
    if ($passwordRequired -notcontains $requiredTool) {
      Fail "password-server dependency inventory missing required tool $requiredTool"
    }
  }
  if (@($passwordDeps.missing_required).Count -gt 0 -and $passwordDepsCode -eq 0) {
    Fail "password-server dependency inventory returned success despite missing required tools"
  }
  if (@($passwordDeps.missing_required).Count -eq 0 -and (-not $passwordDeps.ok -or $passwordDepsCode -ne 0)) {
    Fail "password-server dependency inventory failed despite complete required tools"
  }

  $bareSetupJson = (& $CommandPath --json --dry-run 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0) {
    Fail "bare setup without -t unexpectedly succeeded"
  }
  $bareSetup = $bareSetupJson | ConvertFrom-Json
  if (-not $bareSetup.error.message.Contains("explicit -t/--time")) {
    Fail "bare setup error did not require explicit lifetime"
  }

  $topCertOptionJson = (& $CommandPath --json --public-key "ssh-ed25519 AAAAunit" --dry-run 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0) {
    Fail "top-level certificate option without --certificate unexpectedly succeeded"
  }
  $topCertOption = $topCertOptionJson | ConvertFrom-Json
  if (-not $topCertOption.error.message.Contains("Certificate setup options require --certificate")) {
    Fail "top-level cert option error was masked"
  }

  $bareCertSetupJson = (& $CommandPath --json --certificate --dry-run 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0) {
    Fail "certificate setup without -t unexpectedly succeeded"
  }
  $bareCertSetup = $bareCertSetupJson | ConvertFrom-Json
  if (-not $bareCertSetup.error.message.Contains("explicit -t/--time")) {
    Fail "certificate setup error did not require explicit lifetime"
  }

  $setupCertMissingLifetimeJson = (& $CommandPath --json setup --certificate 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0) {
    Fail "setup --certificate without -t unexpectedly succeeded"
  }
  $setupCertMissingLifetime = $setupCertMissingLifetimeJson | ConvertFrom-Json
  if (-not $setupCertMissingLifetime.error.message.Contains("explicit -t/--time")) {
    Fail "setup --certificate missing lifetime did not return stable JSON"
  }

  $setupCertOptionJson = (& $CommandPath --json setup --public-key "ssh-ed25519 AAAAunit" --dry-run 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0) {
    Fail "setup certificate option without --certificate unexpectedly succeeded"
  }
  $setupCertOption = $setupCertOptionJson | ConvertFrom-Json
  if (-not $setupCertOption.error.message.Contains("Certificate setup options require --certificate")) {
    Fail "setup cert option error was masked"
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
  if ($policy.effective.access_level -ne "standard") {
    Fail "policy default access level was not standard"
  }
  if ($policy.policy.version -ne 2) {
    Fail "policy schema version was not stable"
  }
  if ($policy.access_levels.standard.rank -ne 0) {
    Fail "policy access level catalog was not returned"
  }

  $accessPolicyPath = Join-Path $tempRoot "access-policy.json"
  @'
{
  "version": 2,
  "default": {
    "max_time_seconds": 3600,
    "max_connections": 2,
    "access_level": "standard-user"
  },
  "users": {
    "deploy": {
      "max_time_seconds": 1800,
      "max_connections": 1,
      "access_level": "operator"
    },
    "maint": {
      "access_level": "sudo_limited"
    }
  }
}
'@ | Set-Content -Encoding ASCII $accessPolicyPath
  $accessPolicyJson = (& $CommandPath --json policy show --policy-file $accessPolicyPath --user deploy | Out-String)
  $accessPolicy = $accessPolicyJson | ConvertFrom-Json
  if (-not $accessPolicy.ok -or $accessPolicy.effective.access_level -ne "operator" -or $accessPolicy.effective.max_time_seconds -ne 1800) {
    Fail "policy access-level effective user policy was not normalized"
  }
  if ($accessPolicy.policy.default.access_level -ne "standard" -or $accessPolicy.policy.users.maint.access_level -ne "sudo-limited") {
    Fail "policy access-level aliases were not normalized"
  }
  if (-not $accessPolicy.access_levels.admin.root_equivalent) {
    Fail "policy admin access level did not report root-equivalent semantics"
  }

  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $preservePolicyPath = Join-Path $tempRoot "preserve-policy.json"
    Copy-Item -Force $accessPolicyPath $preservePolicyPath
    $preserveUserJson = (& $CommandPath --json policy install --policy-file $preservePolicyPath --user deploy --access-level sudo-limited | Out-String)
    $preserveUser = $preserveUserJson | ConvertFrom-Json
    if (-not $preserveUser.ok -or $preserveUser.effective.access_level -ne "sudo-limited" -or $preserveUser.effective.max_time_seconds -ne 1800 -or $preserveUser.effective.max_connections -ne 1) {
      Fail "policy install changed user time/connection limits when only access level was supplied"
    }
    $preserveDefaultJson = (& $CommandPath --json policy install --policy-file $preservePolicyPath --access-level operator | Out-String)
    $preserveDefault = $preserveDefaultJson | ConvertFrom-Json
    if (-not $preserveDefault.ok -or $preserveDefault.effective.access_level -ne "operator" -or $preserveDefault.effective.max_time_seconds -ne 3600 -or $preserveDefault.effective.max_connections -ne 2) {
      Fail "policy install changed default time/connection limits when only access level was supplied"
    }
  }

  $invalidPolicyPath = Join-Path $tempRoot "invalid-policy.json"
  '{"default": {"access_level": "superuser"}}' | Set-Content -Encoding ASCII $invalidPolicyPath
  $invalidPolicyJson = (& $CommandPath --json policy show --policy-file $invalidPolicyPath 2>$null | Out-String)
  if ($LASTEXITCODE -eq 0) {
    Fail "invalid policy access level was accepted"
  }
  $invalidPolicy = $invalidPolicyJson | ConvertFrom-Json
  if ($invalidPolicy.ok -or -not $invalidPolicy.error.message.Contains("Invalid access level")) {
    Fail "invalid policy access-level error was not stable"
  }

  $env:SSHFLING_CONNECT_DRY_RUN = "1"
  $env:SSHFLING_SSH_BIN = "ssh"
  $connectOutput = (& $CommandPath -p 2222 s123@example.invalid whoami | Out-String).Trim()
  Remove-Item Env:\SSHFLING_CONNECT_DRY_RUN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SSH_BIN -ErrorAction SilentlyContinue
  foreach ($needle in @(
      "PreferredAuthentications=password,keyboard-interactive",
      "PubkeyAuthentication=no",
      "ForwardAgent=no",
      "ClearAllForwardings=yes",
      "-p 2222",
      "s123@example.invalid",
      "whoami"
    )) {
    if (-not $connectOutput.Contains($needle)) {
      Fail "connect dry-run missing $needle"
    }
  }

  $env:SSHFLING_TRANSFER_DRY_RUN = "1"
  $env:SSHFLING_SCP_BIN = "scp"
  $scpOutput = (& $CommandPath scp --recursive --preserve -P 2222 .\logs s123@example.invalid:/tmp/ | Out-String).Trim()
  foreach ($needle in @(
      "scp -O -r -p -P 2222",
      "PreferredAuthentications=password,keyboard-interactive",
      "PubkeyAuthentication=no",
      "ForwardAgent=no",
      "ClearAllForwardings=yes",
      "s123@example.invalid:/tmp/"
    )) {
    if (-not $scpOutput.Contains($needle)) {
      Fail "scp dry-run missing $needle"
    }
  }

  $env:SSHFLING_RSYNC_BIN = "rsync"
  $env:SSHFLING_SSH_BIN = "ssh"
  $rsyncOutput = (& $CommandPath rsync --recursive --preserve --mode u=rwX,go=rX --chown deploy:deploy -P 2222 .\dist\ s123@example.invalid:/srv/app/ | Out-String).Trim()
  foreach ($needle in @(
      "rsync -r --perms --times",
      "--chmod=u=rwX,go=rX",
      "--chown=deploy:deploy",
      "PreferredAuthentications=password,keyboard-interactive",
      "-p 2222",
      "s123@example.invalid:/srv/app/"
    )) {
    if (-not $rsyncOutput.Contains($needle)) {
      Fail "rsync dry-run missing $needle"
    }
  }

  Remove-Item Env:\SSHFLING_TRANSFER_DRY_RUN -ErrorAction SilentlyContinue
  $env:SSHFLING_RSYNC_BIN = "sshfling-rsync-missing.exe"
  $missingRsyncRaw = & $CommandPath rsync .\dist\ s123@example.invalid:/srv/app/ 2>&1
  $missingRsyncCode = $LASTEXITCODE
  $missingRsyncOutput = ($missingRsyncRaw | Out-String)
  if ($missingRsyncCode -eq 0 -or -not $missingRsyncOutput.Contains("rsync is required for sshfling rsync")) {
    Fail "missing-rsync error was not actionable: $($missingRsyncOutput.Trim())"
  }

  $env:SSHFLING_RSYNC_BIN = $tempRoot
  $rsyncDirRaw = & $CommandPath rsync .\dist\ s123@example.invalid:/srv/app/ 2>&1
  $rsyncDirCode = $LASTEXITCODE
  $rsyncDirOutput = ($rsyncDirRaw | Out-String)
  if ($rsyncDirCode -eq 0 -or -not $rsyncDirOutput.Contains("rsync is required for sshfling rsync")) {
    Fail "directory rsync path error was not actionable: $($rsyncDirOutput.Trim())"
  }
  Remove-Item Env:\SSHFLING_RSYNC_BIN -ErrorAction SilentlyContinue

  $env:SSHFLING_TRANSFER_DRY_RUN = "1"
  $scpModeRaw = & $CommandPath scp --mode u=rw .\dist\file s123@example.invalid:/srv/app/file 2>&1
  $scpModeCode = $LASTEXITCODE
  $scpModeOutput = ($scpModeRaw | Out-String)
  if ($scpModeCode -eq 0 -or -not $scpModeOutput.Contains("cannot safely set explicit destination modes")) {
    Fail "scp mode rejection was not actionable: $($scpModeOutput.Trim())"
  }
  Remove-Item Env:\SSHFLING_TRANSFER_DRY_RUN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SCP_BIN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SSH_BIN -ErrorAction SilentlyContinue

  $detachedDir = Join-Path $tempRoot "detached"
  $detachedStartCommand = New-NativePowerShellCommand "Write-Output 'detached-ready'; Start-Sleep -Seconds 30"
  $detachedStartJson = (& $CommandPath --json detached start --name cross --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @detachedStartCommand | Out-String)
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
  $plainStartCommand = New-NativePowerShellCommand "Start-Sleep -Seconds 30"
  $null = (& $CommandPath detached start --name plain --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @plainStartCommand | Out-String).Trim()
  $plainKillOutput = (& $CommandPath detached kill --detached-dir $detachedDir plain | Out-String).Trim()
  if (-not [regex]::IsMatch($plainKillOutput, "^killed [1-9][0-9]* detached process\(es\)$")) {
    Fail "plain detached kill output was not stable: $plainKillOutput"
  }
  $missingCwd = Join-Path $tempRoot "missing-cwd"
  $badCommand = New-NativePowerShellCommand "Write-Output 'bad'"
  $startFailsRaw = & $CommandPath --json detached start --name start-fails --time 30s --cwd $missingCwd --detached-dir $detachedDir -- @badCommand 2>&1
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
  $replaceActiveRaw = & $CommandPath --json detached start --replace --name replace-active --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @badCommand 2>&1
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
  $firstCommand = New-NativePowerShellCommand "Write-Output 'first'"
  $null = (& $CommandPath --json detached start --name replace-done --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @firstCommand | Out-String)
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
  $replaceDoneRaw = & $CommandPath --json detached start --name replace-done --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @badCommand 2>&1
  $replaceDoneCode = $LASTEXITCODE
  $replaceDoneJson = ($replaceDoneRaw | Out-String)
  if ($replaceDoneCode -eq 0) {
    Fail "inactive detached job was replaced without --replace: $($replaceDoneJson.Trim())"
  }
  if (-not $replaceDoneJson.Contains("Use --replace after it is inactive")) {
    Fail "inactive detached replace did not require --replace: $($replaceDoneJson.Trim())"
  }
  $secondCommand = New-NativePowerShellCommand "Write-Output 'second'; Start-Sleep -Seconds 30"
  $null = (& $CommandPath --json detached start --replace --name replace-done --time 30s --cwd $tempRoot --detached-dir $detachedDir -- @secondCommand | Out-String)
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
  $noCommand = New-NativePowerShellCommand "Write-Output 'no'"
  $tooLongRaw = & $CommandPath --json detached start --name too-long --time 25h --detached-dir $detachedDir -- @noCommand 2>&1
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
        "username": None,
        "ca_key": None,
        "ca_key_explicit": False,
        "login_user": None,
        "login_user_explicit": False,
        "access_level": None,
        "public_key": None,
        "public_key_file": None,
        "out": None,
        "session_dir": None,
        "session_dir_explicit": False,
        "key_id": None,
        "source_address": None,
        "no_pty": False,
        "session_wrapper": "/tmp/sshfling-session",
        "policy_file": "/tmp/sshfling-policy.json",
        "time": 60,
        "seconds": None,
        "json": True,
        "dry_run": False,
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
    assert sshfling.cmd_setup(setup_args(access_level="operator")) == 0
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
        sshfling.cmd_setup(setup_args(password=True, public_key_file="/tmp/client.pub"))
    except sshfling.SSHFlingError as exc:
        assert "require --certificate" in exc.message, exc.message
        assert "--public-key-file" in exc.details["options"], exc.details
    else:
        raise AssertionError("--password accepted certificate material options without --certificate")

    try:
        sshfling.cmd_setup(setup_args(password=True, certificate=True))
    except sshfling.SSHFlingError as exc:
        assert "not both" in exc.message, exc.message
    else:
        raise AssertionError("--password and --certificate were accepted together")
finally:
    sshfling.cmd_setup_password = original_password
    sshfling.cmd_setup_certificate = original_certificate

policy = sshfling.normalize_policy({
    "default": {"max_time_seconds": 3600, "max_connections": 2, "access_level": "standard"},
    "users": {
        "deploy": {"max_time_seconds": 1800, "max_connections": 1, "access_level": "operator"},
        "maint": {"access_level": "sudo_limited"},
    },
})
assert sshfling.effective_policy(policy, "deploy")["access_level"] == "operator", policy
assert sshfling.effective_policy(policy, "maint")["access_level"] == "sudo-limited", policy
assert sshfling.enforce_policy_access_level(sshfling.effective_policy(policy, "deploy"), "deploy", "standard") == "standard"
try:
    sshfling.enforce_policy_access_level(sshfling.effective_policy(policy, "deploy"), "deploy", "admin")
except sshfling.SSHFlingError as exc:
    assert "exceeds policy access level" in exc.message, exc.message
else:
    raise AssertionError("operator policy allowed admin access-level request")
try:
    sshfling.enforce_policy_access_level(sshfling.effective_policy(policy, "root"), "root", None)
except sshfling.SSHFlingError as exc:
    assert "root-equivalent" in exc.message, exc.message
else:
    raise AssertionError("root-equivalent user accepted standard access-level policy")

assert sshfling.validate_certificate_principal("ticket-1234@example") == "ticket-1234@example"
for bad_principal in ["ticket,root", "ticket\nroot", "-ticket", "ticket root"]:
    try:
        sshfling.validate_certificate_principal(bad_principal)
    except sshfling.SSHFlingError as exc:
        assert "Certificate principal must match" in exc.message, exc.message
    else:
        raise AssertionError(f"invalid certificate principal was accepted: {bad_principal!r}")

if sys.platform == "win32":
    print("Windows client package import checks passed; Unix host lifecycle checks are POSIX-only.")
    sys.exit(0)

with tempfile.TemporaryDirectory() as marker_tmp:
    marker_root = Path(marker_tmp)
    original_delete_user = getattr(sshfling, "delete_password_user")
    setattr(sshfling, "delete_password_user", lambda username, dry_run=False, **kwargs: {"user": username, "would_delete": dry_run})
    try:
        try:
            sshfling.delete_host_user("sshflingtmp", marker_root, dry_run=True)
        except sshfling.SSHFlingError as exc:
            assert "without a SSHFling-created host-user marker" in exc.message, exc.message
        else:
            raise AssertionError("host user deletion succeeded without a marker")
        sshfling.write_host_user_marker(marker_root, "sshflingtmp", {
            "managed_by": "sshfling",
            "auth": "certificate-host",
            "username": "sshflingtmp",
            "created_user": True,
        })
        delete_result = sshfling.delete_host_user("sshflingtmp", marker_root, dry_run=True)
        assert delete_result["would_delete"] is True, delete_result
        assert delete_result["would_remove_marker"] is True, delete_result
        sshfling.write_host_user_marker(marker_root, "sshflingreuse", {
            "managed_by": "sshfling",
            "auth": "certificate-host",
            "username": "sshflingreuse",
            "created_user": True,
            "user_uid": 12345,
            "user_gid": 12345,
            "user_home": "/home/sshflingreuse",
        })
        setattr(sshfling, "delete_password_user", lambda username, dry_run=False, **kwargs: {
            "user": username,
            "status": "skipped-user-mismatch",
            "expected_identity": {"uid": 12345, "gid": 12345, "home": "/home/sshflingreuse"},
            "current_identity": {"uid": 67890, "gid": 67890, "home": "/home/sshflingreuse-new"},
        })
        mismatch_result = sshfling.delete_host_user("sshflingreuse", marker_root, dry_run=False)
        assert mismatch_result["status"] == "skipped-user-mismatch", mismatch_result
        assert mismatch_result["marker_preserved"] is True, mismatch_result
        assert "removed_marker" not in mismatch_result, mismatch_result
        assert "would_remove_marker" not in mismatch_result, mismatch_result
        assert (marker_root / "sshflingreuse.json").exists(), mismatch_result
        setattr(sshfling, "delete_password_user", lambda username, dry_run=False, **kwargs: {"user": username, "would_delete": dry_run})
        sshfling.write_host_user_marker(marker_root, "root", {
            "managed_by": "sshfling",
            "auth": "certificate-host",
            "username": "root",
            "created_user": True,
        })
        try:
            sshfling.delete_host_user("root", marker_root, dry_run=True)
        except sshfling.SSHFlingError as exc:
            assert "root-equivalent" in exc.message, exc.message
        else:
            raise AssertionError("host user deletion allowed a root-equivalent user")
    finally:
        setattr(sshfling, "delete_password_user", original_delete_user)

with tempfile.TemporaryDirectory() as policy_tmp:
    policy_path = Path(policy_tmp) / "policy.json"
    try:
        sshfling.write_policy(policy_path, 300, 1, "root", "standard")
    except sshfling.SSHFlingError as exc:
        assert "root-equivalent" in exc.message, exc.message
    else:
        raise AssertionError("root policy accepted a standard access level")
    written = sshfling.write_policy(policy_path, 300, 1, "root", "root-equivalent")
    assert written["users"]["root"]["access_level"] == "admin", written

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
        ("sshflingmissingfile", True, now - 60, {"managed_by": "sshfling", "auth": "password", "skip_config": True}),
    ]
    for username, created_user, expires_at, extra in fixtures:
        conf = conf_dir / f"91-sshfling-password-{username}.conf"
        if not extra.pop("skip_config", False):
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
    identity_conf = conf_dir / "91-sshfling-password-sshflingidentity.conf"
    identity_conf.write_text("# Managed by sshfling password grant for sshflingidentity.\n", encoding="utf-8")
    (grant_dir / "sshflingidentity.json").write_text(json.dumps({
        "username": "sshflingidentity",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": True,
        "expires_at": now - 60,
        "config_path": str(identity_conf),
        "user_uid": 12345,
        "user_gid": 12345,
        "user_home": "/home/sshflingidentity-old",
    }), encoding="utf-8")
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
    (grant_dir / "root.json").write_text(json.dumps({
        "username": "root",
        "managed_by": "sshfling",
        "auth": "password",
        "created_user": False,
        "expires_at": now - 60,
        "config_path": str(spoof_conf),
    }), encoding="utf-8")

    class UserExists:
        returncode = 0
        stderr = ""
        stdout = ""

    original_run = sshfling.run
    original_unix_user_exists = sshfling.unix_user_exists
    original_unix_user_identity = sshfling.unix_user_identity
    sshfling.run = lambda *args, **kwargs: UserExists()
    sshfling.unix_user_exists = lambda username: True
    sshfling.unix_user_identity = lambda username: {
        "username": username,
        "uid": 67890,
        "gid": 67890,
        "home": f"/home/{username}-new",
    } if username == "sshflingidentity" else {}
    try:
        results = sshfling.prune_password_grants(
            grant_dir,
            all_grants=True,
            delete_users=True,
            dry_run=True,
        )
    finally:
        sshfling.run = original_run
        sshfling.unix_user_exists = original_unix_user_exists
        sshfling.unix_user_identity = original_unix_user_identity

    by_user = {item["username"]: item for item in results}
    assert by_user["sshflingactive"]["status"] == "active", by_user
    expired = by_user["sshflingexpired"]
    assert expired["status"] == "pruned", by_user
    assert expired["config"]["would_remove"] is True, expired
    assert expired["metadata"]["would_remove"] is True, expired
    assert expired["user"]["would_lock"] is True, expired
    assert expired["user"]["delete_skipped"] == "Unix identity evidence is required before deleting an SSHFling-created user", expired
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
    missing_file = by_user["sshflingmissingfile"]
    assert missing_file["status"] == "pruned", missing_file
    assert missing_file["config"]["status"] == "missing", missing_file
    assert missing_file["user"]["would_lock"] is True, missing_file
    assert missing_file["user"]["delete_skipped"] == "Unix identity evidence is required before deleting an SSHFling-created user", missing_file
    identity = by_user["sshflingidentity"]
    assert identity["status"] == "skipped-user-mismatch", identity
    assert "config" not in identity, identity
    assert "metadata" not in identity, identity
    assert identity["user"]["status"] == "skipped-user-mismatch", identity
    assert identity["user"]["expected_identity"]["uid"] == 12345, identity
    assert identity["user"]["current_identity"]["uid"] == 67890, identity
    root_items = [item for item in results if item.get("username") == "root"]
    assert any(item["status"] == "skipped-unmanaged" for item in root_items), root_items
    root_equivalent = next(item for item in root_items if item["status"] == "skipped-root-equivalent")
    assert Path(root_equivalent["metadata_path"]).name == "root.json", root_equivalent
    assert "config" not in root_equivalent, root_equivalent
    assert "user" not in root_equivalent, root_equivalent
    assert "metadata" not in root_equivalent, root_equivalent

    sshfling.run = lambda *args, **kwargs: UserExists()
    sshfling.unix_user_exists = lambda username: True
    sshfling.unix_user_identity = lambda username: {}
    try:
        active_results = sshfling.prune_password_grants(
            grant_dir,
            username="sshflingactive",
            delete_users=True,
            dry_run=True,
        )
        expired_results = sshfling.prune_password_grants(
            grant_dir,
            username="sshflingexpired",
            delete_users=True,
            dry_run=True,
        )
        root_results = sshfling.prune_password_grants(
            grant_dir,
            username="root",
            delete_users=True,
            dry_run=True,
        )
    finally:
        sshfling.run = original_run
        sshfling.unix_user_exists = original_unix_user_exists
        sshfling.unix_user_identity = original_unix_user_identity

    assert len(active_results) == 1, active_results
    assert active_results[0]["status"] == "active", active_results
    assert "user" not in active_results[0], active_results
    assert len(expired_results) == 1, expired_results
    assert expired_results[0]["status"] == "pruned", expired_results
    assert expired_results[0]["user"]["would_lock"] is True, expired_results
    assert expired_results[0]["user"]["delete_skipped"] == "Unix identity evidence is required before deleting an SSHFling-created user", expired_results
    assert len(root_results) == 1, root_results
    assert root_results[0]["status"] == "skipped-root-equivalent", root_results
    assert Path(root_results[0]["metadata_path"]).name == "root.json", root_results
    assert "config" not in root_results[0], root_results
    assert "user" not in root_results[0], root_results
    assert "metadata" not in root_results[0], root_results

    try:
        sshfling.prune_password_grants(grant_dir, delete_users=True, dry_run=True)
    except sshfling.SSHFlingError as exc:
        assert "exactly one" in exc.message, exc.message
    else:
        raise AssertionError("password prune without --username or --all was accepted")

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
        "install_managed_login_shell": sshfling.install_managed_login_shell,
        "provision_session_locks": sshfling.provision_session_locks,
        "write_if_changed": sshfling.write_if_changed,
        "write_password_grant_metadata": sshfling.write_password_grant_metadata,
        "reload_sshd": sshfling.reload_sshd,
        "detect_server_host": sshfling.detect_server_host,
        "audit_log": sshfling.audit_log,
        "emit_json": sshfling.emit_json,
        "create_ca_key": sshfling.create_ca_key,
        "create_temp_client_key": sshfling.create_temp_client_key,
        "sign_user_certificate": sshfling.sign_user_certificate,
    }
    try:
        sshfling.require_root = lambda action: None
        sshfling.require_password_host_tools = lambda: None
        sshfling.unix_user_exists = lambda username: True
        sshfling.ensure_unix_user = lambda username, allow_existing=False, login_shell=None: {
            "user": username,
            "created": False,
            "allow_existing": allow_existing,
            "login_shell": login_shell,
        }
        def capture_password(username, password):
            captured["password_user"] = username
            captured["password"] = password
        sshfling.set_user_password = capture_password
        sshfling.resource_file = lambda relative: command_path
        sshfling.install_file = lambda *args, **kwargs: {"installed": True}
        sshfling.install_managed_login_shell = lambda *args, **kwargs: {"installed_login_shell": True}
        sshfling.provision_session_locks = lambda *args, **kwargs: {"session_locks": "provisioned"}
        sshfling.write_if_changed = lambda *args, **kwargs: {"changed": True}
        def capture_metadata(grant_dir, username, metadata, dry_run=False):
            captured["metadata"] = metadata
            return {"metadata": "captured"}
        sshfling.write_password_grant_metadata = capture_metadata
        sshfling.reload_sshd = lambda: {"reloaded": "sshd"}
        sshfling.detect_server_host = lambda: "127.0.0.1"
        sshfling.audit_log = lambda *args, **kwargs: None
        sshfling.emit_json = lambda payload: captured.__setitem__("password_payload", payload)
        def certificate_material_forbidden(*args, **kwargs):
            raise AssertionError("password setup attempted to create certificate material")
        sshfling.create_ca_key = certificate_material_forbidden
        sshfling.create_temp_client_key = certificate_material_forbidden
        sshfling.sign_user_certificate = certificate_material_forbidden
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

        prune_called["value"] = False
        try:
            sshfling.cmd_setup_password(SimpleNamespace(
                username="root",
                password_grant_dir=str(grant_dir),
                password_sshd_config_dir=str(conf_dir),
                session_wrapper="/tmp/sshfling-session",
                policy_file=str(root / "policy.json"),
                time=60,
                seconds=None,
                dry_run=True,
                validate=False,
                allow_existing_user=True,
                json=True,
            ))
        except sshfling.SSHFlingError as exc:
            assert "root-equivalent" in exc.message, exc.message
        else:
            raise AssertionError("password setup allowed a root-equivalent Unix user")
        assert prune_called["value"] is False, prune_called

        sshfling.prune_password_grants = lambda *args, **kwargs: [{
            "status": "active",
            "expires_at": int(time.time()) + 3600,
            "metadata_path": str(grant_dir / "sshflingexisting.json"),
        }]
        try:
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
        except sshfling.SSHFlingError as exc:
            assert "Active password grant already exists" in exc.message, exc.message
        else:
            raise AssertionError("active password grant was overwritten by setup")
        assert "password" not in captured, captured

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
    assert captured["metadata"]["auth"] == "password", captured
    assert captured["metadata"]["access_level"] == "standard", captured
    assert captured["password_user"] == "sshflingexisting", captured
    assert len(captured["password"]) >= 20 and not any(ch.isspace() for ch in captured["password"]), captured
    password_payload = captured["password_payload"]
    assert password_payload["auth"] == "password", password_payload
    assert password_payload["access_level"] == "standard", password_payload
    assert password_payload["policy"]["access_level"] == "standard", password_payload
    assert password_payload["password"] == captured["password"], password_payload
    for forbidden_key in ["certificate", "private_key", "public_key", "ca"]:
        assert forbidden_key not in password_payload, password_payload

    try:
        sshfling.cmd_setup_certificate(setup_args(certificate=False, ca_key=str(root / "ca"), session_dir=str(root / "sessions")))
    except sshfling.SSHFlingError as exc:
        assert "requires --certificate" in exc.message, exc.message
    else:
        raise AssertionError("certificate setup was reachable without --certificate")

    parser = sshfling.build_parser()
    cert_issue_args = [
        "cert",
        "issue",
        "--public-key",
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest cert-issue",
        "--username",
        "sshflingcert",
    ]
    cert_issue_missing = parser.parse_args(cert_issue_args)
    assert getattr(cert_issue_missing, "certificate", False) is False, cert_issue_missing
    for argv in [
        ["--certificate"] + cert_issue_args,
        ["cert", "--certificate"] + cert_issue_args[1:],
        cert_issue_args + ["--certificate"],
    ]:
        parsed = parser.parse_args(argv)
        assert getattr(parsed, "certificate", False) is True, (argv, parsed)
        assert parsed.func is sshfling.cmd_cert_issue, (argv, parsed)

    try:
        sshfling.cmd_cert_issue(cert_issue_missing)
    except sshfling.SSHFlingError as exc:
        assert "requires --certificate" in exc.message, exc.message
    else:
        raise AssertionError("cert issue was reachable without --certificate")

    cert_captured = {"calls": []}
    cert_originals = {
        "require_root": sshfling.require_root,
        "create_temp_client_key": sshfling.create_temp_client_key,
        "sign_user_certificate": sshfling.sign_user_certificate,
        "detect_server_host": sshfling.detect_server_host,
        "audit_log": sshfling.audit_log,
        "emit_json": sshfling.emit_json,
    }
    try:
        cert_root = root / "cert-flow"
        cert_root.mkdir()
        ca_key = cert_root / "ca"
        ca_pub = cert_root / "ca.pub"
        ca_key.write_text("stub ca key\n", encoding="utf-8")
        ca_pub.write_text("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest ca\n", encoding="utf-8")
        partial_ca = cert_root / "partial-ca"
        partial_ca.write_text("stub partial ca key\n", encoding="utf-8")
        try:
            sshfling.create_ca_key(SimpleNamespace(ca_key=str(partial_ca), force=False))
        except sshfling.SSHFlingError as exc:
            assert "incomplete" in exc.message, exc.message
        else:
            raise AssertionError("ca init accepted an incomplete CA keypair")
        sshfling.require_root = lambda action: None
        def fake_create_temp_client_key(username, session_dir):
            cert_captured["calls"].append("create_temp_client_key")
            key_dir = Path(session_dir) / username
            key_dir.mkdir(parents=True)
            private_key = key_dir / "id_ed25519"
            public_key = key_dir / "id_ed25519.pub"
            private_key.write_text("stub private key\n", encoding="utf-8")
            public_key.write_text("ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITest cert-flow\n", encoding="utf-8")
            return {"private_key": str(private_key), "public_key": str(public_key), "generated_key": True}
        def fake_sign_user_certificate(**kwargs):
            cert_captured["calls"].append("sign_user_certificate")
            cert_captured["sign_kwargs"] = kwargs
            return {
                "ok": True,
                "certificate": "ssh-ed25519-cert-v01@openssh.com AAAA cert",
                "username": kwargs["principal"],
                "principal": kwargs["principal"],
                "seconds": kwargs["seconds"],
                "valid_before": "2030-01-01T00:00:00Z",
                "key_id": kwargs["key_id"] or "stub-key-id",
                "serial": 123,
                "out": kwargs["out_file"],
                "force_command": "stub",
                "access_level": kwargs["access_level"] or "standard",
            }
        sshfling.create_temp_client_key = fake_create_temp_client_key
        sshfling.sign_user_certificate = fake_sign_user_certificate
        sshfling.detect_server_host = lambda: "203.0.113.10"
        sshfling.audit_log = lambda *args, **kwargs: None
        sshfling.emit_json = lambda payload: cert_captured.__setitem__("payload", payload)
        cert_issue_no_time = parser.parse_args(cert_issue_args + ["--certificate", "--ca-key", str(ca_key)])
        try:
            sshfling.cmd_cert_issue(cert_issue_no_time)
        except sshfling.SSHFlingError as exc:
            assert "explicit -t/--time" in exc.message, exc.message
        else:
            raise AssertionError("cert issue accepted an implicit lifetime")

        assert sshfling.cmd_setup(setup_args(
            certificate=True,
            username="sshflingcert",
            ca_key=str(ca_key),
            session_dir=str(cert_root / "sessions"),
        )) == 0

        missing_ca = cert_root / "missing-ca"
        try:
            sshfling.cmd_setup(setup_args(
                certificate=True,
                username="sshflingmissingca",
                ca_key=str(missing_ca),
                session_dir=str(cert_root / "missing-sessions"),
            ))
        except sshfling.SSHFlingError as exc:
            assert "CA keypair does not exist" in exc.message, exc.message
        else:
            raise AssertionError("certificate setup created or accepted a missing CA")

        dry_run_dir = cert_root / "dry-run-sessions"
        try:
            sshfling.cmd_setup(setup_args(
                certificate=True,
                username="sshflingdryrun",
                ca_key=str(ca_key),
                session_dir=str(dry_run_dir),
                dry_run=True,
            ))
        except sshfling.SSHFlingError as exc:
            assert "does not support --dry-run" in exc.message, exc.message
        else:
            raise AssertionError("certificate setup --dry-run was accepted")
        assert not dry_run_dir.exists(), dry_run_dir
    finally:
        for name, value in cert_originals.items():
            setattr(sshfling, name, value)
    assert cert_captured["calls"] == ["create_temp_client_key", "sign_user_certificate"], cert_captured
    assert cert_captured["sign_kwargs"]["principal"] == "sshflingcert", cert_captured
    assert cert_captured["sign_kwargs"]["seconds"] == 60, cert_captured
    assert "cert-flow" in cert_captured["sign_kwargs"]["public_key_text"], cert_captured
    cert_payload = cert_captured["payload"]
    assert cert_payload["ok"] is True, cert_payload
    assert cert_payload["generated_key"] is True, cert_payload
    assert cert_payload["private_key"], cert_payload
    assert cert_payload["ca"]["status"] == "exists", cert_payload
    assert cert_payload["access_level"] == "standard", cert_payload
    assert "password" not in cert_payload, cert_payload

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
        "require_native_policy_parser": sshfling.require_native_policy_parser,
        "require_native_session_lock_tool": sshfling.require_native_session_lock_tool,
        "require_native_identity_backend": sshfling.require_native_identity_backend,
        "resource_file": sshfling.resource_file,
        "install_managed_login_shell": sshfling.install_managed_login_shell,
        "unix_user_identity": sshfling.unix_user_identity,
        "provision_session_locks": sshfling.provision_session_locks,
        "validate_sshd_effective": sshfling.validate_sshd_effective,
    }
    try:
        sshfling.require_root = lambda action: None
        sshfling.require_native_policy_parser = lambda dry_run=False: None
        sshfling.require_native_session_lock_tool = lambda dry_run=False: None
        sshfling.require_native_identity_backend = lambda: None
        sshfling.resource_file = lambda relative: template
        sshfling.install_managed_login_shell = lambda *args, **kwargs: {"installed_login_shell": True}
        sshfling.unix_user_identity = lambda username: {
            "username": username, "uid": 1234, "gid": 1234, "home": f"/home/{username}"
        }
        sshfling.provision_session_locks = lambda *args, **kwargs: {"session_locks": "provisioned"}
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
      "native\sshfling-linux-account",
      "native\sshfling-unix-identity",
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
      "production\sshfling-login-shell",
      "production\sshfling-session",
      "systemd\sshflingd.service",
      "systemd\sshfling-prune.service",
      "systemd\sshfling-prune.timer",
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
  if ($productionWrapper -match "\bpython(3)?\b") {
    Fail "production wrapper should use native shell policy parsing, not Python"
  }
  if ($productionWrapper.Contains("exec {")) {
    Fail "production wrapper should remain compatible with macOS Bash 3.2"
  }
  if ($productionWrapper.Contains("run_limited /bin/bash")) {
    Fail "production wrapper should use the active platform Bash path"
  }
  $loginShell = Get-Content -Raw -Path (Join-Path $project "production\sshfling-login-shell")
  if (-not $loginShell.Contains("unset BASH_ENV ENV")) {
    Fail "managed login shell did not clear startup-file environment variables"
  }
  if ($loginShell -match "\bpython(3)?\b") {
    Fail "managed login shell should use native shell commands, not Python"
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
  Remove-Item Env:\SSHFLING_TRANSFER_DRY_RUN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SCP_BIN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_RSYNC_BIN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_SSH_BIN -ErrorAction SilentlyContinue
  Remove-Item Env:\SSHFLING_ACTIVE_MARKER -ErrorAction SilentlyContinue
  if ($hasNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $previousNativeCommandUseErrorActionPreference
  }
}
