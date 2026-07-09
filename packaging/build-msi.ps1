param(
  [string]$Version = $(if ($env:SSHFLING_VERSION) { $env:SSHFLING_VERSION } else { "" })
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$SourceVersionMatch = Select-String -Path (Join-Path $RepoRoot "bin\sshfling") -Pattern '^VERSION = "([^"]+)"' | Select-Object -First 1
if (-not $SourceVersionMatch) {
  throw "VERSION constant was not found in bin\sshfling."
}
$SourceVersion = $SourceVersionMatch.Matches[0].Groups[1].Value
if (-not $Version) {
  $Version = $SourceVersion
}
if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+$') {
  throw "Invalid SSHFling version '$Version'. Use exactly three numeric components, for example: 1.2.3."
}
if ($Version -ne $SourceVersion) {
  throw "Package version '$Version' does not match bin\sshfling VERSION '$SourceVersion'."
}

$BuildRoot = Join-Path $RepoRoot "build\msi"
$Stage = Join-Path $BuildRoot "stage"
$Dist = Join-Path $RepoRoot "dist"
$ProductDir = Join-Path $Stage "SSHFling"
$TemplateDir = Join-Path $ProductDir "templates"
$Manufacturer = "SSHFling Maintainers"
$AboutUrl = "https://github.com/GRWLX/sshfling"
$HelpUrl = "https://github.com/GRWLX/sshfling/issues"
$PackageDescription = "Temporary SSH access broker and CLI"
$UninstallScope = "Uninstall removes package files and PATH entry only; host SSH state, local policy, CA material, and dependencies are managed separately."
$DependencyScope = "The MSI does not bundle or remove Python, OpenSSH, or Windows OpenSSH Server components."
$WindowsStateScope = "The MSI does not create Windows services, scheduled tasks, or other Windows persistence entries."
$RequireAuthenticode = $env:SSHFLING_WINDOWS_REQUIRE_AUTHENTICODE -match '^(1|true|TRUE|yes|YES)$'
$SignCertSha1 = $env:SSHFLING_WINDOWS_SIGN_CERT_SHA1
$TimestampUrl = if ($env:SSHFLING_WINDOWS_SIGN_TIMESTAMP_URL) { $env:SSHFLING_WINDOWS_SIGN_TIMESTAMP_URL } else { "http://timestamp.digicert.com" }

foreach ($tool in @("candle.exe", "light.exe", "heat.exe")) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "WiX Toolset v3 is required. Missing $tool on PATH."
  }
}
if ($RequireAuthenticode) {
  if (-not (Get-Command signtool.exe -ErrorAction SilentlyContinue)) {
    throw "signtool.exe is required when SSHFLING_WINDOWS_REQUIRE_AUTHENTICODE is true."
  }
  if (-not $SignCertSha1) {
    throw "SSHFLING_WINDOWS_SIGN_CERT_SHA1 is required when SSHFLING_WINDOWS_REQUIRE_AUTHENTICODE is true."
  }
}

function Invoke-CheckedNative {
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )
  & $FilePath @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$FilePath failed with exit code $LASTEXITCODE"
  }
}

Remove-Item -Recurse -Force $BuildRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $ProductDir, $TemplateDir, $Dist | Out-Null

Copy-Item -Force (Join-Path $RepoRoot "bin\sshfling") (Join-Path $ProductDir "sshfling.py")
Copy-Item -Force (Join-Path $RepoRoot "packaging\policy.json") (Join-Path $ProductDir "policy.json")
Copy-Item -Force (Join-Path $RepoRoot "LICENSE") (Join-Path $ProductDir "LICENSE")

@"
SSHFling $Version package notes

Runtime dependencies:
- The MSI does not bundle Python, OpenSSH, or Windows OpenSSH Server.
- Client commands require Python and OpenSSH client tools on PATH.
- Server-side host setup requires the target host's OpenSSH server tooling.

Uninstall and revert scope:
- MSI uninstall removes files under the SSHFling install directory and the PATH entry added by the MSI.
- It does not remove Python, OpenSSH, Windows OpenSSH Server, host SSH configuration, temporary grant state, CA material, or policy/configuration stored outside the install directory.
- The MSI does not create Windows services, scheduled tasks, or other Windows persistence entries.
- Exact preinstall state restoration must come from Intune, Group Policy, configuration management, backups, or another source of recorded original state.
"@ | Set-Content -Encoding ASCII (Join-Path $ProductDir "PACKAGE-NOTES.txt")

@"
@echo off
python "%~dp0sshfling.py" %*
"@ | Set-Content -Encoding ASCII (Join-Path $ProductDir "sshfling.cmd")

$templateEntries = @(
  ".env.example",
  "LICENSE",
  "README.md",
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
  "systemd\sshfling-prune.service",
  "systemd\sshfling-prune.timer",
  "systemd\sshflingd.env.example"
)

foreach ($entry in $templateEntries) {
  $src = Join-Path $RepoRoot $entry
  $dst = Join-Path $TemplateDir $entry
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item -Force $src $dst
}

