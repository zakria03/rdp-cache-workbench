<#
.SYNOPSIS
    Collects and reviews Windows RDP bitmap cache artefacts.

.DESCRIPTION
    Invoke-RdpCacheReview.ps1 searches for Windows Remote Desktop bitmap cache files,
    copies them into a working case folder, extracts bitmap tiles using ANSSI bmc-tools,
    and runs BriMor Labs RDPieces against the extracted tiles to attempt automated
    reconstruction.

    The script is defensive/forensic tooling. Run it only on systems and user profiles
    you are authorised to inspect.

.PARAMETER SearchRoot
    Optional root folder to search. If omitted, the script searches fixed local drives
    for common RDP bitmap cache locations.

.PARAMETER WorkingRoot
    Optional root folder for case output. If omitted, a timestamped folder is created
    on the current user's Desktop.

.PARAMETER ToolCacheRoot
    Optional fixed folder for cached third-party tools. If omitted, the script uses
    %LOCALAPPDATA%\RdpCacheWorkbench\tools. This folder is reused across runs so
    bmc-tools and RDPieces do not need to be downloaded again after first install.

.PARAMETER NonInteractive
    Do not prompt. This requires SearchRoot in most operational cases and will process
    all discovered source cache folders. Dependency installation is not attempted unless
    InstallDependencies is also provided.

.PARAMETER InstallDependencies
    Allow dependency installation prompts. In interactive mode, each installation is
    still explicitly confirmed. In NonInteractive mode, this switch allows winget/cpan
    installation without prompt.

.PARAMETER NoOpenFolders
    Do not open extracted/rebuilt output folders in Explorer.

.PARAMETER ProcessAllSources
    Process all discovered cache directories without asking the user to select one.

.EXAMPLE
    .\Invoke-RdpCacheReview.ps1

.EXAMPLE
    .\Invoke-RdpCacheReview.ps1 -SearchRoot "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache"

.EXAMPLE
    .\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users -WorkingRoot D:\Cases\RDP-Case-001 -ProcessAllSources

.EXAMPLE
    .\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users\ZM -ToolCacheRoot D:\RdpCacheWorkbench\tools

.NOTES
    External tools downloaded by this script are pinned to explicit Git commits:
    - ANSSI bmc-tools v3.05: https://github.com/ANSSI-FR/bmc-tools/commit/5a4cad32be78b3b874aeec910cb478e04ba3501e
    - BriMor Labs RDPieces v1.1 build 20201118: https://github.com/brimorlabs/rdpieces/commit/2a74aeb4b8f42fac1af1f6c9d721fcb299224021

    Optional dependencies installed through winget/cpan after confirmation:
    - Python: https://www.python.org/downloads/windows/
    - Strawberry Perl: https://strawberryperl.com/
    - ImageMagick: https://imagemagick.org/download/
    - Perl modules from MetaCPAN/CPAN: https://metacpan.org/
#>

#requires -version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$SearchRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$WorkingRoot,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$ToolCacheRoot,

    [switch]$NonInteractive,
    [switch]$InstallDependencies,
    [switch]$NoOpenFolders,
    [switch]$ProcessAllSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ToolSources = [ordered]@{
    Python = [ordered]@{
        Name      = 'Python 3.13'
        PackageId = 'Python.Python.3.13'
        Url       = 'https://www.python.org/downloads/windows/'
    }
    StrawberryPerl = [ordered]@{
        Name      = 'Strawberry Perl'
        PackageId = 'StrawberryPerl.StrawberryPerl'
        Url       = 'https://strawberryperl.com/'
    }
    ImageMagick = [ordered]@{
        Name      = 'ImageMagick'
        PackageId = 'ImageMagick.ImageMagick'
        Url       = 'https://imagemagick.org/download/'
    }
    Pillow = [ordered]@{
        Name      = 'Python Pillow module'
        PackageId = 'Pillow'
        Url       = 'https://pypi.org/project/pillow/'
    }
    PerlModules = [ordered]@{
        Name      = 'Perl modules for RDPieces'
        PackageId = 'IO::All DBI DBD::SQLite'
        Url       = 'https://metacpan.org/'
    }
    BmcTools = [ordered]@{
        Name                  = 'ANSSI bmc-tools'
        Url                   = 'https://github.com/ANSSI-FR/bmc-tools'
        Repository            = 'ANSSI-FR/bmc-tools'
        Version               = '3.05'
        PinnedCommit          = '5a4cad32be78b3b874aeec910cb478e04ba3501e'
        ZipUrl                = 'https://github.com/ANSSI-FR/bmc-tools/archive/5a4cad32be78b3b874aeec910cb478e04ba3501e.zip'
        ExpectedArchiveSha256 = ''
        License               = 'CECILL-2.1'
    }
    RDPieces = [ordered]@{
        Name                  = 'BriMor Labs RDPieces'
        Url                   = 'https://github.com/brimorlabs/rdpieces'
        Repository            = 'brimorlabs/rdpieces'
        Version               = '1.1 build 20201118'
        PinnedCommit          = '2a74aeb4b8f42fac1af1f6c9d721fcb299224021'
        ZipUrl                = 'https://github.com/brimorlabs/rdpieces/archive/2a74aeb4b8f42fac1af1f6c9d721fcb299224021.zip'
        ExpectedArchiveSha256 = ''
        License               = 'LGPL-3.0'
    }
}

