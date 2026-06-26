# ENV-1 — Wipe, Rebuild, and Storage Lock

**Date:** 2026-06-25  
**Workspace:** `C:/odysseus`

## .env created

New `C:/odysseus/.env` with explicit paths under repo data tree:

```
ODYSSEUS_DATA_DIR=C:/odysseus/data
HF_HOME=C:/odysseus/data/huggingface
HUGGINGFACE_HUB_CACHE=C:/odysseus/data/huggingface/hub
OLLAMA_HOME=C:/odysseus/data/ollama
FASTEMBED_CACHE_PATH=C:/odysseus/data/fastembed_cache
```

## TMUX / temp session dirs

- `TMUX_LOG_DIR` (`routes/shell_routes.py:399`) remains `%TEMP%/odysseus-tmux` — **by design** (A4-7); not moved under `DATA_DIR` (runtime temp, wiped on clean rebuild).
- Wiped: `%TEMP%/odysseus-tmux`, `%TEMP%/odysseus-sessions`.

## Wipe executed

| Target | Result |
|--------|--------|
| `venv/` | Removed (recreated; old tree renamed to `venv.broken` after file lock) |
| `__pycache__/` | Cleared recursively |
| `.pytest_cache/` | Removed |
| `data/huggingface/` | Removed |
| `data/chroma/` | Removed |
| `data/fastembed_cache/` | Not present pre-wipe |
| `data/logs/` | Removed |
| `logs/` | Removed |
| `data/cookbook_state.json` | Not present |
| `data/bg_jobs*` | Not present |
| `models/` | Not present |
| `%TEMP%/odysseus-tmux` | Removed |
| `%TEMP%/odysseus-sessions` | Not present |

**Note:** Initial edits failed with `SQLITE_FULL`; wipe freed disk (~venv + huggingface cache).

## Rebuild

```
py -3 -m venv C:/odysseus/venv
C:/odysseus/venv/Scripts/pip.exe install -r requirements.txt
```

**Status:** Success (after renaming locked `venv/` → `venv.broken`).

## Smoke-start

```
uvicorn app:app --host 127.0.0.1 --port 7000  (AUTH_ENABLED=false)
```

| Check | Result |
|-------|--------|
| `GET /api/health` | **200** `{"status":"healthy",...}` |
| ChromaDB at startup | Expected warning (no docker chromadb) — non-blocking |
| Path contract | Pending manual UI check; `.env` + constants align to `C:/odysseus/data/huggingface/hub` |

## Blockers

1. **Disk was full** at start — resolved by wipe.
2. **`venv/` file lock** on `rpds.cp313-win_amd64.pyd` — resolved by renaming broken venv.
3. **`venv.broken/`** left on disk (locked partial tree) — safe to delete manually when no process holds handles.
4. **ChromaDB** not running — expected for native Windows smoke; RAG lazy-retries.
