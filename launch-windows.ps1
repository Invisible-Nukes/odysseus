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
$script:EffectiveDataDir = $env:ODYSSEUS_DATA_DIR
if (-not $script:EffectiveDataDir) { $script:EffectiveDataDir = Join-Path $PSScriptRoot "data" }
if (-not [System.IO.Path]::IsPathRooted($script:EffectiveDataDir)) {
    $script:EffectiveDataDir = Join-Path $PSScriptRoot $script:EffectiveDataDir
}
$script:EffectiveDataDir = [System.IO.Path]::GetFullPath($script:EffectiveDataDir)
$env:ODYSSEUS_LAUNCHER_MODE = "1"
$env:ODYSSEUS_DATA_DIR = $script:EffectiveDataDir

# Keep all persistent data under the repo-managed data tree by default so
# Ollama, model caches, and app state live with this checkout instead of an
# arbitrary parent directory on the machine.
if (-not $env:HF_HOME) { $env:HF_HOME = Join-Path $script:EffectiveDataDir "huggingface" }
if (-not $env:HUGGINGFACE_HUB_CACHE) { $env:HUGGINGFACE_HUB_CACHE = Join-Path $env:HF_HOME "hub" }
if (-not $env:OLLAMA_HOME) { $env:OLLAMA_HOME = Join-Path $script:EffectiveDataDir "ollama" }
if (-not $env:OLLAMA_BIN) { $env:OLLAMA_BIN = $env:OLLAMA_HOME }

function Write-Step($msg) { Write-Host ""; Write-Host ("==> " + $msg) -ForegroundColor Cyan }
function Wait-For-LauncherExit($message) {
    Write-Host ""
    if ($message) { Write-Host $message -ForegroundColor Yellow }
    Write-Host "Press Enter to close this window." -ForegroundColor Yellow
    try { Read-Host | Out-Null } catch {}
}

function Fail($msg) {
    Write-Host ""
    Write-Host ("ERROR: " + $msg) -ForegroundColor Red
    Write-Host ""
    Wait-For-LauncherExit "The launcher stopped because an error occurred."
    throw $msg
}

function Save-StartupErrorLog($context, $message, $details) {
    $logsDir = Join-Path $script:EffectiveDataDir "logs"
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }

    $ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $logPath = Join-Path $logsDir ("startup_error_{0}.log" -f $ts)

    $body = @(
        "Context: $context",
        "Message: $message",
        "",
        ($details -as [string])
    ) -join [Environment]::NewLine

    Set-Content -Path $logPath -Value $body -Encoding UTF8
    return $logPath
}

function Show-LogTail($logPath, $label, $tailLines = 40) {
    if (-not (Test-Path $logPath)) { return }

    $lines = Get-Content -Path $logPath -Tail $tailLines -ErrorAction SilentlyContinue
    if (-not $lines -or $lines.Count -eq 0) { return }

    Write-Host ("[progress] {0} (latest {1} lines)" -f $label, $lines.Count) -ForegroundColor DarkGray
    foreach ($line in $lines) {
        Write-Host ("    {0}" -f $line) -ForegroundColor DarkGray
    }
}

function Invoke-LoggedCommand($filePath, $argumentList, $logPath, $label) {
    $logDir = Split-Path -Path $logPath -Parent
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    if (Test-Path $logPath) { Remove-Item -Path $logPath -Force -ErrorAction SilentlyContinue }

    Write-Host ("[progress] Running {0}..." -f $label) -ForegroundColor Cyan
    Write-Host ("[progress] Log file: {0}" -f $logPath) -ForegroundColor DarkGray

    $exitCode = 0
    & $filePath @argumentList 2>&1 |
        Tee-Object -FilePath $logPath |
        ForEach-Object {
            Write-Host ("    {0}" -f $_) -ForegroundColor DarkGray
            if ($_ -match 'error|failed|fatal|Traceback') { Write-Host ("    [warn] {0}" -f $_) -ForegroundColor Yellow }
        }
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        throw ("{0} failed with exit code {1}. See {2}" -f $label, $exitCode, $logPath)
    }
}

function Test-Url($url) {
    try {
        $null = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
        return $true
    } catch {
        return $false
    }
}

