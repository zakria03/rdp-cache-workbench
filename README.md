# RDP Cache Review Workbench

PowerShell tooling for defensively reviewing Windows Remote Desktop bitmap cache artefacts.

This repository can be used directly as a script or packaged as the `RdpCacheWorkbench` PowerShell module.

The project automates a practical RDP bitmap cache review workflow:

1. Search for Windows RDP bitmap cache files across the PC or inside a user-specified folder.
2. Copy the cache files into a working case folder and generate a SHA-256 manifest.
3. Use a fixed local tool cache for pinned ANSSI `bmc-tools` and BriMor Labs `rdpieces`.
4. Extract bitmap tiles from `.bin` / `.bmc` cache files with `bmc-tools`.
5. Install/check the dependencies needed by `rdpieces` after user confirmation.
6. Run `rdpieces` to attempt automated reconstruction and open the output folder.

> Use this only on systems and user profiles you are authorised to inspect. RDP bitmap cache output may contain sensitive fragments of past remote desktop sessions.

## What it looks for

The script searches for files matching typical Windows RDP bitmap cache names:

- `Cache0000.bin`, `Cache0001.bin`, `Cache????.bin`
- `bcache*.bmc`

Default full-PC mode searches fixed local drives and narrows results to paths containing:

```text
\Microsoft\Terminal Server Client\Cache\
```

When you provide `-SearchRoot`, the script searches that folder more broadly for cache-like filenames. This allows you to point it at a copied evidence folder.

## External tools and dependency sources

The script asks before downloading or installing anything. Sources are shown in the prompt.

Pinned `bmc-tools` and `rdpieces` are stored in a fixed local cache so later runs can work offline after the first successful online setup.

Default tool cache:

```text
%LOCALAPPDATA%\RdpCacheWorkbench\tools
```

Override it with:

```powershell
.\Invoke-RdpCacheReview.ps1 -ToolCacheRoot D:\RdpCacheWorkbench\tools
```

| Component | Purpose | Source |
|---|---|---|
| Python | Runs `bmc-tools` | <https://www.python.org/downloads/windows/> |
| Pillow | Optional/needed for bmc-tools collage output | <https://pypi.org/project/pillow/> |
| Strawberry Perl | Runs `rdpieces.pl` on Windows | <https://strawberryperl.com/> |
| ImageMagick | Used by `rdpieces` for image operations | <https://imagemagick.org/download/> |
| ANSSI bmc-tools | Extracts RDP cache bitmap tiles | <https://github.com/ANSSI-FR/bmc-tools> |
| BriMor Labs RDPieces | Attempts automated reconstruction | <https://github.com/brimorlabs/rdpieces> |
| Perl modules | `IO::All`, `DBI`, `DBD::SQLite` | <https://metacpan.org/> |

## Quick start

Open PowerShell. For full-PC search, run as Administrator for better coverage:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Invoke-RdpCacheReview.ps1
```

Or import the module from a local clone:

```powershell
Import-Module .\RdpCacheWorkbench\RdpCacheWorkbench.psd1
Invoke-RdpCacheReview
```

After the module is published to PowerShell Gallery, install it with:

```powershell
Install-Module RdpCacheWorkbench -Scope CurrentUser
Invoke-RdpCacheReview
```

Search a specific folder:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache"
```

Use a custom working folder:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users -WorkingRoot D:\Cases\RDP-Case-001
```

Use a custom fixed tool cache:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users\ZM -ToolCacheRoot D:\RdpCacheWorkbench\tools
```

After the first successful online run, the script reuses the cached pinned copies of `bmc-tools` and `rdpieces`. If Python, Pillow, Strawberry Perl, ImageMagick, and the required Perl modules are already installed, later runs do not need internet access.

Process all discovered cache locations without selecting one interactively:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users -WorkingRoot D:\Cases\RDP-Case-001 -ProcessAllSources
```

Run in non-interactive mode without opening Explorer windows:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users\ZM -WorkingRoot D:\Cases\RDP-Case-001 -ProcessAllSources -NonInteractive -NoOpenFolders
```

The same parameters are available through the module command:

```powershell
Invoke-RdpCacheReview -SearchRoot C:\Users\ZM -WorkingRoot D:\Cases\RDP-Case-001 -ProcessAllSources -NonInteractive -NoOpenFolders
```

## Parameters

| Parameter | Description |
|---|---|
| `-SearchRoot` | Folder to search. If omitted, fixed local drives are searched. |
| `-WorkingRoot` | Case output folder. If omitted, a timestamped Desktop folder is created. |
| `-ToolCacheRoot` | Fixed folder for pinned third-party tools. Defaults to `%LOCALAPPDATA%\RdpCacheWorkbench\tools`. |
| `-ProcessAllSources` | Process all discovered source cache directories. |
| `-NonInteractive` | Avoid prompts. Intended for pre-prepared environments. |
| `-InstallDependencies` | With `-NonInteractive`, allows dependency installation. Interactive runs still ask before each install. |
| `-NoOpenFolders` | Do not open extracted/rebuilt output folders in Explorer. |

