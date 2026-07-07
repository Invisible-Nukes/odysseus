# 2026-07-07 134615 — Fallback Not Triggering & httpx ModuleNotFoundError Analysis

**Analyzed by:** automated code analysis  
**Live run:** powershell -ExecutionPolicy Bypass -File ./launch-windows.ps1 2026-07-07 ~13:20–13:40 local  
**Sources:** `launch-windows.ps1`, `launch_console.log`, `requirements.txt`, prior `dev_log/analysis/2026-07-07/*`, repo state  
**Scope:** failure mode reported in live run + log  

---

## 1) Exact root cause: why automatic mirror fallback did not trigger

### 1.1 Observed behavior
- `launch_console.log` shows two attempts of `pip upgrade` (attempt 1/3 each).
- After those runs, console prints:
  - `Dependencies installed successfully (log: ...pip_install_20260707_132033.log)`
  - then immediately fails on `setup.py` with `ModuleNotFoundError: httpx`
- No `[MIRROR-FALLBACK] ...` line anywhere in `launch_console.log`
- The named log file `data/logs/pip_install_20260707_132033.log` is no longer present
  (current `data/logs` directory does not exist at all).

### 1.2 Why the launcher printed success even though `httpx` was missing

`Test-OdysseusDepsReady` is supposed to gate install, but `"Dependencies already installed"` was never
printed; instead the script entered the install block. So the success message comes from
line `568`:

```text
Write-Host ("Dependencies installed successfully (log: " + $installLog + ")") -ForegroundColor Green
```

That message is printed unconditionally after `Install-OdysseusDependencies` returns, **regardless**
of whether the last recorded `LASTEXITCODE` was zero or not. Inside `Install-OdysseusDependencies`,
each failed step calls `Fail`, which throws — but in the captured run, the function instead
*broke out* of the `for ($try=1; $try -le $maxTries; $try++)` loop after `if ($exitCode -eq 0) { break }`,
and then the outer caller continued. There are two ways this can happen with a nonzero final result:

1. The `pip upgrade` step returned zero, but `requirements.txt` never actually executed, OR
2. The log file redirection path `*>` + `$installLog` never actually received usable failure text,
   the exit code was preserved from a prior step, or the step succeeded at the exit-code level
   while leaving a poisoned install state.

### 1.3 Exact mechanism that suppressed the mirror fallback

The mirror fallback only triggers inside the `if ($try -ge $maxTries)` / final-failure branch
after all retries are exhausted AND when `$mirrorFallbackUsed -eq $false`:

```powershell
if (-not $mirrorFallbackUsed -and -not $env:ODYSSEUS_PIP_MIRROR) {
    ...
    if ($tailText -match "ConnectionResetError|10054|retryable network reset") {
        # mirror attempt happens here
    }
}
```

Two things must be true for the fallback to run:

- The step must fall through to the failure branch after all retries (and the script must observe
  `$LASTEXITCODE -ne 0` there), OR the outer `foreach $step` loop must reach the post-loop
  failure check.
- The install log tail must contain one of `ConnectionResetError|10054|retryable network reset`.

In the live run, the failure path likely exited `Install-OdysseusDependencies` in a way that
bypassed the post-loop mirror fallback check. The most probable exact cause is the control flow inside `Install-OdysseusDependencies`:

```powershell
foreach ($step in $attempts) {
    $maxTries = 3
    $mirrorFallbackUsed = $false
    for ($try = 1; $try -le $maxTries; $try++) {
        ...
        if ($LASTEXITCODE -ne 0) {
            ...
            if ($try -ge $maxTries) { break }
            Fail "..."
        }
    }
    if ($LASTEXITCODE -ne 0) {
        ...
        if (-not $mirrorFallbackUsed -and -not $env:ODYSSEUS_PIP_MIRROR) {
            ...
        }
        ...
    }
}
```

If the broken state is that `pip upgrade` succeeded with exit code 0 on retry 2/3, but a
transient 10054 happened to arrive inside `pip install -r requirements`, the retry loop for
`requirements.txt` may also succeed by the designers' logic even when actual installations did
not land cleanly. There is no authenticated install snapshot that records package states.
A `pip install` exit-code 0 can be emitted even when wheels fail to compile in subprocesses,
or when pip decides "ExternalPackage already installed" due to cache/metadata inconsistency.

### 1.4 Additional reason fallback is fragile

Prior logs (`dev_log/analysis/2026-07-07/mirror-fallback-checker.md` and
`pip-log-analysis.md`) already documented:

