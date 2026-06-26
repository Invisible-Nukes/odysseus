# DA-1 — Backend Routes Dead-Code Audit

**Commit:** bd7106e (`align Windows download, scan, and serve path contract`)  
**Files:** `routes/cookbook_routes.py`, `routes/cookbook_helpers.py`, `routes/cookbook_output.py`, `routes/codex_routes.py`

## Method

Compared `git show bd7106e^:<file>` → `git show bd7106e -- <file>`, grepped repo for each candidate symbol.

## Candidates

| Symbol / pattern | Location | Classification | Action |
|------------------|----------|----------------|--------|
| `_git_bash_path` | `cookbook_helpers.py:58-63` | **Orphaned duplicate** — mirrors `core.platform_compat.git_bash_path` (219-230); only caller is `_local_tooling_path_export` | **Remove** — import `git_bash_path` from `platform_compat` |
| `WIN_SESSION_DIR` | `cookbook_helpers.py:1243` | **Orphaned** — defined at bd7106e, zero imports/usages; routes inline `$env:TEMP\odysseus-sessions` via `resolve_cookbook_log_path` / `win_session_stop_tree_ps` | **Remove** constant |
| Hardcoded `/tmp/odysseus-tmux` in codex | `codex_routes.py` | **Live** — replaced by `resolve_cookbook_log_path` in bd7106e | Keep |
| `python3` in bash runner strings | `cookbook_routes.py` (serve/download wrappers) | **Live** — Git Bash runners on all platforms; local probes use `resolve_python_for_probe()` | Keep |
| `resolve_python_for_probe` | `cookbook_output.py:48-56` | **Live** — new in bd7106e, used by `cookbook_routes.py` probes | Keep |
| `_safe_env_prefix_ps`, `_build_dl_pyarg`, `_strip_path_trailing_seps` | `cookbook_helpers.py` | **Live** — new helpers wired in bd7106e | Keep |
| `resolve_cookbook_log_path`, `win_session_stop_tree_ps` | `cookbook_helpers.py` | **Live** — used by codex, tool_implementations, tests | Keep |
| tmux tee paths in serve runner | `cookbook_routes.py:1523-1526` | **Live** — Linux/macOS remote/local bash serve path (A2-13 open, not dead) | Keep |

## Removal list (DA-1)

1. Delete `WIN_SESSION_DIR` constant (`cookbook_helpers.py:1243`)
2. Delete `_git_bash_path` function; change `_local_tooling_path_export` to use `git_bash_path` from `core.platform_compat`

## Ambiguous — keep

- `python3` strings inside bash heredocs — intentional for Git Bash/Linux runners, not superseded by Windows probe fix.
- Inline `$env:TEMP\odysseus-sessions` in helpers — live, not replaceable by removed `WIN_SESSION_DIR`.
