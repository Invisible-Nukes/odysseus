# launch-windows.ps1 & ChromaDB Audit — 2026-06-26

## Summary

Commits `22c12d2` and `b258f50` add pip install hardening and ChromaDB auto-install/start/stop to the native Windows launcher. Paths align with `src/constants.py` (`CHROMA_DIR` = `{DATA_DIR}/chroma`). Manual E2E verified: ChromaDB connects at startup; Odysseus serves on `:7000`.

No **critical** blockers. Several **low/medium** launcher polish items remain.

## Verified OK

| Item | Detail |
|------|--------|
| Pip hardening | `Test-OdysseusDepsReady`, retries, cache purge on `IncompleteRead` |
| Chroma paths | `ODYSSEUS_DATA_DIR`, `data/chroma`, logs under `data/logs/chromadb_*.log` |
| CHROMADB_HOST/PORT | Defaults `localhost` / `8100`; matches `src/chroma_client.py` |
| Lifecycle | `Start-OdysseusChromaDb` before uvicorn; `Stop-OdysseusChromaDb` in `finally` |
| Install skip | `Ensure-ChromaDbPackage` detects `chroma.exe` / `pip show chromadb` |
| macOS parity | Same port (8100), same data dir pattern as `start-macos.sh` |
| Regression tests | **164/164 passed** (path contract, helpers, log resolver, platform, pip builder, launcher unit tests) |

## Issues found

### Medium

| Issue | Location | Notes |
|-------|----------|-------|
| `chromadb-client` + `chromadb` co-installed | `Ensure-ChromaDbPackage`; venv | macOS uninstalls client before full `chromadb` (`start-macos.sh:151-158`); Windows skips repair when `chroma.exe` exists — documented conflict risk in `docs/setup.md` |
| No `.env` load in launcher | `launch-windows.ps1` | `CHROMADB_*` / custom `ODYSSEUS_DATA_DIR` in `.env` ignored unless pre-exported; macOS loads `.env` |
| Broad process kill | `Get-OdysseusProcesses` L81–94 | Matches repo root in cmdline — kills Chroma, MCP, cookbook children on relaunch |
| Uvicorn orphaned on Ctrl+C | `finally` block | Stops Chroma only; uvicorn left running until next launch |
| `CHROMADB_HOST=0.0.0.0` skipped | L241–244 | macOS treats as local bind; Windows treats as remote |
| Logs path vs custom data dir | L51, L404 | Pip/Chroma logs hardcoded `{repo}\data\logs` even when `ODYSSEUS_DATA_DIR` relocated |
| Misleading log banner | L540–548 | `Start-Process` uvicorn does not stream logs to launcher console |

### Low

| Issue | Location | Notes |
|-------|----------|-------|
| PowerShell string repeat | L541–543 | `Write-Host "═" * 70` prints literal `* 70`; needs `Write-Host ("═" * 70)` |
| Unicode checkmarks | L516–517, L528–529 | `✓` may garble in some consoles |
| `chromadb` + `chromadb-client` | venv | Both installed (1.5.9); macOS launcher removes client before full `chromadb` — Windows does not; no observed runtime conflict |
| No automated tests | — | Launcher/Chroma functions untested in CI |
| First Chroma pip install | `Ensure-ChromaDbPackage` | Large dependency tree; ~1–2 min first run |

## Recommended fixes

| Priority | Fix | When |
|----------|-----|------|
| Defer | Fix `Write-Host ("═" * 70)` and optional ASCII status lines | Next launcher touch |
| Defer | Document "use launch-windows.ps1" for full stack (Chroma + Odysseus) | README / session log |
| Defer | Narrow `Get-OdysseusProcesses` matcher (exclude `chroma.exe` until after stop?) | Only if false kills reported |
| Defer | `ollama pull nomic-embed-text` for vector RAG embeddings | User ops |

## macOS gap vs Windows

| Feature | macOS `start-macos.sh` | Windows `launch-windows.ps1` |
|---------|------------------------|--------------------------------|
| Chroma install | Removes `chromadb-client`, installs full `chromadb` | Installs `chromadb` on demand; keeps client |
| Chroma stop | `trap` kills `$CHROMA_PID` | `finally` + `taskkill /T` |
| Chroma log | `$TMPDIR/odysseus-chromadb.log` | `data/logs/chromadb_*.log` |
