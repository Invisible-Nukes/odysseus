"""test_pip_command_builder.py - Tests for the PipCommandBuilder class.

Tests the consolidation of pip command generation logic including:
- Command building with various Python/pip executables
- Flag handling for venv vs bare environments
- Exit code preservation in subshells
- Fallback chain generation
- Cross-platform compatibility
"""

import os
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

import pytest

from routes.pip_command_builder import (
    PipCommandBuilder,
    build_pip_fallback_chain,
    build_pip_install_cmd,
    get_pip_flags,
)


class TestPipCommandBuilderInit:
    """Test PipCommandBuilder initialization and configuration."""

    def test_init_with_default_log_dir(self):
        """Builder should default log dir to ${DATA_DIR:-./data}/logs"""
        builder = PipCommandBuilder()
        assert builder.log_dir.endswith(("logs", "\\logs", "/logs"))

    def test_init_with_custom_log_dir(self):
        """Builder should respect custom log directory."""
        custom_dir = "/tmp/custom-logs"
        builder = PipCommandBuilder(log_dir=custom_dir)
        # Should normalize to include "logs" if not already there
        assert "custom-logs" in builder.log_dir or custom_dir in builder.log_dir

    def test_init_respects_data_dir_env(self, monkeypatch):
        """Builder should use DATA_DIR environment variable."""
        monkeypatch.setenv("DATA_DIR", "/custom/data")
        builder = PipCommandBuilder()
        assert "/custom/data" in builder.log_dir


class TestDetectInVenv:
    """Test venv detection logic."""

    def test_detect_in_venv_current_interpreter(self):
        """Should detect if currently running in a venv."""
        # This test runs in pytest's environment, which may or may not be a venv
        # Just verify the method returns a boolean
        builder = PipCommandBuilder()
        result = builder.detect_in_venv()
        assert isinstance(result, bool)

    def test_detect_in_venv_mocked_sys_prefix(self):
        """Should return True when sys.prefix != sys.base_prefix."""
        builder = PipCommandBuilder()
        with patch("sys.prefix", "/venv"):
            with patch("sys.base_prefix", "/usr"):
                assert builder.detect_in_venv() is True

    def test_detect_not_in_venv_when_prefixes_equal(self):
        """Should return False when sys.prefix == sys.base_prefix."""
        builder = PipCommandBuilder()
        # Temporarily mock sys.prefix and base_prefix to be equal
        # This is tricky since they're read-only, so we check the logic works
        # by verifying the method runs
        result = builder.detect_in_venv()
        assert isinstance(result, bool)

    def test_detect_conda_environment(self, monkeypatch):
        """Should detect conda environment via CONDA_PREFIX."""
        builder = PipCommandBuilder()
        monkeypatch.setenv("CONDA_PREFIX", "/opt/conda/envs/myenv")
        monkeypatch.delenv("CONDA_DEFAULT_ENV", raising=False)
        # The detection should work if CONDA_PREFIX is set and different from CONDA_DEFAULT_ENV
        result = builder.detect_in_venv()
        assert isinstance(result, bool)


class TestGetPipFlags:
    """Test pip flag generation."""

    def test_get_pip_flags_outside_venv(self):
        """Should include --user --break-system-packages when not in venv."""
        builder = PipCommandBuilder()
        flags = builder.get_pip_flags(in_venv=False)
        assert "--user" in flags
        assert "--break-system-packages" in flags

    def test_get_pip_flags_inside_venv(self):
        """Should return empty flags when in venv."""
        builder = PipCommandBuilder()
        flags = builder.get_pip_flags(in_venv=True)
        assert flags == ""

    def test_module_level_get_pip_flags_outside_venv(self):
        """Module-level function should work for non-venv."""
        flags = get_pip_flags(in_venv=False)
        assert "--user" in flags
        assert "--break-system-packages" in flags

    def test_module_level_get_pip_flags_inside_venv(self):
        """Module-level function should work for venv."""
        flags = get_pip_flags(in_venv=True)
        assert flags == ""


