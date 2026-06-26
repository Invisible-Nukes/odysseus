# Repo Artifacts Cleanup — 2026-06-25

**Agent:** deadcode-cleanup-artifacts  
**Workspace:** `C:/odysseus`  
**Commit/push:** None (pre-commit hygiene only)

## Summary

Filesystem build/test artifacts were cleared. No orphaned debug scripts found at repo root. `scripts/hf_download.py` is live (tested). `.gitignore` extended for leftover venv and test-tooling dirs. `venv/` is absent on this machine; smoke import could not run against the intended venv.

---

## Deleted

| Artifact | Count / notes |
|----------|----------------|
| `.pytest_cache/` | Removed entirely |
| `__pycache__/` (outside venv) | 17 directories removed |
| `*.pyc` (outside venv) | 9 stray files under `src/agent_tools/__pycache__/` removed with parent dirs |
| `venv.broken/` | **Partial** — bulk removed; **29 locked files remain** (`.pyd`, `.dll`, `Scripts/python.exe`) — Access denied; likely held by another process from ENV-1 rebuild |

### Not present (no action)

- `.coverage`, `htmlcov/`, `.mypy_cache/`
- `%TEMP%/odysseus-tmux`, `%TEMP%/odysseus-sessions`
- `test_phase3_*.py` or other one-off debug scripts at repo root (referenced only in `dev_log/sessions/2026-06-23-session.md` as already removed)

---

## Orphan scan

| Item | Verdict |
|------|---------|
| Root `*.py` | Only `app.py`, `launcher.py`, `setup.py` — all legitimate |
| `test_phase3_1_api_endpoints.py`, `test_phase3_2_vision_model.py` | Not on disk |
| `scripts/hf_download.py` | **Keep** — used by `tests/test_hf_download.py`; `PipeTqdm` / `_patch_tqdm` are internal helpers, not dead exports |
| `dev_log/analysis/2026-06-25-*.md` | Kept (today's committed analysis) |
| `dev_log/sessions/2026-06-25-session.md` | Untracked session note — not deleted |

---

## `.gitignore` additions

```gitignore
venv.broken/
.pytest_cache/
.coverage
htmlcov/
.mypy_cache/
```

Existing coverage already adequate for: `__pycache__/`, `*.pyc`, `venv/`, `.env`.

---

## Git status (post-cleanup)

| Path | Status |
|------|--------|
| `.gitignore` | Modified (artifact patterns) |
| `.env` | Ignored — **not staged** ✓ |
| `dev_log/sessions/2026-06-25-session.md` | Untracked |
| `venv.broken/` | Now ignored (29 locked remnants on disk) |

No staged changes. Working tree clean aside from `.gitignore` edit and one session note.

---

## Smoke test

```
C:/odysseus/venv/Scripts/python.exe  →  NOT FOUND (venv/ absent)
```

Fallback `py -3 -c "import app"` from repo root:

```
ModuleNotFoundError: No module named 'cryptography'
```

**Verdict:** Smoke **not passed** — active venv missing on this host; system Python lacks deps. Parent coordinator should rerun after ENV-1 venv rebuild completes:

```powershell
C:/odysseus/venv/Scripts/python.exe -c "import app; print('import ok')"
```

---

## Manual follow-up

1. **Delete `venv.broken/` remnants** — close any process holding `.pyd` locks (IDE, stray Python from broken venv), then `Remove-Item -Recurse -Force C:/odysseus/venv.broken`.
2. **Rebuild `venv/`** if not already done (see `dev_log/analysis/2026-06-25-deadcode-env1.md`).
3. Re-run import smoke after venv exists.

---

## Recommended commit message (for parent coordinator)

```
chore: ignore test artifacts and venv.broken; clear build caches

Add .gitignore patterns for pytest/coverage/mypy and leftover venv.broken
from ENV-1 file-lock rebuild. Remove __pycache__ and .pytest_cache from
working tree before GitHub push.
```
