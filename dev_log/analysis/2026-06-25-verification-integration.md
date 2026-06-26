# Integration Verification — Cookbook Dead-Code & Path Remediation

**Date:** 2026-06-25  
**Agent:** INTEGRATION VERIFICATION  
**Scope:** Broad Cookbook + HW Fit pytest subset, import smoke, live API smoke, `.env` ↔ constants alignment  
**Commits under test:** Working tree (dead-code cleanup + path remediation; includes `969bc36` backend/frontend strips)

---

## Executive Summary

| Gate | Result |
|------|--------|
| Environment runnable (venv + deps) | **PASS** — fresh venv created |
| Cookbook/HW Fit pytest (277 tests) | **270 passed, 7 failed, 0 skipped** |
| Import smoke (as specified) | **FAIL** — symbol moved to `cookbook_output.py` |
| Import smoke (corrected) | **PASS** |
| API smoke (health / state / cached) | **PASS** |
| `.env` ↔ `src/constants.py` alignment | **PASS** (5/5 paths) |
| New regressions from dead-code cleanup | **NONE identified** |

**Verdict:** Environment is runnable; core Cookbook backend path contract and API surface are healthy. All 7 test failures are **Windows-host / test-harness artifacts**, not functional regressions from the cleanup diff. No new failures beyond known platform caveats.

---

## 1. Environment Setup

| Item | Status |
|------|--------|
| `C:/odysseus/venv` | **Created** — was absent at start (`venv.broken` existed but unusable) |
| Python | `py -3.13` → Python 3.13.5 (`C:\Program Files\Python313\python.exe`) |
| `pip install -r requirements.txt` | **PASS** — all deps installed (~4 min) |
| Notes | Initial venv recreate hit WinError 32 file lock on pip upgrade; `ensurepip` + direct install succeeded |

**Degraded at startup (non-blocking for Cookbook):**
- ChromaDB not reachable at `localhost:8100` → VectorRAG + MemoryVectorStore degraded
- `python-magic` not available → basic MIME detection fallback

---

## 2. Pytest — Cookbook + HW Fit Subset

**Command:**
```powershell
.\venv\Scripts\pytest.exe (Get-ChildItem tests/test_cookbook*.py, tests/test_hwfit*.py) -q --tb=no
```

| Metric | Count |
|--------|-------|
| Collected | **277** |
| Passed | **270** |
| Failed | **7** |
| Skipped | **0** |
| Duration | ~71 s |

### Known pre-existing: `test_pip_install_attempt_success_exits_zero`

| Test | Result | Note |
|------|--------|------|
| `tests/test_cookbook_helpers.py::test_pip_install_attempt_success_exits_zero` | **PASSED** | Re-run isolated: 1 passed in 0.72 s. Previously flaky on Windows VM when Git Bash unavailable; **not failing on this run**. |

### Failed tests — classification

| Test | Failure | Classification |
|------|---------|----------------|
| `test_cookbook_port_parsing_js.py` (3 tests) | `ERR_UNSUPPORTED_ESM_URL_SCHEME` — Node ESM loader rejects `c:` path in `import … from 'c:/odysseus/…'` | **Pre-existing Windows test harness** — `_HELPER.as_posix()` needs `pathToFileURL()` on Windows; unrelated to cleanup |
| `test_cookbook_same_host_server_profiles_js.py::test_cookbook_submodules_resolve_visible_profile_selection` | Assert expects `_serverByVal?.(_envState.remoteServerKey \|\| _zh)` in `cookbookDownload.js` | **Stale test string** — live code uses `host` / `remoteHost` (semantically equivalent); not a runtime regression |
| `test_hwfit_cpu_arch_detection.py` (2 tests) | Expected `cuda`/`arm` backend from mocked `_detect_nvidia`; got `cpu_x86` / `x86_64` | **Pre-existing Windows host** — `detect_system()` short-circuits to `_detect_windows()` at L844–849 before mocked Linux GPU probes run |
| `test_hwfit_macos.py::test_detect_system_propagates_unified_memory` | Expected `metal` backend from mocked `_detect_apple_silicon`; got `cpu_x86` | **Pre-existing Windows host** — same `_detect_windows()` early return |

**Conclusion:** Zero failures attributable to dead-code removal or path remediation. Backend-focused subset (97 tests in prior verification) remains fully green; broad suite failures are platform/test-infra only.

---

## 3. Import Smoke

### As specified (FAIL)

```powershell
python -c "import app; from routes.cookbook_helpers import resolve_cookbook_log_path, resolve_python_for_probe; print('ok')"
```

```
ImportError: cannot import name 'resolve_python_for_probe' from 'routes.cookbook_helpers'
```

