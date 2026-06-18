# PipCommandBuilder Refactoring - Completion Summary

## Overview
Successfully created a centralized `PipCommandBuilder` class that consolidates all pip command generation logic previously scattered across `routes/cookbook_helpers.py`. The new module is fully tested, documented, and ready for integration.

---

## Files Created

### 1. **routes/pip_command_builder.py** (350+ lines)
Centralized pip command generation module with:

#### **Class: PipCommandBuilder**
A stateful builder class for creating pip install commands with environment awareness.

**Constructor:**
```python
__init__(self, log_dir: str | None = None)
```
- Accepts optional log directory (defaults to `${DATA_DIR:-./data}/logs`)
- Respects `DATA_DIR` environment variable

**Core Methods:**

1. **`detect_in_venv() -> bool`**
   - Detects if running in venv (checks `sys.prefix != sys.base_prefix`)
   - Also detects conda environments via `CONDA_PREFIX`

2. **`get_pip_flags(in_venv: bool = False) -> str`**
   - Returns `"--user --break-system-packages"` when NOT in venv
   - Returns `""` (empty) when in venv (user flags are invalid in venv)

3. **`normalize_pip_command(python_cmd: str) -> str`**
   - Converts `python` → `python -m pip`
   - Converts `python3` → `python3 -m pip`
   - Leaves `pip` and `pip3` unchanged
   - Handles paths like `/usr/bin/python3`

4. **`wrap_with_exit_code_preservation(cmd: str) -> str`**
   - Wraps pip commands in bash subshell to:
     - Create temp log in configured directory
     - Capture pip's exit code (`_rc=$?`)
     - Print last 5 lines on failure
     - Exit with pip's real status (not tail's)
   - Returns: `bash -c '...'` format

5. **`build_install_command(package: str, python_cmd: str = 'python3', upgrade: bool = False, in_venv: bool = False) -> str`**
   - Builds single pip install command
   - Handles package specs with extras: `llama-cpp-python[server]`
   - Special handling for `llama-cpp-python` (adds wheel index URL)
   - Example output: `python3 -m pip install --user --break-system-packages -q numpy`

6. **`build_fallback_chain(package: str, python_cmd: str = 'python3', upgrade: bool = False) -> str`**
   - Generates bash script with 3-tier fallback:
     1. Basic install (system or venv python)
     2. User install (if not in venv)
     3. User + --break-system-packages (if supported)
   - Each attempt wrapped with exit code preservation
   - Includes venv detection: skips user flags when in venv

**Module-Level Functions:**
```python
def get_pip_flags(in_venv: bool = False) -> str
def build_pip_install_cmd(...) -> str
def build_pip_fallback_chain(...) -> str
```

---

### 2. **tests/test_pip_command_builder.py** (550+ lines)
Comprehensive test suite with **53 tests** organized in 8 test classes:

#### **Test Classes:**

1. **TestPipCommandBuilderInit** (3 tests)
   - Default log directory initialization
   - Custom log directory handling
   - Environment variable respect

2. **TestDetectInVenv** (4 tests)
   - Current interpreter detection
   - Mocked sys.prefix detection
   - Conda environment detection

3. **TestGetPipFlags** (4 tests)
   - Flags for bare environment
   - Flags for venv environment
   - Module-level function testing

4. **TestNormalizePipCommand** (7 tests)
   - Python → python -m pip conversion
   - Pip command passthrough
   - Windows .exe handling
   - Whitespace handling

5. **TestWrapWithExitCodePreservation** (10 tests)
   - Bash -c format verification
   - $(mktemp) inclusion
   - Exit code capture `_rc=$?`
   - Real exit status preservation
   - No bare pipe tail (prevents masking)
   - Conditional tail placement
   - Log file cleanup
   - Single quote escaping
   - Command argument preservation
   - Log directory configuration

6. **TestBuildInstallCommand** (8 tests)
   - Bare environment (includes user flags)
   - Venv environment (no user flags)
   - Upgrade flag (-U) handling
   - Extras notation handling (e.g., [server])
   - llama-cpp-python special handling
   - Various pip commands (pip, python, python3)
   - Module-level function

7. **TestBuildFallbackChain** (8 tests)
   - Base install attempt inclusion
   - User fallback inclusion
   - --break-system-packages support check
   - Venv detection in chain
   - Exit code preservation wrapping
   - Upgrade flag handling
   - llama-cpp-python URL injection
   - Module-level function

8. **TestIntegration** (4 tests)
   - Command consistency
   - Venv vs bare differences
   - Module-level function cooperation
   - pip command normalization

9. **TestEdgeCases** (5 tests)
   - Empty package names
   - Special characters in packages
   - Very long package names
   - Python commands with paths
   - Multiple builder independence

#### **Test Results:**
✅ **53 tests PASSED** (0 failed)
- Coverage: All major code paths tested
- Edge cases: Empty strings, special characters, long names
- Integration: Cross-function compatibility
- Regression: Existing tests still pass (18 pip-related tests in cookbook_helpers)

---

## Key Implementation Details

