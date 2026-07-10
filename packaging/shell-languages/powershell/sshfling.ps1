$ErrorActionPreference = 'Stop'

$packageRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$oldPackageRoot = $env:SSHFLING_PACKAGE_ROOT
try {
    $env:SSHFLING_PACKAGE_ROOT = $packageRoot
    $modulePath = Join-Path $packageRoot 'share/powershell/Modules/SSHFling/SSHFling.psd1'
    Import-Module $modulePath -Force
    $status = Invoke-SSHFling -ArgumentList @($args)
    exit [int] $status
}
finally {
    $env:SSHFLING_PACKAGE_ROOT = $oldPackageRoot
}
