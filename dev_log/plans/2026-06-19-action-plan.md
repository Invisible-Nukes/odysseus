# Action Plan for Tomorrow - 2026-06-19
## Dependency Download Reliability Improvements

---

## Overview
Based on analysis from 2026-06-18, we identified 14 verified real issues. This plan prioritizes fixes by impact, providing implementation details, testing strategy, and code locations.

**Estimated Implementation Time:**
- 🔴 Priority 1 (CUDA Checks): 3-4 hours
- 🔴 Priority 2 (Disk Space): 2-3 hours
- 🔴 Priority 3 (Build Tools): 2-3 hours
- 🟠 Priority 4-6 (Timeouts, Retries, Wheels): 4-5 hours each

---

## Issue #1: CUDA Version Incompatibility Check
**Priority:** 🔴 CRITICAL  
**Impact:** Prevents installation of incompatible vLLM (saves 2GB bandwidth)

### Problem
```
User requests vLLM serve
  ↓
System installs vLLM (2GB download)
  ↓
Runtime fails: "CUDA version 11.0 < required 11.8"
  ↓
User wasted bandwidth, must reinstall
```

### Solution Design
Create new module: `core/cuda_compat.py`

**Functions Needed:**
1. `detect_cuda_version()` - Run `nvcc --version`, parse version
2. `get_package_cuda_requirement(package_name)` - Query requirement
   - vLLM: requires 11.8+
   - llama-cpp-python: requires any CUDA 10.2+
   - torch: requires 11.8+ or 12.x
3. `validate_cuda_compatibility(package, cuda_version)` - Compare versions
4. `get_cuda_recommendation(package)` - Suggest fix

**Integration Points:**
1. `routes/cookbook_routes.py` Line 1341 (before vLLM install)
   ```python
   cuda_version = detect_cuda_version()
   if not validate_cuda_compatibility('vllm', cuda_version):
       return error_response("CUDA 11.8+ required, found: " + cuda_version)
   ```

2. `routes/model_routes.py` (if exists - before serve)

3. `static/js/cookbook-diagnosis.js` (parse CUDA errors)

**Test Strategy:**
- Unit tests for version parsing (11.8 vs 12.0 vs 10.2)
- Mock CUDA detection (test with and without CUDA)
- Integration test: verify error message before install
- Edge cases: No CUDA installed, CUDA detection fails

**Files to Modify:**
- ✏️ Create: `core/cuda_compat.py` (150 lines)
- ✏️ Modify: `routes/cookbook_routes.py` (add 5-10 lines at 1341)
- ✏️ Modify: `tests/test_cuda_compat.py` (new, 40+ tests)

---

## Issue #2: Pre-flight Disk Space Validation
**Priority:** 🔴 CRITICAL  
**Impact:** Prevents partial downloads and corruption

### Problem
```
User starts 10GB model download
  ↓
Disk fills at 8GB
  ↓
Corrupted .incomplete file remains
  ↓
User must manually clean + retry
```

### Solution Design
Create new module: `core/disk_validator.py`

**Functions Needed:**
1. `get_available_disk_space(path)` - Get free space in path
2. `estimate_download_size(huggingface_url)` - HEAD request for Content-Length
3. `get_cache_path(model_name)` - Resolve cache directory
4. `validate_disk_space(model_name, cache_path)` - Compare required vs available
5. `get_disk_recommendation(model_name, cache_path)` - Suggest cleanup

**Integration Points:**
1. `routes/cookbook_routes.py` Line 414 (model download start)
   ```python
   if not validate_disk_space(model_id, cache_path):
       return error_response("Insufficient disk: need 10GB, have 2GB")
   ```

2. `static/js/cookbook-diagnosis.js` (add disk check to serve errors)

3. Error messages should suggest: "Clean cache with: `rm -rf ~/.cache/huggingface/*`"

**Test Strategy:**
- Mock filesystem with limited space
- Test HuggingFace HEAD request (cache size lookup)
- Test cache path resolution (various systems)
- Test recommendation generation
- Edge cases: Network unreachable, permission denied, symlinks

