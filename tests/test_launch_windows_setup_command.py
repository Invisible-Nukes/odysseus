from pathlib import Path


def test_launcher_uses_raw_python_paths_for_setup_subprocess():
    script = Path("launch-windows.ps1").read_text(encoding="utf-8")

    assert "subprocess.run([r'$venvPy', r'$setupPy'], check=True, env=env)" in script
