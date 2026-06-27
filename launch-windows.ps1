#Requires -Version 5.1
<#
  Odysseus - native Windows launcher (no Docker).

  One command to: create a virtualenv, install dependencies, run first-time
  setup (prints an admin password on first run), and start the server.
  Safe to re-run - it skips whatever already exists.

  Usage:
    powershell -ExecutionPolicy Bypass -File .\launch-windows.ps1
    powershell -ExecutionPolicy Bypass -File .\launch-windows.ps1 -Port 7000 -BindHost 127.0.0.1

  Tip: bind 127.0.0.1 (default) for local-only use. Use 0.0.0.0 only when you
  intentionally want other devices on your LAN to reach it.
#>
param(
    [int]$Port = 7000,
    [string]$BindHost = "127.0.0.1"
)

$ErrorActionPreference = "Stop"
Set-Location -Path $PSScriptRoot

# Keep all persistent data under the repo-managed data tree by default so
# Ollama, model caches, and app state live with this checkout instead of an
# arbitrary parent directory on the machine.
if (-not $env:ODYSSEUS_DATA_DIR) { $env:ODYSSEUS_DATA_DIR = Join-Path $PSScriptRoot "data" }
if (-not $env:HF_HOME) { $env:HF_HOME = Join-Path $env:ODYSSEUS_DATA_DIR "huggingface" }
if (-not $env:HUGGINGFACE_HUB_CACHE) { $env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME "hub" }
if (-not $env:OLLAMA_HOME) { $env:OLLAMA_HOME = Join-Path $env:ODYSSEUS_DATA_DIR "ollama" }
if (-not $env:OLLAMA_BIN) { $env:OLLAMA_BIN = $env:OLLAMA_HOME }

function Write-Step($msg) { Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host ""
    Write-Host ("ERROR: " + $msg) -ForegroundColor Red
    Write-Host ""
    throw $msg
}

function Test-Url($url) {
    try {
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
        return $true
    } catch {
        return $false
    }
}

function Save-StartupErrorLog($category, $message, $content = "") {
    $logsDir = Join-Path $PSScriptRoot "data\logs"
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $categoryClean = $category.Replace(' ', '_')
    $logPath = Join-Path $logsDir ("error_{0}_{1}.log" -f $categoryClean, $timestamp)
    
    $logContent = @(
        "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        "Category: $category",
        "Message: $message",
        "---",
        $content
    ) -join "`n"
    
    $logContent | Out-File -FilePath $logPath -Encoding UTF8 -Force
    return $logPath
}

