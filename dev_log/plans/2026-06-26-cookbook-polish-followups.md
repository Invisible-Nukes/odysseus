# Cookbook & Windows Polish Follow-ups — 2026-06-26

Post–Jun 26 audit plan for medium/low items **not** addressed in today's launcher commits. Jun 25 path contract remediation stands; these are follow-on polish and VM operational items.

## Workstreams

| WS | Title | Issues | Effort |
|----|-------|--------|--------|
| WS-A | Diagnosis defaultHubPath | A5-005 | S |
| WS-B | Git Bash HF path normalization | A2-10 | M |
| WS-C | hwfit llamacpp preview path | hwfit L1672 | S |
| WS-D | Windows local llama-cpp strategy | Py3.13 CPU, long paths | M — prefer Ollama |
| WS-E | Launcher cosmetic fixes | `Write-Host ("═" * 70)` | S |
| WS-F | VM E2E smoke | HF token download→serve | M |
| WS-G | Launcher lifecycle parity | chromadb-client cleanup, `.env` load, uvicorn stop in `finally` | M |

## WS-A — Diagnosis defaultHubPath (A5-005)

**Goal:** "Check HF cache size" quick-cmd uses `_defaultHubPath()` / `defaultHuggingfaceHome`, not `%USERPROFILE%\.cache\huggingface`.

**Files:** `static/js/cookbook-diagnosis.js` ~L550–552

**Verify:** Local Windows VM reports size under `C:/odysseus/data/huggingface`.

## WS-B — Git Bash backslash normalization (A2-10)

**Goal:** Windows drive paths in bash `export HF_HOME=...` use forward slashes or `git_bash_path()`.

**Files:** `routes/cookbook_helpers.py` `_shell_path()`, download wrapper in `cookbook_routes.py`

**Verify:** Git Bash detached download with explicit `local_dir` under `data/huggingface`.

## WS-C — hwfit llamacpp defaultHubPath

**Goal:** Replace `$HOME/.cache/huggingface/hub/...` in hwfit quick-run with `_defaultHubPath()`.

**Files:** `static/js/cookbook-hwfit.js` ~L1672–1674

## WS-D — Windows local llama-cpp (defer / Ollama path)

**Goal:** Do not rely on Linux source-build bootstrap for `local_windows`. Document Ollama as primary local backend on CPU-only Windows VM.

**Optional code:** Skip llama.cpp native build branch when `local_windows`; surface Ollama preset in diagnosis.

**Env blockers:** Windows Long Paths off; no cmake/MSVC; Python 3.13 no official CPU wheel.

## WS-E — Launcher cosmetics

**Goal:** Fix separator lines and optional ASCII status in `launch-windows.ps1` L516–543.

## WS-F — VM E2E smoke (carried from 2026-06-25)

**Goal:** HuggingFace download → completed → serve with HF token on Windows VM.

**Blocked on:** HF token in `.env` / UI.

## WS-G — Launcher lifecycle parity (2026-06-26 audit)

**Goal:** Align `launch-windows.ps1` with macOS: uninstall `chromadb-client` before full `chromadb`; load `.env` for `CHROMADB_*`; stop uvicorn in `finally` on Ctrl+C; fix `Write-Host ('═' * 70)`.

**Files:** `launch-windows.ps1`

**Verify:** Ctrl+C stops both uvicorn and launcher-started Chroma; vector store healthy with single chromadb package.

## Success criteria

- Path contract regression tests stay green (6/6 minimum).
- No new hardcoded `/home/pewds` or `~/.cache` in primary Cookbook flows.
- Windows VM starts via `launch-windows.ps1` with Chroma + Odysseus + Ollama paths under `data/`.

## Out of scope (unchanged)

- Upstream fork merge (`#4423` tool split high conflict risk).
- Docker/ChromaDB compose path (native Windows uses launcher Chroma).
- CUDA / GPU tooling (CPU-only VM).
