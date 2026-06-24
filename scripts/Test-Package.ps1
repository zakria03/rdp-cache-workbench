#requires -version 5.1
[CmdletBinding()]
param(
    [string]$OutputRoot = '.\artifacts\package',
    [switch]$SkipStaging
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $repoRoot 'RdpCacheWorkbench'
$manifestPath = Join-Path $moduleRoot 'RdpCacheWorkbench.psd1'

Push-Location $repoRoot
try {
    $manifest = Test-ModuleManifest -Path $manifestPath

    if ($manifest.Name -ne 'RdpCacheWorkbench') {
        throw "Unexpected module name: $($manifest.Name)"
    }

    if (-not $manifest.ExportedFunctions.ContainsKey('Invoke-RdpCacheReview')) {
        throw 'The module must export Invoke-RdpCacheReview.'
    }

    if ([string]::IsNullOrWhiteSpace($manifest.Author)) {
        throw 'The module manifest must include Author.'
    }

    if ([string]::IsNullOrWhiteSpace($manifest.Description)) {
        throw 'The module manifest must include Description.'
    }

    if ([string]::IsNullOrWhiteSpace($manifest.PrivateData.PSData.LicenseUri)) {
        throw 'The module manifest must include PrivateData.PSData.LicenseUri.'
    }

    if ([string]::IsNullOrWhiteSpace($manifest.PrivateData.PSData.ProjectUri)) {
        throw 'The module manifest must include PrivateData.PSData.ProjectUri.'
    }

    $moduleFiles = Get-ChildItem -LiteralPath $moduleRoot -File
    $unexpected = @($moduleFiles | Where-Object { $_.Name -notin @('RdpCacheWorkbench.psd1', 'RdpCacheWorkbench.psm1') })
    if ($unexpected.Count -gt 0) {
        throw "Unexpected files in module package folder: $($unexpected.Name -join ', ')"
    }

    Import-Module $manifestPath -Force
    Get-Command Invoke-RdpCacheReview -ErrorAction Stop | Out-Null

    if (-not $SkipStaging) {
        $version = $manifest.Version.ToString()
        if (-not (Test-Path -LiteralPath $OutputRoot)) {
            New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
        }

        $stageRoot = Join-Path (Resolve-Path $OutputRoot).Path "RdpCacheWorkbench-$version"
        if (Test-Path -LiteralPath $stageRoot) {
            Remove-Item -LiteralPath $stageRoot -Recurse -Force
        }

        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        Copy-Item -Path (Join-Path $moduleRoot '*') -Destination $stageRoot -Recurse

        $stagedManifest = Join-Path $stageRoot 'RdpCacheWorkbench.psd1'
        Test-ModuleManifest -Path $stagedManifest | Out-Null
        Write-Host "Staged package files: $stageRoot"
    }

    Write-Host 'Package validation passed.'
}
finally {
    Pop-Location
}
