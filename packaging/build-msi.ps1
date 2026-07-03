param(
  [string]$Version = $(if ($env:FLING_VERSION) { $env:FLING_VERSION } else { "0.1.0" })
)

$ErrorActionPreference = "Stop"

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$BuildRoot = Join-Path $RepoRoot "build\msi"
$Stage = Join-Path $BuildRoot "stage"
$Dist = Join-Path $RepoRoot "dist"
$ProductDir = Join-Path $Stage "Fling"
$TemplateDir = Join-Path $ProductDir "templates"

foreach ($tool in @("candle.exe", "light.exe", "heat.exe")) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    throw "WiX Toolset v3 is required. Missing $tool on PATH."
  }
}

Remove-Item -Recurse -Force $BuildRoot -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $ProductDir, $TemplateDir, $Dist | Out-Null

Copy-Item -Force (Join-Path $RepoRoot "bin\fling") (Join-Path $ProductDir "fling.py")
Copy-Item -Force (Join-Path $RepoRoot "packaging\policy.json") (Join-Path $ProductDir "policy.json")

@"
@echo off
python "%~dp0fling.py" %*
"@ | Set-Content -Encoding ASCII (Join-Path $ProductDir "fling.cmd")

$templateEntries = @(
  ".env.example",
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
  "production\fling-session",
  "systemd\flingd.service",
  "systemd\flingd.env.example"
)

foreach ($entry in $templateEntries) {
  $src = Join-Path $RepoRoot $entry
  $dst = Join-Path $TemplateDir $entry
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item -Force $src $dst
}

$ProductCode = "*"
$UpgradeCode = "9F86364E-40E3-4E90-93D2-907112B2B945"
$Wxs = Join-Path $BuildRoot "fling.wxs"
$HarvestedWxs = Join-Path $BuildRoot "harvested.wxs"
$WixObj = Join-Path $BuildRoot "fling.wixobj"
$HarvestedObj = Join-Path $BuildRoot "harvested.wixobj"

heat.exe dir $ProductDir -nologo -cg FlingFiles -dr INSTALLFOLDER -srd -sreg -gg -var var.ProductDir -out $HarvestedWxs

@"
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="$ProductCode" Name="Fling" Language="1033" Version="$Version" Manufacturer="Fling Maintainers" UpgradeCode="$UpgradeCode">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of Fling is already installed." />
    <MediaTemplate EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFilesFolder">
        <Directory Id="INSTALLFOLDER" Name="Fling">
          <Component Id="PathComponent" Guid="5B92775A-4A2D-4E65-AE38-43B17117697D">
            <RegistryValue Root="HKLM" Key="Software\Fling" Name="InstallDir" Value="[INSTALLFOLDER]" Type="string" KeyPath="yes" />
            <Environment Id="PathFling" Name="PATH" Value="[INSTALLFOLDER]" Permanent="no" Part="last" Action="set" System="yes" />
          </Component>
        </Directory>
      </Directory>
    </Directory>

    <Feature Id="DefaultFeature" Title="Fling" Level="1">
      <ComponentRef Id="PathComponent" />
      <ComponentGroupRef Id="FlingFiles" />
    </Feature>
  </Product>
</Wix>
"@ | Set-Content -Encoding UTF8 $Wxs

candle.exe -nologo -dProductDir="$ProductDir" -out $WixObj $Wxs
candle.exe -nologo -dProductDir="$ProductDir" -out $HarvestedObj $HarvestedWxs
light.exe -nologo -out (Join-Path $Dist "fling-$Version.msi") $WixObj $HarvestedObj

Write-Output (Join-Path $Dist "fling-$Version.msi")
