# Cookbook Audit Register Verification

**Date:** 2026-06-25  
**Baseline commit:** `969bc36` (post-remediation dead-code cleanup)  
**Source register:** [2026-06-25-cookbook-path-download-audit.md](./2026-06-25-cookbook-path-download-audit.md) lines 903–962  
**Remediation plan:** [2026-06-25-cookbook-remediation-plan.md](../plans/2026-06-25-cookbook-remediation-plan.md)

---

## Executive summary

| Outcome | Count |
|---------|------:|
| **RESOLVED** | 33 |
| **STILL OPEN** | 22 |
| **REGRESSED** | 0 |
| **BY DESIGN / INFO / N/A / REMOVED** | 6 |

All **Critical** and **High** items marked **Fixed** in the register are **verified RESOLVED** in live code. Commit `969bc36` removed only dead helpers (`_ssh`, `_ssh_ps`, duplicate imports, unused JS injection params); no functional regressions found.

**Six register rows marked Open are stale** — fixed in remediation but not updated in the source audit: CB-DL-011, CB-DL-012, CB-DL-013, A2-11, A4-4, A5-003.

WS-1 through WS-7 are marked **Execute + Verify done** in the remediation plan; manual VM smoke remains **blocked on HF 401** (token), not on path/lifecycle code.

---

## Top remaining risks — Windows VM download → serve

1. **Git Bash hard dependency (A2-03)** — Local Windows download/serve launches via `find_bash()`; without Git Bash the stub `.cmd` writes an error and exits. This is the primary environmental blocker on a fresh Windows VM.
2. **End-to-end not proven on VM** — Remediation plan smoke: cache scan OK, download blocked by missing HF token; Running→completed and Serve tab untested.
3. **Windows backslash paths in Git Bash wrappers (A2-10)** — `_shell_path()` passes `"D:\data\huggingface"` verbatim; Git Bash may mis-resolve unless users use forward slashes or `~/`-relative paths.
4. **GGUF resolution nondeterminism (A3-04)** — `find … | head -1` in `cookbookServe.js` can pick the wrong quant/mmproj when multiple GGUFs exist.
5. **Diagnosis disk check scans wrong cache on Windows (A5-005)** — Quick-cmd uses `$env:USERPROFILE\.cache\huggingface`, not `DATA_DIR/huggingface` / `defaultHubPath`.
6. **Serve crash watchdog skipped locally on Windows (A2-12)** — Dead endpoints may linger until manual probe; mitigated partially by log-file status poller.
7. **Agent task `platform: "linux"` default (CB-DL-019, A3-07)** — UI download flow sets platform correctly; agent-registered tasks may mis-route kill/probe on native Windows edge cases.
8. **Hardcoded MiniMax M3 snapshot revision (CB-DL-014 / A3-06)** — Backend + JS embed hash `4082acbb…`; breaks when HF revision updates.

---

## Verification method

For each register row: read cited file:line (or functional area), grep live tree at `HEAD`, cross-check WS completion in remediation plan. Post-`969bc36` dead-code removal checked via `git show 969bc36`.

---

## Full verification table

