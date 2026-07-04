param(
  [string]$Version = $(if ($env:SSHFLING_VERSION) { $env:SSHFLING_VERSION } else { "0.1.4" })
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BuildRoot = Join-Path $RepoRoot "build\msi"
$Stage = Join-Path $BuildRoot "stage"
$Dist = Join-Path $RepoRoot "dist"
$ProductDir = Join-Path $Stage "SSHFling"
$TemplateDir = Join-Path $ProductDir "templates"

foreach ($tool in @("candle.exe", "light.exe", "heat.exe")) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "WiX Toolset v3 is required. Missing $tool on PATH."
  }
}

Remove-Item -Recurse -Force $BuildRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $ProductDir, $TemplateDir, $Dist | Out-Null

Copy-Item -Force (Join-Path $RepoRoot "bin\sshfling") (Join-Path $ProductDir "sshfling.py")
Copy-Item -Force (Join-Path $RepoRoot "packaging\policy.json") (Join-Path $ProductDir "policy.json")
Copy-Item -Force (Join-Path $RepoRoot "LICENSE") (Join-Path $ProductDir "LICENSE")

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

heat.exe dir $ProductDir -nologo -cg SSHFlingFiles -dr INSTALLFOLDER -srd -sreg -gg -var var.ProductDir -out $HarvestedWxs

@"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="$ProductCode" Name="SSHFling" Language="1033" Version="$Version" Manufacturer="SSHFling Maintainers" UpgradeCode="$UpgradeCode">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of SSHFling is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="SSHFling">
          <Component Id="PathComponent" Guid="5B92775A-4A2D-4E65-AE38-43B17117697D">
            <RegistryValue Root="HKLM" Key="Software\SSHFling" Name="InstallDir" Value="[INSTALLFOLDER]" Type="string" KeyPath="yes" />
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

candle.exe -nologo -dProductDir="$ProductDir" -out $WixObj $Wxs
candle.exe -nologo -dProductDir="$ProductDir" -out $HarvestedObj $HarvestedWxs
$MsiPath = Join-Path $Dist "sshfling-$Version.msi"
$ZipPath = Join-Path $Dist "sshfling-$Version-windows.zip"

light.exe -nologo -out $MsiPath $WixObj $HarvestedObj

Remove-Item -Force $ZipPath -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $ProductDir "*") -DestinationPath $ZipPath

Write-Output $MsiPath
Write-Output $ZipPath
