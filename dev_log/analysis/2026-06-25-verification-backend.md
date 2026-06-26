# Backend Verification — Dead-Code Cleanup (969bc36)

**Date:** 2026-06-25  
**Agent:** BACKEND VERIFICATION  
**Commits under test:** `969bc36` (dead-code strip), prior remediation `bd7106e` / `8306f24`  
**Scope:** Cookbook backend pathing, download, serve, probes, cancel — confirm path contract intact after `_ssh` / `_ssh_ps` / duplicate-import removal.

---

## Executive Summary

| Area | Verdict |
|------|---------|
| Dangling references after 969bc36 | **PASS** |
| Path contract end-to-end (Python) | **PASS** |
| Audit register fixes (backend IDs) | **PASS** (13/13 confirmed) |
| New regressions from dead-code removal | **NONE** |
| Pytest suite (5 files) | **PASS — 97/97** |

**Blockers:** None for the dead-code diff. Optional follow-ups remain open in the audit register (A2-03, CB-DL-011–017, etc.) but are pre-existing and unrelated to 969bc36.

---

## 1. Removed Symbols — Dangling Reference Check

### `_ssh`, `_ssh_ps` (removed in 969bc36)

| Check | Result |
|-------|--------|
| Repo-wide grep for `_ssh(` / `_ssh_ps(` | **PASS** — zero production references |
| Superseding path | `core.platform_compat._ssh_exec_argv` + `run_ssh_command_async` in `cookbook_helpers.py` (unchanged) |

Only hits: `dev_log/analysis/2026-06-25-deadcode-cleanup-backend.md` (documentation) and unrelated symbols (`app_ssh`, `_powershell_encoded_for_ssh`, `_ssh_exec_argv` in tests/hwfit).

### Duplicate / unused imports (removed in 969bc36)

| Removed from `cookbook_routes.py` | Still needed elsewhere? | Result |
|-----------------------------------|-------------------------|--------|
| `_diagnose_serve_output` (helpers import) | Nested copy at L95 used at L3520 | **PASS** — live nested function retained |
| `run_ssh_command_async` | Used in `tests/test_cookbook_helpers.py` only | **PASS** — routes never called it |
| `_append_vllm_linux_preflight_lines` | Used in tests only | **PASS** — routes import was dead |
| Duplicate `_ollama_bind_from_cmd` … block | — | **PASS** — single import block at L43–55 |

Import smoke test: all key symbols import cleanly; `HUGGINGFACE_HOME` → `C:\odysseus\data\huggingface`, `resolve_python_for_probe()` → venv `python.exe`.

---

## 2. Path Contract — End-to-End Trace

### Constants (`src/constants.py`)

| Constant | Definition | Verdict |
|----------|------------|---------|
| `HUGGINGFACE_HOME` | `os.getenv("HF_HOME", join(DATA_DIR, "huggingface"))` | **PASS** |
| `HUGGINGFACE_HUB_CACHE` | `os.getenv("HUGGINGFACE_HUB_CACHE", join(HUGGINGFACE_HOME, "hub"))` | **PASS** |

### Probe & lifecycle helpers

| Symbol | Location | Used by | Verdict |
|--------|----------|---------|---------|
| `resolve_python_for_probe()` | `routes/cookbook_output.py:46-55` | `cookbook_routes.py:3215,3242` (local probes use `sys.executable`) | **PASS** |
| `resolve_cookbook_log_path()` | `routes/cookbook_helpers.py:1230-1247` | `codex_routes.py`, `tool_implementations.py` | **PASS** |
| `win_session_stop_tree_ps()` | `routes/cookbook_helpers.py:1260+` | `tool_implementations.py:2305` (remote Windows kill) | **PASS** |

### Download HF env exports (`POST /api/model/download`)

| Branch | Lines | Exports | Verdict |
|--------|-------|---------|---------|
| Bash (local/remote Linux) | 570–572 | `HF_HOME`, `HUGGINGFACE_HUB_CACHE`, `HF_HUB_CACHE` | **PASS** |
| PowerShell (remote Windows) | 632–641 | Same trio via `$env:` | **PASS** |
| Custom `local_dir` | 542–543, 627–633 | `_strip_path_trailing_seps` + `_shell_path` / `_ps_squote` | **PASS** |
| Python fallback include | 550, 669, 677 | `_build_dl_pyarg(req.include)` → `allow_patterns=[...]` | **PASS** |

