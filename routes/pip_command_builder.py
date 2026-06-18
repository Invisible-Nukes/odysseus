"""pip_command_builder.py - Centralized pip command generation logic.

This module consolidates all pip command generation previously scattered across
cookbook_helpers.py. It provides both a class-based interface (PipCommandBuilder)
and module-level functions for building pip install commands with proper:
- Exit code preservation
- Venv detection and handling
- Fallback chain generation
- Cross-platform compatibility
"""

import os
import shlex
import sys
from pathlib import Path


class PipCommandBuilder:
    """Centralized pip command builder with logging and environment awareness."""

    def __init__(self, log_dir: str | None = None):
        """Initialize PipCommandBuilder with optional log directory.

        Args:
            log_dir: Directory for pip logs. Defaults to ${DATA_DIR:-./data}/logs
        """
        self.log_dir = log_dir or os.environ.get("DATA_DIR", "data")
        if not self.log_dir.endswith(("logs", "\\logs", "/logs")):
            self.log_dir = os.path.join(self.log_dir, "logs")

    def detect_in_venv(self) -> bool:
        """Detect if currently running in a venv or conda environment."""
        # Check if in venv: sys.prefix != sys.base_prefix (Python 3.3+)
        if sys.prefix != sys.base_prefix:
            return True
        # Check for conda environment via CONDA_PREFIX
        if os.environ.get("CONDA_PREFIX") and os.environ.get("CONDA_PREFIX") != os.environ.get("CONDA_DEFAULT_ENV"):
            return True
        return False

    def get_pip_flags(self, in_venv: bool = False) -> str:
        """Get appropriate pip flags based on environment.

        Returns --user --break-system-packages only when NOT in venv/conda.
        Inside venv/conda, user installs are not allowed and --break-system-packages
        is not needed.

        Args:
            in_venv: Whether running in a venv/conda environment.
                    If None, auto-detects.

        Returns:
            String of pip flags: "--user --break-system-packages" or ""
        """
        if in_venv:
            return ""
        return "--user --break-system-packages"

    def wrap_with_exit_code_preservation(self, cmd: str) -> str:
        """Wrap a pip command to preserve exit status in a bash subshell.

        The wrapper:
        1. Creates a temp log in ${DATA_DIR:-./data}/logs
        2. Redirects stdout/stderr to the temp log
        3. Captures pip's exit code
        4. Prints last 5 lines on failure, success path on success
        5. Removes temp file
        6. Exits with pip's real exit code (not tail/rm's)

        Args:
            cmd: The pip command to wrap (e.g., "pip install -q package")

        Returns:
            Bash subshell command: bash -c '...'
        """
        # Escape cmd for safe embedding in single-quoted bash string
        escaped_cmd = cmd.replace("'", "'\\''")

        script = (
            f'mkdir -p "{self.log_dir}"; '
            f'export TMPDIR="{self.log_dir}"; '
            f'LOGFILE=$(mktemp); '
            f'{escaped_cmd} >"$LOGFILE" 2>&1; _rc=$?; '
            f'if [ $_rc -eq 0 ]; then echo "OK $LOGFILE"; '
            f'else echo "ERROR (last 5 lines) from $LOGFILE"; tail -5 "$LOGFILE"; fi; '
            f'rm -f "$LOGFILE"; '
            f'exit $_rc'
        )

        return f"bash -c '{script}'"

    def normalize_pip_command(self, python_cmd: str) -> str:
        """Normalize a Python/pip command to a consistent pip format.

        Converts:
        - "python" -> "python -m pip"
        - "python3" -> "python3 -m pip"
        - "pip" -> "pip"
        - "python3 -m pip" -> "python3 -m pip"

        Args:
            python_cmd: The Python or pip command string

        Returns:
            Normalized pip command string
        """
        cmd = python_cmd.strip()

        # Already a pip command or has -m pip
        if " -m pip" in cmd or cmd in {"pip", "pip3"}:
            return cmd

        # Python executable - convert to python -m pip
        if cmd in {"python", "python3", "python.exe"} or cmd.endswith(("/python", "/python3", "\\python.exe")):
            return f"{cmd} -m pip"

        # Return as-is if unclear
        return cmd

    def build_install_command(
        self,
        package: str,
        python_cmd: str = "python3",
        upgrade: bool = False,
        in_venv: bool = False,
    ) -> str:
        """Build a single pip install command.

        Args:
            package: Package name/spec (e.g., "numpy", "llama-cpp-python[server]")
            python_cmd: Python or pip command (defaults to "python3")
            upgrade: Whether to include -U (upgrade) flag
            in_venv: Whether running in venv (disables --user flags)

        Returns:
            A complete pip install command string
        """
        pip_cmd = self.normalize_pip_command(python_cmd)
        upgrade_flag = " -U" if upgrade else ""

        # Shell-quote the package spec to handle extras like [server]
        pkg = shlex.quote(package)

        # Special handling for llama-cpp-python source builds
        if "llama-cpp-python" in package:
            pkg += " --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu"

        pip_flags = self.get_pip_flags(in_venv)

        if pip_flags:
            return f"{pip_cmd} install {pip_flags} -q{upgrade_flag} {pkg}"
        else:
            return f"{pip_cmd} install -q{upgrade_flag} {pkg}"

    def build_fallback_chain(
        self,
        package: str,
        python_cmd: str = "python3",
        upgrade: bool = False,
    ) -> str:
        """Build a bash script with fallback pip install attempts.

        The fallback chain:
        1. Try basic install (system python or venv)
        2. If that fails AND not in venv, try --user install
        3. If --user fails AND pip supports --break-system-packages, try that

        Each attempt is wrapped via wrap_with_exit_code_preservation() so that:
        - Exit codes are preserved (not masked by pipe/tail)
        - Last 5 lines of output appear in logs on failure

        Args:
            package: Package name/spec to install
            python_cmd: Python or pip command
            upgrade: Whether to use -U flag

        Returns:
            A bash command string suitable for subprocess.run(['bash', '-c', result])
        """
        pip_cmd = self.normalize_pip_command(python_cmd)
        upgrade_flag = " -U" if upgrade else ""
        pkg = shlex.quote(package)

        # Special handling for llama-cpp-python
        if "llama-cpp-python" in package:
            pkg += " --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu"

        # Build three attempt levels
        base_cmd = f"{pip_cmd} install -q{upgrade_flag} {pkg}"
        base = self.wrap_with_exit_code_preservation(base_cmd)

        user_cmd = f"{pip_cmd} install --user -q{upgrade_flag} {pkg}"
        user = self.wrap_with_exit_code_preservation(user_cmd)

        user_break_cmd = f"{pip_cmd} install --user --break-system-packages -q{upgrade_flag} {pkg}"
        user_break = self.wrap_with_exit_code_preservation(user_break_cmd)

        # Check if pip supports --break-system-packages
        break_support_check = f"{pip_cmd} install --help 2>/dev/null | grep -q -- --break-system-packages"

        # Fallback: try --user, then try --user + --break-system-packages if supported
        user_fallback = f"( {user} || {{ {break_support_check} && {user_break}; }} )"

        # Derive python executable for venv detection
        if " -m pip" in pip_cmd:
            python_exe = pip_cmd.replace(" -m pip", "")
        elif pip_cmd.strip() == "pip":
            python_exe = "python"
        elif pip_cmd.strip() == "pip3":
            python_exe = "python3"
        else:
            python_exe = "python3"

        # Check if in venv: succeeds (0) when NOT in venv
        venv_check = f'{python_exe} -c "import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)"'

        # If base install fails, try --user only when NOT in venv
        # ! venv_check succeeds when NOT in venv -> try user fallback
        # In venv, ! venv_check fails -> skip user fallback
        return f"{base} || {{ ! {venv_check} && {user_fallback}; }}"


