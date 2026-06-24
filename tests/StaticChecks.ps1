#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-RepoFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    return Join-Path $repoRoot $Path
}

$license = Get-Content -Path (Get-RepoFile 'LICENSE') -Raw
Assert-True ($license -match 'BSD 3-Clause License') 'LICENSE must use BSD 3-Clause.'
Assert-True ($license -match 'Zakria Mahmood') 'LICENSE must name Zakria Mahmood.'
Assert-True ($license -notmatch 'MIT License') 'LICENSE must not still declare MIT.'

$readme = Get-Content -Path (Get-RepoFile 'README.md') -Raw
Assert-True ($readme -match 'Install-Module RdpCacheWorkbench') 'README must document PowerShell Gallery install command.'
Assert-True ($readme -match 'Publish-Module -Path \.\\RdpCacheWorkbench') 'README must document PowerShell Gallery publish command.'
Assert-True ($readme -match 'GitHub release') 'README must document GitHub release install/download path.'
Assert-True ($readme -match 'scripts/Sync-ModuleFromScript\.ps1.*maintainer helper') 'README must identify the sync script as a maintainer helper.'

$lock = Get-Content -Path (Get-RepoFile 'third_party.lock.json') -Raw | ConvertFrom-Json
Assert-True ($lock.schema -eq 'rdp-cache-workbench.third_party_lock.v1') 'third_party.lock.json schema is unexpected.'
Assert-True (@($lock.tools).Count -eq 2) 'third_party.lock.json should describe exactly two pinned tools.'

foreach ($tool in $lock.tools) {
    Assert-True ($tool.pinned_commit -match '^[0-9a-f]{40}$') "Pinned commit for $($tool.name) must be a full SHA-1."
    Assert-True ($tool.zip_url -match [regex]::Escape($tool.pinned_commit)) "ZIP URL for $($tool.name) must contain the pinned commit."
    Assert-True ($tool.zip_url -notmatch '/archive/(main|master|HEAD)\.zip$') "ZIP URL for $($tool.name) must not use a moving branch archive."
}

$script = Get-Content -Path (Get-RepoFile 'Invoke-RdpCacheReview.ps1') -Raw
foreach ($tool in $lock.tools) {
    Assert-True ($script -match [regex]::Escape($tool.pinned_commit)) "Script must reference pinned commit for $($tool.name)."
}

$scriptBlock = [scriptblock]::Create($script)
Assert-True ($null -ne $scriptBlock) 'Invoke-RdpCacheReview.ps1 must parse as PowerShell.'

$manifest = Test-ModuleManifest -Path (Get-RepoFile 'RdpCacheWorkbench\RdpCacheWorkbench.psd1')
Assert-True ($manifest.Name -eq 'RdpCacheWorkbench') 'Module manifest name is unexpected.'
Assert-True ($manifest.Version.ToString() -eq '0.2.0') 'Module manifest version must be 0.2.0.'
Assert-True ($manifest.ExportedFunctions.ContainsKey('Invoke-RdpCacheReview')) 'Module must export Invoke-RdpCacheReview.'

Import-Module (Get-RepoFile 'RdpCacheWorkbench\RdpCacheWorkbench.psd1') -Force
$command = Get-Command Invoke-RdpCacheReview -ErrorAction Stop
Assert-True ($command.ModuleName -eq 'RdpCacheWorkbench') 'Invoke-RdpCacheReview must import from RdpCacheWorkbench.'

Write-Host 'Static checks passed.'
