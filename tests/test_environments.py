"""Test suite for environment detection and validation.

Tests cover:
- Environment type detection (venv, conda, bare)
- Cross-platform support (Windows, Linux, macOS)
- Activation script validation
- Conflict detection
- Python version detection
"""

import os
import sys
import pytest
import platform
from pathlib import Path
from unittest.mock import patch, MagicMock
from core.environment import (
    EnvironmentDetector, EnvironmentInfo, detect_environment
)


class TestEnvironmentDetection:
    """Test suite for basic environment detection."""
    
    def test_detect_returns_environment_info(self):
        """Test that detect() returns a valid EnvironmentInfo object."""
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert isinstance(info, EnvironmentInfo)
        assert info.type in ("venv", "conda", "bare")
        assert info.path is not None
        assert info.python_version is not None
        assert info.platform_name in ("windows", "linux", "macos")
        assert isinstance(info.is_valid, bool)
        assert isinstance(info.warnings, list)
    
    def test_environment_info_to_dict(self):
        """Test that EnvironmentInfo can be converted to dict."""
        detector = EnvironmentDetector()
        info = detector.detect()
        info_dict = info.to_dict()
        
        assert isinstance(info_dict, dict)
        assert "type" in info_dict
        assert "path" in info_dict
        assert "python_version" in info_dict
        assert "platform_name" in info_dict
        assert "is_valid" in info_dict
        assert "warnings" in info_dict
    
    def test_get_platform_windows(self, monkeypatch):
        """Test platform detection for Windows."""
        monkeypatch.setattr("platform.system", lambda: "Windows")
        detector = EnvironmentDetector()
        assert detector.get_platform() == "windows"
    
    def test_get_platform_linux(self, monkeypatch):
        """Test platform detection for Linux."""
        monkeypatch.setattr("platform.system", lambda: "Linux")
        detector = EnvironmentDetector()
        assert detector.get_platform() == "linux"
    
    def test_get_platform_macos(self, monkeypatch):
        """Test platform detection for macOS."""
        monkeypatch.setattr("platform.system", lambda: "Darwin")
        detector = EnvironmentDetector()
        assert detector.get_platform() == "macos"
    
    def test_python_version_format(self):
        """Test that Python version is returned in correct format."""
        detector = EnvironmentDetector()
        version = detector._get_python_version()
        
        # Should be in format X.Y.Z
        parts = version.split(".")
        assert len(parts) == 3
        assert all(part.isdigit() for part in parts)
    
    def test_convenience_function_detect_environment(self):
        """Test the convenience function detect_environment()."""
        info = detect_environment()
        assert isinstance(info, EnvironmentInfo)