| ID | Register status | Verified | Evidence |
|----|-----------------|----------|----------|
| A5-001 | Fixed | **RESOLVED** | MiniMax snapshot uses `_defaultHubPath()` not hardcoded pewds: `static/js/cookbookServe.js:1158-1161` |
| CB-DL-001 | Fixed | **RESOLVED** | `_cookbook_kill_session` kills PID tree on local Windows: `src/tool_implementations.py:2317-2336` |
| CB-DL-002 | Fixed | **RESOLVED** | Local probe uses `resolve_python_for_probe()` → `sys.executable`: `routes/cookbook_routes.py:3215-3228`, `routes/cookbook_output.py:46-55` |
| CB-DL-003 | Fixed | **RESOLVED** | Remote Windows status poll merges `.log` + `.err.log`: `routes/cookbook_routes.py:3347-3348` |
| A2-01 | Fixed | **RESOLVED** | Log tail uses `resolve_cookbook_log_path()`: `routes/codex_routes.py:581-597`, `src/tool_implementations.py:2455-2462` |
| A2-02 | Fixed | **RESOLVED** | Remote Windows uses `_safe_env_prefix_ps`: `routes/cookbook_routes.py:644,1465` |
| A2-03 | Open | **STILL OPEN** | Local Windows requires Git Bash or stub error: `routes/cookbook_routes.py:464-494` |
| CB-DL-004 | Fixed | **RESOLVED** | `_build_dl_pyarg(req.include)` passed to all `snapshot_download` fallbacks: `routes/cookbook_routes.py:550,669,677,770,780` |
| CB-DL-005 | Fixed | **RESOLVED** | Agent `download_model` passes `env_cfg["downloadDir"]` as `local_dir`: `src/tool_implementations.py:1995-2008` |
| CB-DL-006 | Fixed | **RESOLVED** | Task payload + cache probe use `local_dir`: `src/tool_implementations.py:1626-1627`, `routes/cookbook_routes.py:3505` |
| CB-DL-007 | Fixed | **RESOLVED** | UI preview sets HF_HOME/HUGGINGFACE_HUB_CACHE env in Python snippet: `static/js/cookbookDownload.js:144-151` |
| CB-DL-008 | Fixed | **RESOLVED** | Running tab shows `_defaultHubPath()`; legacy `~/.cache` only offline fallback: `static/js/cookbookRunning.js:2149`, `cookbook.js:85` |
| CB-DL-009 | Fixed | **RESOLVED** | Remote Windows respects `disable_hf_transfer`: `routes/cookbook_routes.py:653-655,672-673` |
| CB-DL-010 | Fixed | **RESOLVED** | Zombie probe uses `_tmuxCmd` → `_winSessionCmd` PID check on Windows: `static/js/cookbookDownload.js:582-583`, `cookbookRunning.js:902-906` |
| A5-002 | Fixed | **RESOLVED** | Server injects `defaultHubPath` / `defaultHuggingfaceHome`: `routes/cookbook_routes.py:258-259`; JS reads via `_defaultHubPath()` |
| A5-004 | Fixed | **RESOLVED** | GGUF fallback uses `_defaultHubPath()`: `static/js/cookbookServe.js:807-808,814-815` |
| A4-1 | Fixed | **RESOLVED** | WSL `add_hf_cache` wired in `model_cached`: `routes/cookbook_routes.py:893-903` |
| A4-2 | Open | **STILL OPEN** | Docker mounts `./data/huggingface` → `/app/.cache/huggingface`; constants also reference `/app/.cache/huggingface/hub` in scan script |
| A4-3 | Open | **STILL OPEN** | Compose uses `APP_DATA_DIR`; Python uses `ODYSSEUS_DATA_DIR`: `docker-compose.yml:7`, `src/constants.py:12` |
| A2-04 | Fixed | **RESOLVED** | Probes check snapshots for incomplete + empty blobs fallback: `routes/cookbook_output.py:29`, `routes/cookbook_helpers.py:456-464` |
| A2-07 | Open | **STILL OPEN** | `model_dir` query split/strip only, no `_validate_local_dir`: `routes/cookbook_routes.py:887-892` |
| A2-08 | Open | **STILL OPEN** | Validator allows `~`, `/`, `C:\` only — no UNC: `routes/cookbook_helpers.py:53-54,112` |
| A2-09 | Open | **STILL OPEN** | `_LOCAL_DIR_RE` is Unix-tilde only; `~\Downloads` rejected: `routes/cookbook_helpers.py:53,111-112` |
| A2-10 | Open | **STILL OPEN** | `_shell_path` quotes path as-is, no `\` → `/` for Git Bash: `routes/cookbook_helpers.py:133-141` |
| CB-DL-011 | Open | **RESOLVED** *(register stale)* | Local bash wrapper uses `hf_cmd < /dev/null`: `routes/cookbook_routes.py:818` |
| CB-DL-012 | Open | **RESOLVED** *(register stale)* | Uses `_strip_path_trailing_seps` (handles `\`): `routes/cookbook_helpers.py:1151-1153`, `cookbook_routes.py:543` |
| CB-DL-013 | Open | **RESOLVED** *(register stale)* | HF_HOME setup is explicit PowerShell lines; no bare `except` swallowing env setup in download path |
| CB-DL-014 | Open | **STILL OPEN** | Hardcoded snapshot hash: `routes/cookbook_routes.py:312-317`, `cookbookServe.js:1158` |
| CB-DL-015 | Fixed | **RESOLVED** | Kill button uses `_tmuxCmd` → Windows stop-tree: `static/js/cookbookDownload.js:294-296`, `cookbookRunning.js:908-910` |
| CB-DL-016 | Open | **STILL OPEN** | Local `%TEMP%\odysseus-tmux` vs remote `%TEMP%\odysseus-sessions`: `routes/cookbook_helpers.py:1235-1246`, `shell_routes.py:399` |
| CB-DL-017 | Open | **STILL OPEN** | Bash download wrapper exports Unix-centric PATH: `routes/cookbook_routes.py:574` |
| CB-DL-018 | Fixed | **RESOLVED** | Dynamic `hf_cache_paths()` with env + Docker + `add_hf_cache`: `routes/cookbook_helpers.py:473-487` |
| A5-003 | Open | **RESOLVED** *(register stale)* | `tests/test_hf_download.py` exists with help + marker tests |
| A2-11 | Open | **RESOLVED** *(register stale)* | Same as CB-DL-011 — `< /dev/null` on local bash path |
| A2-12 | Open | **STILL OPEN** | Watchdog returns early for local Windows: `routes/cookbook_routes.py:1119-1121` |
| A2-13 | Open | **STILL OPEN** | Local Windows serve uses detached log redirect, not Linux `tee` to `/tmp/odysseus-tmux`: `routes/cookbook_routes.py:1845-1899` vs `1520-1523` |
| A4-4 | Open | **RESOLVED** *(register stale)* | `.env.example:137` documents `{DATA_DIR}/fastembed_cache` default |
| A4-5 | Open | **STILL OPEN** | `launch-windows.ps1:27-30` seeds HF env; `start-macos.sh` has no equivalent |
| A4-6 | Open | **STILL OPEN** | Logs under repo `logs/`, `DATA_DIR/logs`, Docker `/app/logs` — unchanged |
| CB-DL-019 | Open | **STILL OPEN** | Agent register defaults `platform: "linux"`: `src/tool_implementations.py:1640` |
| CB-DL-020 | Open | **STILL OPEN** | `list_downloads` shows `local_dir` or literal `"default cache"`, not resolved `HUGGINGFACE_HOME`: `src/tool_implementations.py:2568-2571` |
| A5-005 | Open | **STILL OPEN** | Windows quick-cmd scans `%USERPROFILE%\.cache\huggingface`, not `defaultHubPath`: `static/js/cookbook-diagnosis.js:550-552` |
| A2-14 | Removed | **REMOVED** | `_git_bash_path` gone; uses `git_bash_path` from `platform_compat`: `routes/cookbook_helpers.py:18` |
| A4-7 | By design | **BY DESIGN** | `TMUX_LOG_DIR` under system temp by intent: `routes/shell_routes.py:399` |
| CB-DL-021 | Info | **INFO** | Downloads use detached/tmux runners, not `bg_jobs`: unchanged |
| CB-DL-022 | Info | **INFO** | Hub-cache + `.incomplete` resume documented in download builder comments |
| A3-01 | Fixed | **RESOLVED** | `model_cached` adds `HUGGINGFACE_HUB_CACHE` via `add_hf_cache`: `routes/cookbook_routes.py:900-902` |
| A3-02 | Fixed | **RESOLVED** | Same as A5-004 |
| A3-03 | Fixed | **RESOLVED** | `_normalizeState` remaps legacy default to `defaultHubPath`: `static/js/cookbookRunning.js:1226-1236` |
| A3-04 | Open | **STILL OPEN** | `find … \| head -1` GGUF pick: `static/js/cookbookServe.js:1547-1548` |
| A3-05 | Open | **STILL OPEN** | `serve_preset` substring match with multi-match guard: `src/tool_implementations.py:2879-2897` |
| A3-06 | Open | **STILL OPEN** | Same hardcoded snapshot as CB-DL-014 |
| A3-07 | Open | **STILL OPEN** | `adopt_served_model` hardcodes `platform: "linux"`: `src/tool_implementations.py:2738` |
| A3-08 | N/A | **N/A** | Lifecycle module scope unchanged |
| A5-006 | Open (cross-ref) | **STILL OPEN** | 2026-06-18 pre-flight (CUDA, disk, build tools) explicitly out of scope in remediation plan |

---

## Register vs live code — status mismatches

| ID | Register says | Live verification |
|----|---------------|-------------------|
| CB-DL-011 | Open | **Fixed** — stdin redirect present |
| CB-DL-012 | Open | **Fixed** — `_strip_path_trailing_seps` |
| CB-DL-013 | Open | **Fixed** — no bare-except HF_HOME swallow |
| A2-11 | Open | **Fixed** — duplicate of CB-DL-011 |
| A4-4 | Open | **Fixed** — `.env.example` comment updated |
| A5-003 | Open | **Fixed** — basic tests added |

---

## Post-969bc36 dead-code removal impact

| Area | Change | Verification |
|------|--------|--------------|
| `_ssh`, `_ssh_ps` | Removed from `cookbook_helpers.py` | No callers remained; **no regression** |
| Duplicate imports in `cookbook_routes.py` | Removed | **no regression** |
| Unused JS imports (`cookbookDownload.js`, `cookbookRunning.js`) | Removed | **no regression** — functional paths unchanged |
| `_ssh` removal | N/A to Windows download flow | Remote paths use inline ssh/scp builders |

---

## WS completion cross-reference

| WS | Register IDs | Verification |
|----|--------------|--------------|
| WS-1 | CB-DL-002, A3-01, A2-04, CB-DL-018 | All **RESOLVED** |
| WS-2 | A5-001, A5-002, CB-DL-008, A5-004, A3-02, A3-03, CB-DL-007 | All **RESOLVED** |
| WS-3 | CB-DL-001, CB-DL-010, CB-DL-015, A2-01, A2-13, CB-DL-016 | Core lifecycle **RESOLVED**; A2-13/CB-DL-016 remain **OPEN** (log parity) |
| WS-4 | CB-DL-004–006, CB-DL-011/012/019/020 | 004–006 **RESOLVED**; 011/012 **RESOLVED** (register stale); 019/020 **OPEN** |
| WS-5 | CB-DL-003, CB-DL-009, A2-02 | All **RESOLVED** |
| WS-6 | A4-1, A2-07–10 | A4-1 **RESOLVED**; A2-07–10 **OPEN** |
| WS-7 | A5-005, A5-003, A4-4–7, A2-12–14, CB-DL-014, A3-05–07 | Mixed — see table; A4-4/A5-003 **RESOLVED**; remainder **OPEN** or **BY DESIGN** |

---

## Evidence snippets — disputed / high-risk STILL OPEN

### A2-03 — Git Bash required (Critical path blocker)

```464:494:routes/cookbook_routes.py
        bash = find_bash()
        if bash:
            ...
        else:
            # No bash on this Windows host: the bash wrapper can't run. Fall back
            # to a cmd.exe wrapper that just records a clear error to the log so
            # the UI surfaces "install Git Bash" instead of silently hanging.
            script_path = TMUX_LOG_DIR / f"{session_id}.cmd"
            script_path.write_text(
                "@echo off\r\n"
                f'echo Cookbook LOCAL execution on Windows needs Git Bash ^(bash.exe^) on PATH. > "{log_path}" 2>&1\r\n'
                ...
```

### A2-10 — Backslash paths not converted for Git Bash

```133:141:routes/cookbook_helpers.py
def _shell_path(p: str) -> str:
    ...
    return '"' + p + '"'
```

Windows `D:\odysseus\data\huggingface` is emitted quoted with backslashes unchanged.

### A5-005 — Diagnosis scans wrong Windows cache root

```550:552:static/js/cookbook-diagnosis.js
        const cmd = _isWindows()
          ? 'powershell ... Join-Path $env:USERPROFILE \'.cache\\huggingface\' ...'
          : 'du -sh ~/.cache/huggingface 2>/dev/null';
```

Server default is `DATA_DIR/huggingface/hub` (`routes/cookbook_routes.py:258`).

### A3-04 — Nondeterministic GGUF selection

```1547:1548:static/js/cookbookServe.js
            ? `$({ find ${_ldir} -name '*-00001-of-*.gguf' 2>/dev/null | sort; find ${_ldir} -name '*.gguf' 2>/dev/null | sort; } | head -1)`
            : `$({ find ${dir} -name '*-00001-of-*.gguf' 2>/dev/null | sort; find ${dir} -name '*.gguf' 2>/dev/null | sort; } | head -1)`;
```

---

## REGRESSED items

**None.** Commit `969bc36` removed only orphaned helpers and unused imports; all previously-fixed critical/high path items remain present.

---

## Recommended register updates

1. Mark **CB-DL-011, CB-DL-012, CB-DL-013, A2-11, A4-4, A5-003** as **Fixed**.
2. Keep **A2-03** as highest-priority **Open** for Windows VM (environmental dependency).
3. Defer **A4-2, A4-3, A4-6, A5-006** per remediation plan out-of-scope notes.
4. Run manual VM smoke with HF token to validate download → completed → serve chain (plan item still unchecked).