function Write-Section {
    param([string]$Text)
    Write-Host ""
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Text)
    Write-Host "WARNING: $Text" -ForegroundColor Yellow
}

function Confirm-Action {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$SourceUrl,
        [string]$Command
    )

    if ($SourceUrl) { Write-Host "Source URL: $SourceUrl" -ForegroundColor DarkCyan }
    if ($Command) { Write-Host "Command: $Command" -ForegroundColor DarkCyan }

    if ($NonInteractive) {
        if ($InstallDependencies) { return $true }
        return $false
    }

    $answer = Read-Host "$Message [y/N]"
    return ($answer -match '^(y|yes)$')
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $extra = @(
        'C:\Strawberry\perl\bin',
        'C:\Strawberry\c\bin'
    )

    $paths = @($machinePath, $userPath) -join ';'
    foreach ($p in $extra) {
        if ((Test-Path $p) -and ($paths -notlike "*$p*")) {
            $paths = "$paths;$p"
        }
    }

    $imageMagickDirs = Get-ChildItem 'C:\Program Files' -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'ImageMagick*' }
    foreach ($dir in $imageMagickDirs) {
        if ($paths -notlike "*$($dir.FullName)*") {
            $paths = "$paths;$($dir.FullName)"
        }
    }

    $env:Path = $paths
}

function Get-CommandPath {
    param([Parameter(Mandatory = $true)][string]$CommandName)
    $cmd = Get-Command $CommandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

function Install-WingetPackage {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$PackageId,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )

    $winget = Get-CommandPath -CommandName 'winget'
    if (-not $winget) {
        throw "winget was not found. Install manually from $SourceUrl and rerun this script."
    }

    $cmd = "winget install -e --id $PackageId --source winget --accept-package-agreements --accept-source-agreements"
    if (-not (Confirm-Action -Message "Install $Name using winget?" -SourceUrl $SourceUrl -Command $cmd)) {
        throw "$Name is required but was not installed."
    }

    & $winget install -e --id $PackageId --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install failed for $Name ($PackageId)." }
    Update-SessionPath
}

function Get-PythonRunner {
    Update-SessionPath

    $py = Get-CommandPath -CommandName 'py'
    if ($py) {
        & $py -3 --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return @{ Exe = $py; Args = @('-3') }
        }
    }

    $python = Get-CommandPath -CommandName 'python'
    if ($python) {
        & $python --version *> $null
        if ($LASTEXITCODE -eq 0) {
            return @{ Exe = $python; Args = @() }
        }
    }

    return $null
}

function Ensure-Python {
    $runner = Get-PythonRunner
    if ($runner) { return $runner }

    $src = $script:ToolSources.Python
    Install-WingetPackage -Name $src.Name -PackageId $src.PackageId -SourceUrl $src.Url

    $runner = Get-PythonRunner
    if (-not $runner) {
        throw 'Python was installed or already present, but no usable py/python command was found in this session. Open a new PowerShell window and rerun the script.'
    }
    return $runner
}