**Files to Modify:**
- ✏️ Create: `core/disk_validator.py` (120 lines)
- ✏️ Modify: `routes/cookbook_routes.py` (add 5-10 lines at 414)
- ✏️ Modify: `tests/test_disk_validator.py` (new, 35+ tests)

---

## Issue #3: Build Tools Prerequisite Validation
**Priority:** 🔴 CRITICAL  
**Impact:** Prevents failed llama.cpp builds

### Problem
```
User requests llama-cpp-python[server] serve
  ↓
System starts: pip install llama-cpp-python[server]
  ↓
Build phase: `git clone https://github.com/ggml-org/llama.cpp` fails
  → "command not found: git"
  ↓
User sees cryptic pip error
```

### Solution Design
Create new module: `core/build_tools_checker.py`

**Functions Needed:**
1. `check_build_tool_available(tool)` - Check if cmake/git/gcc exists
   - Linux: `which cmake`
   - Windows: Check PATH or MSVC SDK
   - macOS: Check Xcode or brew
2. `get_system_build_tools()` - Return available tools
3. `get_required_build_tools(package)` - Return requirements
   - llama-cpp-python: [cmake, git] (or [msvc] on Windows)
   - torch: [cmake] (for some variants)
4. `validate_build_prerequisites(package)` - Check all required
5. `get_build_tool_installation_command(tool)` - Return platform-specific install

**Integration Points:**
1. `routes/cookbook_routes.py` Line 1376 (before llama-cpp-python install)
   ```python
   if not validate_build_prerequisites('llama-cpp-python[server]'):
       missing = get_required_build_tools('llama-cpp-python[server]')
       return error_response(
           f"Missing build tools: {', '.join(missing)}. "
           f"Install with: apt-get install build-essential cmake git"
       )
   ```

2. `start-macos.sh` (macOS: Xcode detection)
3. `setup.py` (Windows: MSVC SDK detection)

**Test Strategy:**
- Mock missing tools and verify detection
- Test across platforms (Linux apt, macOS brew, Windows SDK)
- Test package-to-requirements mapping
- Edge cases: Partial install (cmake but no git), broken PATH, symlinks

**Files to Modify:**
- ✏️ Create: `core/build_tools_checker.py` (140 lines)
- ✏️ Modify: `routes/cookbook_routes.py` (add 8-12 lines at 1376)
- ✏️ Modify: `tests/test_build_tools_checker.py` (new, 40+ tests)

---

## Issue #4: Adaptive Network Timeouts
**Priority:** 🟠 HIGH  
**Impact:** Improves reliability on slow connections

### Problem
```
Remote server over 2Mbps SSH link
  ↓
GPU detection timeout = 10s (hardcoded)
  ↓
nvidia-smi returns in 12s due to SSH latency
  ↓
GPU detection fails, fallback to CPU
```

### Solution Design
Create new module: `core/timeout_config.py`

**Functions Needed:**
1. `detect_network_speed()` - Measure bandwidth to common endpoints
   - Ping response time
   - Small download speed (1MB file)
   - Returns: 'slow' (< 1Mbps), 'medium' (1-10Mbps), 'fast' (> 10Mbps)
2. `get_adaptive_timeout(operation, network_speed)` - Return timeout
   - Operation types: gpu_detection, probe, download, setup
   - Multipliers: slow=3x, medium=1.5x, fast=1x
3. `estimate_download_time(file_size, network_speed)` - Calculate timeout

**Integration Points:**
1. `services/hwfit/hardware.py` Line 45
   ```python
   timeout = get_adaptive_timeout('gpu_detection', detect_network_speed())
   # timeout = 10s * multiplier (instead of hardcoded 10s)
   ```

2. `routes/cookbook_routes.py` Line 1758 (server setup)
   ```python
   timeout = estimate_download_time(package_size, network_speed)
   # timeout = dynamic based on network (instead of hardcoded 120s)
   ```

3. `routes/cookbook_routes.py` Line 1807 (GPU probe)

**Test Strategy:**
- Mock network speed detection
- Test timeout calculations for each operation
- Test fallback on network detection failure
- Edge cases: Network unreachable, extreme slowness

**Files to Modify:**
- ✏️ Create: `core/timeout_config.py` (100 lines)
- ✏️ Modify: `services/hwfit/hardware.py` (5 lines at 45)
- ✏️ Modify: `routes/cookbook_routes.py` (5 lines at 1758, 5 at 1807)
- ✏️ Modify: `tests/test_timeout_config.py` (new, 25+ tests)

---

## Issue #5: Exponential Backoff for Retries
**Priority:** 🟠 HIGH  
**Impact:** Faster success on transient errors, faster failure on permanent errors

### Problem
```
Network hiccup (recovers in 2s)
  ↓
