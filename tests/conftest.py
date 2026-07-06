"""Shared test configuration - ensure project root is on sys.path and stub heavy deps."""
import sys
import os
import types
import importlib.util
from unittest.mock import MagicMock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Importing core.database below runs init_db() at import time, and its default
# (sqlite:///./data/app.db) can't be opened in a clean worktree because SQLite
# won't create the missing ./data parent dir - pytest then dies during
# collection, before any test module loads. Default to an in-memory DB for the
# test session so collection is deterministic and writes no repo-local
# artifacts. An explicit DATABASE_URL (a real test/CI database) is preserved.
# This only unblocks collection/import-time init; it does not provide a shared
# file-backed DB across processes - tests needing that must set DATABASE_URL.
os.environ.setdefault("DATABASE_URL", "sqlite:///:memory:")

# Pre-import real heavy modules BEFORE any test file's module-level stubs can
# replace them with MagicMock. Some test files (e.g. test_llm_core_sanitize_*)
# stub sqlalchemy/core.database at module scope with `if mod not in sys.modules`,
# which fires during collection. If the real module hasn't been imported yet,
# the stub wins and contaminates every subsequent test that needs the real ORM.
try:
    import sqlalchemy  # noqa: F401
    import sqlalchemy.orm  # noqa: F401
    import core.database  # noqa: F401
except ImportError:
    pass  # not installed - the stubs below will handle it

def _has_module(mod_name: str) -> bool:
    try:
        return importlib.util.find_spec(mod_name) is not None
    except (ImportError, ValueError):
        return False


# Stub optional dependencies only when they are not installed. Do not replace
# real FastAPI/Starlette/Pydantic modules: route tests import their subpackages.
for mod_name in [
    "sqlalchemy", "sqlalchemy.orm", "sqlalchemy.types", "sqlalchemy.ext", "sqlalchemy.ext.declarative",
    "sqlalchemy.ext.hybrid", "sqlalchemy.sql", "sqlalchemy.sql.expression",
    "sqlalchemy.sql.sqltypes", "bcrypt", "pyotp",
    "httpx", "fastapi", "fastapi.responses", "fastapi.routing",
    "starlette", "starlette.responses", "starlette.middleware", "starlette.middleware.base",
    "pydantic",
]:
    if mod_name not in sys.modules and not _has_module(mod_name):
        sys.modules[mod_name] = MagicMock()

if "src.database" not in sys.modules and not _has_module("src.database"):
    _db = types.ModuleType("src.database")
    _db.SessionLocal = MagicMock()
    _db.ModelEndpoint = MagicMock()
    sys.modules["src.database"] = _db

# Pre-import core.models before test_agent_loop.py's module-level stubs
# run (it replaces sys.modules['core.models'] with a MagicMock during
# collection, which breaks session import in subsequent tests).
import core.models  # noqa: E402

def pytest_configure(config):
    """Register the dynamic taxonomy ``sub_*`` markers before collection.

    The stable ``area_*`` markers are declared in ``pyproject.toml``. The
    per-file ``sub_*`` markers are derived from the test filenames here so that
    unknown-mark warnings still surface genuine typos outside the taxonomy. This
    only registers marker names; it imports no production module.
    """
    import pathlib
    from tests._taxonomy import discover_markers

    tests_dir = pathlib.Path(__file__).parent
    paths = list(tests_dir.rglob("test_*.py")) + list(tests_dir.rglob("*_test.py"))
    for marker_name in discover_markers(paths):
        if marker_name.startswith("sub_"):
            config.addinivalue_line("markers", f"{marker_name}: taxonomy sub-area marker")


def pytest_collection_modifyitems(config, items):
    """Tag each collected test with its taxonomy ``area_*`` and ``sub_*`` markers.

    Collection-time only: this adds markers and nothing else. It does not skip,
    reorder, or deselect tests, mutate fixtures or the environment, or import any
    production module. See ``tests/_taxonomy.py`` for the classification rules.
    """
    import pytest
    from tests._taxonomy import markers_for_path

    for item in items:
        path = getattr(item, "path", None) or item.fspath
        for marker_name in markers_for_path(path):
            item.add_marker(getattr(pytest.mark, marker_name))


# =========== ENVIRONMENT DETECTION FIXTURES ===========

import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock


@pytest.fixture
def venv_fixture(tmp_path, monkeypatch):
    """Create a mock venv environment.
    
    Returns:
        dict: Contains 'path', 'bin_dir', 'scripts_dir' keys
    """
    venv_path = tmp_path / "venv"
    venv_path.mkdir()
    
    if sys.platform == "win32":
        scripts_dir = venv_path / "Scripts"
        scripts_dir.mkdir()
        (scripts_dir / "activate.ps1").touch()
        (scripts_dir / "activate.bat").touch()
        (scripts_dir / "python.exe").touch()
        bin_dir = scripts_dir
    else:
        bin_dir = venv_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "activate").touch()
        (bin_dir / "python").touch()
    
    return {
        "path": str(venv_path),
        "bin_dir": str(bin_dir),
        "scripts_dir": str(venv_path / "Scripts") if sys.platform == "win32" else None,
    }


@pytest.fixture
def conda_fixture(tmp_path, monkeypatch):
    """Create a mock conda environment.
    
    Returns:
        dict: Contains 'path', 'prefix', 'meta_dir' keys
    """
    conda_path = tmp_path / "conda_env"
    conda_path.mkdir()
    
    # Create conda-meta directory
    meta_dir = conda_path / "conda-meta"
    meta_dir.mkdir()
    (meta_dir / "history").touch()
    
    # Create python executable
    if sys.platform == "win32":
        (conda_path / "python.exe").touch()
    else:
        bin_dir = conda_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "python").touch()
    
    monkeypatch.setenv("CONDA_PREFIX", str(conda_path))
    
    return {
        "path": str(conda_path),
        "prefix": str(conda_path),
        "meta_dir": str(meta_dir),
    }


@pytest.fixture
def bare_python_fixture(tmp_path, monkeypatch):
    """Create a bare Python environment (no venv/conda).
    
    Returns:
        dict: Contains 'python_path', 'base_prefix' keys
    """
    # Create a fake base prefix directory
    base_path = tmp_path / "python_base"
    base_path.mkdir()
    
    return {
        "python_path": sys.executable,
        "base_prefix": str(base_path),
    }


@pytest.fixture
def windows_fixture(monkeypatch):
    """Mock Windows platform."""
    monkeypatch.setattr("sys.platform", "win32")
    monkeypatch.setattr("platform.system", lambda: "Windows")
    return {"platform": "windows"}


@pytest.fixture
def linux_fixture(monkeypatch):
    """Mock Linux platform."""
    monkeypatch.setattr("sys.platform", "linux")
    monkeypatch.setattr("platform.system", lambda: "Linux")
    return {"platform": "linux"}


@pytest.fixture
def macos_fixture(monkeypatch):
    """Mock macOS platform."""
    monkeypatch.setattr("sys.platform", "darwin")
    monkeypatch.setattr("platform.system", lambda: "Darwin")
    return {"platform": "macos"}


@pytest.fixture
def clear_environment_vars(monkeypatch):
    """Clear conda-related environment variables."""
    monkeypatch.delenv("CONDA_PREFIX", raising=False)
    monkeypatch.delenv("CONDA_DEFAULT_ENV", raising=False)
    monkeypatch.delenv("CONDA_PROMPT_MODIFIER", raising=False)
    return monkeypatch
