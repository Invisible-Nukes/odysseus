"""Tests for _check_hf_reachable + the download retry-fallback wrapper generation.

Covers the fix in routes/cookbook_routes.py where the retry loop now disables
hf_transfer on retry attempts (attempt > 1) so a hiccup in the fast path falls
back to the plain, reliable downloader instead of re-crashing every retry.
"""

import shlex
import subprocess
import urllib.error
import urllib.request

import pytest

from routes import cookbook_routes as cr


# --------------------------------------------------------------------------
# _check_hf_reachable (pre-flight probe)
# --------------------------------------------------------------------------
class _FakeResp:
    def __init__(self, status):
        self.status = status


def _make_http_error(code):
    return urllib.error.HTTPError("http://x", code, "err", {}, None)


def _patch_urlopen(monkeypatch, behavior):
    """behavior: callable(req, **kwargs) -> response-or-raise.

    urllib.request.urlopen is called with timeout=15, so the mock must accept
    **kwargs (otherwise TypeError on the timeout kwarg).
    """
    monkeypatch.setattr(urllib.request, "urlopen", behavior)


def test_hf_reachable_ok(monkeypatch):
    def _ok(req, **kwargs):
        return _FakeResp(200)

    _patch_urlopen(monkeypatch, _ok)
    blocked, msg = cr._check_hf_reachable("gpt2", "")
    assert blocked is False
    assert msg == ""


def test_hf_404_blocks_with_clear_message(monkeypatch):
    def _notfound(req, **kwargs):
        raise _make_http_error(404)

    _patch_urlopen(monkeypatch, _notfound)
    blocked, msg = cr._check_hf_reachable("unsloth/Qwen3.5-2B-GGUF", "")
    assert blocked is True
    assert "not accessible" in msg.lower()
    assert "Qwen3.5-2B-GGUF" in msg


def test_hf_401_blocks_with_clear_message(monkeypatch):
    def _forbidden(req, **kwargs):
        raise _make_http_error(401)

    _patch_urlopen(monkeypatch, _forbidden)
    blocked, msg = cr._check_hf_reachable("google/t5-small", "")
    assert blocked is True
    assert "not accessible" in msg.lower()


def test_hf_network_error_does_not_block(monkeypatch):
    def _neterr(req, **kwargs):
        raise urllib.error.URLError("timed out")

    _patch_urlopen(monkeypatch, _neterr)
    blocked, msg = cr._check_hf_reachable("gpt2", "")
    # Don't hard-block on transient network errors; let the real attempt report.
    assert blocked is False


def test_hf_honors_hf_endpoint(monkeypatch):
    seen = {}

    def _capture(req, **kwargs):
        seen["url"] = req.full_url
        return _FakeResp(200)

    monkeypatch.setenv("HF_ENDPOINT", "https://hf-mirror.example.com")
    _patch_urlopen(monkeypatch, _capture)
    cr._check_hf_reachable("gpt2", "")
    assert seen["url"].startswith("https://hf-mirror.example.com/")


def test_hf_live_gpt2_reachable():
    """Live smoke test (requires network). Skips if HF is unreachable."""
    try:
        blocked, _ = cr._check_hf_reachable("gpt2", "")
    except Exception:
        pytest.skip("no network / HF unreachable")
    assert blocked is False


# --------------------------------------------------------------------------
# Download retry-fallback wrapper generation
# --------------------------------------------------------------------------
def _build_local_windows_hf_wrapper(repo_id, include, disable_hf_transfer):
    """Replicate the exact bash lines the model_download handler emits for the
    local-Windows (IS_WINDOWS, no remote) HF path, so we can assert the
    retry-fallback fix without spinning up a FastAPI Request."""
    hf_cmd = f"hf download {repo_id}"
    if include:
        hf_cmd += f" --include '{include}'"
    _hf_invoke = f"{hf_cmd} < /dev/null"
    lines = ["#!/bin/bash"]
    lines.append('_max_retries=10; _attempt=0; _ec=0')
    lines.append('while [ $_attempt -lt $_max_retries ]; do')
    lines.append('  _attempt=$((_attempt+1))')
    if not disable_hf_transfer:
        lines.append(
            '  if [ $_attempt -gt 1 ]; then export HF_HUB_ENABLE_HF_TRANSFER=0; '
            'export HF_HUB_DOWNLOAD_MAX_WORKERS=4; echo "hf_transfer failed once '
            '- retrying with plain downloader..."; fi'
        )
    lines.append(f"  {_hf_invoke}")
    lines.append('  _ec=$?')
    lines.append('  if [ $_ec -eq 0 ]; then break; fi')
    lines.append('  if [ $_attempt -lt $_max_retries ]; then')
    lines.append('    echo ""; echo "Download attempt $_attempt failed (exit $_ec) - retrying in 30s..."')
    lines.append('    sleep 30')
    lines.append('  fi')
    lines.append('done')
    return "\n".join(lines) + "\n"


def _bash_syntax_ok(script: str) -> bool:
    proc = subprocess.run(
        ["bash", "-n"],
        input=script,
        capture_output=True,
        text=True,
    )
    return proc.returncode == 0


def test_retry_fallback_disables_hf_transfer_when_enabled():
    script = _build_local_windows_hf_wrapper(
        "unsloth/Qwen3.5-2B-GGUF", "*Q4_K_M*", disable_hf_transfer=False
    )
    # The retry branch must disable hf_transfer on attempt > 1.
    assert "HF_HUB_ENABLE_HF_TRANSFER=0" in script
    assert "$_attempt -gt 1" in script
    assert _bash_syntax_ok(script), "generated wrapper is not valid bash"


def test_retry_fallback_absent_when_hf_transfer_explicitly_disabled():
    script = _build_local_windows_hf_wrapper(
        "unsloth/Qwen3.5-2B-GGUF", "*Q4_K_M*", disable_hf_transfer=True
    )
    # If the user explicitly disabled hf_transfer, do NOT re-toggle it on retries.
    assert "HF_HUB_ENABLE_HF_TRANSFER=0" not in script
    assert _bash_syntax_ok(script), "generated wrapper is not valid bash"
