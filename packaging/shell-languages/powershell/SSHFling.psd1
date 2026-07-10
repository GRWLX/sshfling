@{
    RootModule = 'SSHFling.psm1'
    ModuleVersion = '0.0.0'
    GUID = 'f7869319-055e-4d28-a695-9aa7f202bb36'
    Author = 'GRWLX'
    CompanyName = 'GRWLX'
    Copyright = 'Copyright (c) 2026 GRWLX. All rights reserved.'
    Description = 'PowerShell launcher module for the bundled SSHFling runtime and templates.'
    PowerShellVersion = '7.2'
    FunctionsToExport = @(
        'Get-SSHFlingVersion',
        'Get-SSHFlingRuntimePath',
        'Get-SSHFlingTemplateDirectory',
        'Invoke-SSHFling'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            ProjectUri = 'https://github.com/GRWLX/sshfling'
            LicenseUri = 'https://github.com/GRWLX/sshfling/blob/main/LICENSE'
            Tags = @('SSH', 'OpenSSH', 'TemporaryAccess')
        }
    }
}
