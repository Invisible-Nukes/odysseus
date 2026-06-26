# DA-4 — Tests + Register Reconciliation

**Commit:** bd7106e  
**Scope:** Tests covering removed behavior; audit register Open/Fixed vs live code.

## Tests — stale vs live

| Test file | Covers | Status |
|-----------|--------|--------|
| `test_cookbook_path_contract_regression.py` | No pewds paths; `_defaultHubPath` usage | **Live** — keep |
| `test_cookbook_log_path_resolver.py` | `resolve_cookbook_log_path` | **Live** — keep |
| `test_cookbook_windows_stop_tree_js.py` | JS no hardcoded f-string log paths | **Live** — keep |
| `test_cookbook_helpers.py` | `_local_tooling_path_export`, cache scan | **Live** — keep; still valid after `git_bash_path` consolidation |
| `test_cookbook_dead_download_status.py` | Dead download probes | **Live** — keep |
| `test_hf_download.py` | HF download script | **Live** — keep |

**No tests target removed behavior** (pre-bd7106e hardcoded paths, tmux-only cancel, pewds paths). No test deletions required.

## Register reconciliation (selected rows)

| ID | Register status | Live code verdict | Post-cleanup status |
|----|-----------------|-------------------|---------------------|
| A5-001 | Fixed | `cookbookServe.js` uses `_defaultHubPath()` | Fixed |
| A5-002 | Fixed | JS + backend inject `defaultHubPath` | Fixed |
| CB-DL-001 | Fixed | Windows PID kill in tools + JS `_tmuxCmd` | Fixed |
| CB-DL-002 | Fixed | `resolve_python_for_probe()` for local probes | Fixed |
| CB-DL-010 | Fixed | `_tmuxCmd` zombie check in `cookbookDownload.js` | Fixed |
| CB-DL-015 | Fixed | hwfit kill uses `_tmuxCmd` | Fixed |
| A2-01 | Fixed | `resolve_cookbook_log_path` in codex + tools | Fixed |
| A2-14 | Open | Duplicate `_git_bash_path` still present | → **Removed** (DA-1) |
| CB-DL-008 | Open | UI shows `_defaultHubPath()` when server loaded; legacy fallback remains | Open (intentional offline fallback) |
| A5-004 / A3-02 | Open | Serve uses `_defaultHubPath()` not `$HOME/.cache` | **Fixed** (register stale — update to Fixed) |
| CB-DL-007 | Open | Download preview uses HF_HOME env not `local_dir=` flat layout | Fixed in bd7106e |
| A3-03 | Open | `_normalizeState` maps legacy → `hubDefault` | Fixed in bd7106e |
| A5-005 | Open | diagnosis has Windows branch; Unix still `du` only after cleanup | Partial — Open |
| CB-DL-019 / A3-07 | Open | `platform: "linux"` hardcoded in adopt | Open (not dead code) |
| A4-7 | By design | `TMUX_LOG_DIR` under system temp | By design |

## Removal list (DA-4)

**Empty** — no test files or test cases to delete.

## Register updates needed (Phase 4)

- A2-14 → Removed
- A5-004, A3-02, CB-DL-007, A3-03 → Fixed (register was stale vs live code)
