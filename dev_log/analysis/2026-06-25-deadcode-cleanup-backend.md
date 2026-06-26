# Backend Dead-Code Cleanup — 2026-06-25

**Agent:** BACKEND cleanup (post bd7106e / 8306f24 remediation)  
**Scope:** `routes/cookbook_*.py`, `routes/codex_routes.py`, `routes/shell_routes.py`, cookbook symbols in `src/tool_implementations.py`, `core/platform_compat.py`

## Already removed (8306f24 — no action)

| Item | File | Status |
|------|------|--------|
| `WIN_SESSION_DIR` | `cookbook_helpers.py` | Gone in 8306f24 |
| `_git_bash_path` duplicate | `cookbook_helpers.py` | Gone; uses `git_bash_path` from `platform_compat` |

## Removed this pass

| # | File | Lines | Symbol / change | Rationale |
|---|------|-------|-----------------|-----------|
| 1 | `routes/cookbook_helpers.py` | −12 | `_ssh`, `_ssh_ps` | Zero references repo-wide; superseded by `core.platform_compat._ssh_exec_argv` / `run_ssh_command_async` |
| 2 | `routes/cookbook_routes.py` | −5 | Duplicate import block | `_ollama_bind_from_cmd`, `_pip_install_fallback_chain`, `_pip_install_no_cache`, `_user_shell_path_bootstrap`, `_venv_safe_local_pip_install_cmd` imported twice |
| 3 | `routes/cookbook_routes.py` | (in #2) | Unused imports: `_diagnose_serve_output`, `run_ssh_command_async`, `_append_vllm_linux_preflight_lines` | Shadowed by nested `_diagnose_serve_output` (L98); `run_ssh_command_async` never called in routes; vLLM preflight helper only used in tests |

**Net:** 2 files changed, **17 lines removed**, 0 behavior changes.

## Kept (not dead code)

| Candidate | Decision | Why |
|-----------|----------|-----|
| Nested `_diagnose_serve_output` in `cookbook_routes.py` | **Keep** | Live (L3523); shadows helpers import but is the route handler's active copy |
| Module-level `_diagnose_serve_output` in `cookbook_helpers.py` | **Keep** | Used by `tests/test_cookbook_diagnosis.py`, `tests/test_cookbook_error_feedback.py` |
| `_append_vllm_linux_preflight_lines` in helpers | **Keep** | Test-covered; only the routes import was dead |
| `python3` in bash runner strings | **Keep** | Live Git Bash/Linux paths (DA-1) |
| `platform: "linux"` in agent task registration | **Keep** | Live stale default — CB-DL-019 / A3-07 behavior fix out of scope |
| `/tmp/odysseus-tmux` in serve tee + `resolve_cookbook_log_path` | **Keep** | Live Linux/macOS paths |
| `TMUX_LOG_DIR` in `shell_routes.py` | **Keep** | By design (A4-7) |
| All cookbook symbols in `tool_implementations.py` | **Keep** | DA-2 found no orphans |
| `core/platform_compat.py` | **Keep** | No duplicate helpers remain after 8306f24 |

## Files unchanged (clean)

- `routes/cookbook_output.py`
- `routes/codex_routes.py`
- `routes/shell_routes.py`
- `src/tool_implementations.py`
- `core/platform_compat.py`

## Tests

```
.venv\Scripts\python.exe -m pytest \
  tests/test_cookbook_helpers.py \
  tests/test_cookbook_log_path_resolver.py \
  tests/test_cookbook_dead_download_status.py \
  tests/test_cookbook_path_contract_regression.py -q
```

**Result:** 94 passed, 1 failed

| Test | Verdict |
|------|---------|
| `test_pip_install_attempt_success_exits_zero` | **Pre-existing env failure** — Git Bash on this VM has no `python`/`python3` on PATH; unrelated to this cleanup |

All path-contract, log-resolver, dead-download, and regression tests passed.

## Blockers for commit

None for the dead-code diff itself. Optional follow-ups (out of scope):

1. Consolidate duplicate `_diagnose_serve_output` (routes nested copy vs helpers module) — would add `lm_head.input_scale` pattern to routes path.
2. Wire `_append_vllm_linux_preflight_lines` into serve runners or document as test-only helper.
