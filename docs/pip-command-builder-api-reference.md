# PipCommandBuilder API Reference

## Quick Reference

### Class: `PipCommandBuilder`

```python
from routes.pip_command_builder import PipCommandBuilder

# Initialize
builder = PipCommandBuilder(log_dir=None)
```

#### Methods

**Environment Detection:**
```python
builder.detect_in_venv() -> bool
# Returns True if running in venv or conda, False otherwise
```

**Flag Generation:**
```python
builder.get_pip_flags(in_venv: bool = False) -> str
# Returns "--user --break-system-packages" or "" based on environment
```

**Command Normalization:**
```python
builder.normalize_pip_command(python_cmd: str) -> str
# "python" -> "python -m pip"
# "pip" -> "pip"
# "python3 -m pip" -> "python3 -m pip"
```

**Exit Code Wrapping:**
```python
builder.wrap_with_exit_code_preservation(cmd: str) -> str
# Returns: bash -c '...' with exit code preservation
```

**Single Install Command:**
```python
builder.build_install_command(
    package: str,
    python_cmd: str = "python3",
    upgrade: bool = False,
    in_venv: bool = False
) -> str
# Example: "python3 -m pip install --user --break-system-packages -q numpy"
```

**Fallback Chain:**
```python
builder.build_fallback_chain(
    package: str,
    python_cmd: str = "python3",
    upgrade: bool = False
) -> str
# Returns bash script with 3-tier fallback + venv detection
```

### Module-Level Functions

```python
from routes.pip_command_builder import (
    get_pip_flags,
    build_pip_install_cmd,
    build_pip_fallback_chain
)

# Get flags for environment
flags = get_pip_flags(in_venv=False)

# Build single command
cmd = build_pip_install_cmd(
    package="numpy",
    python_cmd="python3",
    upgrade=False,
    in_venv=False
)

# Build fallback chain
chain = build_pip_fallback_chain(
    package="numpy",
    python_cmd="python3",
    upgrade=False
)
```

---

## Usage Examples

### Example 1: Simple bare environment install
```python
builder = PipCommandBuilder()
cmd = builder.build_install_command("torch")
# python3 -m pip install --user --break-system-packages -q torch
```

### Example 2: Venv install (no user flags)
```python
cmd = builder.build_install_command("torch", in_venv=True)
# python3 -m pip install -q torch
```

### Example 3: Upgrade package
```python
cmd = builder.build_install_command("numpy", upgrade=True)
# python3 -m pip install --user --break-system-packages -q -U numpy
```

### Example 4: With custom Python command
```python
cmd = builder.build_install_command(
    "torch",
    python_cmd="/usr/bin/python3.11"
)
# /usr/bin/python3.11 -m pip install --user --break-system-packages -q torch
```

### Example 5: Fallback chain (detects venv automatically)
```python
chain = builder.build_fallback_chain("torch")
# bash -c 'base_install || { ! venv_check && user_install; }'
```

### Example 6: Wrapped command with exit code preservation
```python
wrapped = builder.wrap_with_exit_code_preservation("pip install numpy")
# bash -c 'mkdir -p logs; LOGFILE=$(mktemp); pip install numpy >"$LOGFILE" 2>&1; _rc=$?; ...; exit $_rc'
```

### Example 7: Using module-level functions
```python
from routes.pip_command_builder import build_pip_fallback_chain

chain = build_pip_fallback_chain("transformers", upgrade=True)
# Use in subprocess.run(['bash', '-c', chain])
```

---

## Behavior Details

### Pip Flags Strategy
```python
Environment         | Flags                                  | Reason
==================================================================================
Bare Python         | --user --break-system-packages         | Allow user install + PEP 668 compat
Virtual Env (venv)  | (empty)                               | User installs invalid in venv
Conda Environment   | (empty)                               | Conda manages site-packages
```

### Package Handling
```python
Input                              | Output
==============================================================================================
"numpy"                           | 'numpy'
"package[extra]"                  | 'package[extra]'
"llama-cpp-python"                | 'llama-cpp-python' + --extra-index-url https://...
"llama-cpp-python[server]"        | 'llama-cpp-python[server]' + --extra-index-url https://...
```

### Python Command Normalization
```python
Input                          | Output
==============================================================================================
"python"                       | python -m pip
"python3"                      | python3 -m pip
"python.exe"                   | python.exe -m pip
"pip"                          | pip
"pip3"                         | pip3
"python3 -m pip"               | python3 -m pip
"/usr/bin/python3"             | /usr/bin/python3 -m pip
```

### Exit Code Preservation Wrapper
```
Input:  pip install numpy
Output: bash -c 'mkdir -p "data/logs"; 
                 export TMPDIR="data/logs"; 
                 LOGFILE=$(mktemp); 
                 pip install numpy >"$LOGFILE" 2>&1; 
                 _rc=$?; 
                 if [ $_rc -eq 0 ]; then echo "OK $LOGFILE"; 
                 else echo "ERROR"; tail -5 "$LOGFILE"; fi; 
                 rm -f "$LOGFILE"; 
                 exit $_rc'

Key features:
- Captures pip exit code (doesn't mask with tail)
- Shows last 5 lines on failure
- Cleans up temp file
- Uses configured log directory
```

### Fallback Chain Strategy
```
Step 1: Try basic install
   -> Base pip install without --user

Step 2: If fails AND not in venv
   -> Try with --user flag
   
Step 3: If --user fails AND pip supports it
   -> Try --user --break-system-packages

Venv Detection:
   -> python -c "import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)"
   -> Exit 0 = not in venv (try --user)
   -> Exit 1 = in venv (skip --user)
```

---

## Integration with subprocess

### Running a single command
```python
import subprocess
from routes.pip_command_builder import PipCommandBuilder

builder = PipCommandBuilder()
cmd = builder.build_install_command("numpy", in_venv=False)
result = subprocess.run([cmd], shell=True, capture_output=True, text=True)
```

### Running a fallback chain
```python
import subprocess
from routes.pip_command_builder import build_pip_fallback_chain

chain = build_pip_fallback_chain("torch")
result = subprocess.run(
    ["bash", "-c", chain],
    capture_output=True,
    text=True,
    timeout=300
)
```

### Running wrapped command
```python
import subprocess
from routes.pip_command_builder import PipCommandBuilder

builder = PipCommandBuilder()
wrapped = builder.wrap_with_exit_code_preservation("pip install -q numpy")
result = subprocess.run(
    ["bash", "-c", wrapped],
    capture_output=True,
    text=True
)
print(f"Return code: {result.returncode}")
print(f"Stdout: {result.stdout}")
```

---

## Environment Variables

### `DATA_DIR`
- Used to determine log directory
- Default: `./data`
- Override: `os.environ["DATA_DIR"] = "/custom/path"`

### `CONDA_PREFIX`
- Used for conda environment detection
- Checked alongside `sys.prefix` for venv detection

### `CONDA_DEFAULT_ENV`
- Checked to differentiate conda environments

---

## Limitations & Notes

1. **Bash required** for fallback chains and wrapped commands
   - Use on Windows with Git Bash, WSL, or MSYS2

2. **No --break-system-packages check in build methods**
   - Fallback chain includes check automatically
   - Single commands assume support (use fallback chain for safety)

3. **Cannot handle complex shell metacharacters in package names**
   - Package names are shlex.quote()'d but embedded in bash
   - Use fallback chain for robustness

4. **Python 3.10+ required**
   - Uses union type syntax: `str | None`

5. **Windows log paths**
   - Backslashes in paths may need escaping in bash contexts
   - Use forward slashes when possible
