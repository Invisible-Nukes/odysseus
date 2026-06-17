#Requires -Version 5.1

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Step([string]$Message) {
    Write-Host "" 
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    throw $Message
}

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

$effectiveDataDir = $env:ODYSSEUS_DATA_DIR
if (-not $effectiveDataDir) { $effectiveDataDir = Join-Path $repoRoot 'data' }
if (-not [System.IO.Path]::IsPathRooted($effectiveDataDir)) {
    $effectiveDataDir = Join-Path $repoRoot $effectiveDataDir
}
$effectiveDataDir = [System.IO.Path]::GetFullPath($effectiveDataDir)

Write-Step "This will remove local runtime state and rebuild from a clean checkout"
if (-not $Force) {
    $response = Read-Host "Type 'RESET' to confirm"
    if ($response -ne 'RESET') {
        Write-Host "Aborted. No files were deleted." -ForegroundColor Yellow
        return
    }
}

Write-Step "Stopping Odysseus-related processes"
$processNames = @('python', 'python.exe', 'uvicorn', 'uvicorn.exe', 'powershell', 'pwsh')
foreach ($name in $processNames) {
    Get-CimInstance Win32_Process -Filter "name = '$name'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'odysseus|app.py|launch-windows.ps1|uvicorn' } |
        ForEach-Object {
            try { 
                Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
                Write-Host "Stopped $($_.ProcessId) $($_.Name)" -ForegroundColor Yellow
            } catch {
                Write-Host "Could not stop $($_.ProcessId): $_" -ForegroundColor DarkYellow
            }
        }
}
Start-Sleep -Milliseconds 1000

$pathsToDelete = @(
    (Join-Path $repoRoot '.venv'),
    (Join-Path $repoRoot 'venv'),
    $effectiveDataDir,
    (Join-Path $repoRoot '.env'),
    (Join-Path $repoRoot 'auth.json'),
    (Join-Path $repoRoot 'app.db'),
    (Join-Path $repoRoot '__pycache__'),
    (Join-Path $repoRoot '.pytest_cache'),
    (Join-Path $repoRoot '.mypy_cache'),
    (Join-Path $repoRoot '.ruff_cache')
) | Select-Object -Unique

$runtimeStateFiles = @(
    (Join-Path $effectiveDataDir 'auth.json'),
    (Join-Path $effectiveDataDir 'app.db'),
    (Join-Path $effectiveDataDir 'sessions.json'),
    (Join-Path $effectiveDataDir 'memory.json'),
    (Join-Path $effectiveDataDir 'settings.json')
) | Select-Object -Unique
foreach ($path in $runtimeStateFiles) {
    if (Test-Path $path) {
        Write-Host "Removing $path"
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    }
}

foreach ($path in $pathsToDelete) {
    if (Test-Path $path) {
        Write-Host "Removing $path" -ForegroundColor DarkGray
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Host "  [ok] Removed" -ForegroundColor Green
        } catch {
            Write-Host "  [error] Failed to remove: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "Not found: $path" -ForegroundColor DarkGray
    }
}

$subdirs = @(
    'core', 'routes', 'scripts', 'services', 'tests', 'src', 'mcp_servers'
)
foreach ($subdir in $subdirs) {
    $cachePath = Join-Path $repoRoot $subdir
    if (Test-Path $cachePath) {
        Get-ChildItem -LiteralPath $cachePath -Recurse -Directory -Filter '__pycache__' -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Step "Removing downloaded Ollama assets"
$ollamaDownloadDir = Join-Path $effectiveDataDir 'downloads'
if (Test-Path $ollamaDownloadDir) { Remove-Item -LiteralPath $ollamaDownloadDir -Recurse -Force -ErrorAction SilentlyContinue }
$ollamaDir = Join-Path $effectiveDataDir 'ollama'
if (Test-Path $ollamaDir) { Remove-Item -LiteralPath $ollamaDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Step "Removing pip caches and temporary files"
$cacheRoots = @(
    $env:TEMP,
    (Join-Path $env:LOCALAPPDATA 'pip'),
    (Join-Path $env:APPDATA 'pip'),
    (Join-Path $env:USERPROFILE '.cache'),
    (Join-Path $env:USERPROFILE 'AppData\Local\pip'),
    (Join-Path $env:USERPROFILE 'AppData\Roaming\pip'),
    (Join-Path $env:LOCALAPPDATA 'odysseus'),
    (Join-Path $env:APPDATA 'odysseus')
)
foreach ($cacheRoot in $cacheRoots) {
    if (Test-Path $cacheRoot) {
        Get-ChildItem -LiteralPath $cacheRoot -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match 'odysseus|pip|cache' } |
            ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Write-Step "Recreating clean directories"
try {
    New-Item -ItemType Directory -Path (Join-Path $effectiveDataDir 'logs') -Force | Out-Null
    Write-Host "Created logs directory" -ForegroundColor Green
} catch {
    Write-Host "Failed to create logs directory: $_" -ForegroundColor Yellow
}
try {
    New-Item -ItemType Directory -Path (Join-Path $effectiveDataDir 'downloads') -Force | Out-Null
    Write-Host "Created downloads directory" -ForegroundColor Green
} catch {
    Write-Host "Failed to create downloads directory: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Reset complete. Re-run launch-windows.ps1 to rebuild from a fresh checkout state." -ForegroundColor Green
