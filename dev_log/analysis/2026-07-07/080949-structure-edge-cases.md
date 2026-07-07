---
date: 2026-07-07
time: 08:49:39
subagent_task: Overall Codebase Structure + Edge Case Analysis
delegation_id: deleg_dae230c1
status: completed
summary: Surveyed repo structure and edge cases for Windows launch/install paths
---

# Overall Codebase Structure

- Startup path: `launch-windows.ps1` is the primary Windows flow. It hardcodes Python discovery to local candidates, creates/recreates `venv`, sanitizes `sys.path`, installs deps, runs `setup.py`, then starts the app via uvicorn.
- Portable build path: `build-windows-portable.ps1` wraps `launcher.py` with PyInstaller and bundles `static`, `scripts`, `mcp_servers`, `services/hwfit/data`, and `.env.example`. It does not currently harden pip TLS handling or Hermes-separation logic.
- Path isolation: `venv\Lib\site-packages\sitecustomize.py` strips Hermes Agent prefixes from `sys.path` to avoid cross-interpreter contamination during local runs.
- Runtime layout: `core/`, `mcp_servers/`, and `scripts/` are the main Python behaviors. Persistent state lives under `data/` with SQLite DBs, auth state, and logs.

# Edge Case Analysis

- Windows startup/reset risk from SIGINT: `launch-windows.ps1` contains repeated `Stop-OdysseusProcesses` force-kills. On a sensitive Windows startup/reset path, forced `Stop-Process`/`taskkill` during boot-time scripted runs can interact badly with hung or partially-spawned services.
- venv Hermes contamination: creation guard in the launcher checks `venvHome` for Hermes paths and recreates the venv when detected. Data already written under `data/` from a contaminated run may persist and affect subsequent fresh runs.
- PATH sanitization side effect: the launcher strips `Programs\Python`/`WindowsApps`/`Git\bin`; users relying on system scripts from these paths lose them for the spawned process tree until PATH is restored after restart.
- Launch-Windows installer plays tug-of-war with pip retries and trusted-hosts: current logic retries 3 times, but trusted hosts are hardcoded to public PyPI; a resolver/DNS split between PowerShell and Python often shows up only as intermittent packet-reset during package metadata fetch.
- Reset/reinstall escape hatch: `setup.py` and first-run setup writing are invoked only via venv Python; on a failed install before dep readiness, rerun must clean `venv` manually to avoid retrying against Hermes-corrupted prefix/cert state.
- PyPI TLS reset diagnosis — likely root cause: pip's outbound stack here is urllib3 + pip's vendored truststore/certifi, not WinHTTP. The same network path reaches PyPI fine from PowerShell but is hard-reset from Python, which strongly points to TLS trust-store handling rather than a real connectivity outage. Candidate triggers include inheriting Hermes Agent's `certifi` venv file into corrupted / absent state, Schannel/OpenSSL mismatch on Windows, or an offloading proxy/firewall that resets only Python TLS sessions.
- Impossible workarounds: you cannot make `Invoke-WebRequest` fix pip's internal certificate verification; its success is evidence that the network is reachable but is not transferable to Python's SSL stack. Similarly, `--trusted-host` only skips hostname checking for index URL access; it does not bypass cert verification when the index link returns HTTPS wheel/sdist links to files.pythonhosted.org. Changing plain HTTP index mirrors is unsafe and increasingly unsupported by PyPI.
- Preferred next actions: 1) determine and sanity-check the env vars `SSL_CERT_FILE`, `PIP_CERT`, and `PIP_INDEX_URL` in the exact shell where the launcher runs; 2) reproduce with `python.exe -I -m pip install --no-cache-dir fastapi` to isolate venv/system env; 3) if Hermes `certifi` exists but is corrupt or missing, remove the explicit `SSL_CERT_FILE` assignment or replace it with the venv's own `certifi\\cacert.pem`; 4) if the issue is network offloading, consider temporarily toggling WiFi offload/proxy for the test.
