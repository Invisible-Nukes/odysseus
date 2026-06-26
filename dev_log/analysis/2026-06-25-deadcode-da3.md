# DA-3 — Frontend JS Dead-Code Audit

**Commit:** bd7106e  
**Files:** `static/js/cookbook.js`, `cookbookRunning.js`, `cookbookServe.js`, `cookbookDownload.js`, `cookbook-hwfit.js`, `cookbook-diagnosis.js`

## Method

Compared bd7106e JS diffs; grepped for seed patterns (`~/.cache`, `$HOME/.cache`, pewds, tmux-only branches).

## Candidates

| Pattern | Location | Classification | Action |
|---------|----------|----------------|--------|
| `/home/pewds` hardcodes | all cookbook JS | **Removed in bd7106e** — regression test guards | Already gone |
| `_defaultHubPath()` + server `defaultHubPath` | `cookbook.js:86` | **Live** — canonical path helper; `~/.cache/...` is offline fallback only | Keep |
| `LEGACY_DEFAULT` / `~/.cache/huggingface/hub` in `_normalizeState` | `cookbookRunning.js:1230-1231` | **Live migration** — maps legacy stored paths to server default | Keep |
| `~/.cache/huggingface/hub` equality checks | `cookbook.js`, `cookbookServe.js`, `cookbook-hwfit.js` | **Live** — detects legacy persisted server entries | Keep |
| `$HOME/.cache/huggingface/hub` in hwfit llamacpp cmd | `cookbook-hwfit.js:1672` | **Live stale path** (not dead) — HWFit preview still uses Unix default; bd7106e did not touch this line | Keep (behavior fix out of scope) |
| `_tmuxCmd` / `_winSessionCmd` | `cookbookRunning.js:884+` | **Live** — Windows parity added in bd7106e | Keep |
| tmux-only fallback when `!_tmuxCmd` | `cookbookDownload.js:592-594` | **Orphaned branch** — `initDownload` always injects `_tmuxCmd` from `cookbook.js:3193` | **Remove** fallback; require `_tmuxCmd` |
| tmux-only hwfit kill (pre-bd7106e) | `cookbookDownload.js:285+` | **Replaced** by `_tmuxCmd` kill in bd7106e | Already fixed |
| `$HOME/.cache` serve fallback | `cookbookServe.js:807-815` | **Removed in bd7106e** — uses `_defaultHubPath()` | Already gone |
| powershell fallback in non-Windows diagnosis cmd | `cookbook-diagnosis.js:555` else branch | **Orphaned** — copy-paste artifact; Unix branch never needs PowerShell | **Remove** `|| powershell ...` from else branch |
| Windows diagnosis cache check USERPROFILE | `cookbook-diagnosis.js:554` | **Live stale** — checks `~/.cache` not `DATA_DIR/huggingface` | Keep (ENV/path fix out of scope) |
| pewds comment | `cookbook.js:2730` | **Comment only** — not executable | Keep |

## Removal list (DA-3)

1. `cookbookDownload.js` — drop tmux-only `: \`tmux has-session...\`` fallback; use `_tmuxCmd` directly
2. `cookbook-diagnosis.js` — simplify non-Windows HF cache size cmd to `du -sh ~/.cache/huggingface 2>/dev/null` only

## Ambiguous — keep

- All `~/.cache/huggingface/hub` legacy migration strings — still referenced for persisted state normalization.
- `cookbook-hwfit.js:1672` `$HOME/.cache` — active code path, needs separate behavior fix.
