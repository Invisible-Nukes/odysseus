import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "hf_download.py"


def test_hf_download_help():
    result = subprocess.run(
        [sys.executable, str(SCRIPT), "--help"],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0
    assert "repo_id" in result.stdout.lower()


def test_hf_download_script_documents_start_done_markers():
    source = SCRIPT.read_text(encoding="utf-8")
    assert 'print(f"START {args.repo_id}"' in source
    assert 'print(f"DONE {path}"' in source