## Output structure

```text
rdp-cache-review-YYYYMMDD-HHMMSS/
  cache/        Copied cache files grouped by source directory
  extracted/    BMP tiles extracted by bmc-tools
  rebuilt/      RDPieces reconstruction output
  logs/
    cache-manifest.csv
    third-party-run-manifest.json
    run-summary.json

%LOCALAPPDATA%\RdpCacheWorkbench\tools\
  bmc-tools/    Pinned cached copy, reused across runs
  rdpieces/     Pinned cached copy, reused across runs
```

## Interpretation limitations

RDP bitmap cache data is not a clean screen recording. The output is usually fragmented. Reconstructed images should be treated as heuristic artefacts and validated against other evidence.

Common limitations:

- Tiles may come from multiple sessions.
- Individual tiles generally do not carry reliable timestamps.
- Automated reconstruction can create false matches.
- Missing tiles are normal.
- Sensitive data may appear in fragments.

## Troubleshooting

### RDPieces says the output folder already exists

`rdpieces` expects to create the output directory itself. Delete the target output folder or choose a new name.

### `perl`, `magick`, `py`, or `python` is not found after installation

Open a new PowerShell window and rerun the script. Some installers update the PATH only for new shells.

### No files found

Provide a specific folder:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot "$env:LOCALAPPDATA\Microsoft\Terminal Server Client\Cache"
```

Or check all profiles:

```powershell
.\Invoke-RdpCacheReview.ps1 -SearchRoot C:\Users
```

## PowerShell module packaging

The `RdpCacheWorkbench/` folder is structured for PowerShell Gallery packaging:

```text
RdpCacheWorkbench/
  RdpCacheWorkbench.psd1
  RdpCacheWorkbench.psm1
```

Validate the module manifest:

```powershell
Test-ModuleManifest .\RdpCacheWorkbench\RdpCacheWorkbench.psd1
```

If `Invoke-RdpCacheReview.ps1` changes, regenerate the module wrapper before validating:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Sync-ModuleFromScript.ps1
```

Publish to PowerShell Gallery after reviewing the package and setting an API key:

```powershell
Publish-Module -Path .\RdpCacheWorkbench -NuGetApiKey $env:PSGALLERY_API_KEY
```

Keep the module in this repository unless the project grows into multiple independently versioned tools. GitHub Releases and PowerShell Gallery can both point at the same source repository.

## GitHub Pages landing site

The `docs/` folder contains a static landing page. To publish it with GitHub Pages:

1. Push this repository to GitHub.
2. Go to **Settings → Pages**.
3. Set **Source** to `Deploy from a branch`.
4. Select branch `main` and folder `/docs`.
5. Save.

## Offline and repeated-run behaviour

The script is designed to avoid unnecessary reinstall/download loops:

- Python, Pillow, Perl, ImageMagick, and Perl modules are checked before installation.
- `bmc-tools` and `rdpieces` are downloaded only if the fixed tool cache is missing or not locked to the configured pinned commit.
- Existing tool folders are accepted only when `.rdp-cache-workbench-tool-lock.json` matches the configured commit and ZIP URL.
- If you run offline before the first successful setup, the script cannot download missing tools or dependencies.

## Security notes

This script downloads pinned public tooling from GitHub only when the fixed local tool cache is missing or stale. For controlled environments, pre-populate `-ToolCacheRoot` from a reviewed internal source or publish reviewed release assets from your own fork and set `ExpectedArchiveSha256`.


## Supply-chain posture

This version pins the two forensic helper tools to explicit Git commits instead of downloading moving branch heads:

| Tool | Version | Commit |
|---|---:|---|
| ANSSI bmc-tools | 3.05 | `5a4cad32be78b3b874aeec910cb478e04ba3501e` |
| BriMor Labs RDPieces | 1.1 build 20201118 | `2a74aeb4b8f42fac1af1f6c9d721fcb299224021` |

The lock file is `third_party.lock.json`. The script also writes `logs/third-party-run-manifest.json` during execution, including the fixed tool cache path. Downloaded tool directories receive their own `.rdp-cache-workbench-tool-lock.json`; if an existing tool folder is not locked to the configured commit, the script asks before replacing it.

RDPieces uses ImageMagick through Perl backtick execution. The wrapper mitigates path-injection and path-parsing risk by staging BMP input under a temporary `subst` drive and passing RDPieces simple paths such as `R:\source` and `R:\output`. See `SECURITY_REVIEW.md` for details.