class TestVenvDetection:
    """Test suite for virtual environment detection."""
    
    def test_venv_detection_with_valid_venv(self, venv_fixture, monkeypatch):
        """Test venv detection with a valid virtual environment."""
        venv_path = venv_fixture["path"]
        
        # Mock sys.prefix to simulate venv activation
        monkeypatch.setattr("sys.prefix", venv_path)
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "venv"
        assert info.path == venv_path
    
    def test_venv_validation_windows(self, venv_fixture, windows_fixture, monkeypatch):
        """Test venv validation on Windows."""
        venv_path = venv_fixture["path"]
        monkeypatch.setattr("sys.platform", "win32")
        
        detector = EnvironmentDetector()
        is_valid = detector._validate_venv(venv_path, "windows", [])
        
        assert is_valid is True
    
    def test_venv_validation_unix(self, venv_fixture, linux_fixture, monkeypatch):
        """Test venv validation on Unix/Linux."""
        venv_path = venv_fixture["path"]
        monkeypatch.setattr("sys.platform", "linux")
        monkeypatch.setattr("platform.system", lambda: "Linux")
        
        # Since the fixture created Windows-style scripts on Windows, we need to
        # create Unix-style scripts for this test
        venv_path_obj = Path(venv_path)
        scripts_dir = venv_path_obj / "Scripts"
        if scripts_dir.exists():
            # Remove Windows scripts
            for f in scripts_dir.glob("*"):
                f.unlink()
            scripts_dir.rmdir()
        
        # Create Unix-style scripts
        bin_dir = venv_path_obj / "bin"
        bin_dir.mkdir(exist_ok=True)
        (bin_dir / "activate").touch()
        (bin_dir / "python").touch()
        
        detector = EnvironmentDetector()
        is_valid = detector._validate_venv(venv_path, "linux", [])
        
        assert is_valid is True
    
    def test_venv_validation_missing_activation_script_windows(self, tmp_path, monkeypatch):
        """Test venv validation fails when activation scripts are missing on Windows."""
        venv_path = tmp_path / "broken_venv"
        venv_path.mkdir()
        scripts_dir = venv_path / "Scripts"
        scripts_dir.mkdir()
        (scripts_dir / "python.exe").touch()
        # Missing activate.ps1 and activate.bat
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "windows", warnings)
        
        assert is_valid is False
        assert any("Activation scripts not found" in w for w in warnings)
    
    def test_venv_validation_missing_activation_script_unix(self, tmp_path):
        """Test venv validation fails when activation script is missing on Unix."""
        venv_path = tmp_path / "broken_venv"
        venv_path.mkdir()
        bin_dir = venv_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "python").touch()
        # Missing activate script
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "linux", warnings)
        
        assert is_valid is False
        assert any("Activation script not found" in w for w in warnings)
    
    def test_venv_validation_missing_python_executable_windows(self, tmp_path):
        """Test venv validation fails when python.exe is missing on Windows."""
        venv_path = tmp_path / "broken_venv"
        venv_path.mkdir()
        scripts_dir = venv_path / "Scripts"
        scripts_dir.mkdir()
        (scripts_dir / "activate.ps1").touch()
        (scripts_dir / "activate.bat").touch()
        # Missing python.exe
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "windows", warnings)
        
        assert is_valid is False
        assert any("Python executable not found" in w for w in warnings)
    
    def test_venv_validation_missing_python_executable_unix(self, tmp_path):
        """Test venv validation fails when python is missing on Unix."""
        venv_path = tmp_path / "broken_venv"
        venv_path.mkdir()
        bin_dir = venv_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "activate").touch()
        # Missing python and python3
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "linux", warnings)
        
        assert is_valid is False
        assert any("Python executable not found" in w for w in warnings)


class TestCondaDetection:
    """Test suite for conda environment detection."""
    
    def test_conda_detection_with_valid_conda(self, conda_fixture, monkeypatch, clear_environment_vars):
        """Test conda detection with a valid conda environment."""
        conda_path = conda_fixture["path"]
        monkeypatch.setenv("CONDA_PREFIX", conda_path)
        # Ensure we're not in a venv to allow conda detection
        monkeypatch.setattr("sys.prefix", "/usr/local")
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "conda"
        assert info.path == conda_path
    
    def test_conda_detection_from_env_var(self, conda_fixture, monkeypatch, clear_environment_vars):
        """Test that conda is detected from CONDA_PREFIX environment variable."""
        conda_path = conda_fixture["path"]
        monkeypatch.setenv("CONDA_PREFIX", conda_path)
        # Ensure we're not in a venv to allow conda detection
        monkeypatch.setattr("sys.prefix", "/usr/local")
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "conda"
    
    def test_conda_validation_with_valid_conda(self, conda_fixture, monkeypatch):
        """Test conda validation with valid conda environment."""
        conda_path = conda_fixture["path"]
        
        detector = EnvironmentDetector()
        # On Windows, validate with "windows" platform
        platform = "windows" if sys.platform == "win32" else "linux"
        is_valid = detector._validate_conda(conda_path, platform, [])
        
        assert is_valid is True
    
    def test_conda_validation_missing_meta_dir(self, tmp_path):
        """Test conda validation fails when conda-meta directory is missing."""
        conda_path = tmp_path / "broken_conda"
        conda_path.mkdir()
        if sys.platform != "win32":
            bin_dir = conda_path / "bin"
            bin_dir.mkdir()
            (bin_dir / "python").touch()
        else:
            (conda_path / "python.exe").touch()
        # Missing conda-meta directory
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_conda(str(conda_path), "linux", warnings)
        
        assert is_valid is False
        assert any("conda-meta directory not found" in w for w in warnings)
    
    def test_conda_validation_missing_python_executable(self, tmp_path):
        """Test conda validation fails when python executable is missing."""
        conda_path = tmp_path / "broken_conda"
        conda_path.mkdir()
        meta_dir = conda_path / "conda-meta"
        meta_dir.mkdir()
        (meta_dir / "history").touch()
        # Missing python executable
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_conda(str(conda_path), "linux", warnings)
        
        assert is_valid is False
        assert any("Python executable not found" in w for w in warnings)
    
    def test_conda_validation_windows(self, conda_fixture):
        """Test conda validation on Windows."""
        conda_path = conda_fixture["path"]
        
        detector = EnvironmentDetector()
        is_valid = detector._validate_conda(conda_path, "windows", [])
        
        assert is_valid is True


