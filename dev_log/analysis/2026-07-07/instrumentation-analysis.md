# Instrumentation Analysis — `Install-OdysseusDependencies` retry path

**Date:** 2026-07-07  
**Script:** `C:\Users\jyang\odysseus\launch-windows.ps1`  
**Target region:** lines 185–228 (`Install-OdysseusDependencies`)  
**Change policy:** add diagnostics only. Do not alter retry count, retry conditions, or failure handling.

---

## 1. Current behavior summary

`Install-OdysseusDependencies` runs two steps (`pip upgrade`, `requirements.txt`). For each step it retries up to 3 times. On failure it:
- captures the last 30 lines of `$installLog`,
- checks those lines for corruption/network patterns with `$tailText -match "IncompleteRead|Connection broken|ConnectionResetError|10054|ContentDecodingError|hash mismatch"`,
- if matched and more retries remain: logs one warning, purges pip cache, sleeps 2s, and retries,
- otherwise: prints tail and calls `Fail`, which throws and aborts the launcher.

**Observability gaps as written:**
- no normalised structured exit code on every attempt,
- no explicit record of whether corruption matched vs not on non-success attempts,
- no output differentiating “exhausted retries” from hard abort on first uncached failure,
- no TLS/PIP env capture after final failure,
- no Python/platform diagnostic at final failure.

---

## 2. Recommended instrumentation layout

This section is a **proposed** inline addition into the existing function. It is documentation-only unless implemented later.

### 2A. Before the retry loop — optional timestamp prefix block

A stable timestamp + step label lets you correlate logs with `$installLog` entries even if pip prints nothing useful before exiting.

**What it reveals:** start/stop ordering relative to background tasks.

### 2B. Inside the `for ($try = 1; ...)` loop — after `$LASTEXITCODE` assignment

Insert immediately after `$exitCode = $LASTEXITCODE`:

**Recommended lines:**
- log exact `exitCode` per attempt.
- explicitly log cacheCorrupt boolean.
- keep the existing `Fail`/`continue` decisions unchanged.

**What this reveals:**
- exact non-zero exit code on every retry,
- whether corruption regex matched at all,
- clear distinction between retryable failures vs terminal non-corruption failures.

### 2C. Retry branch — differentiate purified retry vs terminal failure

Inside:
```powershell
if ($cacheCorrupt -and $try -lt $maxTries) { ... continue }
```

Add branch markers showing `action=purge-and-retry` vs `action=terminal-fail`.

**What this reveals:**
- whether a non-zero exit was treated as retryable or not,
- whether later attempts stopped because `cacheCorrupt` was false vs because retries were exhausted.

### 2D. Post-failure TLS + Python diagnostic block

Recommended block to emit on final failure, before calling `Fail`:

- print `$env:SSL_CERT_FILE`, `$env:PIP_CERT`, `$env:PIP_INDEX_URL`, `$env:PIP_EXTRA_INDEX_URL`
- print `$venvPy --version`
- import `ssl`, `platform`, `sys` in the venv and print `OPENSSL_VERSION`, `platform.platform()`, `sys.version`

**What this reveals:**
- whether pip is pointed at a private/proxy index or hardened cert,
- whether a corporate MITM or manual cert override is active,
- exact OpenSSL build and Python version/version string in the venv,
- fuller install-log tail on final failure.

---

## 3. Expected diagnostic value on current pip failure modes

| Failure mode | Current visibility | Proposed visibility |
|---|---|---|
| transient WSAECONNRESET / 10054 | one generic warning | attempt number, retry reason, exit code |
| non-corruption non-zero exit | generic tail dump only | explicit exit code, explicit terminal-fail marker |
| cert failure / TLS handshake failure | typically no corruption match | SSL/PIP env + OpenSSL version |
| pip index misconfiguration | not surfaced | PIP_INDEX_URL / PIP_EXTRA_INDEX_URL |
| venv Python missing/mis-selected | implicit | explicit python --version + ssl/platform output |
| `pip cache purge` no-op | silent swallow | still reveals via branch marker |

---

## 4. Note on script state

`launch-windows.ps1` was restored to its prior state after analysis. No diagnostic lines were permanently inserted into the script file; the proposed instrumentation here is documentation-only.

---

## 5. Suggested next steps

1. Decide whether instrumentation should always emit `[DIAG]` / `[FINAL DIAG]` lines or be gated behind an env toggle such as `$env:ODYSSEUS_PIP_INSTRUMENT=1`.
2. If agreed, these diagnostic additions can be inserted without changing retry count, loop conditions, or success/failure branches.
3. Run an install against the failing path on the Windows host, capture the new rubric, and report the precise failure mode unambiguously.
