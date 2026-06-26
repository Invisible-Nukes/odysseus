# Frontend Dead-Code Cleanup — Cookbook JS

**Date:** 2026-06-25  
**Scope:** `static/js/cookbook.js`, `cookbookRunning.js`, `cookbookServe.js`, `cookbookDownload.js`, `cookbook-hwfit.js`, `cookbook-diagnosis.js`  
**Baseline:** post-remediation (`8306f24` already applied DA-3 tmux/PowerShell fallbacks)

## Method

1. Read DA-3 + merged removal list.
2. Grep scoped files for pewds paths, tmux-only fallbacks, PowerShell copy-paste, duplicate helpers, zero-reference injected vars.
3. Remove only provably unused symbols (no behavior refactors).
4. `node --check` on all six files; run JS contract regression tests.

## Already removed (8306f24 — not re-done)

| Item | File | Status |
|------|------|--------|
| tmux-only `has-session` fallback when `!_tmuxCmd` | `cookbookDownload.js` | Removed in 8306f24 |
| PowerShell fallback on non-Windows HF cache `du` cmd | `cookbook-diagnosis.js` | Removed in 8306f24 |

## Removed in this pass

| File | Removed | Rationale |
|------|---------|-----------|
| `cookbookDownload.js` | Unused import `_defaultHubPath` | Zero references after download preview migration |
| `cookbookDownload.js` | Injected vars never read: `_getPlatform`, `_detectBackend`, `_detectToolParser`, `modelLogo`, `esc` + `initDownload` assignments | Copy-paste from `shared` init; download module never calls them |
| `cookbookDownload.js` | `const SERVE_STATE_KEY` | Duplicate artifact; live key lives in `cookbookRunning.js` / `cookbookServe.js` |
| `cookbookRunning.js` | Injected vars never read: `_detectBackend`, `_detectToolParser`, `_detectModelOptimizations`, `_buildServeCmd` + `initRunning` assignments | Assigned from `shared` but never referenced in Running tab |
| `cookbook-diagnosis.js` | Unused imports: `_removeTask`, `_buildEnvPrefix`, `_tmuxCmd` | Import-only; no call sites |
| `cookbook.js` | `const SERVE_STATE_KEY` | Zero references; serve state key owned by Running/Serve modules |

## Kept (intentional / live)

| Pattern | Location | Why kept |
|---------|----------|----------|
| `_defaultHubPath()` + `~/.cache/huggingface/hub` fallback | `cookbook.js`, `cookbookServe.js`, `cookbook-hwfit.js` | Offline/server default + legacy persisted path normalization |
| `LEGACY_DEFAULT` / `~/.cache/huggingface/hub` in `_normalizeState` | `cookbookRunning.js:1230+` | Live migration for stored server entries |
| `$HOME/.cache/huggingface/hub` in hwfit llamacpp cmd preview | `cookbook-hwfit.js:1672` | Active stale path — behavior fix out of scope |
| `_tmuxCmd` / `_winSessionCmd` / tmux probe strings | `cookbookRunning.js` | Live Windows/Linux session parity |
| Windows diagnosis HF cache check via `USERPROFILE\.cache` | `cookbook-diagnosis.js:554` | Live (ENV/path fix out of scope) |
| pewds comment | `cookbook.js:2730` | Comment only, not executable |

## Unchanged files

- `cookbookServe.js` — no zero-reference dead code found
- `cookbook-hwfit.js` — no zero-reference dead code found

## Verification

```
node --check static/js/cookbook.js
node --check static/js/cookbookRunning.js
node --check static/js/cookbookServe.js
node --check static/js/cookbookDownload.js
node --check static/js/cookbook-hwfit.js
node --check static/js/cookbook-diagnosis.js
# all exit 0

py -m pytest tests/test_cookbook_path_contract_regression.py tests/test_cookbook_windows_stop_tree_js.py -q
# 11 passed
```

## Files changed

- `static/js/cookbook.js` (−1 line)
- `static/js/cookbookDownload.js` (−13 lines)
- `static/js/cookbookRunning.js` (−8 lines)
- `static/js/cookbook-diagnosis.js` (−3 import lines)
- `dev_log/analysis/2026-06-25-deadcode-cleanup-frontend.md` (this file)

No commit/push per task constraints.
