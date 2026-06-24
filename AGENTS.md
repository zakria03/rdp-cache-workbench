# Agent Instructions

## Read This First

This repository contains a defensive PowerShell workbench for reviewing Windows RDP bitmap cache artefacts.

Start with these files, in this order:

1. `README.md` for the intended user workflow, parameters, outputs, and interpretation limits.
2. `Invoke-RdpCacheReview.ps1` for the implementation.
3. `third_party.lock.json` for pinned external tool versions.
4. `SECURITY_REVIEW.md` before changing download, install, path handling, cache validation, or third-party tool execution logic.
5. `SECURITY.md` before changing vulnerability reporting or security posture language.

## Safety And Scope

- Treat copied cache files, extracted tiles, rebuilt images, manifests, and logs as potentially sensitive forensic material.
- Keep the project defensive. Do not add offensive collection, persistence, evasion, credential access, or unauthorized access behavior.
- Preserve explicit user prompts before downloads or installs in interactive mode.
- Preserve `-NonInteractive`, `-InstallDependencies`, and `-NoOpenFolders` behavior as documented.
- Do not replace pinned third-party commits with moving branch heads.
- Do not silently broaden filesystem search scope without updating the README and safety language.

## Supply-Chain Notes

- `third_party.lock.json` is the source of truth for pinned ANSSI `bmc-tools` and BriMor Labs `rdpieces` references.
- Existing cached tool folders are accepted only when their `.rdp-cache-workbench-tool-lock.json` metadata matches the configured source and commit.
- If changing download or cache-lock behavior, update both `README.md` and `SECURITY_REVIEW.md`.

## RDPieces Path Handling

`rdpieces` invokes ImageMagick from Perl. The wrapper intentionally stages BMP input under a temporary `subst` drive and passes simple paths such as `R:\source` and `R:\output`.

Before changing this area, read `SECURITY_REVIEW.md` and preserve the path-injection/path-parsing mitigations unless replacing them with an explicitly reviewed safer approach.

## Change Guidance

- Prefer small, conservative PowerShell changes that match the existing style.
- Keep generated case output out of the repository.
- Update documentation when user-visible behavior, parameters, outputs, dependency sources, or security posture changes.
- Use clear, direct language for prompts and warnings.
- Avoid broad refactors unless they reduce a concrete risk or make a requested change materially safer.

## Suggested Checks

Before finishing code changes, run the narrowest useful checks available:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$null = [scriptblock]::Create((Get-Content -Raw .\Invoke-RdpCacheReview.ps1))"
```

For behavior changes, also run the relevant documented command in a controlled test folder and inspect the generated manifests.
