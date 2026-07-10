Set-StrictMode -Version Latest

$script:SSHFlingVersion = '0.0.0'

function Get-SSHFlingVersion {
    [CmdletBinding()]
    param()

    return $script:SSHFlingVersion
}

function Get-SSHFlingPackageRoot {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:SSHFLING_PACKAGE_ROOT)) {
        return [System.IO.Path]::GetFullPath($env:SSHFLING_PACKAGE_ROOT)
    }
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\..'))
}

function Get-SSHFlingRuntimePath {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:SSHFLING_RUNTIME)) {
        return $env:SSHFLING_RUNTIME
    }
    return Join-Path (Get-SSHFlingPackageRoot) 'libexec/sshfling/sshfling.py'
}

function Get-SSHFlingTemplateDirectory {
    [CmdletBinding()]
    param()

    if (-not [string]::IsNullOrWhiteSpace($env:SSHFLING_TEMPLATE_DIR)) {
        return $env:SSHFLING_TEMPLATE_DIR
    }
    return Join-Path (Get-SSHFlingPackageRoot) 'share/sshfling/templates'
}

function Invoke-SSHFling {
    [CmdletBinding(PositionalBinding = $false)]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $ArgumentList
    )

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($env:SSHFLING_PYTHON)) {
        $candidates += [pscustomobject]@{ Program = $env:SSHFLING_PYTHON; Prefix = @() }
    }
    if ($IsWindows) {
        $candidates += [pscustomobject]@{ Program = 'py'; Prefix = @('-3') }
        $candidates += [pscustomobject]@{ Program = 'python'; Prefix = @() }
        $candidates += [pscustomobject]@{ Program = 'python3'; Prefix = @() }
    }
    else {
        $candidates += [pscustomobject]@{ Program = 'python3'; Prefix = @() }
        $candidates += [pscustomobject]@{ Program = 'python'; Prefix = @() }
    }

    $selected = $null
    foreach ($candidate in $candidates) {
        if (Get-Command -Name $candidate.Program -CommandType Application -ErrorAction SilentlyContinue) {
            $selected = $candidate
            break
        }
    }
    if ($null -eq $selected) {
        throw 'Python 3 is required; set SSHFLING_PYTHON to its executable.'
    }

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $selected.Program
    $startInfo.UseShellExecute = $false
    foreach ($argument in @($selected.Prefix)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.ArgumentList.Add((Get-SSHFlingRuntimePath))
    foreach ($argument in @($ArgumentList)) {
        $startInfo.ArgumentList.Add($argument)
    }
    $startInfo.Environment['SSHFLING_TEMPLATE_DIR'] = Get-SSHFlingTemplateDirectory
    $startInfo.Environment['PYTHONUNBUFFERED'] = if ([string]::IsNullOrEmpty($env:PYTHONUNBUFFERED)) { '1' } else { $env:PYTHONUNBUFFERED }

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $process.WaitForExit()
    return $process.ExitCode
}

Export-ModuleMember -Function Get-SSHFlingVersion, Get-SSHFlingRuntimePath, Get-SSHFlingTemplateDirectory, Invoke-SSHFling