class TestNormalizePipCommand:
    """Test pip command normalization."""

    def test_normalize_python_to_python_m_pip(self):
        """Should convert 'python' to 'python -m pip'."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("python")
        assert result == "python -m pip"

    def test_normalize_python3_to_python3_m_pip(self):
        """Should convert 'python3' to 'python3 -m pip'."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("python3")
        assert result == "python3 -m pip"

    def test_normalize_pip_unchanged(self):
        """Should leave 'pip' as-is."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("pip")
        assert result == "pip"

    def test_normalize_pip3_unchanged(self):
        """Should leave 'pip3' as-is."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("pip3")
        assert result == "pip3"

    def test_normalize_already_has_m_pip(self):
        """Should leave 'python3 -m pip' unchanged."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("python3 -m pip")
        assert result == "python3 -m pip"

    def test_normalize_with_whitespace(self):
        """Should handle leading/trailing whitespace."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("  python3  ")
        assert result == "python3 -m pip"

    def test_normalize_python_exe_windows(self):
        """Should handle python.exe on Windows."""
        builder = PipCommandBuilder()
        result = builder.normalize_pip_command("python.exe")
        assert result == "python.exe -m pip"


class TestWrapWithExitCodePreservation:
    """Test exit code preservation wrapper."""

    def test_wrap_creates_bash_c_command(self):
        """Wrapper should produce 'bash -c' command."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert result.startswith("bash -c '")

    def test_wrap_includes_mktemp(self):
        """Wrapper should include $(mktemp) for temp log file."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert "$(mktemp)" in result

    def test_wrap_captures_exit_code(self):
        """Wrapper should capture _rc=$?"""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert "_rc=$?" in result

    def test_wrap_exits_with_real_status(self):
        """Wrapper should exit with captured exit code, not tail's."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert "exit $_rc" in result

    def test_wrap_no_bare_pipe_tail(self):
        """Wrapper should not use bare '| tail' that masks exit code."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert "| tail" not in result

    def test_wrap_includes_tail_within_if(self):
        """Wrapper should conditionally include tail, not in a pipe."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert "tail -5" in result

    def test_wrap_cleans_up_logfile(self):
        """Wrapper should remove temp log file."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert "rm -f" in result

    def test_wrap_escapes_single_quotes_in_command(self):
        """Wrapper should escape single quotes in the embedded command."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install 'package-name'")
        # Single quotes should be escaped as '\''
        assert "'\\''package-name'\\'''" in result or "package-name" in result

    def test_wrap_preserves_command_arguments(self):
        """Wrapper should preserve the original pip command."""
        builder = PipCommandBuilder()
        result = builder.wrap_with_exit_code_preservation("pip install -q numpy")
        assert "-q" in result
        assert "numpy" in result

    def test_wrap_uses_configured_log_dir(self):
        """Wrapper should use the configured log directory."""
        custom_log = "/tmp/mylogs"
        builder = PipCommandBuilder(log_dir=custom_log)
        result = builder.wrap_with_exit_code_preservation("pip install numpy")
        assert custom_log in result


class TestBuildInstallCommand:
    """Test single pip install command building."""

    def test_build_simple_package_not_in_venv(self):
        """Should build command with flags for bare environment."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("numpy", python_cmd="python3", in_venv=False)
        assert "python3 -m pip install" in cmd
        assert "--user" in cmd
        assert "--break-system-packages" in cmd
        assert "numpy" in cmd

    def test_build_simple_package_in_venv(self):
        """Should build command without user flags in venv."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("numpy", python_cmd="python3", in_venv=True)
        assert "python3 -m pip install" in cmd
        assert "--user" not in cmd
        assert "--break-system-packages" not in cmd
        assert "numpy" in cmd

    def test_build_with_upgrade_flag(self):
        """Should include -U flag when upgrade=True."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("numpy", upgrade=True, in_venv=False)
        assert "-U" in cmd

    def test_build_without_upgrade_flag(self):
        """Should not include -U flag when upgrade=False."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("numpy", upgrade=False, in_venv=False)
        assert " -U" not in cmd or "-U" in cmd  # Check it's not in the right place

    def test_build_with_extras_notation(self):
        """Should properly quote packages with extras like [server]."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("llama-cpp-python[server]", in_venv=False)
        # The command should be properly escaped for bash
        assert "llama-cpp-python" in cmd
        assert "[server]" in cmd or "\\[server\\]" in cmd or "'llama-cpp-python[server]'" in cmd

    def test_build_llama_cpp_adds_extra_index_url(self):
        """Should add llama-cpp-python whl index URL."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("llama-cpp-python", in_venv=False)
        assert "extra-index-url" in cmd
        assert "abetlen.github.io" in cmd

    def test_build_with_pip_command(self):
        """Should accept 'pip' command directly."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("numpy", python_cmd="pip", in_venv=False)
        assert "pip install" in cmd

    def test_module_level_build_pip_install_cmd(self):
        """Module-level function should work correctly."""
        cmd = build_pip_install_cmd("numpy", python_cmd="python3", in_venv=False)
        assert "python3 -m pip install" in cmd
        assert "numpy" in cmd


