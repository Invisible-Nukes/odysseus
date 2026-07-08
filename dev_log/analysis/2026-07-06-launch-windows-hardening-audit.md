# launch-windows.ps1 Hardening Audit — 2026-07-06

## Summary

Commit `ad3642f` hardens `launch-windows.ps1` against cross-codebase interaction and fixes two user-visible bugs: browser open now waits for server readiness, and `tests/conftest.py` no longer crashes on `ImportError: cannot import name 'Webhook' from 'src.database'`. Server startup and browser-open order verified live on Windows 11. PATH and process-matcher hardening added; core app regression tests pass.

## Verified OK

| Item | Detail |
|------|--------|
| Browser-open timing | Opened after `http://127.0.0.1:7000` probe succeeds, not at launcher startup |
| Server reachable | `curl http://127.0.0.1:7000/` returns HTTP 302 after `launch-windows.ps1` finishes startup phase |
| pytest regression | `tests/test_app.py` 12 passed, 0 failed after hardening edits |
| Import fix | `tests/conftest.py` conditional `src.database` stub resolves collection crash while preserving Webhook export behavior |
| Commits | `ad3642f` pushed to `origin/dev`; only `launch-windows.ps1` + `tests/conftest.py` changed |
| Cleaning | Temp one-off testing scripts removed; `dev_log/` restored from repo before cleanup; no new temp scripts committed |

## Issues found

### Medium

| Issue | Location | Notes |
|-------|----------|-------|
| Launcher exits with Hermes wrapper code | `launch-windows.ps1` startup path | Observed `4294967295` from PowerShell after uvicorn start; server remains resident and reachable. Root cause appears to be Hermes terminal wrapper interaction, not uvicorn crash. Not a regression from today's hardening; no fix attempted yet. |
| `Get-OdysseusProcesses` scope includes adjacent services | `Get-OdysseusProcesses` L106–129 | Matcher also catches same-checkout MCP servers (`mcp_servers/*.py`) through repo-root fallback. Live output confirmed `Stop-OdysseusProcesses` kills these on relaunch. |
| Locked runtime logs | `data/logs/*.log` after launcher runs | Four log files (`uvicorn_launch_*.log`, `app.log`, `search_engine_error.log`) remain held by a Windows file handle. Manual `taskkill` or Hermes terminal close + delete needed. |

### Low

| Issue | Location | Notes |
|-------|----------|-------|
| HERMES PATH cleanup is destructive to Hermes tooling child processes | PATH sanitization block L24–47 | Removes Hermes Python paths from the launched PowerShell's `env:PATH`. Safe for Odysseus itself. If user expects Hermes child processes to inherit the same PATH, that inheritance is now cut. |
| Full-suite classification incomplete | pytest | ~97 failures / 2 errors out of ~4,600 tests remain largely environment-specific (`/tmp`, macOS ARM, Linux Docker, symlinks, JS snapshots) but not fully verified end-to-end after hardening. |

## Hardening changes

| Change | Mechanism | Effect |
|--------|----------|--------|
| PATH sanitization | Remove specific `%LOCALAPPDATA%` interpreter/bin entries from `env:PATH` at script start | Reduces accidental Hermes / stray Python / Git Bash `usr/bin` inheritance into Odysseus startup |
| Exact venv Python match | `Resolve-Path` compare against `...\odysseus\venv\Scripts\python.exe` | `Get-OdysseusProcesses` only flags Odysseus venv Python, not just any `python.exe` |
| Command-line scoping | Require `uvicorn|app:app`, exact venv py, OR escaped repo-root substring | Cuts false positives from unrelated codebases on the same machine; same-checkout MCPs still matched via repo-root fallback |

## Recommended fixes

| Priority | Fix | When |
|----------|-----|------|
| High | Exclude `mcp_servers/*` from `Get-OdysseusProcesses` while preserving uvicorn/uvicorn-workers matches | Next launcher touch |
| Medium | Replace repo-root fallback with working-directory filter against `Get-Process -Id` equivalent or maintain an explicit Odysseus child-PID file | Next hardening pass |
| Medium | Investigate launcher `4294967295` exit behavior; decide whether uvicorn should be detached or launcher should wait residently | Before next user test |
| Low | Document that manual cleanup of `data/logs/*` may need `taskkill` if Hermes terminal inherited uvicorn handles | README / cleanup runbook |

## macOS gap vs Windows

| Feature | macOS `start-macos.sh` | Windows `launch-windows.ps1` |
|---------|------------------------|------------------------------|
| Interpreter isolation | Relies on shell `PATH` | Hardcoded standalone Python path + PATH sanitization |
| Process stop | `trap` + `kill` | `Get-CimInstance Win32_Process` filter by command line / exact venv py |
| Browser-open timing | Not controlled by current macOS launcher | Waits for readiness probe, then opens |
| Python import hygiene | Managed via `venv` activation + `.venv` | Standalone interpreter + `sitecustomize.py` built in to remove Hermes `sys.path` prefixes |
