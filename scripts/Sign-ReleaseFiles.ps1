#requires -version 5.1
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Thumbprint')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = 'Certificate')]
    [System.Security.Cryptography.X509Certificates.X509Certificate2]$Certificate,

    [Parameter(Mandatory = $true, ParameterSetName = 'Thumbprint')]
    [ValidateNotNullOrEmpty()]
    [string]$CertificateThumbprint,

    [string[]]$Path = @(
        '.\Invoke-RdpCacheReview.ps1',
        '.\RdpCacheWorkbench\RdpCacheWorkbench.psm1',
        '.\RdpCacheWorkbench\RdpCacheWorkbench.psd1',
        '.\scripts\Sync-ModuleFromScript.ps1',
        '.\scripts\Test-Project.ps1',
        '.\scripts\Test-Package.ps1'
    ),

    [string]$TimestampServer = 'http://timestamp.digicert.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot

Push-Location $repoRoot
try {
    if ($PSCmdlet.ParameterSetName -eq 'Thumbprint') {
        $normalizedThumbprint = $CertificateThumbprint -replace '\s', ''
        $Certificate = Get-ChildItem -Path Cert:\CurrentUser\My, Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
            Where-Object { $_.Thumbprint -eq $normalizedThumbprint } |
            Select-Object -First 1

        if (-not $Certificate) {
            throw "Code-signing certificate not found by thumbprint: $CertificateThumbprint"
        }
    }

    foreach ($item in $Path) {
        $resolved = Resolve-Path -Path $item -ErrorAction Stop
        foreach ($file in $resolved) {
            if ($PSCmdlet.ShouldProcess($file.Path, 'Apply Authenticode signature')) {
                $signature = Set-AuthenticodeSignature -FilePath $file.Path -Certificate $Certificate -TimestampServer $TimestampServer
                if ($signature.Status -ne 'Valid') {
                    throw "Signing failed for $($file.Path): $($signature.StatusMessage)"
                }
            }
        }
    }
}
finally {
    Pop-Location
}
