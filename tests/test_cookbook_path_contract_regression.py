from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def _read(rel_path: str) -> str:
    return (ROOT / rel_path).read_text(encoding="utf-8")


COOKBOOK_JS_FILES = [
    "static/js/cookbook.js",
    "static/js/cookbookRunning.js",
    "static/js/cookbookServe.js",
    "static/js/cookbookDownload.js",
    "static/js/cookbook-hwfit.js",
]


def test_cookbook_js_has_no_hardcoded_pewds_paths():
    for rel in COOKBOOK_JS_FILES:
        source = _read(rel)
        assert "/home/pewds" not in source, f"{rel} still hardcodes /home/pewds"


def test_state_for_client_exposes_default_hub_paths():
    source = _read("routes/cookbook_routes.py")

    assert 'env["defaultHubPath"] = HUGGINGFACE_HUB_CACHE' in source
    assert 'env["defaultHuggingfaceHome"] = HUGGINGFACE_HOME' in source
    assert 'env["localPlatform"]' in source
    assert "_state_for_client({})" in source
    assert "HUGGINGFACE_HUB_CACHE" in source


def test_default_hub_path_helper_is_shared():
    source = _read("static/js/cookbook.js")

    assert "export function _defaultHubPath()" in source
    assert "_envState.defaultHubPath" in source


def test_serve_minimax_snapshot_uses_default_hub_path():
    source = _read("static/js/cookbookServe.js")

    assert "_defaultHubPath()" in source
    assert "MiniMax-M3-AWQ-INT4" in source
    assert "/home/pewds" not in source


def test_download_preview_uses_hf_env_not_local_dir():
    source = _read("static/js/cookbookDownload.js")

    assert "HUGGINGFACE_HUB_CACHE" in source
    assert "defaultHuggingfaceHome" in source
    assert "local_dir=os.path.expanduser" not in source


def test_download_zombie_probe_and_kill_use_tmux_cmd():
    source = _read("static/js/cookbookDownload.js")

    assert "_tmuxCmd" in source
    assert "_downloadSessionTask" in source
    assert "_tmuxCmd(_zTask" in source
    assert "tmux kill-session -t" not in source
    assert "_tmuxCmd(task, `kill-session -t" in source