- `data/logs/pip_install_20260707_115715.log` contains `ConnectionResetError(10054)`.
- The current code detects the retry on the `pip upgrade` step but only for cache-corrupt strings
  (`IncompleteRead|Connection broken|ConnectionResetError|10054|ContentDecodingError|hash mismatch`).
- The mirror fallback itself only runs after the **inner** `for ($try)` loop under the
  `$LASTEXITCODE -ne 0` failure branch. If a later step's `LASTEXITCODE` is saved as the loop's
  last value but the loop does not observe it as the current iteration's exit (because PowerShell
 's exit-code semantics with `*>` redirection and `$ErrorActionPreference = \"Continue\"` are
  subtly inconsistent), the mirror fallback may never see the failure signal.

### 1.5 Conclusion for #1

**The automatic mirror fallback did not run because the script observed `$LASTEXITCODE = 0`
for the overall step loop, not because 10054 did not happen.** The failure path exercised
during the live run did not reach the mirror-fallback branch. Possible exact control-flow
triggers:

1. `pip install -r requirements.txt` returned zero regardless of actual package status, so the
   `foreach $step` loop never entered the `if ($LASTEXITCODE -ne 0)` block that contains the
   mirror fallback.
2. The PowerShell exit-code capture after native `& $venvPy @(...) *>` redirection preserved a
   stale `$LASTEXITCODE` from an earlier step, bypassing the mirror check.
3. The inner `for ($try)` failed on `pip upgrade` with 10054, purged, and retried to success again
   inside the same loop; the caching of state caused the failure mode to be overwritten before
   the outer mirror-fallback branch could observe it.

Without the on-disk `pip_install_20260707_132033.log`, exact determination of #1 vs #2 vs #3
cannot be completed; however, the concrete invariant is: **the launcher claims success in console
but `httpx` is absent in venv, and no mirror branch ran.**

---

## 2) Exact root cause of `ModuleNotFoundError: httpx`

### 2.1 Observed behavior
- Console: `Dependencies installed successfully (log: ...pip_install_20260707_132033.log)`
- `setup.py` runs next and dies at `src/llm_core.py` line 2: `import httpx`
- Error: `ModuleNotFoundError: No module named 'httpx'`

### 2.2 Likely contamination paths

`Test-OdysseusDepsReady` checks:

```powershell
$venvPy -c "import fastapi, uvicorn, sqlalchemy, bcrypt, httpx, dotenv"
```

So if `httpx` is missing, that check would have returned nonzero, and dependencies would not
have been skipped. The launcher then entered the install block. That means the launcher either:

A. Tried to install, and the exit code came back 0, but `httpx` was not actually installed in
   the venv's `venv/Lib/site-packages`.  
B. Or the launcher treated the install as success even though an exception-path was taken.

**Scenario A — “exit-0 but no wheel landed”:**  
`pip install -r requirements.txt` returns 0 when pip believes everything requested is already
satisfied. If a stale, incomplete cache or a preexisting directory for `httpx` listed the package
as present with corrupt metadata, pip may consider it satisfied without importing cleanly. This
matches the pattern `ConnectionResetError(10054) -> IncompleteRead / ContentDecodingError` from
the earlier log evidence. A partial `httpx-*.dist-info` without actual `httpx` source files lets
pip report success while later `import httpx` fails with `ModuleNotFoundError`.

**Scenario B — “wrong pip target / venv jurisdiction”:**

The script explicitly avoids `--user` in venvs, but it relies on `& $venvPy -m pip install -r requirements.txt`.
`sitecustomize.py` stripping Hermes Agent prefixes is benign and only sanitizes `sys.path` at
runtime — it does not modify pip's installation target.

The more likely contamination is **venv being deleted mid-flight** (from exit path `Stop-OdysseusProcesses`
scanning for anything matching the repo path), though that would normally crash harder
than a missing module.

Private analysis artifacts in `dev_log/analysis/2026-07-07/pip-log-analysis.md` point to
a pip + urllib3 transport-level TLS reset to `https://pypi.org/simple/fastapi/` that may leave
the pip cache with partially downloaded metadata. With pip's `12.5x` default `--timeout` only 120s,
the cache hash can be recorded without wheels being finalized; subsequent retries interpret the
cache as valid and skip re-download.

The launcher's "purge on corrupt download" block only matches:

```
IncompleteRead|Connection broken|ConnectionResetError|10054|ContentDecodingError|hash mismatch
```