function Ensure-PythonModule {
    param(
        [Parameter(Mandatory = $true)][hashtable]$PythonRunner,
        [Parameter(Mandatory = $true)][string]$ModuleName,
        [Parameter(Mandatory = $true)][string]$PackageName,
        [Parameter(Mandatory = $true)][string]$SourceUrl
    )

    & $PythonRunner.Exe @($PythonRunner.Args) -c "import $ModuleName" *> $null
    if ($LASTEXITCODE -eq 0) { return }

    $cmd = "$($PythonRunner.Exe) $($PythonRunner.Args -join ' ') -m pip install $PackageName"
    if (-not (Confirm-Action -Message "Install Python module $PackageName?" -SourceUrl $SourceUrl -Command $cmd)) {
        throw "Python module $PackageName is required but was not installed."
    }

    & $PythonRunner.Exe @($PythonRunner.Args) -m pip install $PackageName
    if ($LASTEXITCODE -ne 0) { throw "pip install failed for $PackageName." }
}

function Ensure-StrawberryPerl {
    Update-SessionPath
    $perl = Get-CommandPath -CommandName 'perl'
    if ($perl) { return $perl }

    $src = $script:ToolSources.StrawberryPerl
    Install-WingetPackage -Name $src.Name -PackageId $src.PackageId -SourceUrl $src.Url

    $perl = Get-CommandPath -CommandName 'perl'
    if (-not $perl) {
        throw 'Strawberry Perl was installed or already present, but perl.exe was not found in PATH. Open a new PowerShell window and rerun the script.'
    }
    return $perl
}

function Ensure-ImageMagick {
    Update-SessionPath
    $magick = Get-CommandPath -CommandName 'magick'
    if ($magick) { return $magick }

    $src = $script:ToolSources.ImageMagick
    Install-WingetPackage -Name $src.Name -PackageId $src.PackageId -SourceUrl $src.Url

    $magick = Get-CommandPath -CommandName 'magick'
    if (-not $magick) {
        throw 'ImageMagick was installed or already present, but magick.exe was not found in PATH. Open a new PowerShell window and rerun the script.'
    }
    return $magick
}

function Ensure-PerlModule {
    param(
        [Parameter(Mandatory = $true)][string]$PerlExe,
        [Parameter(Mandatory = $true)][string[]]$Modules
    )

    $missing = @()
    foreach ($module in $Modules) {
        & $PerlExe "-M$module" -e 'exit 0' *> $null
        if ($LASTEXITCODE -ne 0) { $missing += $module }
    }

    if ($missing.Count -eq 0) { return }

    $cpan = Get-CommandPath -CommandName 'cpan'
    if (-not $cpan) { throw "Missing Perl modules: $($missing -join ', '). cpan.exe was not found." }

    $src = $script:ToolSources.PerlModules
    $cmd = "cpan -T -i $($missing -join ' ')"
    if (-not (Confirm-Action -Message "Install missing Perl modules: $($missing -join ', ')?" -SourceUrl $src.Url -Command $cmd)) {
        throw "Missing Perl modules were not installed: $($missing -join ', ')."
    }

    & $cpan -T -i @missing
    if ($LASTEXITCODE -ne 0) { Write-Warn 'cpan returned a non-zero exit code. The script will continue and verify modules again.' }

    foreach ($module in $missing) {
        & $PerlExe "-M$module" -e 'exit 0' *> $null
        if ($LASTEXITCODE -ne 0) { throw "Perl module $module is still missing after attempted installation." }
    }
}

