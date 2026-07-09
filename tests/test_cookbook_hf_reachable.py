"""Tests for _check_hf_reachable: pre-flight HuggingFace repo reachability probe."""

import urllib.error
import urllib.request

import pytest

from routes import cookbook_routes as cr


class _FakeResp:
    def __init__(self, status):
        self.status = status


def _make_http_error(code):
    return urllib.error.HTTPError("http://x", code, "err", {}, None)


def _patch_urlopen(monkeypatch, behavior):
    """behavior: callable(urlopen_request, **kwargs) -> response-or-raise.

    The function calls urllib.request.urlopen(req, timeout=15), so the mock
    must accept **kwargs (otherwise it raises TypeError on the timeout kwarg
    and the test silently falls through to the network-error branch).
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
    # gpt2 is a public repo; on a healthy network this must be reachable.
    assert blocked is False