### Exit Code Preservation Logic
```python
# Wrapped command structure:
bash -c 'mkdir -p "$LOG_DIR"; 
         LOGFILE=$(mktemp); 
         <pip_cmd> >"$LOGFILE" 2>&1; 
         _rc=$?; 
         if [ $_rc -eq 0 ]; then echo "OK $LOGFILE"; 
         else echo "ERROR (last 5 lines)"; tail -5 "$LOGFILE"; fi; 
         rm -f "$LOGFILE"; 
         exit $_rc'
```
- Ensures pip's exit code is preserved (not masked by tail/rm)
- Visible on failure, clean on success

### Fallback Chain Logic
```python
# 1. Try basic install
base_attempt

# 2. If fails AND not in venv, try with --user
|| { ! venv_check && (user_attempt || 
    (break_support_check && user_break_attempt)) }
```
- Venv detection prevents invalid --user flag usage
- Graceful degradation when --break-system-packages not supported

### Venv Detection
```python
python3 -c "import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)"
```
- Returns 0 (success) when NOT in venv
- Used in negated conditionals: `! venv_check && use_user_flags`

---

## Verification

### Module Importability
```python
✓ from routes.pip_command_builder import PipCommandBuilder
✓ from routes.pip_command_builder import build_pip_install_cmd
✓ from routes.pip_command_builder import build_pip_fallback_chain
✓ from routes.pip_command_builder import get_pip_flags
```

### Test Execution
```
Platform: win32 (Windows)
Python: 3.13.5
pytest: 9.1.0

Tests collected: 53
Passed: 53 (100%)
Failed: 0
Warnings: 1 (unrelated to new code)
Execution time: 0.43s
```

### Existing Tests
```
Existing pip tests in cookbook_helpers: 18 tests
Status: All PASSED ✓
No regressions detected
```

---

## Example Usage

### Example 1: Build basic install command
```python
builder = PipCommandBuilder()
cmd = builder.build_install_command("numpy", in_venv=False)
# Output: python3 -m pip install --user --break-system-packages -q numpy
```

### Example 2: Venv-aware install
```python
cmd = builder.build_install_command("numpy", in_venv=True)
# Output: python3 -m pip install -q numpy
# (no --user flags, only -q for quiet)
```

### Example 3: Fallback chain with venv detection
```python
chain = builder.build_fallback_chain("torch")
# Output: bash -c '...venv_check...base_install...user_fallback...'
```

### Example 4: Exit code preservation
```python
wrapped = builder.wrap_with_exit_code_preservation("pip install numpy")
# Output: bash -c 'mkdir -p ...; LOGFILE=$(mktemp); pip install numpy >"$LOGFILE" ...'
```

### Example 5: Module-level functions
```python
from routes.pip_command_builder import build_pip_install_cmd, get_pip_flags

flags = get_pip_flags(in_venv=False)
cmd = build_pip_install_cmd("numpy")
```

---

## Consolidated Logic

The new module consolidates these functions from `cookbook_helpers.py`:

| Source Function | New Location | Status |
|-----------------|--------------|--------|
| `_pip_install_attempt()` | `wrap_with_exit_code_preservation()` | ✓ Refactored |
| `_pip_install_fallback_chain()` | `build_fallback_chain()` | ✓ Refactored |
| `_pip_command()` | `normalize_pip_command()` | ✓ Refactored |
| `_venv_safe_local_pip_install_cmd()` | `get_pip_flags()` + venv detection | ✓ Refactored |
| `_append_pip_install_runner_lines()` | Not included (complex guard logic) | — |
| `_user_shell_path_bootstrap()` | Not included (bootstrap logic) | — |

---

## Design Decisions

### Why a Class?
- Stateful builder pattern for consistent configuration
- Single `log_dir` initialization rather than repeated parameter passing
- Easier to extend with additional methods
- Clear separation of concerns

### Why Module-Level Functions Too?
- Backward compatibility for simple use cases
- Drop-in replacement for existing scattered functions
- Convenience for one-off builds

### Why Consolidate Only Pip Logic?
- `_append_pip_install_runner_lines()`: Complex guard logic for --break-system-packages support checking
- `_user_shell_path_bootstrap()`: Platform-specific shell bootstrapping
- These are orthogonal concerns that can be addressed separately

---

## Next Steps (Not Yet Implemented)

1. **Refactor cookbook_helpers.py** to use `PipCommandBuilder`
2. **Update all call sites** to use new module instead of old functions
3. **Deprecate old functions** once all callers migrated
4. **Add to documentation** for future developers

---

## Files Modified/Created

```
✓ routes/pip_command_builder.py                (NEW - 350+ lines)
✓ tests/test_pip_command_builder.py            (NEW - 550+ lines, 53 tests)
✓ demo_pip_command_builder.py                  (NEW - demonstration script)
  
Total Lines of Code: 900+
Total Test Cases: 53
Test Pass Rate: 100% (53/53)
```

---

## Maintenance Notes

- No external dependencies (uses only stdlib: `os`, `shlex`, `sys`, `pathlib`)
- Compatible with Python 3.10+ (uses `|` union type syntax)
- Cross-platform (Windows, macOS, Linux)
- Tested on Python 3.13.5, pytest 9.1.0
- Ready for integration into existing codebase
