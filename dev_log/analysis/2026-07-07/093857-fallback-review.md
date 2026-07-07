---
date: 2026-07-07
time: 09:38:57
subagent_task: Fallback Review
delegation_id: deleg_99f110b3
status: completed
summary: Reviewed fallback behavior from the 2026-07-07 plan
---

# Fallback Review

## Implemented fallback-related behavior
- Hermes certifi injection is effectively disabled/prevented: `SSL_CERT_FILE`, `PIP_CERT`, `PIP_INDEX_URL`, `PIP_EXTRA_INDEX_URL` are cleared before install, and only reinstated if `certifi\cacert.pem` exists under `venv/Lib/site-packages`.
- `Install-OdysseusDependencies` uses `*>&1 | Tee-Object`, PS 5.1-compatible, with `$ErrorActionPreference` save/restore around native pip calls.
- `ConnectionResetError/10054` triggers cache purge + retry in the main install loop.
- `reset.ps1` reports exact completion status with a failure summary; no blanket `SilentlyContinue` suppression.
- `launch-windows.ps1` ends with `exit $serverExitCode`, removing the prior `4294967295` ambiguity.
- `Test-OdysseusDepsReady` skip path avoids rerunning pip when deps are already importable.

## Only described in the plan; not implemented yet
- Plain Python CLI diagnostics before pip when install fails.
- Temporary local HTTP simple-index mirror fallback for bootstrap-only scenarios.
- Explicit offline/compat mode that writes `pip install` stdout/stderr/env vars to log, prompts the user to toggle VPN/proxy/offload and retry, or falls back to a pinned/importability check when network is unavailable.

## Recommended additions
- Pre-failure diagnostics after the last retry: print current values of `SSL_CERT_FILE`, `PIP_CERT`, `PIP_INDEX_URL`, `PIP_EXTRA_INDEX_URL`, plus `python --version` and platform TLS info.
- Add a small helper like `Test-PypiReachable($venvPy)` and branch behavior based on its result.
- Augment `installLog` with env snapshot metadata so troubleshooting does not require manual reproduction.
- Optional: implement an opt-in local mirror switch and an explicit `--offline` path.
