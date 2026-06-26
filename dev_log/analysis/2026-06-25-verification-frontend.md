# Frontend Verification — Dead-Code Removal (969bc36)

**Date:** 2026-06-25  
**Agent:** FRONTEND VERIFICATION  
**Commit under test:** `969bc363641b4e402ce9023aee420e2dedf9b794`  
**Baseline audits:** `2026-06-25-cookbook-path-download-audit.md`, `2026-06-25-deadcode-cleanup-frontend.md`

## Verdict

**PASS** — JS dead-code removals in 969bc36 did **not** regress the Cookbook UI path contract, serve GGUF resolution, download preview, or Windows lifecycle helpers. Prior audit frontend fixes remain intact.

| Gate | Result |
|------|--------|
| Broken references to removed symbols | **PASS** — none found |
| Path contract (`_defaultHubPath`, HF env preview, legacy migration) | **PASS** |
| Audit fixed items (A5-001/002/004, CB-DL-007/008/010/015, A3-02/03) | **PASS** — still fixed |
| `node --check` (6 cookbook JS files) | **PASS** — exit 0 |
| `pytest` path-contract + Windows stop-tree | **PASS** — 11 passed |

---

## 1. Removed-symbol reference check (969bc36)

### Removed in commit

| File | Removed |
|------|---------|
| `cookbookDownload.js` | `_defaultHubPath` import; `_getPlatform`, `_detectBackend`, `_detectToolParser`, `modelLogo`, `esc`; `SERVE_STATE_KEY`; corresponding `initDownload` assignments |
| `cookbookRunning.js` | `_detectBackend`, `_detectToolParser`, `_detectModelOptimizations`, `_buildServeCmd`; corresponding `initRunning` assignments |
| `cookbook-diagnosis.js` | imports `_removeTask`, `_buildEnvPrefix`, `_tmuxCmd` |
| `cookbook.js` | unused `SERVE_STATE_KEY` constant |

### Grep result — no dangling references

| Symbol | `cookbookDownload.js` | `cookbookRunning.js` | `cookbook-diagnosis.js` |
|--------|----------------------|----------------------|-------------------------|
| `_getPlatform` | absent (was never used) | live via `initRunning` | n/a |
| `_detectBackend` / `_detectToolParser` | absent | absent | n/a |
| `_detectModelOptimizations` / `_buildServeCmd` | n/a | absent | n/a |
| `modelLogo` / `esc` | absent | live (task cards) | n/a |
| `SERVE_STATE_KEY` | absent | live (`cookbookRunning.js:364`) | n/a |
| `_removeTask` / `_buildEnvPrefix` / `_tmuxCmd` | n/a | n/a | absent |

**Conclusion:** Removals were safe; live symbols remain wired through `cookbook.js` → `shared` → module `init*` or direct imports (`cookbook-hwfit.js`, `cookbookServe.js`).

---

## 2. Path contract trace

### `_defaultHubPath()` — shared helper

```85:85:static/js/cookbook.js
export function _defaultHubPath() { return (_envState.defaultHubPath || '').trim() || '~/.cache/huggingface/hub'; }
```

Server injects authoritative paths via `/api/cookbook/state`:

- `env.defaultHubPath` ← `HUGGINGFACE_HUB_CACHE`
- `env.defaultHuggingfaceHome` ← `HUGGINGFACE_HOME`

| Module | Usage | Status |
|--------|-------|--------|
| `cookbook.js` | Server profile defaults, model dir chips | Uses `_defaultHubPath()`; offline fallback `~/.cache/huggingface/hub` only when server path unset |
| `cookbookServe.js` | `_selectedGgufExpr`, `_ggufSearchDirExpr`, MiniMax snapshot, cached scan query | Uses `_defaultHubPath()` — **no pewds path** |
| `cookbookRunning.js` | Download task dir display (`payload.local_dir \|\| _defaultHubPath()`) | Fixed (CB-DL-008) |
| `cookbook-hwfit.js` | Server add/blank profiles, modelDirs normalization | Uses `_defaultHubPath()`; **exception:** llamacpp cmd preview line 1672 still hardcodes `$HOME/.cache/...` (pre-existing, open) |

### No pewds paths

Grep across `static/js/cookbook*.js`: **zero** `/home/pewds` hits. Only benign comment at `cookbook.js:2729`.

MiniMax M3 snapshot now backend-aligned:

```1158:1158:static/js/cookbookServe.js
      const _minimaxM3Snapshot = `${_defaultHubPath().replace(/\/+$/, '')}/models--cyankiwi--MiniMax-M3-AWQ-INT4/snapshots/4082acbbec1236d21828d55b6bb0fe02ade4ab5b`;
```

### Download preview — HF_HOME layout (CB-DL-007)

`_buildDownloadCmd` sets `HF_HOME`, `HUGGINGFACE_HUB_CACHE`, `HF_HUB_CACHE` and calls `snapshot_download(repo)` **without** `local_dir=`. No `local_dir=os.path.expanduser` in any cookbook JS file.

### `initDownload` + `_tmuxCmd` (CB-DL-010, CB-DL-015)

```3190:3197:static/js/cookbook.js
initDownload({
  ...shared,
  _tmuxCmd,
  _addTask,
  _renderRunningTab,
  _loadTasks,
  _saveTasks,
});
```

