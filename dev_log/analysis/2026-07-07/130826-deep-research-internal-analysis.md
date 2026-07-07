---
date: 2026-07-07
time: 13:05:00
subagent_task: Deep research + internal analysis of PyPI 10054 failure and launch-windows problem catalog
delegation_id: deleg_3ff0c130
status: completed
summary: Combined external research on Python pip 10054 to PyPI on Windows and internal analysis of discovered launch-windows.ps1 problems. Recommendations: use mirror-first fallback as production-grade mitigation, with user-selectable ODYSSEUS_PIP_MIRROR override.
---

# Deep Research & Internal Analysis — PyPI 10054 + Launch Path Problems

**Date:** 2026-07-07  
**Repo:** `C:\Users\jyang\odysseus`  
**Sources:** subagent research over Stack Overflow, GitHub issues, pip docs, and live `launch-windows.ps1` inspection.

---

## 1. Problem Statement

On this Windows 11 host, `pip install -r requirements.txt` deterministically fails with `ConnectionResetError(10054)` to `https://pypi.org/simple/fastapi/` from Python’s TLS stack. Meanwhile, PowerShell `Invoke-WebRequest` succeeds, and other HTTPS sites from Python succeed. The failure is PyPI-edge-specific, not universal network outage.

---

## 2. Root-Cause Explanations (Research Findings)

| Plausible Cause | Evidence/Support | Likelihood on this host |
|-----------------|------------------|------------------------|
| **Antivirus/web protection injection** | `pypa/pip#12406`, multiple GH issues identify Kaspersky/AV products injecting into `python.exe` and resetting TLS connections. | **High** — matches deterministic 10054 at ClientHello, no ALPN, no peer cert. |
| **Windows proxy/firewall mismatch** | Python on Windows does not inherit WinHTTP/WinINet proxy settings automatically; PowerShell does. Perimeter firewall resets direct outbound Python connections that would otherwise go through proxy. | **High** — explains PowerShell/python asymmetry. |
| **TLS/ALPN/HTTP-2 profile mismatch** | Python's OpenSSL on Windows may negotiate different ALPN/TLS fingerprinted profile than .NET/SChannel. PyPI Fastly edge resets mismatched profiles. | **Medium** — supported by OpenSSL `s_client` showing `No ALPN negotiated` and immediate reset after ClientHello. |
| **TLS-fips/OpenSSL bundle path issue** | pip/urllib3 may load wrong CA bundle or OpenSSL config on Windows; Schannel vs OpenSSL mismatch. | **Low** — Fix C sanitization did not change behavior, so cert path is less likely the primary cause. |

### What research says is **not** the cause
- General internet outage: other HTTPS sites reachable from Python.
- Python `pip` bug alone: bug repros on `urllib.request`, `curl.exe`, and pip consistently.
- PowerShell limitation: PowerShell reaches PyPI fine via SChannel/WinHTTP.

---

## 3. Safe vs Unsafe Workarounds

### Safe
| Workaround | How it helps | Status here |
|------------|--------------|-------------|
| **Regional HTTPS mirror** (`PIP_INDEX_URL`) | Skips the PyPI Fastly edge entirely, avoiding the TLS profile/reset mismatch. | **Verified** — `tuna` and `aliyun` both installed `fastapi` cleanly in isolation. |
| **Mirror fallback on 10054** | Keeps public PyPI as primary, automatically switches mirror only when 10054 detected. | **Implemented** in `launch-windows.ps1`. |
| **Configurable `ODYSSEUS_PIP_MIRROR`** | Lets user override mirror without script changes. | **Implemented**. |
| **Disable HTTP/2 in pip** (`PIP_NO_INPUT=1` / env tweaks) | Some reports suggest HTTP/2 over pip/urllib3 contributes to reset. | **Not yet tested**; could complement mirror fallback. |
| **System proxy fix** (`winhttp proxy`/`netsh winhttp`) | Makes Python/PIP respect same proxy as PowerShell. | **External** to script; user action. |

### Unsafe / Avoid
- Blanket `--trusted-host` or `trusted-host = *`.
- Random public proxies.
- Replacing system OpenSSL/pip globally without integrity checks.
- Global antivirus tampering without user consent.

---

## 4. Production-Grade Recommendation for Windows Launcher

**Mirror-first, user-overridable.**

