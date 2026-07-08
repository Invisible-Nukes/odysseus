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

function Test-IsHermesAgentPython($pyExe) {
    if (-not $pyExe) { return $false }
    $resolved = $null
    try { $resolved = (Resolve-Path -Path $pyExe -ErrorAction Stop).Path } catch { return $false }
    $homeMarker = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent'
    return $resolved.ToLowerInvariant().Contains($homeMarker.ToLowerInvariant())
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
    try {
        $result = & $venvPy -c "import fastapi, uvicorn, sqlalchemy, bcrypt, httpx, dotenv" 2>&1
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Invoke-PipMirrorFallback($stepLabel, $installLog, $venvPy, $stepArgs, [ref]$mirrorFallbackUsed) {
    if ($mirrorFallbackUsed.Value -or $env:ODYSSEUS_PIP_MIRROR) {
        return $false
    }

    $tail = @()
    if (Test-Path $installLog) {
        $tail = Get-Content -Path $installLog -Tail 30 -ErrorAction SilentlyContinue
    }
    $tailText = ($tail -join "`n")
    if ($tailText -notmatch "ConnectionResetError|10054|retryable network reset") {
        return $false
    }

    $script:prevUserPipEnv.PIP_INDEX_URL       = $env:PIP_INDEX_URL
    $script:prevUserPipEnv.PIP_EXTRA_INDEX_URL = $env:PIP_EXTRA_INDEX_URL
    $env:PIP_INDEX_URL       = "https://pypi.tuna.tsinghua.edu.cn/simple"
    $env:PIP_EXTRA_INDEX_URL = $null
    $mirrorFallbackUsed.Value = $true

    Write-Host ("[MIRROR-FALLBACK] PyPI ConnectionResetError/10054 detected; switched PIP_INDEX_URL to Tsinghua mirror and cleared PIP_EXTRA_INDEX_URL; retrying {0}..." -f $stepLabel) -ForegroundColor Yellow

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $venvPy @($stepArgs) *> $installLog
    $mirrorExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEap

    $env:PIP_INDEX_URL       = $script:prevUserPipEnv.PIP_INDEX_URL
    $env:PIP_EXTRA_INDEX_URL = $script:prevUserPipEnv.PIP_EXTRA_INDEX_URL

    if ($mirrorExit -eq 0) {
        $LASTEXITCODE = 0
        Write-Host ("[MIRROR-FALLBACK] {0} succeeded against mirror." -f $stepLabel) -ForegroundColor Green
        return $true
    }

    Write-Host ("[MIRROR-FALLBACK] {0} failed against mirror. Last lines from {1}:" -f $stepLabel, $installLog) -ForegroundColor Red
    $tail = @()
    if (Test-Path $installLog) {
        $tail = Get-Content -Path $installLog -Tail 30 -ErrorAction SilentlyContinue
    }
    $tail | ForEach-Object { Write-Host $_ }
    return $false
}

function Install-OdysseusDependencies($venvPy, $installLog) {
    $pipArgs = @("-m", "pip", "install", "--retries", "5", "--timeout", "120")
    $attempts = @(
        @{ Label = "pip upgrade"; Args = @($pipArgs + @("--upgrade", "pip")) },
        @{ Label = "requirements.txt"; Args = @($pipArgs + @("-r", "requirements.txt")) }
    )

    foreach ($step in $attempts) {
        $stepExitCode = 0
        $maxTries = 3
        $mirrorFallbackUsed = $false
        for ($try = 1; $try -le $maxTries; $try++) {
            Write-Host ("  {0} (attempt {1}/{2})..." -f $step.Label, $try, $maxTries)
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            & $venvPy @($step.Args) *> $installLog
            $stepExitCode = $LASTEXITCODE
            $ErrorActionPreference = $prevEap

            if ($stepExitCode -eq 0) { $LASTEXITCODE = 0; break }

            Write-Host ("[DIAG] attempt result: step={0} try={1}/{2} exitCode={3}" -f $step.Label, $try, $maxTries, $stepExitCode) -ForegroundColor DarkGray

            $tail = @()
            if (Test-Path $installLog) {
                $tail = Get-Content -Path $installLog -Tail 30 -ErrorAction SilentlyContinue
            }
            $tailText = ($tail -join "`n")
            $cacheCorrupt = $tailText -match "IncompleteRead|Connection broken|ConnectionResetError|10054|ContentDecodingError|hash mismatch"
            Write-Host ("[DIAG] cacheCorrupt={0}" -f $cacheCorrupt) -ForegroundColor DarkGray

            if ($cacheCorrupt -and $try -lt $maxTries) {
                Write-Host ("[DIAG] action=purge-and-retry step={0} try={1} reason=cacheCorrupt" -f $step.Label, $try) -ForegroundColor Yellow
                Write-Host "  pip hit a corrupted download/cache entry; purging pip cache and retrying..." -ForegroundColor Yellow
                try { & $venvPy -m pip cache purge 2>$null } catch {}
                Start-Sleep -Seconds 2
                continue
            }

            Write-Host ("  {0} failed. Last lines from {1}:" -f $step.Label, $installLog) -ForegroundColor Red
            $tail | ForEach-Object { Write-Host $_ }

            Write-Host ("[FINAL DIAG] step={0} all-retries-exhausted-or-nonretryable-fail" -f $step.Label) -ForegroundColor Red
            Write-Host ("[FINAL DIAG] SSL_CERT_FILE={0} PIP_CERT={1} PIP_INDEX_URL={2} PIP_EXTRA_INDEX_URL={3}" -f $env:SSL_CERT_FILE, $env:PIP_CERT, $env:PIP_INDEX_URL, $env:PIP_EXTRA_INDEX_URL) -ForegroundColor Red
            if (Test-Path -LiteralPath $venvPy -ErrorAction SilentlyContinue) {
                try {
                    $pyVerOut = & $venvPy --version 2>&1
                    Write-Host ("[FINAL DIAG] venv python={0}" -f ($pyVerOut -join ' ')) -ForegroundColor Red
                    $certTlsOut = & $venvPy -c "import ssl, platform, sys; print('openssl=' + str(getattr(ssl, 'OPENSSL_VERSION', ''))); print('platform=' + platform.platform()); print('py=' + sys.version)" 2>&1
                    Write-Host ("[FINAL DIAG] python ssl/platform={0}" -f ($certTlsOut -join "`n")) -ForegroundColor Red
                } catch {
                    Write-Host "[FINAL DIAG] python version probe failed" -ForegroundColor Red
                }
            } else {
                Write-Host "[FINAL DIAG] venv python=<missing>" -ForegroundColor Red
            }

            if ($try -ge $maxTries) {
                break
            }
            Fail "Dependency install failed during $($step.Label). Inspect $installLog for details."
        }
        if ($stepExitCode -ne 0) {
            Write-Host ("[FINAL DIAG] step={0} all-retries-exhausted" -f $step.Label) -ForegroundColor Red
            Write-Host ("[FINAL DIAG] SSL_CERT_FILE={0} PIP_CERT={1} PIP_INDEX_URL={2} PIP_EXTRA_INDEX_URL={3}" -f $env:SSL_CERT_FILE, $env:PIP_CERT, $env:PIP_INDEX_URL, $env:PIP_EXTRA_INDEX_URL) -ForegroundColor Red
            if (Test-Path -LiteralPath $venvPy -ErrorAction SilentlyContinue) {
                try {
                    $pyVerOut = & $venvPy --version 2>&1
                    Write-Host ("[FINAL DIAG] venv python={0}" -f ($pyVerOut -join ' ')) -ForegroundColor Red
                    $certTlsOut = & $venvPy -c "import ssl, platform, sys; print('openssl=' + str(getattr(ssl, 'OPENSSL_VERSION', ''))); print('platform=' + platform.platform()); print('py=' + sys.version)" 2>&1
                    Write-Host ("[FINAL DIAG] python ssl/platform={0}" -f ($certTlsOut -join "`n")) -ForegroundColor Red
                } catch {
                    Write-Host "[FINAL DIAG] python version probe failed" -ForegroundColor Red
                }
            } else {
                Write-Host "[FINAL DIAG] venv python=<missing>" -ForegroundColor Red
            }

            if (-not (Invoke-PipMirrorFallback -stepLabel $step.Label -installLog $installLog -venvPy $venvPy -stepArgs $step.Args -mirrorFallbackUsed ([ref]$mirrorFallbackUsed))) {
                $stepExitCode = $LASTEXITCODE
                if ($stepExitCode -ne 0) {
                    Fail "Dependency install failed during $($step.Label). Inspect $installLog for details."
                }
            }
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
    & $venvPy -m pip show chromadb-client 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Ensure-ChromaDbPackage($venvPy) {
    $chromaExe = Get-ChromaDbLauncherPath $venvPy
    if ($chromaExe) {
        Write-Host "ChromaDB server already installed in venv - skipping pip install."
        return $chromaExe
    }
    if (Test-ChromaDbPackageReady $venvPy) {
        Write-Host "ChromaDB client package found in venv." -ForegroundColor Green
        return $null
    }
    Write-Host "ChromaDB client not found in venv; installing chromadb-client..." -ForegroundColor Cyan
    & $venvPy -m pip install -q chromadb-client
    if ($LASTEXITCODE -ne 0) { return $null }
    Write-Host "ChromaDB client installed successfully." -ForegroundColor Green
    return $null
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

# Locate a Python interpreter (3.11+ required)
Stop-OdysseusProcesses
Write-Step "Checking for Python"

# Hardcode the expected Python paths on this machine.
# PATH discovery inside this Hermes session keeps resolving to Hermes Agent Python,
# so `py`/`python` is not reliable here.
$pyExe = $null
$pyArgs = @()
$pyVersion = $null

# Candidate 1: standalone Python installed with winget.
if (-not $pyExe -and (Test-Path 'C:\Users\jyang\AppData\Local\Programs\Python\Python313\python.exe')) {
    $pyExe = 'C:\Users\jyang\AppData\Local\Programs\Python\Python313\python.exe'
    $pyVersion = '3.13.14'
}
# Candidate 2/3: WindowsApps Python shims.
if (-not $pyExe -and (Test-Path 'C:\Users\jyang\AppData\Local\Microsoft\WindowsApps\python3.13.exe')) {
    $pyExe = 'C:\Users\jyang\AppData\Local\Microsoft\WindowsApps\python3.13.exe'
    $pyVersion = '3.13.14'
} elseif (-not $pyExe -and (Test-Path 'C:\Users\jyang\AppData\Local\Microsoft\WindowsApps\python.exe')) {
    $pyExe = 'C:\Users\jyang\AppData\Local\Microsoft\WindowsApps\python.exe'
    $pyVersion = '3.13.14'
}

if (-not $pyExe) {
    Fail "Couldn't find Python 3.11+ for Windows setup. Install Python 3.11+ (or open the Python launcher with 'py -3.11') from https://www.python.org/downloads/, then re-run this script."
}
$pythonLabel = ("Using Python {0}: {1} {2}" -f $pyVersion, $pyExe, ($pyArgs -join ' ')).TrimEnd()
Write-Host $pythonLabel

# 2. Create the virtualenv if missing, or recreate it when it was built from the Hermes Agent interpreter.
$venvPy = Join-Path $PSScriptRoot "venv\Scripts\python.exe"
$shouldCreateVenv = $false
if (-not (Test-Path $venvPy)) {
    $shouldCreateVenv = $true
} else {
    $pyVenvCfg = Join-Path $PSScriptRoot "venv\pyvenv.cfg"
    $venvHome = [System.IO.Path]::GetFullPath((Get-Content -Path $pyVenvCfg | Where-Object { $_ -match '^home\s*=\s*(.+)$' } | ForEach-Object { $matches[1].Trim() }) -join '').ToLowerInvariant()
    if ($venvHome -like "*appdata\local\hermes\hermes-agent*") {
        Write-Host "Recreating venv because it was created from the Hermes Agent Python interpreter." -ForegroundColor Yellow
        $shouldCreateVenv = $true
    }
}
if ($shouldCreateVenv) {
    if ((Test-Path $venvPy) -and $shouldCreateVenv) {
        Remove-Item -LiteralPath (Split-Path -Parent $venvPy) -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-IsHermesAgentPython $pyExe)) {
        Write-Step "Creating virtual environment (venv)"
        & $pyExe @pyArgs -m venv venv
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $venvPy)) { Fail "Failed to create the virtual environment." }
    } else {
        # Hermes Agent Python was selected; bootstrap without pip, then inject clean executable
        Write-Step "Bootstrapping venv from a non-standard Hermes interpreter"
        $seedDir = Join-Path $PSScriptRoot ("venv_seed_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $seedDir -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $seedDir "Scripts") -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $seedDir "Lib") -Force | Out-Null
        $seedPy = Join-Path $seedDir "Scripts\python.exe"
        Copy-Item -LiteralPath $pyExe -Destination $seedPy -Force
        Write-Host "Recreating venv from isolated Python executable..."
        & $seedPy -m venv venv
        $seedExit = $LASTEXITCODE
        Remove-Item -LiteralPath $seedDir -Recurse -Force -ErrorAction SilentlyContinue
        if ($seedExit -ne 0 -or -not (Test-Path $venvPy)) { Fail "Failed to create the virtual environment." }
    }
} else {
    Write-Host "venv already exists - skipping creation."
}

# Ensure the created venv does not inherit Hermes Agent paths in `sys.path`.
$siteCleanup = @'

import sys

_bad_prefixes = [
    r"C:\Users\jyang\AppData\Local\hermes\hermes-agent",
    r"C:\Users\jyang\AppData\Local\hermes\hermes-agent\venv\Lib\site-packages",
]
_clean = []
for p in sys.path:
    pp = sys.prefix if sys.prefix else ""
    ap = str(p)
    if not any(ap.startswith(bad) for bad in _bad_prefixes):
        _clean.append(p)
if _clean != sys.path:
    sys.path = _clean
'@
$siteCustomDir = Join-Path (Split-Path $venvPy -Parent) '..\Lib\site-packages'
if (-not (Test-Path $siteCustomDir)) { New-Item -ItemType Directory -Path $siteCustomDir -Force | Out-Null }
$siteCleanupPath = Join-Path $siteCustomDir 'sitecustomize.py'
Set-Content -LiteralPath $siteCleanupPath -Value $siteCleanup -Encoding UTF8
Write-Host "Wrote site path sanitizer to $siteCleanupPath" -ForegroundColor Cyan
Write-Host $pythonLabel

function Reset-PipTlsEnv($venvPy) {
    $certifiCacert = Join-Path (Join-Path (Split-Path $venvPy -Parent) 'Lib\site-packages\certifi') 'cacert.pem'
    if (Test-Path -LiteralPath $certifiCacert -ErrorAction SilentlyContinue) {
        $env:SSL_CERT_FILE = $certifiCacert
        $env:PIP_CERT      = $certifiCacert
    } else {
        $env:SSL_CERT_FILE = $null
        $env:PIP_CERT      = $null
    }
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

    # Fix C: pre-install TLS/CA env sanitization to avoid broken user/system
    # pip/SSL settings poisoning venv installs.
    $script:prevUserPipEnv = @{
        PIP_INDEX_URL        = $env:PIP_INDEX_URL
        PIP_EXTRA_INDEX_URL  = $env:PIP_EXTRA_INDEX_URL
        SSL_CERT_FILE        = $env:SSL_CERT_FILE
        PIP_CERT             = $env:PIP_CERT
    }
    $env:PIP_INDEX_URL        = $null
    $env:PIP_EXTRA_INDEX_URL  = $null
    $env:SSL_CERT_FILE        = $null
    $env:PIP_CERT             = $null

    Reset-PipTlsEnv $venvPy

    # On this host, public PyPI deterministically resets Python TLS with 10054.
    # Default to a working mirror unless the user explicitly overrides it.
    if (-not $env:ODYSSEUS_PIP_MIRROR) {
        $env:ODYSSEUS_PIP_MIRROR = 'https://pypi.tuna.tsinghua.edu.cn/simple'
    }
    if ($env:ODYSSEUS_PIP_MIRROR) {
        $env:PIP_INDEX_URL = $env:ODYSSEUS_PIP_MIRROR
        Write-Host ("Using ODYSSEUS_PIP_MIRROR as PIP_INDEX_URL={0}" -f $env:ODYSSEUS_PIP_MIRROR) -ForegroundColor Cyan
    }
    try {
        Install-OdysseusDependencies $venvPy $installLog
    } finally {
        # Restore user env regardless of success/failure.
        $env:PIP_INDEX_URL        = $script:prevUserPipEnv.PIP_INDEX_URL
        $env:PIP_EXTRA_INDEX_URL  = $script:prevUserPipEnv.PIP_EXTRA_INDEX_URL

        # Restore SSL_CERT_FILE/PIP_CERT to venv certifi path if present, otherwise clear.
        Reset-PipTlsEnv $venvPy
    }
    if (-not (Test-OdysseusDepsReady $venvPy)) {
        Write-Host ""
        Write-Host ("ERROR: pip reported success, but core dependencies are not importable in the venv.") -ForegroundColor Red
        Write-Host ("Tail of $($installLog):") -ForegroundColor Red
        $tail = @()
        if (Test-Path $installLog) {
            $tail = Get-Content -Path $installLog -Tail 30 -ErrorAction SilentlyContinue
        }
        $tail | ForEach-Object { Write-Host $_ }
        Write-Host ""
        Fail "Dependency install reported success, but post-install verification failed."
    }
    Write-Host ("Dependencies installed successfully (log: " + $installLog + ")") -ForegroundColor Green
}

# 4. First-time setup (creates data dirs, DB, .env, admin user)
Write-Step "Running first-time setup"
$authFile = Join-Path $PSScriptRoot "data\auth.json"
if (-not (Test-Path $authFile)) {
    # First run: let setup.py prompt interactively for username + password
    # (so the user sets their own admin credentials on first load-up).
    Write-Host "First launch detected - you will be prompted to set your admin username and password." -ForegroundColor Cyan
    $prevNoPrompt = $env:ODYSSEUS_SKIP_ADMIN_PROMPT
    Remove-Item Env:ODYSSEUS_SKIP_ADMIN_PROMPT -ErrorAction SilentlyContinue
    & $venvPy setup.py
    $setupExit = $LASTEXITCODE
    $env:ODYSSEUS_SKIP_ADMIN_PROMPT = $prevNoPrompt
} else {
    # Subsequent runs: skip the interactive prompt.
    $prevNoPrompt = $env:ODYSSEUS_SKIP_ADMIN_PROMPT
    $env:ODYSSEUS_SKIP_ADMIN_PROMPT = '1'
    & $venvPy setup.py
    $setupExit = $LASTEXITCODE
    $env:ODYSSEUS_SKIP_ADMIN_PROMPT = $prevNoPrompt
}
if ($setupExit -ne 0) { Fail "setup.py failed." }

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

try {
    $startupUrl = "http://{0}:{1}" -f $BindHost, $Port
    Write-Host "Starting Odysseus at $startupUrl ..." -ForegroundColor Cyan

    # Launch uvicorn via cmd /c start so it is fully DETACHED from this
    # launcher's process tree. On double-click .bat the wrapper kills the
    # direct child on exit; a cmd-started process survives window close.
    # Correct `start` syntax: empty title placeholder, then quoted exe, then args.
    $consoleLog = Join-Path $logsDir "uvicorn_console.log"
    $uvArgs = "-m uvicorn app:app --host $BindHost --port $Port"
    $cmdArgs = '/c start "" "{0}" {1}' -f $venvPy, $uvArgs
    $null = Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden -PassThru

    # Discover the spawned uvicorn PID for readiness probing + later cleanup.
    Start-Sleep -Seconds 2
    $pendingUvicorn = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -match "uvicorn" -and $_.CommandLine -match "app:app"
    } | Sort-Object { $_.ProcessId } | Select-Object -First 1
    if (-not $pendingUvicorn) {
        Fail "Unable to start Odysseus via uvicorn (app:app)."
    }
    Write-Host ("Server PID: {0}" -f $pendingUvicorn.ProcessId)
    Write-Host ("Server logging to: " + $consoleLog)
    Write-Host "Starting server..." -ForegroundColor Cyan

    # Wait until the app actually accepts HTTP connections before opening the browser.
    $deadline = (Get-Date).AddSeconds(30)
    $serverReady = $false
    while ((Get-Date) -lt $deadline) {
        if (-not (Get-Process -Id $pendingUvicorn.ProcessId -ErrorAction SilentlyContinue)) {
            Write-Host "ERROR: uvicorn exited during startup. Inspect $consoleLog" -ForegroundColor Red
            break
        }
        try {
            $probe = Invoke-WebRequest -Uri $startupUrl -UseBasicParsing -TimeoutSec 1
            if ($probe.StatusCode -ge 200 -and $probe.StatusCode -lt 500) {
                $serverReady = $true
                break
            }
        } catch {
            # transient failure while the app is still booting
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $serverReady) {
        Write-Host "WARNING: server did not become ready within 30s. Check $consoleLog" -ForegroundColor Yellow
    } else {
        Write-Host ""
        Open-OdysseusBrowser $startupUrl
        Write-Host ("Opened browser tab for " + $startupUrl)
    }

    Write-Host ""
    Write-Host "Odysseus is running in the background (PID $($pendingUvicorn.ProcessId))." -ForegroundColor Green
    Write-Host "Server is live at $startupUrl - browser tab opened automatically." -ForegroundColor Cyan
    Write-Host "This window will close shortly; the server keeps running." -ForegroundColor DarkGray
    Write-Host "To stop it later: run reset.bat, or end the uvicorn process from Task Manager." -ForegroundColor DarkGray
    Start-Sleep -Seconds 3
} catch {
    Write-Host ""
    Write-Host "ERROR: Server startup failed" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
} finally {
    # Only stop the server if this launcher is terminating it (Ctrl+C / crash).
    # On a normal Read-Host close, leave uvicorn running detached.
    if ($pendingUvicorn -and (Get-Variable -Name ctrlC -ErrorAction SilentlyContinue) -and $ctrlC) {
        try { Stop-Process -Id $pendingUvicorn.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Stop-OdysseusChromaDb $startedChromaPid
}
