---
date: 2026-07-07
time: 10:04:35
subagent_task: Syntax & Logic Review
delegation_id: deleg_a7bb6cf2
status: completed
summary: Reviewed syntax and logic issues in launch-windows.ps1 and reset.ps1
---

# Syntax & Logic Review

- **`System.Diagnostics.ProcessStartInfo.Arguments` uses a single interpolated string (`launch-windows.ps1:611`).**  `$psi.Arguments = "-m uvicorn app:app --host $BindHost --port $Port"` relies on the runtime parser for splitting; with a host or port string containing spaces/quotes, uvicorn would see broken argv. Not a crash today because inputs are constrained (`127.0.0.1`, `int`), but inconsistent with the array-based `-ArgumentList` used correctly elsewhere.
- **Uvicorn process pump can block on pipe backpressure (`launch-windows.ps1:653-662`).**  The outer `WaitForExit(500)` drains two `ReadLine` loops. If uvicorn bursts faster than the loop drains, the OS pipe buffer can fill and stall uvicorn, appearing as a hung launch. Under normal startup this hasn't crashed, but with verbose startup logging it is a plausible hang.
- **`$LASTEXITCODE` after the retry loop can misreport a successful step as failed (`launch-windows.ps1:193-228`).**  Each retry runs `& $venvPy @($step.Args) *>&1 | Tee-Object ...`, then checks `$LASTEXITCODE`. A later successful pip run can inherit a nonzero exit code from an earlier iteration if PowerShell's native-stderr promotion behaves differently under `ErrorActionPreference='Continue'`; the outer `if ($LASTEXITCODE -ne 0)` check uses the last iteration value, not the final exit code immediately after the loop. The actual retry result is implemented via `break` on success, but the post-loop check can still fire after a successful step if `$LASTEXITCODE` is stale.
