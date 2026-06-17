from pathlib import Path


def test_launcher_uses_non_interactive_setup_invocation():
    script = Path("launch-windows.ps1").read_text(encoding="utf-8")

    assert '$env:ODYSSEUS_LAUNCHER_MODE = "1"' in script
    assert '& $venvPy $setupPy' in script


def test_launcher_keeps_window_open_when_server_exits():
    script = Path("launch-windows.ps1").read_text(encoding="utf-8")

    assert 'Press Enter to close this window' in script