function Save-UrlZipTool {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SourceUrl,
        [Parameter(Mandatory = $true)][string]$ZipUrl,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$PinnedCommit,
        [string]$ExpectedSha256
    )

    $installLockPath = Join-Path $Destination '.rdp-cache-workbench-tool-lock.json'
    if (Test-Path -LiteralPath $Destination) {
        $existingMatchesLock = $false
        if (Test-Path -LiteralPath $installLockPath) {
            try {
                $existingLock = Get-Content -LiteralPath $installLockPath -Raw | ConvertFrom-Json
                $existingMatchesLock = ($existingLock.pinned_commit -eq $PinnedCommit -and $existingLock.zip_url -eq $ZipUrl)
            }
            catch {
                $existingMatchesLock = $false
            }
        }

        if ($existingMatchesLock) { return $Destination }

        $replaceCommand = "Remove existing tool directory $Destination and replace it with reviewed pinned $Name commit $PinnedCommit"
        if (-not (Confirm-Action -Message "Existing $Name directory is not locked to the configured pinned commit. Replace it?" -SourceUrl $SourceUrl -Command $replaceCommand)) {
            throw "Existing $Name directory is not locked to the configured pinned commit. Refusing to continue."
        }
        Remove-Item -LiteralPath $Destination -Recurse -Force
    }

    if ($PinnedCommit -and $ZipUrl -notmatch [regex]::Escape($PinnedCommit)) {
        throw "Refusing to download $Name because ZipUrl does not contain the pinned commit $PinnedCommit. URL: $ZipUrl"
    }

    $cmd = "Download pinned ZIP from $ZipUrl and expand into $Destination"
    if ($ExpectedSha256) { $cmd = "$cmd; verify SHA256 $ExpectedSha256" }
    if (-not (Confirm-Action -Message "Download pinned $Name?" -SourceUrl $SourceUrl -Command $cmd)) {
        throw "$Name is required but was not downloaded."
    }

    $parent = Split-Path $Destination -Parent
    New-Item -ItemType Directory -Force $parent | Out-Null

    $tmp = Join-Path $parent ("download-{0}-{1}" -f ($Name -replace '[^a-zA-Z0-9]', ''), [Guid]::NewGuid().ToString('N'))
    $zip = "$tmp.zip"
    New-Item -ItemType Directory -Force $tmp | Out-Null

    try {
        Invoke-WebRequest -Uri $ZipUrl -OutFile $zip -UseBasicParsing

        if ($ExpectedSha256) {
            $actualHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToUpperInvariant()
            if ($actualHash -ne $ExpectedSha256.ToUpperInvariant()) {
                throw "SHA256 mismatch for $Name. Expected $ExpectedSha256 but got $actualHash. Refusing to extract."
            }
        }
        else {
            Write-Warn "$Name is pinned by immutable commit URL, but archive SHA256 is not configured. For higher assurance, host a reviewed release asset and set ExpectedArchiveSha256."
        }

        Expand-Archive -LiteralPath $zip -DestinationPath $tmp -Force
        $expanded = Get-ChildItem $tmp -Directory | Select-Object -First 1
        if (-not $expanded) { throw "Could not find expanded directory for $Name." }
        Move-Item -LiteralPath $expanded.FullName -Destination $Destination

        [ordered]@{
            name = $Name
            source_url = $SourceUrl
            zip_url = $ZipUrl
            pinned_commit = $PinnedCommit
            expected_archive_sha256 = $ExpectedSha256
            installed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json -Depth 5 | Out-File -FilePath (Join-Path $Destination '.rdp-cache-workbench-tool-lock.json') -Encoding UTF8
    }
    finally {
        Remove-Item $zip -Force -ErrorAction SilentlyContinue
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $Destination
}

function Write-ThirdPartyRunManifest {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$ToolCacheRoot
    )

    $manifest = [ordered]@{
        generated_at_utc = (Get-Date).ToUniversalTime().ToString('o')
        supply_chain_model = 'Pinned GitHub commit ZIP URLs stored in a fixed local tool cache. Optional SHA256 verification is supported when ExpectedArchiveSha256 is configured.'
        tool_cache_root = $ToolCacheRoot
        offline_reuse_model = 'After first successful online installation, bmc-tools and RDPieces are reused from this fixed cache if their lock files match the configured pinned commits.'
        tools = @(
            [ordered]@{
                name = $script:ToolSources.BmcTools.Name
                repository = $script:ToolSources.BmcTools.Repository
                upstream_url = $script:ToolSources.BmcTools.Url
                version = $script:ToolSources.BmcTools.Version
                pinned_commit = $script:ToolSources.BmcTools.PinnedCommit
                zip_url = $script:ToolSources.BmcTools.ZipUrl
                expected_archive_sha256 = $script:ToolSources.BmcTools.ExpectedArchiveSha256
                license = $script:ToolSources.BmcTools.License
            },
            [ordered]@{
                name = $script:ToolSources.RDPieces.Name
                repository = $script:ToolSources.RDPieces.Repository
                upstream_url = $script:ToolSources.RDPieces.Url
                version = $script:ToolSources.RDPieces.Version
                pinned_commit = $script:ToolSources.RDPieces.PinnedCommit
                zip_url = $script:ToolSources.RDPieces.ZipUrl
                expected_archive_sha256 = $script:ToolSources.RDPieces.ExpectedArchiveSha256
                license = $script:ToolSources.RDPieces.License
            }
        )
    }

    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
}

