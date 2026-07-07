---
date: 2026-07-07
time: 10:04:34
subagent_task: Pathing & Codebase Interaction Review
delegation_id: deleg_76342322
status: completed
summary: Analyzed path handling and codebase interactions in launch-windows.ps1
---

# Pathing & Codebase Interaction Review

## What the script assumes about the repo
- The file is meant to be run from `$PSScriptRoot`. Almost every repo-relative path is built with `Join-Path $PSScriptRoot ...`, so in-place execution is safe. The weak spot is `& $venvPy setup.py` with no script-relative path, which only works because of the earlier `Set-Location`.
- The uvicorn target is `app:app`. The launcher assumes `app.py` at the repository root exports `app`. If that file is moved or renamed, server startup fails with a vague `Error loading ASGI app` instead of a clear path error.

## Paths that are hardcoded to this user/host
- Python discovery is machine-specific. On another user profile or machine, the script fails fast with `Fail "Couldn't find Python 3.11+..."`. This is intentional here, but it means the script is not portable across accounts without editing.
- `$ODSSEYUS_DATA_DIR` default is `$PSScriptRoot\data`, and ChromaDB/Ollama data paths descend from there. That keeps state inside the checkout, but it also means a failed first-run leaves service-specific subdirectories behind that later reruns interpret as prior installs.

## Where pathing issues can mask real errors
- `Get-OdysseusProcesses` uses repo-root substring fallback. That can over-match anything running from the checkout — not just the launcher/uvicorn. In practice this may kill unrelated processes, and worse, reports them as “Odysseus-related processes” on shutdown, which hides which process actually held a handle on `data/logs/*.log`.
- `$installLog` is shared between the `pip upgrade` and `pip install -r requirements.txt` steps. When the second step fails, the script prints the last 30 lines of the same file. If the first step's tail is what gets shown, it misattributes the failure to `requirements.txt` when the actual break is in `pip upgrade`.

## venv/Hermes separation guard is config-based only
- The recreation guard checks `venv\pyvenv.cfg` for the parent interpreter home. That catches the common Hermes contamination case, but it does not detect a contaminated `site-packages` mixed in during a partial install, or a Hermes-style `sitecustomize.py` copied in from elsewhere. The script writes its own `sitecustomize.py`, which overwrites whatever was there.

## PATH sanitization side effects on external dependencies
- The script strips `Programs\Python`, `WindowsApps`, and `Git\usr\bin` / `Git\bin` from PATH, then later re-adds Git if found. Any other tooling required by requirements — e.g., compilers, libs, or `ffmpeg` on system PATH — is not evaluated, so a first-time install on a machine that depends on one of those bins will fail with a toolchain error that looks unrelated to launch-windows.ps1.

## Summary
The script is careful about isolating its own Python/flags from Hermes Agent, but relative-path assumptions (`setup.py`, `app:app`), per-user hardcoded candidates, over-broad process matching, and a shared install log can all turn a real codebase interaction problem into a confusing launcher-side failure.
