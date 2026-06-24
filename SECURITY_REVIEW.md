# Security Review Notes

## Scope

This review covers the third-party tools used by `Invoke-RdpCacheReview.ps1`:

| Tool | Pinned version | Commit |
|---|---:|---|
| ANSSI bmc-tools | 3.05 | `5a4cad32be78b3b874aeec910cb478e04ba3501e` |
| BriMor Labs RDPieces | 1.1 build 20201118 | `2a74aeb4b8f42fac1af1f6c9d721fcb299224021` |

The lock details are in `third_party.lock.json`.

## Supply-chain control

The script no longer downloads from `master.zip` or branch heads. It downloads commit-addressed ZIP files only. At runtime it checks that the configured ZIP URL contains the expected pinned commit before download. Downloaded tool folders are stamped with `.rdp-cache-workbench-tool-lock.json`; if a previous tool directory lacks the expected lock, the script prompts before replacing it.

SHA256 verification is supported through `ExpectedArchiveSha256`, but it is empty by default because GitHub-generated source archives are not ideal long-term checksum artefacts. For a stronger release model, fork the repositories, audit the code, publish fixed release assets, record the SHA256 of those release ZIPs, and set `ExpectedArchiveSha256` in the script and `third_party.lock.json`.

## ANSSI bmc-tools review

Observed behaviour:

- Python script.
- Reads `.bin` and `.bmc` files.
- Writes `.bmp` files and optional collage output.
- Uses standard library imports visible in the script: `argparse`, `os`, `os.path`, `sys`, and `struct`.
- No observed network access.
- No observed shell execution.
- No observed package installation.
- No observed `eval` usage.

Residual risks:

- It parses untrusted binary cache files.
- Malformed files could cause crashes, excessive CPU usage, or high memory usage.
- Large cache sets can generate large numbers of BMP files.

Mitigations in the wrapper:

- Copies artefacts into a case folder before processing.
- Keeps hashes of copied cache files in `logs/cache-manifest.csv`.
- Processes only the copied evidence, not the original cache path.

## BriMor Labs RDPieces review

Observed behaviour:

- Perl script.
- Reads extracted BMP files.
- Uses ImageMagick through Perl backtick command execution.
- Uses SQLite/DBI-style local processing.
- Creates its own output folder and exits if the output folder already exists.
- Deletes its intermediate `Data` directory after processing.

Key issue found:

RDPieces interpolates file paths into ImageMagick commands executed through Perl backticks. This is fragile and can be dangerous if source/output paths or file names contain spaces or shell metacharacters.

Mitigation implemented:

`Invoke-RdpCacheReview.ps1` no longer passes user-controlled extracted-folder paths directly to RDPieces. It now:

1. Creates a temporary staging directory.
2. Maps it to a simple temporary drive letter using `subst`.
3. Copies only extracted BMP files to `R:\source`-style paths.
4. Sanitizes BMP file names again before staging.
5. Runs RDPieces against the staged source/output paths.
6. Copies the rebuilt output back to the case folder.
7. Removes the temporary `subst` drive and staging folder.

Residual risks:

- ImageMagick still processes untrusted BMP files.
- RDPieces still uses shell command execution internally.
- The tool should be run in a non-production workstation or VM when handling untrusted evidence.

## Operational guidance

- Do not run as Administrator unless full-machine scanning requires it.
- Prefer a VM or disposable analysis workstation for unknown evidence.
- Do not upload cache files or extracted tiles to online services.
- Review output manually; reconstruction is heuristic and may generate misleading combinations.