Current: Wait 30s before retry
  ↓
Better: Try again in 2s, then 4s, then 8s...
  ↓
Total time: 30s vs 2s
```

### Solution Design
Modify: `routes/cookbook_routes.py` (retry logic)

**Current Code (Line 710-730):**
```python
_max_retries=10; _attempt=0; _ec=0
while [ $_attempt -lt $_max_retries ]; do
  _attempt=$((_attempt+1))
  # ... try download ...
  if [ $_ec -eq 0 ]; then break; fi
  if [ $_attempt -lt $_max_retries ]; then
    sleep 30  # ← ALWAYS 30 seconds
  fi
done
```

**New Code:**
```python
_max_retries=10; _attempt=0; _ec=0; _backoff=2
while [ $_attempt -lt $_max_retries ]; do
  _attempt=$((_attempt+1))
  # ... try download ...
  if [ $_ec -eq 0 ]; then break; fi
  if [ $_attempt -lt $_max_retries ]; then
    echo "Retry in ${_backoff}s..."
    sleep $_backoff
    # Cap exponential growth at 60s
    _backoff=$((_backoff * 2))
    if [ $_backoff -gt 60 ]; then _backoff=60; fi
  fi
done
```

**Failure Type Detection (Phase 2 - optional):**
- 404 errors: Don't retry
- Auth errors: Don't retry
- Connection timeout: Retry with backoff
- Server error (5xx): Retry with backoff

**Test Strategy:**
- Test exponential sequence: 2, 4, 8, 16, 32, 60, 60...
- Test cap at 60s
- Verify total time for N failures

**Files to Modify:**
- ✏️ Modify: `routes/cookbook_routes.py` (5-10 lines at 710-730)
- ✏️ Modify: `tests/test_cookbook_helpers.py` (add exponential backoff test)

---

## Issue #6: CUDA-Aware Wheel Selection
**Priority:** 🟠 HIGH  
**Impact:** Enables GPU acceleration for llama-cpp-python

### Problem
```
GPU User requests llama-cpp-python
  ↓
Extra index URL: https://...whl/cpu  ← CPU only!
  ↓
Gets CPU wheels, no GPU support
  ↓
Serves at 5 tokens/sec instead of 50 tokens/sec
```

### Solution Design
Modify: `routes/cookbook_helpers.py` Line 267-275

**Current Code:**
```python
if "llama-cpp-python" in package:
    pkg += " --extra-index-url https://abetlen.github.io/llama-cpp-python/whl/cpu"
```

**New Code:**
```python
if "llama-cpp-python" in package:
    from core.cuda_compat import detect_cuda_version
    cuda_version = detect_cuda_version()
    
    if cuda_version and cuda_version >= "11.8":
        # Map version to wheel variant: 11.8→cu118, 12.0→cu120
        cuda_variant = "cu" + cuda_version.replace(".", "")[:3]
        url = f"https://abetlen.github.io/llama-cpp-python/whl/{cuda_variant}"
    else:
        url = "https://abetlen.github.io/llama-cpp-python/whl/cpu"
    
    pkg += f" --extra-index-url {url}"
    
    # Add fallback if primary unreachable
    pkg += " --extra-index-url https://pypi.org/simple"