# ============================================================================
# Module-level convenience functions
# ============================================================================


def get_pip_flags(in_venv: bool = False) -> str:
    """Get appropriate pip flags (module-level function).

    Args:
        in_venv: Whether running in a venv/conda environment

    Returns:
        String of pip flags: "--user --break-system-packages" or ""
    """
    builder = PipCommandBuilder()
    return builder.get_pip_flags(in_venv)


def build_pip_install_cmd(
    package: str,
    python_cmd: str = "python3",
    upgrade: bool = False,
    in_venv: bool = False,
) -> str:
    """Build a single pip install command (module-level function).

    Args:
        package: Package name/spec
        python_cmd: Python or pip command
        upgrade: Whether to include -U flag
        in_venv: Whether running in venv

    Returns:
        A complete pip install command string
    """
    builder = PipCommandBuilder()
    return builder.build_install_command(package, python_cmd, upgrade, in_venv)


def build_pip_fallback_chain(
    package: str,
    python_cmd: str = "python3",
    upgrade: bool = False,
) -> str:
    """Build a bash fallback chain for pip install (module-level function).

    Args:
        package: Package name/spec to install
        python_cmd: Python or pip command
        upgrade: Whether to use -U flag

    Returns:
        A bash command string
    """
    builder = PipCommandBuilder()
    return builder.build_fallback_chain(package, python_cmd, upgrade)
