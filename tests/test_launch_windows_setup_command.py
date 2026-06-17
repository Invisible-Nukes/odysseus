from pathlib import Path


def test_launcher_uses_non_interactive_setup_invocation():
    script = Path("launch-windows.ps1").read_text(encoding="utf-8")

    assert '$env:ODYSSEUS_LAUNCHER_MODE = "1"' in script
    assert '$env:ODYSSEUS_SKIP_ADMIN_PROMPT = "1"' in script
    assert 'Invoke-LoggedCommand -filePath $venvPy -argumentList @($setupPy)' in script
