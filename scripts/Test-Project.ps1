#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    Write-Host 'Checking PowerShell syntax...'
    [void][scriptblock]::Create((Get-Content -Path '.\Invoke-RdpCacheReview.ps1' -Raw))
    [void][scriptblock]::Create((Get-Content -Path '.\scripts\Sync-ModuleFromScript.ps1' -Raw))
    [void][scriptblock]::Create((Get-Content -Path '.\scripts\Test-Package.ps1' -Raw))
    [void][scriptblock]::Create((Get-Content -Path '.\scripts\Sign-ReleaseFiles.ps1' -Raw))

    Write-Host 'Synchronizing module wrapper...'
    & '.\scripts\Sync-ModuleFromScript.ps1'

    Write-Host 'Validating module manifest...'
    Test-ModuleManifest '.\RdpCacheWorkbench\RdpCacheWorkbench.psd1' | Out-Null

    Write-Host 'Importing module...'
    Import-Module '.\RdpCacheWorkbench\RdpCacheWorkbench.psd1' -Force
    Get-Command Invoke-RdpCacheReview -ErrorAction Stop | Out-Null

    Write-Host 'Running static checks...'
    & '.\tests\StaticChecks.ps1'

    Write-Host 'Project checks passed.'
}
finally {
    Pop-Location
}