function Open-OdysseusBrowser($url) {
    try {
        # Use Windows native start command which properly handles opening in existing browser window
        # The empty string after 'start' is the window title; omitting it prevents opening a cmd window
        cmd /c start "" $url
        Write-Host ("Opened Odysseus in your browser: " + $url) -ForegroundColor Green
    } catch {
        Write-Host ("Could not open the browser automatically: " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

function Get-OdysseusProcesses {
    try {
        $repoRoot = $PSScriptRoot
        $processes = Get-CimInstance Win32_Process
        return $processes | Where-Object {
            if (-not $_.CommandLine) { return $false }
            if ($_.ProcessId -eq $PID) { return $false }
            $cmd = $_.CommandLine
            return ($cmd -match "uvicorn") -or ($cmd -match "app:app") -or ($cmd -match "odysseus") -or ($cmd -match [regex]::Escape($repoRoot))
        }
    } catch {
        return @()
    }
}

function Stop-OdysseusProcesses {
    $procs = Get-OdysseusProcesses
    if (-not $procs) { return }
    Write-Host ""
    Write-Host "Stopping existing Odysseus-related processes..." -ForegroundColor Yellow
    foreach ($proc in $procs) {
        Write-Host ("  PID {0}: {1}" -f $proc.ProcessId, $proc.CommandLine)
        try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Milliseconds 500
}

function Test-WindowsBashStub($path) {
    if (-not $path) { return $false }
    $lowered = $path.ToLowerInvariant()
    foreach ($stub in @("system32\bash.exe", "sysnative\bash.exe", "windowsapps\bash.exe")) {
        if ($lowered.Contains($stub)) { return $true }
    }
    return $false
}

function Find-GitBash {
    $cmd = Get-Command bash -ErrorAction SilentlyContinue
    if ($cmd -and -not (Test-WindowsBashStub $cmd.Source)) { return $cmd.Source }

    $roots = @()
    foreach ($name in @("ProgramFiles", "ProgramW6432", "ProgramFiles(x86)", "LocalAppData")) {
        $base = [Environment]::GetEnvironmentVariable($name)
        if ($base) {
            $roots += (Join-Path $base "Git")
            if ($name -eq "LocalAppData") { $roots += (Join-Path $base "Programs\Git") }
        }
    }
    $roots += @("C:\Program Files\Git", "C:\Program Files (x86)\Git")

    foreach ($root in ($roots | Select-Object -Unique)) {
        foreach ($relative in @("bin\bash.exe", "usr\bin\bash.exe")) {
            $candidate = Join-Path $root $relative
            if (Test-Path $candidate) { return $candidate }
        }
    }
    return $null
}

function Test-OdysseusDepsReady($venvPy) {
    if (-not (Test-Path $venvPy)) { return $false }
    & $venvPy -c "import uvicorn, sqlalchemy" 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-OdysseusDependencies($venvPy, $installLog) {
    $pipArgs = @("-m", "pip", "install", "--retries", "5", "--timeout", "120")
    $attempts = @(
        @{ Label = "pip upgrade"; Args = @($pipArgs + @("--upgrade", "pip")) },
        @{ Label = "requirements.txt"; Args = @($pipArgs + @("-r", "requirements.txt")) }
    )

    foreach ($step in $attempts) {
        $maxTries = 3
        for ($try = 1; $try -le $maxTries; $try++) {
            Write-Host ("  {0} (attempt {1}/{2})..." -f $step.Label, $try, $maxTries)
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            & $venvPy @($step.Args) *> $installLog
            $exitCode = $LASTEXITCODE
            $ErrorActionPreference = $prevEap

            if ($exitCode -eq 0) { break }

            $tail = @()
            if (Test-Path $installLog) {
                $tail = Get-Content -Path $installLog -Tail 30 -ErrorAction SilentlyContinue
            }
            $tailText = ($tail -join "`n")
            $cacheCorrupt = $tailText -match "IncompleteRead|Connection broken|ContentDecodingError|hash mismatch"

            if ($cacheCorrupt -and $try -lt $maxTries) {
                Write-Host "  pip hit a corrupted download/cache entry; purging pip cache and retrying..." -ForegroundColor Yellow
                & $venvPy -m pip cache purge *> $null
                Start-Sleep -Seconds 2
                continue
            }

            Write-Host ("  {0} failed. Last lines from {1}:" -f $step.Label, $installLog) -ForegroundColor Red
            $tail | ForEach-Object { Write-Host $_ }
            Fail "Dependency install failed during $($step.Label). Inspect $installLog for details."
        }
        if ($LASTEXITCODE -ne 0) {
            Fail "Dependency install failed during $($step.Label). Inspect $installLog for details."
        }
    }
}

function Test-ChromaDbReachable($HostName, $Port) {
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $connect = $tcp.BeginConnect($HostName, [int]$Port, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(2), $false)) {
            $tcp.Close()
            return $false
        }
        $reachable = $tcp.Connected
        $tcp.Close()
        return $reachable
    } catch {
        return $false
    }
}

function Get-ChromaDbLauncherPath($venvPy) {
    $chromaExe = Join-Path (Split-Path $venvPy -Parent) "chroma.exe"
    if (Test-Path $chromaExe) { return $chromaExe }
    return $null
}

function Test-ChromaDbPackageReady($venvPy) {
    if (Get-ChromaDbLauncherPath $venvPy) { return $true }
    & $venvPy -m pip show chromadb 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Ensure-ChromaDbPackage($venvPy) {
    $chromaExe = Get-ChromaDbLauncherPath $venvPy
    if ($chromaExe) {
        Write-Host "ChromaDB server already installed in venv - skipping pip install."
        return $chromaExe
    }
    if (Test-ChromaDbPackageReady $venvPy) {
        Write-Host "ChromaDB package found in venv but chroma.exe is missing; repairing..." -ForegroundColor Yellow
        & $venvPy -m pip install -q --force-reinstall chromadb
    } else {
        Write-Host "ChromaDB server not found in venv; installing chromadb (first run can take a minute)..." -ForegroundColor Cyan
        & $venvPy -m pip install -q chromadb
    }
    if ($LASTEXITCODE -ne 0) { return $null }
    $chromaExe = Get-ChromaDbLauncherPath $venvPy
    if ($chromaExe) {
        Write-Host "ChromaDB server installed successfully." -ForegroundColor Green
    }
    return $chromaExe
}

function Start-OdysseusChromaDb($chromaExe, $dataDir, $logsDir) {
    $chromaHost = if ($env:CHROMADB_HOST) { $env:CHROMADB_HOST.Trim() } else { "localhost" }
    $chromaPort = if ($env:CHROMADB_PORT) { [int]$env:CHROMADB_PORT } else { 8100 }
    $localHosts = @("localhost", "127.0.0.1", "::1")
    if ($chromaHost -notin $localHosts) {
        Write-Host ("CHROMADB_HOST=$chromaHost is remote - not starting a local ChromaDB.") -ForegroundColor DarkGray
        return $null
    }

    # Pin probe/bind to IPv4 loopback: Odysseus defaults to localhost:8100 and
    # binding chroma to the literal "localhost" can land on IPv6 ::1 instead.
    $probeHost = "127.0.0.1"
    if (Test-ChromaDbReachable $probeHost $chromaPort) {
        Write-Host ("ChromaDB already running on ${probeHost}:${chromaPort} - using it.") -ForegroundColor Green
        return $null
    }

    if (-not $chromaExe) {
        Write-Host "WARNING: ChromaDB server CLI unavailable. Vector RAG/memory will be degraded." -ForegroundColor Yellow
        return $null
    }

    $chromaDataDir = Join-Path $dataDir "chroma"
    if (-not (Test-Path $chromaDataDir)) {
        New-Item -ItemType Directory -Path $chromaDataDir -Force | Out-Null
    }

    $chromaLog = Join-Path $logsDir ("chromadb_{0}.log" -f (Get-Date).ToString("yyyyMMdd_HHmmss"))
    Write-Host ("Starting ChromaDB on ${probeHost}:${chromaPort} (data: ${chromaDataDir})...") -ForegroundColor Cyan
    Write-Host ("  logging to $chromaLog") -ForegroundColor DarkGray

    $chromaProc = Start-Process -FilePath $chromaExe -ArgumentList @(
        "run", "--host", $probeHost, "--port", [string]$chromaPort, "--path", $chromaDataDir
    ) -PassThru -WindowStyle Hidden -RedirectStandardOutput $chromaLog -RedirectStandardError ($chromaLog + ".err")

    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $chromaProc.Id -ErrorAction SilentlyContinue)) {
            Write-Host "WARNING: ChromaDB exited during startup. Check $chromaLog" -ForegroundColor Yellow
            return $null
        }
        if (Test-ChromaDbReachable $probeHost $chromaPort) {
            Write-Host ("ChromaDB ready on ${probeHost}:${chromaPort}") -ForegroundColor Green
            return $chromaProc.Id
        }
        Start-Sleep -Milliseconds 500
    }

    Write-Host "WARNING: ChromaDB did not become reachable within 30s. Continuing in degraded mode." -ForegroundColor Yellow
    return $chromaProc.Id
}

function Stop-OdysseusChromaDb($processId) {
    if (-not $processId) { return }
    if (-not (Get-Process -Id $processId -ErrorAction SilentlyContinue)) { return }
    Write-Host ""
    Write-Host ("Stopping ChromaDB (PID {0})..." -f $processId) -ForegroundColor Yellow
    try {
        & taskkill.exe /PID $processId /T /F 2>$null | Out-Null
    } catch {
        try { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue } catch {}
    }
}

function Find-GitExe {
    # Try Get-Command first (may be on PATH). If not, probe common Git for Windows install locations.
    $cmd = Get-Command git -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path $env:ProgramFiles "Git\cmd\git.exe"),
        (Join-Path $env:ProgramFiles "Git\bin\git.exe"),
        (Join-Path ([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')) "Git\cmd\git.exe"),
        (Join-Path $env:LocalAppData "Programs\Git\cmd\git.exe"),
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe"
    )
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
}

# If we can find git.exe, ensure its containing dir is on PATH for this process so subsequent commands work.
$gitExe = Find-GitExe
if ($gitExe) {
    $gitBin = Split-Path $gitExe -Parent
    if (-not ($env:PATH.ToLower().Contains($gitBin.ToLower()))) {
        $env:PATH = "$gitBin;$env:PATH"
    }
} else {
    Write-Host ""
    Write-Host "WARNING: git.exe not found on PATH." -ForegroundColor Yellow
    Write-Host "         Install Git for Windows or add its cmd/bin directory to PATH." -ForegroundColor Yellow
    Write-Host "         https://git-scm.com/download/win" -ForegroundColor Yellow
}

# 1. Locate a Python interpreter (3.11+ required)
Stop-OdysseusProcesses
Write-Step "Checking for Python"
function Get-PythonVersionText($launcher, $launcherArgs) {
    try {
        return (& $launcher @launcherArgs -c "import sys; print('.'.join(map(str, sys.version_info[:3])))" 2>$null).Trim()
    } catch {
        return $null
    }
}

$pyExe = $null
$pyArgs = @()
$pyVersion = $null

$pyLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($pyLauncher) {
    foreach ($v in @("-3.13", "-3.12", "-3.11")) {
        $ver = Get-PythonVersionText $pyLauncher.Source @($v)
        if ($ver) {
            $pyExe = $pyLauncher.Source
            $pyArgs = @($v)
            $pyVersion = $ver
            break
        }
    }
}

if (-not $pyExe) {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if ($pythonCmd) {
        $ver = Get-PythonVersionText $pythonCmd.Source @()
        if ($ver) {
            $versionParts = $ver.Split('.')
            $major = [int]$versionParts[0]
            $minor = [int]$versionParts[1]
            if ($major -gt 3 -or ($major -eq 3 -and $minor -ge 11)) {
                $pyExe = $pythonCmd.Source
                $pyVersion = $ver
            }
        }
    }
}

if ($pyExe -like "*WindowsApps*python.exe") {
    $pyCmd = Get-Command py -ErrorAction SilentlyContinue
    if ($pyCmd) {
        $pyExe = $pyCmd.Source
        $pyArgs = @("-3.11")
    }
}

if (-not $pyExe) {
    Fail "Couldn't find Python 3.11+ for Windows setup. Install Python 3.11+ (or open the Python launcher with 'py -3.11') from https://www.python.org/downloads/, then re-run this script."
}
$pythonLabel = ("Using Python {0}: {1} {2}" -f $pyVersion, $pyExe, ($pyArgs -join ' ')).TrimEnd()
Write-Host $pythonLabel

# 2. Create the virtualenv if missing
$venvPy = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
if (-not (Test-Path $venvPy)) {
    Write-Step "Creating virtual environment (venv)"
    & $pyExe @pyArgs -m venv venv
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPy)) { Fail "Failed to create the virtual environment." }
} else {
    Write-Host "venv already exists - skipping creation."
}