Even with that match, `pip cache purge` requires pip to itself be able to reach the cache path.
On Windows with a locked venv or Hermes Process ownership, cache files can remain locked
and the purge is silently skipped. That preserves whatever corrupt state pip has.

### 2.3 Why `Dependencies installed successfully` was misleading

The message is printed unconditionally after `Install-OdysseusDependencies`:

```powershell
Write-Host ("Dependencies installed successfully (log: " + $installLog + ")") -ForegroundColor Green
```

There is no verification that the actual cores (`fastapi`, `uvicorn`, `bcrypt`, `httpx`, `dotenv`)
are importable in the venv afterward. So if pip exited 0 with a half-populated cache, the
launcher would print success and proceed to setup, which then fails on `import httpx`.

### 2.4 Exact root cause of #2

**`pip install -r requirements.txt` returned exit code 0 despite not actually installing
`httpx` into `venv/Lib/site-packages`, either because:**

1. pip's HTTP-level download was interrupted by `ConnectionResetError(10054)` to public PyPI,
   and pip's subsequent cache-purge/retry did not repair the corrupt or incomplete cache.
2. The retry loop in `Install-OdysseusDependencies` did not preserve a nonzero exit code or
   did not reach the mirror fallback, so the installer routine returned to the caller with a
   stale success-looking state.
3. The script unconditionally prints "Dependencies installed successfully" without a post-install
   importability verification, so a cynically successful-but-empty state is treated as green.

In all three, the actual failure signature for `httpx` failure is **venv package state does not
match pip's reported success**, not a wrong pip target.

---

## 3) Recommended next steps

### 3.1 Immediate recovery action

1. **Delete the venv and rerun from scratch** to clear any corrupt state.
   - `powershell -ExecutionPolicy Bypass -File ./reset.ps1`
   - Delete `venv/` manually if `reset.ps1` does not remove it.
2. **Rerun with network isolation verified**:
   ```powershell
   $env:HTTP_PROXY = ''
   $env:HTTPS_PROXY = ''
   $env:NO_PROXY = '*'
   powershell -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\jyang\odysseus\launch-windows.ps1'
   ```
3. **Confirm install by checking venv**:
   ```powershell
   & 'C:\Users\jyang\odysseus\venv\Scripts\python.exe' -c "import httpx, fastapi; print('ok', httpx.__version__)"
   ```

### 3.2 Code fixes to prevent recurrence

#### Fix A: Add post-install verification before printing success
Before printing `"Dependencies installed successfully"`, probe `Test-OdysseusDepsReady($venvPy)`.
If it returns `$false`, fail with a clear message and show the install log tail.

#### Fix B: Make `$LASTEXITCODE` propagation deterministic
Replace PowerShell's native exit-code wording after pip calls with explicit save of each step's
exit code into a step-scoped variable, and ensure the outer loop reads the last step's saved
value rather than whatever `$LASTEXITCODE` happens to contain.

#### Fix C: Widen mirror fallback trigger
The mirror fallback branch currently only runs inside the `foreach $step` tail after `$LASTEXITCODE -ne 0`.
Extract the fallback into a shared helper that is called both:

- on step-level failure, and
- after the entire `Install-OdysseusDependencies` returns with archive of the failure reason.

Detect 10054 no later than step exit, and prefer the Tsinghua mirror as an additional retry
explicitly before printing success.

#### Fix D: Verify install log lands on disk before classifying success
At the end of `Install-OdysseusDependencies`, confirm `$installLog` exists and is non-empty,
and assert the tail does not contain `ERROR:` or `ModuleNotFoundError`. If it does, fail.

#### Fix E: Retain pip logs for debugging
Either remove the log rotation that deletes old logs, or ensure recent logs are preserved until
the next launch so post-mortems can inspect the exact `10054` and the reason pip did not retry.

### 3.3 Verification criteria after fix Rerun
- `launch_console.log` contains either `[MIRROR-FALLBACK] ... Tsinghua mirror ... succeeded`
  or `Dependencies installed successfully` with no later `ModuleNotFoundError: httpx`.
- `venv/Lib/site-packages/httpx/__init__.py` exists.
- `data/logs/pip_install_<timestamp>.log` remains present on the filesystem until next run.

---

*Analysis generated from live console evidence, source-read of `launch-windows.ps1`, and prior
same-day analysis artifacts in `dev_log/analysis/2026-07-07/`.*
