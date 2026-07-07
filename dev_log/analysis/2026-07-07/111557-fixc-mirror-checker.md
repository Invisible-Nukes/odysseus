# Fix C + mirror patch checker report
**Date:** 2026-07-07  
**Script:** launch-windows.ps1  
**Region checked:** Lines 456–487 (`sitecustomize.py` write + `PIP_INDEX_URL` save / mirror override / restore block)

## 1) Sanitization happens before install
**Pass.**  
Lines 456–460 write `sitecustomize.py` unconditionally, *before* the `Test-OdysseusDepsReady` check at line 469 and the `Install-OdysseusDependencies` call at line 480. The site-path sanitizer is therefore in place by the time pip runs.

## 2) ODYSSEUS_PIP_MIRROR still takes effect
**Pass.**  
Lines 474–478 capture `$userPipIndexUrl = $env:PIP_INDEX_URL`, then if `$env:ODYSSEUS_PIP_MIRROR` is set, they set `$env:PIP_INDEX_URL = $env:ODYSSEUS_PIP_MIRROR`. The mirror is active for the entire `Install-OdysseusDependencies` call because it is only reset in the `finally` block.

## 3) PIP_INDEX_URL and PIP_EXTRA_INDEX_URL are restored
**Mixed.**  
- `PIP_INDEX_URL` **is restored correctly**: the `try/finally` at lines 479–485 writes back `$userPipIndexUrl` if a mirror was applied.
- `PIP_EXTRA_INDEX_URL` **is NOT saved or restored** by this region. The `FINAL DIAG` blocks (lines 191, 209) still reference it, but nothing in the patched block captures/restores it. So if the caller set both `PIP_INDEX_URL` and `PIP_EXTRA_INDEX_URL`, only `PIP_INDEX_URL` is round-tripped.

**Recommended follow-up:** wrap `PIP_EXTRA_INDEX_URL` in the same save/restore pattern if callers depend on it.

## 4) PS 5.1 compatibility
**Pass.**  
- No `*>` usage in the *patched* region; the `*>` at line 163 is the standard PowerShell 5.1 "redirect all streams" syntax, which is valid.  
- No `-replace` regex that is PS 5.1-only, no splatting issues beyond PS 5.1 support, no `using module` / module-version requirements.  
- `try/catch`/`finally`, `$ErrorActionPreference = "Continue"` save/restore, and array splatting at lines 151, 153, 154, 303, 581 are all PS 5.1 safe.  
- `[version]` cast at line 553–554 is wrapped in `try/catch`, so it does not terminate on malformed folder names.

## 5) Control flow unchanged for the success path
**Pass.**  
- Success path: `Test-OdysseusDepsReady` returns true → script prints "Dependencies already installed ..." and skips `Install-OdysseusDependencies` entirely. No env-var perturbation happens. Downstream steps (setup, ChromaDB, uvicorn) are untouched.
- First-run path: deps missing → script enters install block. The `PIP_INDEX_URL` value is temporarily replaced, `Install-OdysseusDependencies` runs its retry loop exactly as before (purge + retry on cache corruption at lines 179–185, `Fail` on exhaustion at lines 205/222), and `finally` restores the original `PIP_INDEX_URL`. No behavior change beyond the env-var round-trip.

## Verdict
**Overall: Fix C + mirror patch is correct.**
- Ordering is correct: sanitize before install, mirror takes effect, `PIP_INDEX_URL` is restored.
- PS 5.1 compatible.
- Success-path control flow is unchanged.
- One minor gap: `PIP_EXTRA_INDEX_URL` is not captured/restored, but this is a limitation of the patch, not a regression in control flow.