# 3. Install / update dependencies (skip when venv already has core packages)
$logsDir = Join-Path $PSScriptRoot "data\logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$installLog = Join-Path $logsDir ("pip_install_$ts.log")

if (Test-OdysseusDepsReady $venvPy) {
    Write-Host "Dependencies already installed in venv - skipping pip install."
} else {
    Write-Step "Installing dependencies (first run can take a few minutes)"
    Write-Host "Installing Python packages; logging to $installLog"
    Install-OdysseusDependencies $venvPy $installLog
    Write-Host ("Dependencies installed successfully (log: " + $installLog + ")") -ForegroundColor Green
}

# 4. First-time setup (creates data dirs, DB, .env, admin user)
Write-Step "Running first-time setup"
& $venvPy setup.py
if ($LASTEXITCODE -ne 0) { Fail "setup.py failed." }

# 5. Friendly note about Git Bash (full Cookbook / agent-shell parity)
if (-not (Find-GitBash)) {
    Write-Host ""
    Write-Host "NOTE: Git Bash (bash.exe) was not found on PATH." -ForegroundColor Yellow
    Write-Host "      The core app works without it. For full Cookbook background" -ForegroundColor Yellow
    Write-Host "      downloads and the agent shell tool, install Git for Windows:" -ForegroundColor Yellow
    Write-Host "      https://git-scm.com/download/win" -ForegroundColor Yellow
}