function Open-OdysseusBrowser($url) {
    $attempts = @(
        { Start-Process -FilePath $url -ErrorAction Stop },
        { Start-Process -FilePath "explorer.exe" -ArgumentList $url -ErrorAction Stop }
    )

    foreach ($attempt in $attempts) {
        try {
            & $attempt
            Write-Host ("Opened Odysseus in your default browser: " + $url) -ForegroundColor Green
            return $true
        } catch {
            Write-Host ("Browser open attempt failed: " + $_.Exception.Message) -ForegroundColor DarkYellow
        }
    }

    Write-Host ("Could not open the browser automatically. Please open this URL manually: " + $url) -ForegroundColor Yellow
    return $false
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
    $procs = Get-OdysseusProcesses | Sort-Object ProcessId -Unique
    if (-not $procs) { return }

    Write-Host ""
    Write-Host "Stopping existing Odysseus-related processes..." -ForegroundColor Yellow
    foreach ($proc in $procs) {
        Write-Host ("  PID {0}: {1}" -f $proc.ProcessId, $proc.CommandLine)
        try {
            & taskkill /F /T /PID $proc.ProcessId 2>$null | Out-Null
        } catch {}
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        } catch {}
    }
    Start-Sleep -Milliseconds 1000

    # Give Windows a moment to release sockets and child handles before we reset state.
    $stillRunning = Get-OdysseusProcesses | Where-Object { $_.ProcessId -in ($procs | Select-Object -ExpandProperty ProcessId) }
    if ($stillRunning) {
        Start-Sleep -Milliseconds 1500
    }
}

