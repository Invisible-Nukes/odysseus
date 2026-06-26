"""Tests for resolve_cookbook_log_path and Windows lifecycle helpers."""


def test_resolve_cookbook_log_path_linux_local(monkeypatch):
    from routes import cookbook_helpers as ch

    monkeypatch.setattr(ch, "IS_WINDOWS", False)
    assert ch.resolve_cookbook_log_path("serve-abc") == "/tmp/odysseus-tmux/serve-abc.log"


def test_resolve_cookbook_log_path_windows_local(monkeypatch, tmp_path):
    from routes import cookbook_helpers as ch

    monkeypatch.setattr(ch, "IS_WINDOWS", True)
    monkeypatch.setattr(ch.tempfile, "gettempdir", lambda: str(tmp_path))
    assert ch.resolve_cookbook_log_path("serve-abc") == str(
        tmp_path / "odysseus-tmux" / "serve-abc.log"
    )


def test_resolve_cookbook_log_path_remote_windows():
    from routes.cookbook_helpers import resolve_cookbook_log_path

    assert (
        resolve_cookbook_log_path("serve-abc", remote_host="winbox", platform="windows")
        == r"%TEMP%\odysseus-sessions\serve-abc.log"
    )


def test_resolve_cookbook_log_path_remote_linux():
    from routes.cookbook_helpers import resolve_cookbook_log_path

    assert (
        resolve_cookbook_log_path("serve-abc", remote_host="linuxbox", platform="linux")
        == "/tmp/odysseus-tmux/serve-abc.log"
    )