### Cache scan (`GET /api/model/cached`)

| Behavior | Lines | Verdict |
|----------|-------|---------|
| WSL split-cache | 895–898 | `is_wsl()` → `add_hf_cache = join(win_profile, ".cache", "huggingface", "hub")` | **PASS** |
| Native non-WSL | 900–902 | Injects `HUGGINGFACE_HUB_CACHE` when not in `model_dirs` | **PASS** |
| Scanner script | `_cached_model_scan_script` | Probes `HUGGINGFACE_HUB_CACHE` env, `HF_HOME/hub`, `~/.cache`, `/app/.cache`, `add_hf_cache` | **PASS** |
| Windows snapshot fallback | `scan_hf()` L456–464 | Falls back to snapshots when blobs empty | **PASS** |

### Agent `download_model` (`src/tool_implementations.py`)

| Field | Lines | Verdict |
|-------|-------|---------|
| `local_dir` from server `downloadDir` | 1995–1996 | **PASS** |
| Task registration includes `local_dir` | 2008 | **PASS** |
| Platform / ssh_port forwarded | 2009–2010 | **PASS** |

### CLI script (`scripts/hf_download.py`)

| Behavior | Lines | Verdict |
|----------|-------|---------|
| `HF_HOME` / `HUGGINGFACE_HUB_CACHE` from constants | 155–157 | **PASS** |
| `allow_patterns` when `--include` set | 178–179 | **PASS** |

### Client path contract exposure

| API | Lines | Verdict |
|-----|-------|---------|
| `_state_for_client` | `cookbook_routes.py:258-259` | Exposes `defaultHubPath`, `defaultHuggingfaceHome` | **PASS** |

---

## 3. Audit Register — Fixed Backend IDs (post-969bc36)

| ID | Title | Verification | Status |
|----|-------|--------------|--------|
| **CB-DL-001** | Cancel/kill tmux-only on Windows | Agent kill: `local_windows` → `kill_process_tree` (L2317–2335); remote Windows → `win_session_stop_tree_ps` (L2304–2310) | **Still fixed** |
| **CB-DL-002** | Probes hardcode `python3` | Local probes use `resolve_python_for_probe()` (L3215, 3242); env seeds `HF_HOME`/`HUGGINGFACE_HUB_CACHE` (L3226–3227) | **Still fixed** |
| **CB-DL-003** | Remote Windows stderr split | Status capture reads `.log` + `.err.log` (L3347–3348) | **Still fixed** |
| **CB-DL-004** | `snapshot_download` drops `include` | `_build_dl_pyarg` wired into PS fallback (L669, 677) and bash paths | **Still fixed** |
| **CB-DL-005** | Agent ignores `downloadDir` | `payload["local_dir"] = env_cfg["downloadDir"]` (L1995–1996) | **Still fixed** |
| **CB-DL-006** | Agent task omits `local_dir` | `_cookbook_register_task(..., local_dir=...)` (L2008) | **Still fixed** |
| **CB-DL-009** | Remote Windows ignores `disable_hf_transfer` | PS branch honors flag (L652–655, 666–668) | **Still fixed** |
| **CB-DL-018** | Scanner hardcodes Unix HF paths | Scanner probes env + `add_hf_cache`; native injects `HUGGINGFACE_HUB_CACHE` | **Still fixed** |
| **A2-01** | Agent/codex log tail hardcodes `/tmp/odysseus-tmux` | `resolve_cookbook_log_path` in `codex_routes.py:582,595` and `tool_implementations.py` | **Still fixed** |
| **A2-02** | Bash `env_prefix` in PS runners | Remote Windows uses `_safe_env_prefix_ps` (L643–646) | **Still fixed** |
| **A2-04** | Incomplete probe blobs-only | Both probes check snapshots for `.incomplete` (`cookbook_output.py:29,41`) | **Still fixed** |
| **A3-01** | Cache scan omits `HUGGINGFACE_HUB_CACHE` | `model_cached` injects hub constant (L900–902) | **Still fixed** |
| **A4-1** | WSL `add_hf_cache` unwired | Wired when `is_wsl()` (L895–898) | **Still fixed** |