# 5b. Ensure Ollama headless is available under the Odysseus data tree.
Write-Step "Checking for Ollama"
$ollamaData = $env:ODYSSEUS_DATA_DIR
if (-not $ollamaData) { $ollamaData = Join-Path $PSScriptRoot "data" }
$ollamaDir = Join-Path $ollamaData "ollama"
$ollamaExe = Join-Path $ollamaDir "ollama.exe"

if (-not (Test-Path $ollamaExe)) {
    Write-Host "Ollama not found at $ollamaDir. Attempting install via scripts\install_ollama.ps1" -ForegroundColor Cyan
    $installScript = Join-Path $PSScriptRoot "scripts\install_ollama.ps1"
    if (Test-Path $installScript) {
        & powershell -ExecutionPolicy Bypass -File $installScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Ollama install failed or was skipped. Continuing without Ollama." -ForegroundColor Yellow
        } else {
            if (Test-Path $ollamaExe) {
                $ollamaBin = Split-Path $ollamaExe -Parent
                if (-not ($env:PATH.ToLower().Contains($ollamaBin.ToLower()))) {
                    $env:PATH = "$ollamaBin;$env:PATH"
                }
            }
        }
    } else {
        Write-Host "Install script not found: $installScript" -ForegroundColor Yellow
    }
} else {
    $ollamaBin = Split-Path $ollamaExe -Parent
    if (-not ($env:PATH.ToLower().Contains($ollamaBin.ToLower()))) {
        $env:PATH = "$ollamaBin;$env:PATH"
    }
}

