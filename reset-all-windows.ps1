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

Write-Step "This will remove all runtime state, caches, logs, and build artifacts"
Write-Host "Keeping: repository source files, configuration templates (.env.example, .gitignore, etc)" -ForegroundColor DarkGray
if (-not $Force) {
    $response = Read-Host "Type 'RESET' to confirm"
    if ($response -ne 'RESET') {
        Write-Host "Aborted. No files were deleted." -ForegroundColor Yellow
        return
    }
}

Write-Step "Stopping Odysseus-related processes"
$processNames = @('python', 'python.exe', 'uvicorn', 'uvicorn.exe', 'powershell', 'pwsh')
$stoppedCount = 0
foreach ($name in $processNames) {
    Get-CimInstance Win32_Process -Filter "name = '$name'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'odysseus|app.py|launch-windows.ps1|uvicorn' } |
        ForEach-Object {
            try { 
                Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
                Write-Host "  Stopped PID $($_.ProcessId): $($_.Name)" -ForegroundColor Yellow
                $stoppedCount++
            } catch {
                Write-Host "  Could not stop PID $($_.ProcessId): $_" -ForegroundColor DarkYellow
            }
        }
}
if ($stoppedCount -eq 0) {
    Write-Host "  No Odysseus processes running" -ForegroundColor DarkGray
}
Start-Sleep -Milliseconds 1000

Write-Step "Removing virtual environments"
$venvPaths = @(
    (Join-Path $repoRoot '.venv'),
    (Join-Path $repoRoot 'venv')
)
foreach ($path in $venvPaths) {
    if (Test-Path $path) {
        Write-Host "  Removing $path" -ForegroundColor DarkGray
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Host "    [ok]" -ForegroundColor Green
        } catch {
            Write-Host "    [error] $_" -ForegroundColor Red
        }
    }
}

Write-Step "Removing runtime data directory"
if (Test-Path $effectiveDataDir) {
    Write-Host "  Removing $effectiveDataDir" -ForegroundColor DarkGray
    try {
        Remove-Item -LiteralPath $effectiveDataDir -Recurse -Force -ErrorAction Stop
        Write-Host "    [ok]" -ForegroundColor Green
    } catch {
        Write-Host "    [error] $_" -ForegroundColor Red
    }
}

Write-Step "Removing Python cache files"
$cleanedCache = 0
Get-ChildItem -Path $repoRoot -Recurse -ErrorAction SilentlyContinue | Where-Object {
    if ($_.PSIsContainer) {
        return ($_.Name -in @('__pycache__', '.pytest_cache', '.mypy_cache', '.ruff_cache')) -or $_.Name -like '*.egg-info'
    }
    return $_.Name -like '*.pyc' -or $_.Name -like '*.pyo' -or $_.Name -like '*.pyd'
} | ForEach-Object {
    try {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
        Write-Host "  Removed $($_.FullName -replace [regex]::Escape($repoRoot), '.')" -ForegroundColor DarkGray
        $cleanedCache++
    } catch {}
}
if ($cleanedCache -eq 0) {
    Write-Host "  (No Python cache files found)" -ForegroundColor DarkGray
}

Write-Step "Removing build artifacts"
$buildDirs = @('build', 'dist', '.eggs')
$foundBuild = $false
foreach ($dir in $buildDirs) {
    $path = Join-Path $repoRoot $dir
    if (Test-Path $path) {
        Write-Host "  Removing $path" -ForegroundColor DarkGray
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Host "    [ok]" -ForegroundColor Green
            $foundBuild = $true
        } catch {
            Write-Host "    [error] $_" -ForegroundColor Red
        }
    }
}
if (-not $foundBuild) {
    Write-Host "  (No build artifacts found)" -ForegroundColor DarkGray
}

Write-Step "Removing repository root config files"
$configFiles = @('.env', 'auth.json', 'app.db')
$foundConfig = $false
foreach ($file in $configFiles) {
    $path = Join-Path $repoRoot $file
    if (Test-Path $path) {
        Write-Host "  Removing $path" -ForegroundColor DarkGray
        try {
            Remove-Item -LiteralPath $path -Force -ErrorAction Stop
            Write-Host "    [ok]" -ForegroundColor Green
            $foundConfig = $true
        } catch {
            Write-Host "    [error] $_" -ForegroundColor Red
        }
    }
}
if (-not $foundConfig) {
    Write-Host "  (No config files found in repo root)" -ForegroundColor DarkGray
}

Write-Step "Removing IDE and editor caches"
$ideCacheDirs = @('.vscode', '.idea', '.vs', '.vscode-test')
$foundIde = $false
foreach ($dir in $ideCacheDirs) {
    $path = Join-Path $repoRoot $dir
    if (Test-Path $path) {
        Write-Host "  Removing $path" -ForegroundColor DarkGray
        try {
            Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            Write-Host "    [ok]" -ForegroundColor Green
            $foundIde = $true
        } catch {
            Write-Host "    [error] $_" -ForegroundColor Red
        }
    }
}
if (-not $foundIde) {
    Write-Host "  (No IDE caches found)" -ForegroundColor DarkGray
}