`resolve_python_for_probe()` lives in `routes/cookbook_output.py:46-55` (remediation commit `bd7106e`), not `cookbook_helpers.py`. `cookbook_routes.py` imports it from `cookbook_output`.

### Corrected (PASS)

```powershell
python -c "import app; from routes.cookbook_helpers import resolve_cookbook_log_path; from routes.cookbook_output import resolve_python_for_probe; print('ok')"
```

Output: `ok` (app loads; ChromaDB warnings only).

Also confirmed live:
- `resolve_cookbook_log_path` — `cookbook_helpers.py:1230`
- `resolve_python_for_probe` — returns `sys.executable` on this host

---

## 4. API Smoke (uvicorn)

**Start:**
```powershell
$env:AUTH_ENABLED='false'
$env:ODYSSEUS_DATA_DIR='C:/odysseus/data'
$env:HF_HOME='C:/odysseus/data/huggingface'
$env:HUGGINGFACE_HUB_CACHE='C:/odysseus/data/huggingface/hub'
.\venv\Scripts\uvicorn.exe app:app --host 127.0.0.1 --port 7000
```

Log: `Auth middleware disabled (set AUTH_ENABLED=true to enable)` — startup complete ~15 s.

| Endpoint | Status | Key fields |
|----------|--------|------------|
| `GET /api/health` | **200** | `{"status":"healthy","timestamp":"…"}` |
| `GET /api/cookbook/state` | **200** | `env.defaultHubPath` = `c:\odysseus\data\huggingface\hub`, `env.localPlatform` = `windows`, `env.defaultHuggingfaceHome` = `c:\odysseus\data\huggingface` |
| `GET /api/model/cached` | **200** | `{"models":[],"host":"local"}` (empty cache — expected on fresh data dir) |

Server stopped after checks.

---

## 5. `.env` ↔ `src/constants.py` Alignment

`.env` contents (paths only — no secrets present):

| Variable | `.env` value | `constants.py` resolution | Match |
|----------|--------------|---------------------------|-------|
| `ODYSSEUS_DATA_DIR` | `C:/odysseus/data` | `DATA_DIR` | ✅ |
| `HF_HOME` | `C:/odysseus/data/huggingface` | `HUGGINGFACE_HOME` | ✅ |
| `HUGGINGFACE_HUB_CACHE` | `C:/odysseus/data/huggingface/hub` | `HUGGINGFACE_HUB_CACHE` | ✅ |
| `OLLAMA_HOME` | `C:/odysseus/data/ollama` | `OLLAMA_HOME` | ✅ |
| `FASTEMBED_CACHE_PATH` | `C:/odysseus/data/fastembed_cache` | `FASTEMBED_CACHE_DIR` | ✅ |

Default fallback (no env): `get_default_data_dir()` → `{app_root}/data` = `C:/odysseus/data` — consistent with `.env`.

API `/api/cookbook/state` exposes the same hub path the constants module resolves, confirming end-to-end wiring.

---

## 6. Blockers for Production Windows Cookbook Use

| Severity | Blocker | Status |
|----------|---------|--------|
| **High** | Git Bash required for local Windows download/serve runners (A2-03) | Open — pre-existing |
| **Medium** | ChromaDB not running → RAG / semantic memory degraded | Open — unrelated to Cookbook core |
| **Medium** | Local Windows `hf download` stdin redirect (CB-DL-011) | Open — pre-existing |
| **Low** | Empty model cache on fresh install | Expected — download flow untested end-to-end this run |
| **Low** | 7 pytest failures on Windows host | Test infra / platform mocks — not production runtime blockers |

**Not blockers:**
- Dead-code removal (`969bc36`) — no dangling refs, path contract intact
- venv / uvicorn / API health — all operational
- `test_pip_install_attempt_success_exits_zero` — passing on this VM

---

## 7. Recommended Follow-ups (non-blocking)

1. Update integration smoke import to use `routes.cookbook_output.resolve_python_for_probe` (or re-export from helpers for backward compat).
2. Fix JS pytest harness on Windows: use `pathToFileURL()` for ESM imports in `test_cookbook_port_parsing_js.py`.
3. Update `test_cookbook_same_host_server_profiles_js.py` assertion: `_zh` → `host` / `remoteHost`.
4. Mark hwfit Linux/macOS mock tests `@pytest.mark.skipif(os.name == "nt")` or mock `_detect_windows` when testing GPU backend propagation.
5. Optional: start ChromaDB (`docker compose up chromadb`) for full-stack verification.

---

## 8. Verdict

**Integration verification: PASS (with documented Windows test caveats)**

Environment is runnable. Cookbook API path contract (`defaultHubPath`, `localPlatform`, HF cache scan) works correctly against `.env` and `src/constants.py`. Broad pytest: **270/277 pass**; 7 failures are known Windows-host limitations, not regressions from dead-code cleanup or path remediation.