- Zombie duplicate probe: `_tmuxCmd(_zTask, \`has-session -t …\`)` — platform-aware via `_winSessionCmd` on Windows
- Hwfit output kill: `_tmuxCmd(task, \`kill-session -t …\`)` — no raw `tmux kill-session` string

### `_normalizeState` legacy migration (A3-03)

```1226:1236:static/js/cookbookRunning.js
    const LEGACY_DEFAULT = '~/.cache/huggingface/hub';
    const hubDefault = ((state.env.defaultHubPath) || '').trim() || LEGACY_DEFAULT;
    ...
        .map(d => (d === LEGACY_DEFAULT ? hubDefault : d));
      if (!dirs.includes(hubDefault)) dirs.unshift(hubDefault);
```

Intentional: migrates persisted `~/.cache/huggingface/hub` entries to server `defaultHubPath`; offline-only fallback when server path absent.

### Windows lifecycle

- `_tmuxCmd` → `_winSessionCmd` for local/remote Windows (`cookbookRunning.js:880+`)
- `_winSessionStopTreePs` / recursive `Stop-Tree` unchanged by 969bc36
- Regression tests confirm JS helper parity with Python `win_session_stop_tree_ps`

---

## 3. Prior audit fixed items — re-verified

| ID | Title | Status after 969bc36 |
|----|-------|----------------------|
| **A5-001** | MiniMax M3 pewds path in Serve UI | **Still fixed** — `_defaultHubPath()` snapshot |
| **A5-002** | JS defaults vs `DATA_DIR/huggingface` | **Still fixed** — server-injected `defaultHubPath` + `_defaultHubPath()` |
| **A5-004** | Serve GGUF `$HOME/.cache` fallback | **Still fixed** — `_selectedGgufExpr` / `_ggufSearchDirExpr` use `_defaultHubPath()` |
| **CB-DL-007** | Download preview flat `local_dir` | **Still fixed** — HF env + `snapshot_download(repo)` |
| **CB-DL-008** | Running tab shows wrong default dir | **Still fixed** — `_defaultHubPath()` in task card |
| **CB-DL-010** | Zombie probe tmux-only | **Still fixed** — `_tmuxCmd` + `_downloadSessionTask` |
| **CB-DL-015** | Hwfit kill tmux-only | **Still fixed** — `_tmuxCmd` kill path |
| **A3-02** | Serve GGUF hardcoded `$HOME/.cache` | **Still fixed** (same as A5-004) |
| **A3-03** | `_normalizeState` legacy hub path | **Still fixed** — `LEGACY_DEFAULT` migration |

---

## 4. Still-open issues (unchanged by dead-code pass)

| ID | Severity | Issue | Location |
|----|----------|-------|----------|
| **A5-005** | Low | Diagnosis "Check HF cache size" uses Unix `du -sh ~/.cache/huggingface` on non-Windows branch | `cookbook-diagnosis.js:552` (Windows branch uses `USERPROFILE\.cache` — OK) |
| **hwfit stale path** | Medium | HWFit llamacpp quick-run preview hardcodes `"$HOME/.cache/huggingface/hub/models--…"` | `cookbook-hwfit.js:1672` |
| **A3-04** | Medium | `find \| head -1` may pick wrong GGUF quant | `cookbookServe.js`, `cookbook-hwfit.js` |
| **A2-03** | High | Git Bash required for local Windows download/serve | backend |
| **CB-DL-011+** | Medium/Low | Various backend/platform gaps (stdin redirect, agent platform, log dirs) | see audit register |

Note: `~/.cache/huggingface/hub` and `$HOME/.cache/...` strings that remain are **intentional** offline/legacy fallbacks or remote-SSH bash targets — not primary Windows-native defaults when server state is loaded.

---

## 5. Automated checks

### `node --check`

```
static/js/cookbook.js
static/js/cookbookRunning.js
static/js/cookbookServe.js
static/js/cookbookDownload.js
static/js/cookbook-hwfit.js
static/js/cookbook-diagnosis.js
```

All exit **0**.

### Pytest

```
py -m pytest tests/test_cookbook_path_contract_regression.py tests/test_cookbook_windows_stop_tree_js.py -q
```

**11 passed** (6 path-contract source guards + 5 Windows stop-tree / agent-kill guards).

Key assertions still satisfied:

- No `/home/pewds` in cookbook JS
- `_defaultHubPath()` exported and used in serve MiniMax path
- Download preview uses `HUGGINGFACE_HUB_CACHE` / `defaultHuggingfaceHome`, not `local_dir=`
- Zombie probe/kill use `_tmuxCmd`, not bare `tmux kill-session`

---

## 6. Regressions from 969bc36

**None identified.**

The commit removed only zero-reference injection parameters, duplicate storage keys, and unused imports. Live wiring for path contract (`_defaultHubPath`, server env injection), download preview (HF env), serve GGUF resolution, `_tmuxCmd` Windows branching, and `_normalizeState` migration is unchanged in behavior.

---

## 7. Recommendations (out of scope for this verification)

1. Fix `cookbook-hwfit.js:1672` to use `_defaultHubPath()` (align with serve/download contract).
2. Consider `_defaultHubPath()`-based diagnosis cache check on Unix instead of hardcoded `~/.cache` (A5-005 partial fix).
3. No action needed on 969bc36 dead-code removals — safe to keep.

No commit/push performed per task constraints.