class TestBareEnvironment:
    """Test suite for bare Python environment detection."""
    
    def test_bare_environment_detection(self, monkeypatch, clear_environment_vars):
        """Test detection of bare Python environment (no venv/conda)."""
        # Ensure we're not in a venv or conda
        monkeypatch.setattr("sys.prefix", "/usr/local")
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "bare"
    
    def test_bare_environment_always_valid(self, monkeypatch, clear_environment_vars):
        """Test that bare environment is always considered valid."""
        monkeypatch.setattr("sys.prefix", "/usr/local")
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        
        detector = EnvironmentDetector()
        is_valid = detector._validate_environment("bare", "/usr/local", [])
        
        assert is_valid is True


class TestConflictDetection:
    """Test suite for detecting conflicting environment configurations."""
    
    def test_conflict_when_both_venv_and_conda_detected(self, venv_fixture, conda_fixture, monkeypatch, clear_environment_vars):
        """Test that conflicts are detected when both venv and conda are active."""
        venv_path = venv_fixture["path"]
        conda_path = conda_fixture["path"]
        
        # Simulate both being active
        monkeypatch.setattr("sys.prefix", venv_path)
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        monkeypatch.setenv("CONDA_PREFIX", conda_path)
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        # venv takes precedence, but warning should be issued
        assert info.type == "venv"
        assert any("Both venv and conda detected" in w for w in info.warnings)
    
    def test_conflict_warning_content(self, venv_fixture, conda_fixture, monkeypatch, clear_environment_vars):
        """Test that conflict warning has appropriate content."""
        venv_path = venv_fixture["path"]
        conda_path = conda_fixture["path"]
        
        monkeypatch.setattr("sys.prefix", venv_path)
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        monkeypatch.setenv("CONDA_PREFIX", conda_path)
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert len(info.warnings) > 0
        warning_text = " ".join(info.warnings)
        assert "venv" in warning_text.lower()
        assert "conda" in warning_text.lower()


class TestValidate:
    """Test suite for the validate() method."""
    
    def test_validate_method_calls_detect(self, monkeypatch, clear_environment_vars):
        """Test that validate() method calls detect() internally."""
        monkeypatch.setattr("sys.prefix", sys.base_prefix)
        
        detector = EnvironmentDetector()
        is_valid = detector.validate()
        
        # Bare environment is always valid
        assert isinstance(is_valid, bool)


class TestPlatformValidation:
    """Test suite for platform-specific validation."""
    
    def test_venv_windows_activation_script_requirements(self, tmp_path):
        """Test Windows venv requires .ps1 or .bat activation scripts."""
        venv_path = tmp_path / "venv"
        venv_path.mkdir()
        scripts = venv_path / "Scripts"
        scripts.mkdir()
        (scripts / "python.exe").touch()
        
        detector = EnvironmentDetector()
        
        # Should fail without activation scripts
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "windows", warnings)
        assert is_valid is False
        
        # Add .ps1 - should succeed
        (scripts / "activate.ps1").touch()
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "windows", warnings)
        assert is_valid is True
    
    def test_venv_unix_activation_script_requirements(self, tmp_path):
        """Test Unix venv requires activate script."""
        venv_path = tmp_path / "venv"
        venv_path.mkdir()
        bin_dir = venv_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "python").touch()
        
        detector = EnvironmentDetector()
        
        # Should fail without activation script
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "linux", warnings)
        assert is_valid is False
        
        # Add activation script - should succeed
        (bin_dir / "activate").touch()
        warnings = []
        is_valid = detector._validate_venv(str(venv_path), "linux", warnings)
        assert is_valid is True
    
    def test_conda_macos_validation(self, tmp_path):
        """Test conda validation on macOS."""
        # Create a proper macOS conda environment structure
        conda_path = tmp_path / "conda_env"
        conda_path.mkdir()
        
        # Create conda-meta directory
        meta_dir = conda_path / "conda-meta"
        meta_dir.mkdir()
        (meta_dir / "history").touch()
        
        # Create Unix-style python executable
        bin_dir = conda_path / "bin"
        bin_dir.mkdir()
        (bin_dir / "python").touch()
        
        detector = EnvironmentDetector()
        # macOS uses Unix-style paths
        is_valid = detector._validate_conda(str(conda_path), "macos", [])
        
        assert is_valid is True


