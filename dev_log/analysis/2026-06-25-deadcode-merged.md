# Dead-Code Merge — Approved Removals

**Date:** 2026-06-25  
**Sources:** DA-1, DA-2, DA-3, DA-4

## Approved removals (apply in Phase 3)

| # | File | Change | Rationale |
|---|------|--------|-----------|
| 1 | `routes/cookbook_helpers.py` | Remove `WIN_SESSION_DIR` | Zero references; superseded by `resolve_cookbook_log_path` |
| 2 | `routes/cookbook_helpers.py` | Remove `_git_bash_path`; import `git_bash_path` from `core.platform_compat` | Duplicate of platform helper (A2-14) |
| 3 | `static/js/cookbookDownload.js` | Remove tmux-only `has-session` fallback when `!_tmuxCmd` | `_tmuxCmd` always injected at init |
| 4 | `static/js/cookbook-diagnosis.js` | Remove PowerShell fallback from non-Windows HF cache size cmd | Orphaned copy-paste in else branch |

## Rejected / keep

| Candidate | Decision | Why |
|-----------|----------|-----|
| `python3` in bash runner strings (routes) | **Keep** | Live Git Bash/Linux paths; not superseded |
| `~/.cache/huggingface/hub` JS fallbacks | **Keep** | Offline/legacy migration; still referenced |
| `$HOME/.cache` in `cookbook-hwfit.js:1672` | **Keep** | Active stale path — behavior fix, not dead code |
| `platform: "linux"` in adopt_served_model | **Keep** | Live default; CB-DL-019 out of scope |
| TMUX_LOG_DIR relocation | **Keep** | A4-7 by design; ENV wipe clears temp dirs |
| Any tool_implementations.py symbols | **Keep** | DA-2 found no orphans |

## DA-2 / DA-4

No code removals. Register rows A5-004, A3-02, CB-DL-007, A3-03 marked Fixed in Phase 4 (live code already correct).