function Get-DefaultSearchRoots {
    $roots = @()
    try {
        $disks = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop
        foreach ($disk in $disks) { $roots += "$($disk.DeviceID)\" }
    }
    catch {
        $roots = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -match '^[A-Z]:\\$' }).Root
    }
    return $roots | Sort-Object -Unique
}

function Find-RdpCacheFiles {
    param(
        [Parameter(Mandatory = $true)][string[]]$Roots,
        [switch]$StrictRdpPath
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) {
            Write-Warn "Search root not found: $root"
            continue
        }

        Write-Host "Searching: $root"
        $patterns = @('Cache*.bin', 'bcache*.bmc')
        foreach ($pattern in $patterns) {
            try {
                Get-ChildItem -LiteralPath $root -Filter $pattern -Recurse -File -Force -ErrorAction SilentlyContinue |
                    Where-Object {
                        ($_.Name -match '^Cache\d{4}\.bin$' -or $_.Name -match '^bcache\d*\.bmc$') -and
                        (-not $StrictRdpPath -or $_.FullName -match '\\Microsoft\\Terminal Server Client\\Cache\\')
                    } |
                    ForEach-Object { [void]$results.Add($_) }
            }
            catch {
                Write-Warn "Search issue under $root for $pattern: $($_.Exception.Message)"
            }
        }
    }

    return $results | Sort-Object FullName -Unique
}

function Request-SearchRoots {
    if ($SearchRoot) { return @{ Roots = @($SearchRoot); Strict = $false } }
    return @{ Roots = @(Get-DefaultSearchRoots); Strict = $true }
}

function Get-SourceSelection {
    param([Parameter(Mandatory = $true)]$Groups)

    if ($Groups.Count -eq 1 -or $NonInteractive -or $ProcessAllSources) { return $Groups }

    Write-Host ""
    Write-Host "Discovered cache source directories:" -ForegroundColor Green
    for ($i = 0; $i -lt $Groups.Count; $i++) {
        $g = $Groups[$i]
        $nonZero = @($g.Group | Where-Object { $_.Length -gt 0 }).Count
        Write-Host ("[{0}] {1} ({2} files, {3} non-zero)" -f ($i + 1), $g.Name, $g.Count, $nonZero)
    }

    while ($true) {
        $choice = Read-Host "Enter a number to process one source, A for all, or Q to exit"
        if ($choice -match '^(q|quit)$') { exit 0 }
        if ($choice -match '^(a|all)$') { return $Groups }
        if ($choice -match '^\d+$') {
            $idx = [int]$choice - 1
            if ($idx -ge 0 -and $idx -lt $Groups.Count) { return @($Groups[$idx]) }
        }
        Write-Warn 'Invalid selection.'
    }
}

function Convert-ToSafeName {
    param([Parameter(Mandatory = $true)][string]$Value)
    $safe = $Value -replace '^[A-Za-z]:', ''
    $safe = $safe -replace '[\\/:*?"<>| ]+', '_'
    $safe = $safe.Trim('_')
    if ([string]::IsNullOrWhiteSpace($safe)) { $safe = [Guid]::NewGuid().ToString('N') }
    if ($safe.Length -gt 80) { $safe = $safe.Substring($safe.Length - 80) }
    return $safe
}

function Get-NonExistingPath {
    param([Parameter(Mandatory = $true)][string]$BasePath)
    if (-not (Test-Path -LiteralPath $BasePath)) { return $BasePath }
    for ($i = 1; $i -lt 999; $i++) {
        $candidate = "{0}_{1:000}" -f $BasePath, $i
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
    }
    throw "Could not create a non-existing path based on $BasePath"
}

function Copy-CacheGroup {
    param(
        [Parameter(Mandatory = $true)]$Group,
        [Parameter(Mandatory = $true)][string]$CacheRoot
    )

    $safe = Convert-ToSafeName -Value $Group.Name
    $dest = Join-Path $CacheRoot $safe
    New-Item -ItemType Directory -Force $dest | Out-Null

    $manifestRows = @()
    foreach ($file in $Group.Group) {
        $destFile = Join-Path $dest $file.Name
        Copy-Item -LiteralPath $file.FullName -Destination $destFile -Force
        $hash = Get-FileHash -LiteralPath $destFile -Algorithm SHA256
        $manifestRows += [pscustomobject]@{
            SourceDirectory = $Group.Name
            SourceFile      = $file.FullName
            CopiedFile      = $destFile
            Name            = $file.Name
            Length          = $file.Length
            LastWriteTime   = $file.LastWriteTime.ToString('o')
            SHA256          = $hash.Hash
        }
    }

    return [pscustomobject]@{
        SafeName = $safe
        SourceDirectory = $Group.Name
        CacheCopyDirectory = $dest
        ManifestRows = $manifestRows
    }
}

