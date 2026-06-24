#requires -version 5.1
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$source = Join-Path $repoRoot 'Invoke-RdpCacheReview.ps1'
$modulePath = Join-Path $repoRoot 'RdpCacheWorkbench\RdpCacheWorkbench.psm1'

if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
    throw "Source script not found: $source"
}

$content = Get-Content -Path $source -Raw
$content = $content -replace '(?m)^#requires -version 5\.1\r?\n', ''
$content = $content -replace '(?m)^\s*exit 1\s*$', '        throw'

$module = @"
#requires -version 5.1
# This module command is generated from ../Invoke-RdpCacheReview.ps1.
# Keep both entry points in sync when changing review workflow behavior.
function Invoke-RdpCacheReview {
$content
}

Export-ModuleMember -Function Invoke-RdpCacheReview
"@

Set-Content -Path $modulePath -Value $module -Encoding UTF8
Write-Host "Updated $modulePath"