Current `launch-windows.ps1` already has the right shape:
1. **Default**: keep public PyPI primary for maximum compatibility.
2. **Auto fallback**: on `ConnectionResetError/10054` retry failure, switch to `https://pypi.tuna.tsinghua.edu.cn/simple` automatically if `ODYSSEUS_PIP_MIRROR` is not set.
3. **User opt-in**: user can set `ODYSSEUS_PIP_MIRROR` to any trusted HTTPS mirror to bypass auto-detection.
4. **Safety constraints**:
   - do not hardcode mirror as permanent default
   - do not use `--trusted-host` by default
   - preserve Fix C cert bundle logic
   - let user disable fallback by setting `ODYSSEUS_PIP_MIRROR=` to empty

Optional hardening:
- Add `PIP_NO_INPUT=1` or equivalent to disable HTTP/2 pip behavior if resets persist after mirror fallback.
- Add diagnostic capture of proxy settings when 10054 occurs.

---

## 5. Internal Problem Catalog (Launch Path)

### Fixed
| # | Problem | Location | Fix |
|---|---------|----------|-----|
| 1 | `$LASTEXITCODE` false-failure after successful retry | `Install-OdysseusDependencies` | Reset `$LASTEXITCODE = 0` on success before `break`. |
| 2 | Missing `Test-IsHermesAgentPython` function | venv creation block | Added function with `Resolve-Path` + Hermes prefix check. |
| 3 | Broken `sitecustomize.py` missing `import sys` | venv `sitecustomize.py` writer | Added `import sys` to generated `sitecustomize.py`. |
| 4 | Documentation claimed Fix C present when live code had lost it | `dev_log/analysis/2026-07-07-*` | Restored Fix C + corrected analysis docs to verified state. |
| 5 | `reset.ps1` truthful reporting / silent failure masking | `reset.ps1` | Removed `$ErrorActionPreference = 'SilentlyContinue'`, added `try/catch` and `$failed` tracking. |

### Latent / Remaining Risks
| # | Problem | Severity | Notes |
|---|---------|----------|-------|
| 1 | Post-loop `$LASTEXITCODE` check can still misreport on exotic pip stderr promotion | Medium | Mitigated by reset-on-success; not fully eliminable in PS 5.1. |
| 2 | `PIP_EXTRA_INDEX_URL` not cleared/saved around mirror fallback / Fix C restore | Low | Could defeat mirror intent if user had extra index set. Small patch to cover both. |
| 3 | `Get-OdysseusProcesses` repo-root fallback can over-match same-checkout MCPs | Medium | May kill unrelated processes; not yet patched. |
| 4 | Uvicorn output pump can block on pipe backpressure under chatty startup | Low | Has not crashed in normal use; can hang under verbose startup. |
| 5 | `Open-OdysseusBrowser` URL not quoted; fragile if URL ever contains spaces | Low | Not a crash today because URL is constrained. |
| 6 | `System.Diagnostics.ProcessStartInfo.Arguments` uses interpolated string instead of array | Low | Same as above — inputs are safe currently, but inconsistent with array form elsewhere. |

### Active Blockers
| # | Blocker | Current State |
|---|---------|---------------|
| 1 | Deterministic `ConnectionResetError(10054)` to public PyPI from Python stack | **Not fully resolved** — mirror fallback code is in place, but functional end-to-end validation by live launcher run is still pending. |
| 2 | No executable test runner for `.ps1` changes | No Pester/pytest available; verification is AST/syntax + live log inspection. |

---

## 6. Minimum Viable Launcher State

1. All A–G fixes present.
2. Fix C actually active in script, verified by checker.
3. `ODYSSEUS_PIP_MIRROR` opt-in present.
4. Automatic mirror fallback present for 10054.
5. `sitecustomize.py` valid and imports `sys`.
6. `Test-IsHermesAgentPython` present.
7. Functional live launcher run completes dependency install via mirror fallback without public PyPI.

Current status: items 1–6 are in place; item 7 is the next verification target.

---

## 7. Recommended Next Actions

1. Live-run `launch-windows.ps1` after reset with no env overrides to verify the automatic mirror fallback triggers and completes `requirements.txt`.
2. Patch `PIP_EXTRA_INDEX_URL` save/restore around mirror fallback.
3. Optionally add `PIP_NO_INPUT=1` or equivalent to reduce HTTP/2 edge cases.
4. Add one PowerShell regression-test script under `scripts/` if the user wants future checks without manual AST commands.
5. If 10054 persists even on mirrors, check AV/web protection or proxy settings on this host as the likely root cause.