function Invoke-BmcTools {
    param(
        [Parameter(Mandatory = $true)][hashtable]$PythonRunner,
        [Parameter(Mandatory = $true)][string]$BmcToolsDirectory,
        [Parameter(Mandatory = $true)][string]$SourceCacheDirectory,
        [Parameter(Mandatory = $true)][string]$DestinationDirectory
    )

    New-Item -ItemType Directory -Force $DestinationDirectory | Out-Null
    $scriptPath = Join-Path $BmcToolsDirectory 'bmc-tools.py'
    if (-not (Test-Path -LiteralPath $scriptPath)) { throw "bmc-tools.py not found at $scriptPath" }

    Write-Host "Running bmc-tools against: $SourceCacheDirectory"
    & $PythonRunner.Exe @($PythonRunner.Args) $scriptPath -s $SourceCacheDirectory -d $DestinationDirectory -b -v
    if ($LASTEXITCODE -ne 0) { Write-Warn "bmc-tools returned exit code $LASTEXITCODE for $SourceCacheDirectory" }
}

function Get-FreeSubstDrive {
    $used = @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Name.ToUpperInvariant() })
    foreach ($letter in @('R','S','T','U','V','W','X','Y','Z')) {
        if ($used -notcontains $letter) { return "$letter`:" }
    }
    throw 'No free drive letter was available for safe RDPieces staging.'
}

function New-SubstDrive {
    param([Parameter(Mandatory = $true)][string]$TargetPath)

    $subst = Join-Path $env:SystemRoot 'System32\subst.exe'
    if (-not (Test-Path -LiteralPath $subst)) { $subst = 'subst.exe' }

    $drive = Get-FreeSubstDrive
    & $subst $drive $TargetPath
    if ($LASTEXITCODE -ne 0) { throw "subst failed while mapping $drive to $TargetPath" }
    return $drive
}

function Remove-SubstDrive {
    param([string]$Drive)
    if (-not $Drive) { return }
    $subst = Join-Path $env:SystemRoot 'System32\subst.exe'
    if (-not (Test-Path -LiteralPath $subst)) { $subst = 'subst.exe' }
    & $subst $Drive /D *> $null
}

