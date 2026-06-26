# Git Bash Discovery Improvements

**Date:** 2026-06-25

## Summary

Enhanced `find_bash()` / `find_git()` in `core/platform_compat.py` to locate Git for Windows regardless of install location.

## Changes

- Registry probe: `HKLM\SOFTWARE\GitForWindows`, `WOW6432Node`, and `HKCU\SOFTWARE\GitForWindows` `InstallPath`
- Derive install root from `git.exe` on PATH when `bash.exe` is not (e.g. only `cmd\` on PATH)
- Package-manager paths: Scoop (`%USERPROFILE%\scoop\apps\git\current`) and Chocolatey (`%ProgramData%\chocolatey\lib\git\tools\Git`)
- Shared `_windows_git_install_roots()` used by both `find_bash()` fallbacks and `find_git()`

## Live verification (VM)

```
find_bash(): C:\Users\jyang11\AppData\Local\Programs\Git\bin\bash.EXE
find_git():  C:\Users\jyang11\AppData\Local\Programs\Git\cmd\git.EXE
```

Registry: `HKCU\SOFTWARE\GitForWindows\InstallPath` → same LocalAppData install.

## Register impact

- **A2-03** (Git Bash hard dependency): discovery improved; stub `.cmd` fallback still applies when no Git install exists at all.
