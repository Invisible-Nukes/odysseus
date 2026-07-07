---
date: 2026-07-07
time: 08:49:36
subagent_task: Path Analysis
delegation_id: deleg_f3bd9835
status: completed
summary: Analyzed the install/retry path in launch-windows.ps1
---

# Path Analysis

- Shared log path: `$installLog` under `PSScriptRoot\data\logs\pip_install_<ts>.log` is used for both `pip upgrade` and `pip install -r requirements.txt`. Each step's retry reads the same file's tail, so the second step can surface the first step's tail on failure and obscure which phase actually failed.
- Cache-corrupt detection is narrow: retry triggers only on `IncompleteRead`, `Connection broken`, `ContentDecodingError`, `hash mismatch`. A `ConnectionResetError(10054)` to `https://pypi.org/simple/fastapi/` does not match, so the script falls through to `Fail` immediately instead of purging cache and retrying.
- Retry loop does not reset `$LASTEXITCODE` after `tee`-style redirection with `*>`: if a retry succeeds but the statement still leaves a nonzero `$LASTEXITCODE`, the outer `if ($LASTEXITCODE -ne 0)` check after the loop can fail an otherwise successful step.
- Working directory: `Set-Location $PSScriptRoot` makes `requirements.txt` resolution implicit; if re-launched from another directory without script-relative context, relative paths can break during manual rerun or scripted wrapper.
- Log/temp isolation: no temp file for pip output; `pip cache purge` writes/shared state under the default per-user cache directory outside the repo-managed `ODYSSEUS_DATA_DIR`, leaving stale cache/hashes that survive script reruns despite the `--retries 5 --timeout 120` pip flags.
- Trusted-host allowlist: hardcoded hosts are pip-level args and do not set environment-wide trust; if the actual failure is mirrored index/CDN behavior, the host list provides misleading reassurance but no fallback mirror logic.
- Output redirection suppresses stderr/stdout interaction: `*>` captures all streams, so transient TLS cert or proxy diagnostics are not surfaced interactively; only the final 30 tail lines are printed.
- SSL cert fallback points at Hermes Agent's `certifi\cacert.pem`; if that venv is absent, no alternative cert is set. Network/TLS-FIPS/OpenSSL issues therefore alias into ordinary pip install failures.
- No preflight check for disk space or write access under `PSScriptRoot\data\logs` before redirecting output; a logged-on User vs elevated-run mismatch can cause the install step to fail with an inaccessible path that is then misattributed to PyPI.
