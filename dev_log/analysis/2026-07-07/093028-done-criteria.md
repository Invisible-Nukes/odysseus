---
date: 2026-07-07
time: 09:30:28
subagent_task: Done Criteria Check
delegation_id: deleg_done-criteria-1
status: completed
summary: Checked all done criteria against current scripts
---

# Done Criteria Check

| # | Criterion | Result | Evidence |
|---|-----------|--------|----------|
| 1 | Launcher loads under PS 5.1; no `*>` parser error | PASS | `launch-windows.ps1` uses `*>&1 | Tee-Object` only. Header still declares `#Requires -Version 5.1`. |
| 2 | `pip install -r requirements.txt` succeeds on clean `venv` without Hermes certifi contamination | PASS | `launch-windows.ps1:461-469` saves and clears `SSL_CERT_FILE`/`PIP_CERT`/`PIP_INDEX_URL`/`PIP_EXTRA_INDEX_URL`; `Reset-PipTlsEnv` only restores them if `certifi/cacert.pem` exists under the venv. |
| 3 | `ConnectionResetError(10054)` triggers cache purge + retry | PASS | `launch-windows.ps1:210` regex matches `ConnectionResetError|10054`; matching path purges cache and continues retry loop before falling through to `Fail`. |
| 4 | `reset.ps1` reports exact deletion results; no blank suppression | PASS | No `$ErrorActionPreference = 'SilentlyContinue'`. Each `Remove-Item` uses `try/catch` with `-ErrorAction Stop` and appends failures to `$failed`; final block prints either `Reset complete.` or `Reset incomplete; N paths...`. |
| 5 | Deterministic launcher exit code; never `4294967295` | PASS | Main uvicorn path computes `$serverExitCode` from `$proc.ExitCode`, normalizes negatives to `1`, and terminates with `exit $serverExitCode`. `4294967295` is not produced by any explicit path. |
| 6 | Chromadb install failure degrades RAG without crashing launcher | PASS | `Ensure-ChromaDbPackage` localizes `$ErrorActionPreference = 'Continue'`, suppresses stderr, and on nonzero `$LASTEXITCODE` prints a warning and returns `$null`. |
| 7 | Rerun reaches uvicorn without rerunning pip when deps are already importable | PASS | `Test-OdysseusDepsReady` checks importable core deps; when true, `Install-OdysseusDependencies` is skipped, so rerun goes straight through setup to uvicorn. |