# 5c. ChromaDB backs vector RAG, memory vectors, and the tool index. Install
#     the server package if needed, then start it before uvicorn when
#     CHROMADB_HOST points at this machine. Stops when the launcher exits.
Write-Step "Checking for ChromaDB"
if (-not $env:CHROMADB_HOST) { $env:CHROMADB_HOST = "localhost" }
if (-not $env:CHROMADB_PORT) { $env:CHROMADB_PORT = "8100" }
$chromaExe = Ensure-ChromaDbPackage $venvPy
$startedChromaPid = Start-OdysseusChromaDb $chromaExe $env:ODYSSEUS_DATA_DIR $logsDir

# 6. Point CUDA_PATH at a real CUDA toolkit so GPU llama-cpp-python can import.
$cudaBase = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
if (Test-Path $cudaBase) {
    $cudaBest = Get-ChildItem $cudaBase -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName "bin") } |
        Sort-Object { try { [version]($_.Name -replace "^v", "") } catch { [version]"0.0" } } -Descending |
        Select-Object -First 1
    if ($cudaBest) {
        $env:CUDA_PATH = $cudaBest.FullName
        Write-Host ("Using CUDA_PATH = " + $cudaBest.FullName) -ForegroundColor Cyan
    }
}

# 7. Start the server (use `python -m uvicorn` - bare `uvicorn` may not be on PATH)
Write-Step ("Starting Odysseus at http://{0}:{1}" -f $BindHost, $Port)
$logsDir = Join-Path $PSScriptRoot "data\logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

Write-Host ""
Write-Host "Press Ctrl+C to stop the server at any time." -ForegroundColor Yellow
Write-Host ""

$startupUrl = "http://{0}:{1}" -f $BindHost, $Port

try {
    # Start uvicorn process without output redirection so logs stream to console
    $uvicornProcess = Start-Process -FilePath $venvPy -ArgumentList "-m", "uvicorn", "app:app", "--host", $BindHost, "--port", $Port -PassThru -NoNewWindow
    Write-Host "Starting server..." -ForegroundColor Cyan
    Write-Host ("Server PID: " + $uvicornProcess.Id) -ForegroundColor DarkGray
    Write-Host ""

    # Wait for server to be ready and open browser
    $openTriggered = $false
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $uvicornProcess.Id -ErrorAction SilentlyContinue)) {
            break
        }
        if (Test-Url $startupUrl) {
            if (-not $openTriggered) {
                Open-OdysseusBrowser $startupUrl
                $openTriggered = $true
                Write-Host ""
                Write-Host "✓ Server is ready and browser tab opened" -ForegroundColor Green
                Write-Host "✓ Odysseus is now running at $startupUrl" -ForegroundColor Green
                Write-Host ""
            }
            break
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not $openTriggered -and (Test-Url $startupUrl)) {
        Open-OdysseusBrowser $startupUrl
        Write-Host ""
        Write-Host "✓ Server is ready and browser tab opened" -ForegroundColor Green
        Write-Host "✓ Odysseus is now running at $startupUrl" -ForegroundColor Green
        Write-Host ""
    }

    if (-not (Get-Process -Id $uvicornProcess.Id -ErrorAction SilentlyContinue)) {
        Write-Host ""
        Write-Host "ERROR: Server startup failed (process exited unexpectedly)" -ForegroundColor Red
        Write-Host "Check the terminal output above for error details." -ForegroundColor Red
        return
    }

    # Keep the launcher window open while server runs and stream logs
    Write-Host "═" * 70 -ForegroundColor DarkGray
    Write-Host "Server logs are streaming below. Press Ctrl+C to stop." -ForegroundColor Cyan
    Write-Host "═" * 70 -ForegroundColor DarkGray
    Write-Host ""

    # Monitor the process
    while (Get-Process -Id $uvicornProcess.Id -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 1
    }
    
    Write-Host ""
    Write-Host "Server has stopped." -ForegroundColor Yellow
} catch {
    Write-Host ""
    Write-Host "ERROR: Server startup failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    Stop-OdysseusChromaDb $startedChromaPid
}