Write-Step "Removing pip and module caches"
$pipCacheRoots = @(
    $env:TEMP,
    (Join-Path $env:LOCALAPPDATA 'pip'),
    (Join-Path $env:APPDATA 'pip'),
    (Join-Path $env:USERPROFILE '.cache\pip'),
    (Join-Path $env:USERPROFILE 'AppData\Local\pip'),
    (Join-Path $env:USERPROFILE 'AppData\Roaming\pip')
)
$removedPip = 0
foreach ($cacheRoot in $pipCacheRoots) {
    if (Test-Path $cacheRoot) {
        try {
            Get-ChildItem -Path $cacheRoot -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match 'pip|cache' } |
                ForEach-Object {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    $removedPip++
                }
            Remove-Item -LiteralPath $cacheRoot -Recurse -Force -ErrorAction SilentlyContinue
        } catch {}
    }
}
if ($removedPip -eq 0) {
    Write-Host "  (No pip caches found)" -ForegroundColor DarkGray
} else {
    Write-Host "  Removed $removedPip cache entries" -ForegroundColor DarkGray
}

Write-Step "Removing Odysseus-specific caches and temporary files"
$odysseusCacheDirs = @(
    (Join-Path $env:LOCALAPPDATA 'odysseus'),
    (Join-Path $env:APPDATA 'odysseus'),
    (Join-Path $env:USERPROFILE '.odysseus')
)
$foundOdysseus = $false
foreach ($dir in $odysseusCacheDirs) {
    if (Test-Path $dir) {
        Write-Host "  Removing $dir" -ForegroundColor DarkGray
        try {
            Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
            Write-Host "    [ok]" -ForegroundColor Green
            $foundOdysseus = $true
        } catch {
            Write-Host "    [error] $_" -ForegroundColor Red
        }
    }
}
if (-not $foundOdysseus) {
    Write-Host "  (No Odysseus user caches found)" -ForegroundColor DarkGray
}

Write-Step "Verifying cleanup - checking for leftover runtime state"
$hasIssues = $false

# Check for .pyc files
$pycFiles = @(Get-ChildItem -Path $repoRoot -Recurse -Filter "*.pyc" -ErrorAction SilentlyContinue)
if ($pycFiles.Count -gt 0) {
    Write-Host "  WARNING: Found .pyc files:" -ForegroundColor Yellow
    $pycFiles | ForEach-Object { Write-Host "    $_" }
    $hasIssues = $true
}

# Check for __pycache__ directories
$pycacheDirs = @(Get-ChildItem -Path $repoRoot -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue)
if ($pycacheDirs.Count -gt 0) {
    Write-Host "  WARNING: Found __pycache__ directories:" -ForegroundColor Yellow
    $pycacheDirs | ForEach-Object { Write-Host "    $_" }
    $hasIssues = $true
}

# Check for .pytest_cache
$pytestCacheDirs = @(Get-ChildItem -Path $repoRoot -Recurse -Directory -Filter ".pytest_cache" -ErrorAction SilentlyContinue)
if ($pytestCacheDirs.Count -gt 0) {
    Write-Host "  WARNING: Found .pytest_cache directories:" -ForegroundColor Yellow
    $pytestCacheDirs | ForEach-Object { Write-Host "    $_" }
    $hasIssues = $true
}

# Check for data directory
if (Test-Path $effectiveDataDir) {
    Write-Host "  WARNING: Data directory still exists: $effectiveDataDir" -ForegroundColor Yellow
    $hasIssues = $true
}

# Check for venv
if ((Test-Path (Join-Path $repoRoot '.venv')) -or (Test-Path (Join-Path $repoRoot 'venv'))) {
    Write-Host "  WARNING: Virtual environment directory still exists" -ForegroundColor Yellow
    $hasIssues = $true
}

if (-not $hasIssues) {
    Write-Host "  [ok] All runtime state cleaned up" -ForegroundColor Green
}

Write-Step "Recreating clean runtime directories"
try {
    $logsDir = Join-Path $effectiveDataDir 'logs'
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    Write-Host "  Created $logsDir" -ForegroundColor Green
} catch {
    Write-Host "  Failed to create logs directory: $_" -ForegroundColor Yellow
}

try {
    $downloadsDir = Join-Path $effectiveDataDir 'downloads'
    New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null
    Write-Host "  Created $downloadsDir" -ForegroundColor Green
} catch {
    Write-Host "  Failed to create downloads directory: $_" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Reset complete." -ForegroundColor Green
Write-Host "Repository is now in a clean state. Run launch-windows.ps1 to rebuild from scratch." -ForegroundColor Green
Write-Host ""
