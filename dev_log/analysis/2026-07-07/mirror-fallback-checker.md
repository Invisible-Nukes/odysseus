# Mirror Fallback Patch — Checker Review
**Analyzed by:** subagent  
**Date:** 2026-07-07  
**Scope:** `launch-windows.ps1` automatic pip mirror fallback + current pip install log evidence  
**Findings:**

## 1) Gating: mirror fallback triggers only on 10054-style failures
**Result:** PASS  
**Evidence:**
- `launch-windows.ps1:241` — retry block only executes when `$tailText -match "ConnectionResetError|10054|retryable network reset"`.  
- General pip-network failures without this signature do NOT enter the mirror block.

## 2) User-set `ODYSSEUS_PIP_MIRROR` is never overridden
**Result:** PASS  
**Evidence:**
- `launch-windows.ps1:235` — mirror block guard is `if (-not $mirrorFallbackUsed -and -not $env:ODYSSEUS_PIP_MIRROR)`.  
- `launch-windows.ps1:511-514` — if user set `ODYSSEUS_PIP_MIRROR`, it’s applied as `PIP_INDEX_URL` up front and the Tsinghua hardcoded fallback is skipped entirely.

## 3) Fix C restore logic remains intact around new fallback
**Result:** PASS  
**Evidence:**
- Save: `launch-windows.ps1:498-503` (`$script:prevUserPipEnv = @{...}`).
- Mirror switch: `launch-windows.ps1:242-244`.
- Always restore to prior user value after mirror attempt: `launch-windows.ps1:264` (`$env:PIP_INDEX_URL = $script:prevUserPipEnv.PIP_INDEX_URL`).
- Outer `try/finally` still resets `PIP_INDEX_URL`/`PIP_EXTRA_INDEX_URL` and calls `Reset-PipTlsEnv` regardless of success/failure.

## 4) PowerShell 5.1 compatibility preserved
**Result:** PASS  
**Evidence:**
- File still starts with `#Requires -Version 5.1`.
- New fallback uses only 5.1-safe constructs: `$script:` scope, `$false`, `try/catch/finally`, `-match`, `@(...)` splat arrays, `Get-Content -Tail`, `join-pattern` style arrays.

## 5) Failure path still aborts cleanly if mirror also fails
**Result:** PASS with minor behavioral note
**Evidence:**
- Mirror retry runs with `ErrorActionPreference = Continue`.  
- If mirror attempt exit code ≠ 0, tail is printed, then post-retry check at `launch-windows.ps1:268` catches `$LASTEXITCODE -ne 0` and calls `Fail ...`, aborting cleanly.
- Minor note: only `PIP_INDEX_URL` is cleared/restored for the mirror attempt; `PIP_EXTRA_INDEX_URL` is left as null for the mirror try. Not a failure-path bug.

## 6) Current pip log confirms public-PyPI 10054 signature is still occurring
**Result:** PASS  
**Evidence:**
- `data/logs/pip_install_20260707_115715.log` contains `ConnectionResetError(10054, 'An existing connection was forcibly closed by the remote host', None, 10054, None)` against `/simple/fastapi/` and other public PyPI package endpoints.
- Multiple urllib3 retry warnings show this happened repeatedly, confirming the fallback is still actively needed.

## Conclusion
All five design checks pass; the fallback is correctly gated, does not override user mirrors, preserves Fix C env restoration, uses PS 5.1-only syntax, and still aborts on mirror failure. Current logs confirm the original 10054 behavior remains active, so the mirror fallback adds real resilience.