function Clear-OdysseusRuntimeArtifacts {
    $artifactRoots = @(
        (Join-Path $script:EffectiveDataDir "logs"),
        (Join-Path $script:EffectiveDataDir "cache"),
        (Join-Path $script:EffectiveDataDir "downloads"),
        (Join-Path $script:EffectiveDataDir "generated_images"),
        (Join-Path $script:EffectiveDataDir "tts_cache")
    )

    foreach ($root in $artifactRoots) {
        if (Test-Path $root) {
            Write-Host ("Clearing stale runtime artifacts under {0}" -f $root) -ForegroundColor DarkGray
            Get-ChildItem -Path $root -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Get-ChildItem -Path $PSScriptRoot -Recurse -Directory -Filter "__pycache__" -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $PSScriptRoot -Recurse -File -Filter "*.pyc" -Force -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $PSScriptRoot -Recurse -Directory -Filter ".pytest_cache" -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
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

# 1. Stop any stale Odysseus runtime, then wipe old logs/cache before reloading venv.
Stop-OdysseusProcesses
Clear-OdysseusRuntimeArtifacts
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
$altVenvPy = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (Test-Path $venvPy) {
    Write-Host "venv already exists - skipping creation."
} elseif (Test-Path $altVenvPy) {
    Write-Host ".venv already exists - using it."
    $venvPy = $altVenvPy
} else {
    Write-Step "Creating virtual environment (venv)"
    & $pyExe @pyArgs -m venv venv
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPy)) { Fail "Failed to create the virtual environment." }
}
Write-Step "Installing dependencies (first run can take a few minutes)"
# Write full pip output to a timestamped log under the repo-managed data/logs
# so failures are visible in the same checkout-local tree.
$logsDir = Join-Path $script:EffectiveDataDir "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$ts = (Get-Date).ToString("yyyyMMdd_HHmmss")
$installLog = Join-Path $logsDir ("pip_install_$ts.log")

Write-Host "Installing Python packages; logging to $installLog"
try {
    Invoke-LoggedCommand -filePath $venvPy -argumentList @("-m", "pip", "install", "--upgrade", "pip") -logPath $installLog -label "pip upgrade"
} catch {
    Write-Host ("pip upgrade failed. See " + $installLog) -ForegroundColor Red
    Show-LogTail $installLog "pip upgrade" 100
    Fail "Dependency install failed during pip upgrade. See the log above."
}

try {
    Invoke-LoggedCommand -filePath $venvPy -argumentList @("-m", "pip", "install", "-r", "requirements.txt") -logPath $installLog -label "pip install -r requirements.txt"
} catch {
    Write-Host ("Dependency install failed. Last 100 lines from " + $installLog + ":") -ForegroundColor Red
    Show-LogTail $installLog "pip install" 100
    Fail "Dependency install failed. Inspect $installLog for details."
}
Write-Host ("Dependencies installed successfully (log: " + $installLog + ")") -ForegroundColor Green

# 4. First-time setup (creates data dirs, DB, .env, admin user)
Write-Step "Running first-time setup"
$setupPy = Join-Path $PSScriptRoot "setup.py"
$setupLog = Join-Path $logsDir ("setup_{0}.log" -f $ts)
$env:ODYSSEUS_LAUNCHER_MODE = "1"
$env:ODYSSEUS_DATA_DIR = $script:EffectiveDataDir
Write-Host ("[progress] Running setup.py...") -ForegroundColor Cyan
Write-Host ("[progress] Log file: {0}" -f $setupLog) -ForegroundColor DarkGray
try {
    # Run setup.py interactively (not through Tee-Object) to allow stdin for credential prompts
    & $venvPy $setupPy 2>&1 | Tee-Object -FilePath $setupLog
    if ($LASTEXITCODE -ne 0) {
        throw ("setup.py failed with exit code {0}. See {1}" -f $LASTEXITCODE, $setupLog)
    }
} catch {
    Write-Host "setup.py failed. See log: $setupLog" -ForegroundColor Red
    Show-LogTail $setupLog "setup.py" 100
    Fail "setup.py failed."
}

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
$ollamaData = $script:EffectiveDataDir
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
$logsDir = Join-Path $script:EffectiveDataDir "logs"
if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$startupLog = Join-Path $logsDir ("uvicorn_{0}.log" -f $timestamp)
$startupErrLog = Join-Path $logsDir ("uvicorn_err_{0}.log" -f $timestamp)

Write-Host ("Server log: " + $startupLog) -ForegroundColor Green
Write-Host ("Server stderr log: " + $startupErrLog) -ForegroundColor DarkGray
Write-Host "Press Ctrl+C to stop the server when you are done." -ForegroundColor Yellow
Write-Host ""

$startupUrl = "http://{0}:{1}" -f $BindHost, $Port

try {
    $uvicornProcess = Start-Process -FilePath $venvPy -ArgumentList "-m", "uvicorn", "app:app", "--host", $BindHost, "--port", $Port -RedirectStandardOutput $startupLog -RedirectStandardError $startupErrLog -PassThru -NoNewWindow
    Write-Host "Starting server in the background..." -ForegroundColor Cyan
    Write-Host ("Server PID: " + $uvicornProcess.Id) -ForegroundColor DarkGray

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
            }
            break
        }
        Show-LogTail $startupLog "uvicorn startup" 25
        Start-Sleep -Seconds 2
    }

    if (-not $openTriggered -and (Test-Url $startupUrl)) {
        Open-OdysseusBrowser $startupUrl
    }

    if (-not (Get-Process -Id $uvicornProcess.Id -ErrorAction SilentlyContinue)) {
        $logPath = Save-StartupErrorLog "uvicorn startup" "Uvicorn exited before the app became ready" (Get-Content -Path $startupLog -Raw -ErrorAction SilentlyContinue)
        Write-Host "Server startup failed. See log: $logPath" -ForegroundColor Red
        foreach ($logFile in @($startupLog, $startupErrLog)) {
            if (Test-Path $logFile) {
                Get-Content -Path $logFile -Tail 100 | ForEach-Object { Write-Host $_ }
            }
        }
        Wait-For-LauncherExit "The launcher will stay open so you can inspect the error output."
        return
    }

    Write-Host "Odysseus is running. Keep this window open to keep the server alive." -ForegroundColor Green
    while (Get-Process -Id $uvicornProcess.Id -ErrorAction SilentlyContinue) {
        Start-Sleep -Seconds 5
    }
    Wait-For-LauncherExit "Odysseus has stopped."
} catch {
    $logPath = Save-StartupErrorLog "uvicorn startup" "Uvicorn threw an exception" $_
    Write-Host "Server startup failed. See log: $logPath" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    Wait-For-LauncherExit "The launcher will stay open so you can inspect the error output."
    return
}
