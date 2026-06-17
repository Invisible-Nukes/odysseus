import os
import shutil
import subprocess
from pathlib import Path

import pytest


@pytest.mark.skipif(shutil.which("powershell") is None, reason="powershell not available")
def test_reset_script_removes_auth_and_app_state(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    script_src = repo_root / "reset-all-windows.ps1"
    script_copy = tmp_path / "reset-all-windows.ps1"
    script_copy.write_text(script_src.read_text(encoding="utf-8"), encoding="utf-8")

    data_dir = tmp_path / "custom-data"
    data_dir.mkdir(parents=True)
    (data_dir / "auth.json").write_text('{"users": {}}', encoding="utf-8")
    (data_dir / "app.db").write_bytes(b"db")
    (data_dir / "logs").mkdir(exist_ok=True)
    (data_dir / "downloads").mkdir(exist_ok=True)
    (tmp_path / ".env").write_text("TEST=1", encoding="utf-8")
    (tmp_path / "venv").mkdir(exist_ok=True)
    (tmp_path / "__pycache__").mkdir(exist_ok=True)

    env = os.environ.copy()
    env["ODYSSEUS_DATA_DIR"] = str(data_dir)
    env["LOCALAPPDATA"] = str(tmp_path / "LocalAppData")
    env["APPDATA"] = str(tmp_path / "AppData")
    env["USERPROFILE"] = str(tmp_path / "UserProfile")
    env["TEMP"] = str(tmp_path / "Temp")

    completed = subprocess.run(
        ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script_copy), "-Force"],
        cwd=tmp_path,
        env=env,
        capture_output=True,
        text=True,
        timeout=600,
    )

    assert completed.returncode == 0, completed.stderr or completed.stdout
    assert not (data_dir / "auth.json").exists()
    assert not (data_dir / "app.db").exists()
    assert (data_dir / "logs").exists()