---

## 4. New Regressions from 969bc36

| Risk | Finding |
|------|---------|
| Broken SSH download/serve on remote | **None** — removed `_ssh`/`_ssh_ps` had zero callers; live paths use `platform_compat` argv SSH |
| ImportError on route load | **None** — smoke import of `cookbook_helpers` + `cookbook_routes` symbols succeeds |
| Serve diagnosis regression | **None** — nested `_diagnose_serve_output` at `cookbook_routes.py:95` still invoked at L3520 |
| Probe / cancel / download path drift | **None** — no edits to path contract functions in 969bc36 diff |

**969bc36 diff summary:** −12 lines (`_ssh`, `_ssh_ps`), −5 lines (duplicate/unused imports). Zero behavior changes confirmed.

---

## 5. Pytest Results

**Command:**
```
venv\Scripts\python.exe -m pytest \
  tests/test_cookbook_helpers.py \
  tests/test_cookbook_log_path_resolver.py \
  tests/test_cookbook_dead_download_status.py \
  tests/test_cookbook_path_contract_regression.py \
  tests/test_hf_download.py -v
```

| File | Tests | Result |
|------|-------|--------|
| `test_cookbook_helpers.py` | 73 | **73 passed** |
| `test_cookbook_log_path_resolver.py` | 4 | **4 passed** |
| `test_cookbook_dead_download_status.py` | 14 | **14 passed** |
| `test_cookbook_path_contract_regression.py` | 6 | **6 passed** |
| `test_hf_download.py` | 2 | **2 passed** |
| **Total** | **97** | **97 passed, 0 failed** |

**Environment notes:**
- Fresh `venv` created via `py -3 -m venv venv` (prior venv absent).
- Initial `pip install` hit WinError 32 file lock on `icalendar`; partial install caused 8 collection failures (`HTTPException` stubbed as `MagicMock`). Re-run after FastAPI fully available: **97/97 pass**.
- `test_pip_install_attempt_success_exits_zero` (Git Bash–dependent) **passed** on this run — previously flaky on VM per cleanup doc.

**Path-contract highlights covered by tests:**
- `_build_dl_pyarg`, `_strip_path_trailing_seps`, `_safe_env_prefix_ps`
- `resolve_cookbook_log_path` (local Windows, remote Windows/Linux)
- HF cache probes with custom dir + snapshot incomplete detection
- `resolve_python_for_probe` prefers `sys.executable`
- JS/backend pewds-path regression guards
- `hf_download.py` help + START/DONE markers

---

## 6. Still-Open Issues (not regressions; out of 969bc36 scope)

These remain in the audit register and were **not** introduced by dead-code removal:

| ID | Severity | Note |
|----|----------|------|
| A2-03 | High | Git Bash required for local Windows download/serve |
| CB-DL-011, A2-11 | Medium | Local Windows `hf download` stdin redirect |
| CB-DL-012 | Medium | `rstrip("/")` only — mitigated by `_strip_path_trailing_seps` on download path |
| CB-DL-013 | Medium | Remote Windows HF_HOME bare `except` |
| CB-DL-014, A3-06 | Medium | Pinned MiniMax snapshot revision |
| CB-DL-016, CB-DL-017 | Medium | Log dir naming split; Unix PATH in bash wrappers |
| CB-DL-019, A3-07 | Low | Agent hardcodes `platform: "linux"` |
| A4-2, A4-3 | Medium | Docker dual HF paths; compose vs Python data dir naming |

---

## 7. Verdict

**Backend verification: PASS**

Commit `969bc36` safely removes orphaned SSH string builders and duplicate imports without breaking the Cookbook path contract, download destination logic, cache probes, cancel flows, or WSL cache wiring established in prior remediation commits. All 97 targeted tests pass.

**Recommended before merge:** None blocking. Optional: consolidate duplicate `_diagnose_serve_output` (routes nested vs helpers module) in a future refactor — not required for this cleanup.
