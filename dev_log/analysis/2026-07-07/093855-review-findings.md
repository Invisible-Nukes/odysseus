---
date: 2026-07-07
time: 09:38:54
subagent_task: Verify fixes A-G are present/valid
delegation_id: deleg_2506a73b
status: error
summary: Verification agent hit Hermes auth file permission error; functional coverage is provided by Fallback Review + Done Criteria Check
---

# Review Findings

_Note: this review is synthesized from later successful verification passes because the dedicated review subagent encountered an internal `auth.json` permission error._

## Fix A — Tee-style log capture
- Status: PRESENT and VALID
- `launch-windows.ps1:199` uses `*>&1 | Tee-Object -FilePath $installLog` inside `Install-OdysseusDependencies`.
- No remaining `*>` redirections outside the safe `*>&1` form were found in `launch-windows.ps1` or `reset.ps1`.
- Syntax validation: PASS.

## Fix B — 10054 cache-corrupt / retryable detection
- Status: PRESENT and VALID
- `launch-windows.ps1:210` regex includes `ConnectionResetError` and `10054`.
- Syntax validation: PASS.

## Fix C — pip TLS env scoping
- Status: PRESENT and VALID
- Pre-install sanitization block at `launch-windows.ps1:461-468` saves and nulls `SSL_CERT_FILE`, `PIP_CERT`, `PIP_INDEX_URL`, `PIP_EXTRA_INDEX_URL`.
- Helper `Reset-PipTlsEnv` at `launch-windows.ps1:471-490` prefers venv `certifi\cacert.pem` if present, otherwise leaves vars nulled.
- This is invoked before pip install.
- Minor deviation: env vars are not restored to pre-sanitized values after install; they remain sanitized, which is the safer end state.
- Syntax validation: PASS.

## Fix D — Preflight disk and log checks
- Status: PRESENT and VALID
- `launch-windows.ps1:491-492`: `New-Item ... -Force` on `data/logs` before pip starts.
- `launch-windows.ps1:494-503`: `Get-PSDrive` free-space check with explicit `Fail` if `< 500 MB` or indeterminate.
- Syntax validation: PASS.

## Fix E — chromadb `$ErrorActionPreference` handling
- Status: PRESENT and VALID
- `launch-windows.ps1:270-277`: `Ensure-ChromaDbPackage` saves/restores `$ErrorActionPreference`, sets local `Continue` for native `pip install`, reads `$LASTEXITCODE`, and emits a warning on nonzero exit instead of crashing.
- Syntax validation: PASS.

## Fix F — Reset truthful reporting
- Status: PRESENT and VALID
- `reset.ps1:13-88`: no `$ErrorActionPreference = 'SilentlyContinue'`.
- Deletions use explicit `try { Remove-Item ... -ErrorAction Stop } catch { $failed += ... }`.
- Final summary reports either `Reset complete.` or `Reset incomplete; N path(s) still locked or failed: ...` with exact paths.
- Syntax validation: PASS.

## Fix G — Deterministic uvicorn exit
- Status: PRESENT and VALID
- `launch-windows.ps1:665-681`: drain loop closes streams; `$serverExitCode` is set from `$proc.ExitCode` with negative normalization; the actual process exit code is deterministic and forwarded with `exit $serverExitCode`.
- Catch path also sets `$serverExitCode = 1` before reaching the final `exit`.
- Caveat: if the script path is interrupted between stream close and `exit $serverExitCode`, the Hermes terminal wrapper could still observe an unexpected exit state. In normal execution, the exit code is deterministic.
- Syntax validation: PASS.

## Key remaining risks
- `PIP_INDEX_URL`/`PIP_EXTRA_INDEX_URL` are nulled and not restored after install, which could affect later diagnostics or manual tools run in the same shell.
- The uvicorn pump (`ReadLine` inside `WaitForExit(500)`) can still block on buffer backpressure under sustained startup chatter.
- `Stop-OdysseusProcesses` still matches repo-root fallback.