```

**Mirror Fallback (Phase 2):**
- Primary: abetlen.github.io
- Fallback 1: huggingface.co CDN
- Fallback 2: PyPI (CPU wheels only)

**Test Strategy:**
- Test CUDA version → wheel variant mapping
- Test fallback on HTTP 404
- Test across CUDA versions: 11.8, 12.0, 12.1
- Mock HTTP failures

**Files to Modify:**
- ✏️ Modify: `routes/cookbook_helpers.py` (15-20 lines at 267-275)
- ✏️ Modify: `tests/test_cookbook_helpers.py` (add GPU wheel selection test)

---

## Issue #7: AMD ROCm Support Framework
**Priority:** 🟡 MEDIUM  
**Impact:** Enables AMD GPU users

### Problem
```
AMD GPU User tries to use Odysseus
  ↓
No GPU detection (nvidia-smi only)
  ↓
Serves on CPU (30x slower than GPU)
```

### Solution Design
Create new module: `services/hwfit/rocm_detector.py`

**Functions Needed:**
1. `detect_rocm_version()` - Run `rocm-smi --version`, parse version
2. `get_amd_gpu_info()` - Run `rocm-smi --showproductname` 
   - Returns: GPU model (Radeon RX 7600, MI250X, etc.)
3. `get_gpu_compute_capability()` - Get RDNA/CDNA generation
4. `validate_rocm_compatibility(package)` - Check package supports ROCm

**Integration Points:**
1. `services/hwfit/hardware.py` (add ROCm detection to GPU detection flow)
   ```python
   # After NVIDIA detection fails:
   gpu_info = detect_rocm_version()
   if gpu_info:
       return {
           "type": "amd",
           "vendor": "AMD",
           "model": gpu_info['model'],
           "driver_version": gpu_info['version'],
           "compute_capability": get_gpu_compute_capability()
       }
   ```

2. `routes/cookbook_routes.py` (set `HIP_VISIBLE_DEVICES` for AMD GPUs)

3. `static/js/cookbook-diagnosis.js` (add AMD GPU error patterns)

**Test Strategy:**
- Mock ROCm detection (with and without ROCm)
- Test version parsing
- Test GPU model identification
- Edge cases: Multiple AMD GPUs, AMD+NVIDIA mix

**Files to Modify:**
- ✏️ Create: `services/hwfit/rocm_detector.py` (150 lines)
- ✏️ Modify: `services/hwfit/hardware.py` (10-15 lines)
- ✏️ Modify: `tests/test_rocm_detector.py` (new, 30+ tests)

---

## Implementation Roadmap

### Phase 1: Critical Blockers (Next Session)
**Estimated: 8-10 hours**

1. ✅ CUDA version check (3-4 hours)
   - Test: Prevents vLLM install on CUDA 11.0
   - Commit: "feat: Add CUDA version compatibility check"

2. ✅ Disk space validation (2-3 hours)
   - Test: Prevents download if < 1GB free
   - Commit: "feat: Add pre-flight disk space validation"

3. ✅ Build tools checker (2-3 hours)
   - Test: Prevents llama.cpp build without cmake
   - Commit: "feat: Add build tools prerequisite validation"

### Phase 2: Reliability Improvements (Following Session)
**Estimated: 6-8 hours**

4. ✅ Adaptive timeouts (2-3 hours)
   - Test: 30s timeout on fast, 90s on slow connections
   - Commit: "feat: Implement adaptive network timeouts"

5. ✅ Exponential backoff (1-2 hours)
   - Test: Backoff sequence: 2, 4, 8, 16, 32, 60s
   - Commit: "feat: Implement exponential backoff retry strategy"

6. ✅ CUDA-aware wheels (1-2 hours)
   - Test: GPU user gets cu118 wheels, CPU user gets cpu wheels
   - Commit: "feat: Enable CUDA-specific wheel selection"

### Phase 3: New Platform Support (Future Session)
**Estimated: 4-6 hours**

7. ✅ AMD ROCm support (2-3 hours)
   - Test: Detects AMD GPU and sets HIP_VISIBLE_DEVICES
   - Commit: "feat: Add AMD ROCm GPU support"

---

## Testing Strategy

### Automated Tests
- Unit tests for each new module (see files to modify above)
- Integration tests for dependency installation paths
- Mock tests for GPU detection (test without actual GPU)
- Mock tests for network conditions (fast/slow/offline)

### Manual Testing Checklist
- [ ] vLLM on CUDA 11.8 system (should succeed)
- [ ] vLLM on CUDA 11.0 system (should fail with clear message)
- [ ] Model download with 500MB free space (should fail)
- [ ] llama.cpp serve without cmake (should fail with install command)
- [ ] llama-cpp-python on GPU (should get GPU wheels)
- [ ] llama-cpp-python on CPU (should get CPU wheels)
- [ ] Remote server over SSH (should use adaptive timeout)
- [ ] Large model download on slow network (should use exponential backoff)

### CI/CD Updates
- Add new test files to pytest configuration
- Update GHA workflows to run new test suites
- Add integration test for dependency installation

---

## Success Criteria

### Issue #1: CUDA Check
- ✅ Clear error message before vLLM install on incompatible CUDA
- ✅ No wasted downloads of incompatible packages
- ✅ Error message includes: required version, installed version, fix

### Issue #2: Disk Space
- ✅ Clear error before download starts if insufficient space
- ✅ Disk space check within 2s (not blocking)
- ✅ Suggestion to cleanup cache included in error

### Issue #3: Build Tools
- ✅ Error message lists exactly which tools are missing
- ✅ Platform-specific install command provided
- ✅ Works on Linux, macOS, Windows

### Issue #4: Adaptive Timeouts
- ✅ GPU detection doesn't fail on 2Mbps SSH
- ✅ Large downloads don't timeout on slow networks
- ✅ Fast networks use original short timeouts

### Issue #5: Exponential Backoff
- ✅ Transient errors recover in 2-8s (not 30s)
- ✅ Permanent errors fail faster (not 5 min retries)
- ✅ Total retry time < 5 min for reasonable failure rate

### Issue #6: CUDA Wheels
- ✅ GPU users get CUDA-specific wheels (cu118, cu120, etc.)
- ✅ CPU users get CPU wheels
- ✅ Fallback works if primary index unreachable

### Issue #7: AMD ROCm
- ✅ AMD GPU detected and reported
- ✅ Package selection uses HIP (AMD equivalent of CUDA)
- ✅ Works with Radeon RX and MI series

---

## Code Quality Standards

- **Test Coverage:** ≥ 90% for new modules
- **Documentation:** Docstrings for all functions
- **Error Messages:** Clear, actionable, user-friendly
- **Backwards Compatibility:** No breaking changes to existing APIs
- **Performance:** New checks < 2s overhead

---

## Known Dependencies

- `core/cuda_compat.py` must complete before `routes/cookbook_routes.py` modifications
- `core/disk_validator.py` must complete before `routes/cookbook_routes.py` modifications
- `core/build_tools_checker.py` should complete before `services/hwfit/hardware.py` modifications
- All Phase 1 items should complete before Phase 2 starts

---

## Schedule

**Session 2026-06-19 Goals:**
- ✅ Complete all Phase 1 items
- ✅ All new modules tested and integrated
- ✅ 95%+ test pass rate maintained
- ✅ Zero regressions in existing functionality

**Commit Strategy:**
- Commit each module independently for clear git history
- Include test files with feature commits
- Use conventional commits: `feat:`, `fix:`, `test:`, `docs:`

---

## Monitoring & Iteration

### Metrics to Track
- Download failure rate (target: < 5%)
- Average download time (track before/after)
- GPU detection success rate (target: 99%)
- User error reports (should decrease)

### Feedback Channels
- Error messages logged to `data/logs/`
- User diagnostics available via `/api/diagnostics`
- Session logs in `/dev_log/sessions/`

---

## Reference Documents

- **Analysis Report:** `/dev_log/analysis/2026-06-18-findings.md`
- **Session Log:** `/dev_log/sessions/2026-06-18-session.md`
- **CUDA Issues Report:** `/DEPENDENCY_ANALYSIS_REPORT.md`

---

**Created:** 2026-06-18  
**For Implementation:** 2026-06-19  
**Status:** READY FOR EXECUTION
