"""Environment detection and validation for Python execution contexts.

Detects the Python environment type (venv, conda, bare) and provides
validation of activation scripts and environment metadata.
"""

import os
import sys
import platform
from dataclasses import dataclass, asdict
from typing import Optional, List
from pathlib import Path


@dataclass
class EnvironmentInfo:
    """Information about the current Python environment."""
    type: str  # "venv", "conda", or "bare"
    path: str  # Path to the environment root
    python_version: str  # e.g., "3.13.5"
    platform_name: str  # "windows", "linux", or "macos"
    is_valid: bool  # True if activation scripts exist and are valid
    warnings: List[str]  # List of warning messages
    remote_host: Optional[str] = None  # SSH host if remote
    
    def to_dict(self):
        """Convert to dictionary for JSON serialization."""
        return asdict(self)


class EnvironmentDetector:
    """Detects and validates Python execution environments."""
    
    def __init__(self):
        """Initialize the environment detector."""
        self._environment_type = None
        self._environment_path = None
        self._platform_name = None
    
    def get_platform(self) -> str:
        """Return the platform name: 'windows', 'linux', or 'macos'."""
        # Don't cache during tests - re-detect each time for proper mocking
        system = platform.system().lower()
        if system == "windows":
            return "windows"
        elif system == "darwin":
            return "macos"
        else:
            return "linux"
    
    def detect(self) -> EnvironmentInfo:
        """Detect the current Python environment and return info.
        
        Returns:
            EnvironmentInfo: Details about the detected environment.
        """
        warnings = []
        env_type = "bare"
        env_path = sys.base_prefix
        
        # Check for venv first (most common)
        is_venv = sys.prefix != sys.base_prefix
        
        # Check for conda
        conda_prefix = os.environ.get("CONDA_PREFIX")
        is_conda = conda_prefix is not None and conda_prefix != ""
        
        # Warn if both are detected
        if is_venv and is_conda:
            warnings.append(
                "Both venv and conda detected simultaneously. "
                "The environment may be unreliable."
            )
        
        # Determine which takes precedence
        if is_venv:
            env_type = "venv"
            env_path = sys.prefix
        elif is_conda:
            env_type = "conda"
            env_path = conda_prefix
        
        # Validate the detected environment
        is_valid = self._validate_environment(env_type, env_path, warnings)
        
        # Get Python version
        python_version = self._get_python_version()
        
        return EnvironmentInfo(
            type=env_type,
            path=env_path,
            python_version=python_version,
            platform_name=self.get_platform(),
            is_valid=is_valid,
            warnings=warnings,
        )
    
    def validate(self) -> bool:
        """Validate the current environment's activation scripts.
        
        Returns:
            bool: True if the environment is valid and all required
                  activation scripts exist.
        """
        info = self.detect()
        return info.is_valid
    
    def _validate_environment(self, env_type: str, env_path: str, 
                              warnings: List[str]) -> bool:
        """Validate an environment by checking for required files.
        
        Args:
            env_type: The detected environment type
            env_path: The path to the environment root
            warnings: List to append warning messages to
            
        Returns:
            bool: True if the environment is valid
        """
        if env_type == "bare":
            # Bare Python is always "valid" - no activation scripts needed
            return True
        
        platform_name = self.get_platform()
        
        if env_type == "venv":
            return self._validate_venv(env_path, platform_name, warnings)
        elif env_type == "conda":
            return self._validate_conda(env_path, platform_name, warnings)
        
        return False
    
    def _validate_venv(self, venv_path: str, platform_name: str,
                       warnings: List[str]) -> bool:
        """Validate a virtual environment.
        
        Args:
            venv_path: Path to the venv root
            platform_name: Platform name (windows/linux/macos)
            warnings: List to append warning messages to
            
        Returns:
            bool: True if the venv is valid
        """
        venv_path = Path(venv_path)
        
        if platform_name == "windows":
            # Check for Windows activation scripts
            activate_ps1 = venv_path / "Scripts" / "activate.ps1"
            activate_bat = venv_path / "Scripts" / "activate.bat"
            python_exe = venv_path / "Scripts" / "python.exe"
            
            has_ps1 = activate_ps1.exists()
            has_bat = activate_bat.exists()
            has_python = python_exe.exists()
            
            if not has_python:
                warnings.append(f"Python executable not found at {python_exe}")
                return False
            
            if not (has_ps1 or has_bat):
                warnings.append(
                    f"Activation scripts not found in {venv_path / 'Scripts'}"
                )
                return False
            
            return True
        else:
            # Check for Unix activation script
            activate_script = venv_path / "bin" / "activate"
            python_exe = venv_path / "bin" / "python"
            python_exe3 = venv_path / "bin" / "python3"
            
            if not activate_script.exists():
                warnings.append(f"Activation script not found at {activate_script}")
                return False
            
            has_python = python_exe.exists() or python_exe3.exists()
            if not has_python:
                warnings.append(
                    f"Python executable not found in {venv_path / 'bin'}"
                )
                return False
            
            return True
    
    def _validate_conda(self, conda_prefix: str, platform_name: str,
                        warnings: List[str]) -> bool:
        """Validate a conda environment.
        
        Args:
            conda_prefix: Path to the conda environment
            platform_name: Platform name (windows/linux/macos)
            warnings: List to append warning messages to
            
        Returns:
            bool: True if the conda environment is valid
        """
        conda_path = Path(conda_prefix)
        
        # Check for conda-meta directory (required for all conda envs)
        conda_meta = conda_path / "conda-meta"
        if not conda_meta.exists():
            warnings.append(f"conda-meta directory not found at {conda_meta}")
            return False
        
        # Check for Python executable
        if platform_name == "windows":
            python_exe = conda_path / "python.exe"
        else:
            python_exe = conda_path / "bin" / "python"
        
        if not python_exe.exists():
            warnings.append(f"Python executable not found at {python_exe}")
            return False
        
        return True
    
    def _get_python_version(self) -> str:
        """Get the current Python version as a string.
        
        Returns:
            str: Version string like "3.13.5"
        """
        return f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}"


def detect_environment() -> EnvironmentInfo:
    """Convenience function to detect the current environment.
    
    Returns:
        EnvironmentInfo: Details about the detected environment.
    """
    detector = EnvironmentDetector()
    return detector.detect()
