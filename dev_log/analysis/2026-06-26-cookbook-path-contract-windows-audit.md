# Cookbook Path Contract Windows Audit — 2026-06-26

## Summary

Jun 25 path remediation remains **intact**. Backend `defaultHubPath` / `localPlatform`, download runners, and JS `_defaultHubPath()` align on `ODYSSEUS_DATA_DIR` → `data/huggingface/hub`. Today's `launch-windows.ps1` work (pip hardening, ChromaDB under `data/chroma`) does **not** regress the Cookbook path contract.

Remaining gaps are polish (diagnosis cache scan, Git Bash backslash HF exports, hwfit preview) and **operational** llama-cpp-python on Python 3.13 CPU-only Windows—not a contract reversion.

## Verification

| Check | Result |
|-------|--------|
| `tests/test_cookbook_path_contract_regression.py` | **6/6 passed** (2026-06-26 re-run) |
| `tests/test_cookbook_log_path_resolver.py` | passed (included in 81-test batch) |
| `tests/test_cookbook_helpers.py` | passed (included in 81-test batch) |

## Path contract — OK

| Layer | Notes |
|-------|-------|
| `src/constants.py` | `HUGGINGFACE_*`, `CHROMA_DIR`, `OLLAMA_HOME` under `DATA_DIR` |
| `launch-windows.ps1` L27–30 | Seeds `ODYSSEUS_DATA_DIR`, HF cache, Ollama paths |
| `routes/cookbook_routes.py` L258–260 | Injects `defaultHubPath`, `defaultHuggingfaceHome`, `localPlatform` |
| Download runners | Default HF env from constants, not `~/.cache` |
| `static/js/cookbook.js` | `_defaultHubPath()` from server state |
| `local_windows` detached launch | Git Bash + `%TEMP%\odysseus-tmux` |
| ChromaDB (Jun 26) | `data/chroma` via launcher |

## Open issues

### Medium

| ID | Issue | Location |
|----|-------|----------|
| A5-005 | Diagnosis HF cache check scans `%USERPROFILE%\.cache\huggingface`, not `defaultHubPath` | `static/js/cookbook-diagnosis.js` ~L550–552 |
| A2-10 | `_shell_path()` leaves Windows backslashes in bash `export HF_HOME=...` | `routes/cookbook_helpers.py` L133–141; download wrapper L549–572 |
| hwfit | llamacpp quick-run uses `$HOME/.cache/huggingface/hub/...` | `static/js/cookbook-hwfit.js` ~L1672–1674 |
| llama-cpp serve | Linux-oriented bash bootstrap on `local_windows`; Py3.13 CPU wheel absent → source build / long-path failure | `routes/cookbook_routes.py` L1545–1655 |

### Low

| ID | Issue | Location |
|----|-------|----------|
| DATA_DIR fallback | `load_stored_hf_token()` uses `DATA_DIR` env, not `ODYSSEUS_DATA_DIR` | `routes/cookbook_helpers.py` L90 |
| Remote Windows serve | PS runner installs bare `llama-cpp-python[server]` without CPU wheel index | `cookbook_routes.py` L1480 |
| A4-7 | `TMUX_LOG_DIR` under system temp, not `DATA_DIR` | `routes/shell_routes.py` L399 — by design |

## Related plans

See `dev_log/plans/2026-06-26-cookbook-polish-followups.md`.