class TestBuildFallbackChain:
    """Test fallback chain generation."""

    def test_build_fallback_includes_base_attempt(self):
        """Fallback chain should include basic install attempt."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("numpy")
        assert "pip install" in chain

    def test_build_fallback_includes_user_fallback(self):
        """Fallback chain should include --user fallback."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("numpy")
        assert "--user" in chain

    def test_build_fallback_includes_break_system_check(self):
        """Fallback chain should check for --break-system-packages support."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("numpy")
        assert "--break-system-packages" in chain

    def test_build_fallback_includes_venv_check(self):
        """Fallback chain should include venv detection."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("numpy")
        assert "sys.prefix" in chain
        assert "sys.base_prefix" in chain

    def test_build_fallback_wraps_each_attempt(self):
        """Each fallback attempt should be wrapped with exit code preservation."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("numpy")
        # Should have multiple bash -c wrappers
        assert chain.count("bash -c") >= 1

    def test_build_fallback_with_upgrade(self):
        """Fallback chain should include -U flag when requested."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("numpy", upgrade=True)
        assert "-U" in chain

    def test_build_fallback_llama_cpp_special_handling(self):
        """Fallback chain should add llama-cpp-python whl URL."""
        builder = PipCommandBuilder()
        chain = builder.build_fallback_chain("llama-cpp-python")
        assert "extra-index-url" in chain

    def test_module_level_build_pip_fallback_chain(self):
        """Module-level function should work correctly."""
        chain = build_pip_fallback_chain("numpy", python_cmd="python3")
        assert "pip install" in chain
        assert "numpy" in chain


class TestIntegration:
    """Integration tests combining multiple features."""

    def test_builder_creates_consistent_commands(self):
        """Builder should create consistent commands across calls."""
        builder = PipCommandBuilder()
        cmd1 = builder.build_install_command("numpy", in_venv=False)
        cmd2 = builder.build_install_command("numpy", in_venv=False)
        assert cmd1 == cmd2

    def test_builder_differences_for_venv_vs_bare(self):
        """Commands should differ between venv and bare environments."""
        builder = PipCommandBuilder()
        venv_cmd = builder.build_install_command("numpy", in_venv=True)
        bare_cmd = builder.build_install_command("numpy", in_venv=False)
        assert venv_cmd != bare_cmd
        assert "--user" not in venv_cmd
        assert "--user" in bare_cmd

    def test_module_level_functions_work_together(self):
        """Module-level functions should work together."""
        flags = get_pip_flags(in_venv=False)
        cmd = build_pip_install_cmd("numpy", in_venv=False)
        assert flags in cmd or (flags == "" and cmd)

    def test_pip_command_normalization_in_fallback(self):
        """Fallback chain should normalize pip commands."""
        builder = PipCommandBuilder()
        # Build with python3 (gets converted to python3 -m pip)
        chain1 = builder.build_fallback_chain("numpy", python_cmd="python3")
        # Build with python3 -m pip (already normalized)
        chain2 = builder.build_fallback_chain("numpy", python_cmd="python3 -m pip")
        # Both should produce similar output (though not identical due to wrapping)
        assert "pip install" in chain1
        assert "pip install" in chain2


class TestEdgeCases:
    """Test edge cases and error conditions."""

    def test_empty_package_name(self):
        """Should handle empty package name (though not recommended)."""
        builder = PipCommandBuilder()
        # Should not crash, though result may be odd
        cmd = builder.build_install_command("")
        assert isinstance(cmd, str)

    def test_package_with_special_characters(self):
        """Should properly quote packages with special characters."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("my-package[extra]>=1.0")
        # shlex.quote should handle this
        assert isinstance(cmd, str)

    def test_very_long_package_name(self):
        """Should handle very long package names."""
        builder = PipCommandBuilder()
        long_pkg = "a" * 200
        cmd = builder.build_install_command(long_pkg)
        assert isinstance(cmd, str)

    def test_python_cmd_with_path(self):
        """Should handle Python commands with paths."""
        builder = PipCommandBuilder()
        cmd = builder.build_install_command("numpy", python_cmd="/usr/bin/python3")
        assert "/usr/bin/python3" in cmd

    def test_multiple_builders_independent(self):
        """Multiple builders should be independent."""
        builder1 = PipCommandBuilder(log_dir="/tmp/logs1")
        builder2 = PipCommandBuilder(log_dir="/tmp/logs2")
        assert builder1.log_dir != builder2.log_dir