function Invoke-RDPieces {
    param(
        [Parameter(Mandatory = $true)][string]$PerlExe,
        [Parameter(Mandatory = $true)][string]$RDPiecesDirectory,
        [Parameter(Mandatory = $true)][string]$SourceBmpDirectory,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    $rdpScript = Join-Path $RDPiecesDirectory 'rdpieces.pl'
    if (-not (Test-Path -LiteralPath $rdpScript)) { throw "rdpieces.pl not found at $rdpScript" }
    if (Test-Path -LiteralPath $OutputDirectory) { throw "RDPieces output directory already exists: $OutputDirectory" }

    $bmpFiles = @(Get-ChildItem -LiteralPath $SourceBmpDirectory -Recurse -Filter '*.bmp' -File -ErrorAction SilentlyContinue)
    if ($bmpFiles.Count -eq 0) {
        Write-Warn "No BMP files found under $SourceBmpDirectory. Skipping RDPieces."
        return $false
    }

    # Security hardening:
    # RDPieces invokes ImageMagick through Perl backticks and interpolates file paths in command strings.
    # To avoid command-line injection and path parsing issues from spaces/metacharacters in user-controlled paths,
    # this wrapper stages only BMP files under a temporary subst drive and passes RDPieces simple paths such as R:\source.
    $stageRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("RDPWB-{0}" -f [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $stageRoot | Out-Null
    $substDrive = $null

    try {
        $substDrive = New-SubstDrive -TargetPath $stageRoot
        $driveRoot = "$substDrive\"
        $stageSource = Join-Path $driveRoot 'source'
        $stageOutput = Join-Path $driveRoot 'output'
        New-Item -ItemType Directory -Force $stageSource | Out-Null

        foreach ($bmp in $bmpFiles) {
            $safeName = $bmp.Name -replace '[^a-zA-Z0-9._-]', '_'
            Copy-Item -LiteralPath $bmp.FullName -Destination (Join-Path $stageSource $safeName) -Force
        }

        Write-Host "Running RDPieces against staged BMPs: $stageSource"
        & $PerlExe $rdpScript -source $stageSource -output $stageOutput
        if ($LASTEXITCODE -ne 0) { Write-Warn "RDPieces returned exit code $LASTEXITCODE for $SourceBmpDirectory" }

        if (Test-Path -LiteralPath $stageOutput) {
            $parent = Split-Path $OutputDirectory -Parent
            New-Item -ItemType Directory -Force $parent | Out-Null
            Copy-Item -LiteralPath $stageOutput -Destination $OutputDirectory -Recurse -Force
        }
        else {
            Write-Warn "RDPieces did not create an output directory for $SourceBmpDirectory"
        }
    }
    finally {
        Remove-SubstDrive -Drive $substDrive
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }

    return $true
}

try {
    if ([Environment]::OSVersion.Platform -ne 'Win32NT') { throw 'This script is intended for Windows PowerShell/PowerShell on Windows.' }

    Write-Section 'RDP Cache Review Workbench'
    if (-not (Test-IsAdmin)) {
        Write-Warn 'You are not running as Administrator. Full-PC scanning and winget installs may be limited.'
    }

    $search = Request-SearchRoots
    $foundFiles = @()
    while ($true) {
        $foundFiles = @(Find-RdpCacheFiles -Roots $search.Roots -StrictRdpPath:([bool]$search.Strict))
        if ($foundFiles.Count -gt 0) { break }

        Write-Warn 'No RDP bitmap cache files were found.'
        if ($NonInteractive) { exit 2 }

        $next = Read-Host 'Enter another directory to search, or press Enter to exit'
        if ([string]::IsNullOrWhiteSpace($next)) { exit 0 }
        $search = @{ Roots = @($next); Strict = $false }
    }

    Write-Section 'Discovered cache files'
    $foundFiles | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize

    $groups = @($foundFiles | Group-Object DirectoryName | Sort-Object Name)
    $selectedGroups = @(Get-SourceSelection -Groups $groups)

    if (-not $WorkingRoot) {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $WorkingRoot = Join-Path $desktop ("rdp-cache-review-{0}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    }

    if (-not $ToolCacheRoot) {
        $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
        if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = $env:LOCALAPPDATA }
        if ([string]::IsNullOrWhiteSpace($localAppData)) { throw 'Could not resolve LOCALAPPDATA for the fixed tool cache. Provide -ToolCacheRoot.' }
        $ToolCacheRoot = Join-Path $localAppData 'RdpCacheWorkbench\tools'
    }

    $cacheRoot = Join-Path $WorkingRoot 'cache'
    $extractedRoot = Join-Path $WorkingRoot 'extracted'
    $rebuiltRoot = Join-Path $WorkingRoot 'rebuilt'
    $toolsRoot = $ToolCacheRoot
    $logsRoot = Join-Path $WorkingRoot 'logs'

    New-Item -ItemType Directory -Force $cacheRoot, $extractedRoot, $rebuiltRoot, $toolsRoot, $logsRoot | Out-Null

    Write-Section 'Copying cache files'
    $cases = @()
    foreach ($group in $selectedGroups) {
        $case = Copy-CacheGroup -Group $group -CacheRoot $cacheRoot
        $cases += $case
        Write-Host "Copied: $($group.Name) -> $($case.CacheCopyDirectory)"
    }

    $manifest = @($cases | ForEach-Object { $_.ManifestRows })
    $manifestPath = Join-Path $logsRoot 'cache-manifest.csv'
    $manifest | Export-Csv -Path $manifestPath -NoTypeInformation -Encoding UTF8
    Write-Host "Manifest written: $manifestPath"

    Write-Section 'Preparing dependencies'
    $pythonRunner = Ensure-Python
    Ensure-PythonModule -PythonRunner $pythonRunner -ModuleName 'PIL' -PackageName 'Pillow' -SourceUrl $script:ToolSources.Pillow.Url
    $perl = Ensure-StrawberryPerl
    $magick = Ensure-ImageMagick
    Ensure-PerlModule -PerlExe $perl -Modules @('IO::All', 'DBI', 'DBD::SQLite')

    Write-Host "Python runner: $($pythonRunner.Exe) $($pythonRunner.Args -join ' ')"
    Write-Host "Perl: $perl"
    Write-Host "ImageMagick: $magick"

    Write-Section 'Preparing external tools'
    $bmcDir = Join-Path $toolsRoot 'bmc-tools'
    $rdpDir = Join-Path $toolsRoot 'rdpieces'
    Save-UrlZipTool -Name $script:ToolSources.BmcTools.Name -SourceUrl $script:ToolSources.BmcTools.Url -ZipUrl $script:ToolSources.BmcTools.ZipUrl -Destination $bmcDir -PinnedCommit $script:ToolSources.BmcTools.PinnedCommit -ExpectedSha256 $script:ToolSources.BmcTools.ExpectedArchiveSha256 | Out-Null
    Save-UrlZipTool -Name $script:ToolSources.RDPieces.Name -SourceUrl $script:ToolSources.RDPieces.Url -ZipUrl $script:ToolSources.RDPieces.ZipUrl -Destination $rdpDir -PinnedCommit $script:ToolSources.RDPieces.PinnedCommit -ExpectedSha256 $script:ToolSources.RDPieces.ExpectedArchiveSha256 | Out-Null
    Write-ThirdPartyRunManifest -OutputPath (Join-Path $logsRoot 'third-party-run-manifest.json') -ToolCacheRoot $toolsRoot

    Write-Section 'Extracting bitmap tiles'
    $summary = @()
    foreach ($case in $cases) {
        $extractDir = Join-Path $extractedRoot $case.SafeName
        Invoke-BmcTools -PythonRunner $pythonRunner -BmcToolsDirectory $bmcDir -SourceCacheDirectory $case.CacheCopyDirectory -DestinationDirectory $extractDir
        $bmpCount = @(Get-ChildItem -LiteralPath $extractDir -Recurse -Filter '*.bmp' -File -ErrorAction SilentlyContinue).Count
        $case | Add-Member -MemberType NoteProperty -Name ExtractedDirectory -Value $extractDir -Force
        $case | Add-Member -MemberType NoteProperty -Name BmpCount -Value $bmpCount -Force
        Write-Host "Extracted BMP count for $($case.SafeName): $bmpCount"
    }

    if (-not $NoOpenFolders) { Start-Process explorer.exe $extractedRoot }

    Write-Section 'Running RDPieces reconstruction'
    foreach ($case in $cases) {
        $target = Join-Path $rebuiltRoot $case.SafeName
        $target = Get-NonExistingPath -BasePath $target
        $ran = Invoke-RDPieces -PerlExe $perl -RDPiecesDirectory $rdpDir -SourceBmpDirectory $case.ExtractedDirectory -OutputDirectory $target
        $case | Add-Member -MemberType NoteProperty -Name RebuiltDirectory -Value $target -Force
        $case | Add-Member -MemberType NoteProperty -Name RDPiecesRan -Value $ran -Force
        if ($ran) { Write-Host "RDPieces output: $target" }
    }

    if (-not $NoOpenFolders) { Start-Process explorer.exe $rebuiltRoot }

    $summary = $cases | ForEach-Object {
        [pscustomobject]@{
            SourceDirectory    = $_.SourceDirectory
            CacheCopyDirectory = $_.CacheCopyDirectory
            ExtractedDirectory = $_.ExtractedDirectory
            RebuiltDirectory   = $_.RebuiltDirectory
            BmpCount           = $_.BmpCount
            RDPiecesRan        = $_.RDPiecesRan
        }
    }

    $summaryPath = Join-Path $logsRoot 'run-summary.json'
    $summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $summaryPath -Encoding UTF8

    Write-Section 'Complete'
    Write-Host "Working root: $WorkingRoot" -ForegroundColor Green
    Write-Host "Tool cache:   $toolsRoot"
    Write-Host "Manifest:     $manifestPath"
    Write-Host "Summary:      $summaryPath"
    Write-Host "Extracted:    $extractedRoot"
    Write-Host "Rebuilt:      $rebuiltRoot"
}
catch {
    Write-Host ""
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host 'If this happened after installing dependencies, open a new PowerShell window and rerun the script.' -ForegroundColor Yellow
    exit 1
}
