# Changelog

All notable changes to this project are documented here.

## v0.2.0 - 2026-06-24

- Added PowerShell module packaging with `RdpCacheWorkbench.psd1` and `RdpCacheWorkbench.psm1`.
- Added local and CI validation scripts for syntax, manifest, import, static checks, and package staging.
- Added GitHub Actions CI for Windows PowerShell validation.
- Added optional Authenticode signing helper for release maintainers with a code-signing certificate.
- Switched the project license to BSD 3-Clause with copyright attribution for Zakria Mahmood.
- Clarified install paths for direct script use, local module import, GitHub release downloads, and future PowerShell Gallery publication.

## v0.1.0 - 2026-06-24

- First public release of the RDP Cache Review Workbench.
- Added defensive PowerShell workflow for discovering and copying RDP bitmap cache artefacts.
- Added SHA-256 manifest generation for copied cache files.
- Added pinned local tool cache support for ANSSI `bmc-tools` and BriMor Labs `rdpieces`.
- Added extraction and reconstruction workflow with explicit dependency prompts.
- Added security and interpretation guidance for sensitive, fragmented RDP bitmap cache output.
- Republished `v0.1.0` on 2026-06-24 to correct the license to BSD 3-Clause.
