---
date: 2026-07-07
time: 08:49:38
subagent_task: Code Correctness Analysis
delegation_id: deleg_8cfdb13a
status: completed
summary: Reviewed launch-windows.ps1 and reset.ps1 for PowerShell correctness
---

# Code Correctness Analysis

## Critical / Crash-on-Windows Risk

- **`*>` redirection contradicts `#Requires -Version 5.1` (line 199).**  `*>` requires PowerShell 6+ and is not supported in Windows PowerShell 5.1. Fixed in later passes.
- **Unhandled native `pip install` stderr under `$ErrorActionPreference = "Stop"` (line 270).**  `& $venvPy -m pip install -q chromadb-client` is invoked without saving/restoring `$ErrorActionPreference`. Fixed in later passes.

## Error-Action & Exit Paths

- **`Fail()` uses `throw`; no explicit `exit` anywhere.**  The launcher relies on `throw` from `Fail()` for abort paths. In PowerShell, `throw` inside a script run with `-File` typically yields process exit code `1`, not the originating native command's exit code. The observed `4294967295` after uvicorn startup is therefore not produced by any explicit exit path in this script; it is most likely the Hermes terminal layer interpreting the child process tree termination, not the script itself.
- **`$ErrorActionPreference = "SilentlyContinue"` in `reset.ps1` (line 9).**  This blanket suppresses all PowerShell terminator errors. `Remove-Item` against locked files (e.g., `data/logs/*`) held by a resident uvicorn will silently fail, leaving stale runtime artifacts. Fixed in later passes.
- **`try { cmd /c start ... } catch {}` and `try { & taskkill ... } catch {}`.**  `cmd /c start` always returns exit code `0`. `taskkill.exe` returns non-zero on failure, but `try/catch` in PowerShell 5.1 only catches PowerShell-terminating errors, not native non-zero exit codes. The empty `catch` blocks are effectively dead code for the intended native-error handling; the desired "swallow failure" behavior happens because stderr is redirected (`2>$null`) and `$LASTEXITCODE` is never checked.

## Stream Redirection & Quoting

- **`psi.Arguments = "-m uvicorn ..."` uses a single interpolated string.**  `Start-Process` with a single `-ArgumentList` string performs shell-like splitting, which breaks if `$BindHost` or `$Port` ever contains spaces or quote characters. Given that `$BindHost` and `$Port` are currently constrained to safe values (`127.0.0.1` / `int`), this is not an immediate crash, but it is inconsistent with the array-based `-ArgumentList` used correctly elsewhere.
- **`Open-OdysseusBrowser` uses `cmd /c start "" $url`.**  The empty `""` is the required window-title placeholder for `cmd /c start`. The unquoted `$url` is safe today because the input is constrained, but if the startup URL were ever changed to a path or search string with spaces, the call would split across multiple arguments.

## Hidden-Process vs Foreground Tradeoffs

- **ChromaDB: `-WindowStyle Hidden`.**
  Appropriate; ChromaDB is a long-running background service. Logs are redirected to `$chromaLog` + `.err`. The only risk is that the camouflaged process can persist across script crashes until `Stop-OdysseusProcesses` is run again.
- **Uvicorn foreground pump.**  Using `System.Diagnostics.Process` with `CreateNoWindow = $false` keeps the PowerShell window resident and the user sees live output. The synchronous `ReadLine` pump inside `WaitForExit(500)` is functional but can stall if uvicorn writes faster than the loop drains, eventually blocking the pipe buffer. No crash today under normal startup traffic; this is a throughput risk, not an immediate failure.

## Reset Behavior

- **`Stop-OdysseusProcesses` in `reset.ps1` matches `uvicorn|app:app|odysseus` case-insensitively but does not exclude other checkout MCP servers.**  Outside the scope of the immediate correctness review, but noted because an over-broad match could stop unrelated processes.