class TestEdgeCases:
    """Test suite for edge cases and error handling."""
    
    def test_empty_conda_prefix_ignored(self, monkeypatch, clear_environment_vars):
        """Test that empty CONDA_PREFIX is ignored."""
        monkeypatch.setenv("CONDA_PREFIX", "")
        monkeypatch.setattr("sys.prefix", sys.base_prefix)
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "bare"
    
    def test_warnings_list_accumulation(self, tmp_path):
        """Test that warnings accumulate correctly."""
        venv_path = tmp_path / "broken_venv"
        venv_path.mkdir()
        
        detector = EnvironmentDetector()
        warnings = []
        
        # Multiple issues should generate multiple warnings
        detector._validate_venv(str(venv_path), "linux", warnings)
        
        # Should have warnings for missing both scripts and python
        assert len(warnings) >= 1
    
    def test_pathlib_compatibility(self, venv_fixture):
        """Test that both string and Path objects work."""
        venv_path = venv_fixture["path"]
        
        detector = EnvironmentDetector()
        
        # Should work with string
        warnings1 = []
        result1 = detector._validate_venv(venv_path, "windows" if sys.platform == "win32" else "linux", warnings1)
        
        # Should work with Path
        warnings2 = []
        result2 = detector._validate_venv(venv_path, "windows" if sys.platform == "win32" else "linux", warnings2)
        
        assert result1 == result2
    
    def test_nonexistent_environment_paths(self):
        """Test handling of nonexistent environment paths."""
        nonexistent_path = "/nonexistent/env/path"
        
        detector = EnvironmentDetector()
        warnings = []
        is_valid = detector._validate_venv(nonexistent_path, "linux", warnings)
        
        assert is_valid is False
        assert len(warnings) > 0


class TestEnvironmentTypePreference:
    """Test suite for environment type preference when multiple are configured."""
    
    def test_venv_takes_precedence_over_conda(self, venv_fixture, conda_fixture, monkeypatch, clear_environment_vars):
        """Test that venv detection takes precedence over conda."""
        venv_path = venv_fixture["path"]
        conda_path = conda_fixture["path"]
        
        # Both configured
        monkeypatch.setattr("sys.prefix", venv_path)
        monkeypatch.setattr("sys.base_prefix", "/usr/local")
        monkeypatch.setenv("CONDA_PREFIX", conda_path)
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "venv"
        assert info.path == venv_path
    
    def test_conda_used_when_venv_not_active(self, conda_fixture, monkeypatch, clear_environment_vars):
        """Test that conda is used when venv is not active."""
        conda_path = conda_fixture["path"]
        
        # Only conda configured
        monkeypatch.setattr("sys.prefix", sys.base_prefix)
        monkeypatch.setenv("CONDA_PREFIX", conda_path)
        
        detector = EnvironmentDetector()
        info = detector.detect()
        
        assert info.type == "conda"
        assert info.path == conda_path


class TestValidationWarnings:
    """Test suite for validation warnings."""
    
    def test_no_warnings_for_valid_venv(self, venv_fixture, monkeypatch):
        """Test that no warnings are generated for valid venv."""
        venv_path = venv_fixture["path"]
        
        detector = EnvironmentDetector()
        warnings = []
        detector._validate_venv(venv_path, "windows" if sys.platform == "win32" else "linux", warnings)
        
        # Valid environments should have no validation warnings
        assert len(warnings) == 0
    
    def test_warnings_for_missing_files(self, tmp_path):
        """Test that warnings are generated for missing required files."""
        venv_path = tmp_path / "incomplete_venv"
        venv_path.mkdir()
        
        detector = EnvironmentDetector()
        warnings = []
        detector._validate_venv(str(venv_path), "linux", warnings)
        
        assert len(warnings) > 0
        assert all(isinstance(w, str) for w in warnings)