$ProductCode = "*"
$UpgradeCode = "9F86364E-40E3-4E90-93D2-907112B2B945"
$Wxs = Join-Path $BuildRoot "sshfling.wxs"
$HarvestedWxs = Join-Path $BuildRoot "harvested.wxs"
$WixObj = Join-Path $BuildRoot "sshfling.wixobj"
$HarvestedObj = Join-Path $BuildRoot "harvested.wixobj"

Invoke-CheckedNative heat.exe @("dir", $ProductDir, "-nologo", "-cg", "SSHFlingFiles", "-dr", "INSTALLFOLDER", "-srd", "-sreg", "-gg", "-var", "var.ProductDir", "-out", $HarvestedWxs)

@"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="$ProductCode" Name="SSHFling" Language="1033" Version="$Version" Manufacturer="$Manufacturer" UpgradeCode="$UpgradeCode">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" Platform="x64" Manufacturer="$Manufacturer" Description="$PackageDescription" Comments="$UninstallScope" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of SSHFling is already installed." />
    <MediaTemplate EmbedCab="yes" />
    <Property Id="ARPCOMMENTS" Value="$UninstallScope" />
    <Property Id="ARPHELPLINK" Value="$HelpUrl" />
    <Property Id="ARPURLINFOABOUT" Value="$AboutUrl" />
    <Property Id="ARPNOMODIFY" Value="1" />
    <Property Id="ARPNOREPAIR" Value="1" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="SSHFling">
          <Component Id="PathComponent" Guid="5B92775A-4A2D-4E65-AE38-43B17117697D">
            <RegistryValue Root="HKLM" Key="Software\SSHFling" Name="InstallDir" Value="[INSTALLFOLDER]" Type="string" KeyPath="yes" />
            <RegistryValue Root="HKLM" Key="Software\SSHFling" Name="Version" Value="$Version" Type="string" />
            <RegistryValue Root="HKLM" Key="Software\SSHFling" Name="UninstallScope" Value="$UninstallScope" Type="string" />
            <RegistryValue Root="HKLM" Key="Software\SSHFling" Name="DependencyScope" Value="$DependencyScope" Type="string" />
            <RegistryValue Root="HKLM" Key="Software\SSHFling" Name="WindowsStateScope" Value="$WindowsStateScope" Type="string" />
            <Environment Id="PathSSHFling" Name="PATH" Value="[INSTALLFOLDER]" Permanent="no" Part="last" Action="set" System="yes" />
          </Component>
        </Directory>
      </Directory>
    </Directory>

    <Feature Id="DefaultFeature" Title="SSHFling" Level="1">
      <ComponentRef Id="PathComponent" />
      <ComponentGroupRef Id="SSHFlingFiles" />
    </Feature>
  </Product>
</Wix>
"@ | Set-Content -Encoding UTF8 $Wxs

foreach ($wixSource in @($Wxs, $HarvestedWxs)) {
  $wixContent = Get-Content -Raw -Path $wixSource
  foreach ($forbidden in @("ServiceInstall", "ServiceControl", "ScheduledTask", "CustomAction")) {
    if ($wixContent -match "<\s*(?:[A-Za-z_][\w.-]*:)?$forbidden\b") {
      throw "Unexpected WiX element <$forbidden> in $wixSource. MSI must not create services, scheduled tasks, or custom persistence actions."
    }
  }
}

$MsiPath = Join-Path $Dist "sshfling-$Version.msi"
$ZipPath = Join-Path $Dist "sshfling-$Version-windows.zip"
Remove-Item -Force $MsiPath, $ZipPath -ErrorAction SilentlyContinue

Invoke-CheckedNative candle.exe @("-nologo", "-arch", "x64", "-dProductDir=$ProductDir", "-out", $WixObj, $Wxs)
Invoke-CheckedNative candle.exe @("-nologo", "-arch", "x64", "-dProductDir=$ProductDir", "-out", $HarvestedObj, $HarvestedWxs)
Invoke-CheckedNative light.exe @("-nologo", "-out", $MsiPath, $WixObj, $HarvestedObj)
if (-not (Test-Path $MsiPath) -or (Get-Item $MsiPath).Length -le 0) {
  throw "MSI was not created: $MsiPath"
}
if ($RequireAuthenticode) {
  Invoke-CheckedNative signtool.exe @("sign", "/fd", "SHA256", "/sha1", $SignCertSha1, "/tr", $TimestampUrl, "/td", "SHA256", $MsiPath)
  Invoke-CheckedNative signtool.exe @("verify", "/pa", "/tw", $MsiPath)
}

Compress-Archive -Path (Join-Path $ProductDir "*") -DestinationPath $ZipPath
if (-not (Test-Path $ZipPath) -or (Get-Item $ZipPath).Length -le 0) {
  throw "Windows ZIP was not created: $ZipPath"
}

Write-Output $MsiPath
Write-Output $ZipPath
