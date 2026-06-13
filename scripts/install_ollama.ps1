# install_ollama.ps1
# Download and install Ollama MSI installer to the Odysseus data folder.
# Behavior:
#  - Downloads the official Ollama Windows MSI installer
#  - Saves to $ODYSSEUS_DATA_DIR\ollama (or ./data/ollama when ODYSSEUS_DATA_DIR unset)
#  - Runs the installer with automatic/quiet mode to install to the odysseus folder
#  - Adds ollama.exe to PATH for the current process

param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# Resolve data dir
$dataDir = $env:ODYSSEUS_DATA_DIR
if (-not $dataDir) { $dataDir = Join-Path $scriptRoot "..\data" | Resolve-Path -ErrorAction SilentlyContinue }
if (-not $dataDir) { $dataDir = Join-Path $scriptRoot "..\data" }

# Resolve to absolute path, creating parent if needed
if (Test-Path $dataDir) {
    $dataDir = (Resolve-Path $dataDir).ProviderPath
} else {
    $dataDir = [System.IO.Path]::GetFullPath($dataDir)
}

$ollamaDir = Join-Path $dataDir "ollama"
$ollamaExe = Join-Path $ollamaDir "ollama.exe"

if (Test-Path $ollamaExe) {
    Write-Host "Ollama already present at: $ollamaExe" -ForegroundColor Green
    exit 0
}

# Create ollama directory if it doesn't exist
if (-not (Test-Path $ollamaDir)) {
    New-Item -ItemType Directory -Path $ollamaDir -Force | Out-Null
    Write-Host "Created directory: $ollamaDir"
}

# Official Ollama Windows standalone .exe installer from ollama.com
$downloadUrl = "https://ollama.com/download/OllamaSetup.exe"
$installerPath = Join-Path $ollamaDir "OllamaSetup.exe"

# Check if installer already downloaded
if (Test-Path $installerPath) {
    Write-Host "Installer already present at: $installerPath" -ForegroundColor Cyan
} else {
    Write-Host "Downloading Ollama installer from $downloadUrl..." -ForegroundColor Cyan
    Write-Host "Destination: $installerPath" -ForegroundColor Cyan
    Write-Host ""
    
    try {
        # Try multiple methods for better reliability
        try {
            # Method 1: Try BITS transfer first (most reliable)
            Start-BitsTransfer -Source $downloadUrl -Destination $installerPath -RetryInterval 60 -RetryTimeout 600 -ErrorAction Stop
            Write-Host "✅ Download completed via BITS" -ForegroundColor Green
        } catch {
            Write-Host "⚠️ BITS transfer failed, trying WebClient..." -ForegroundColor Yellow
            # Method 2: Fall back to WebClient
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($downloadUrl, $installerPath)
            Write-Host "✅ Download completed via WebClient" -ForegroundColor Green
        }
    } catch {
        Write-Host "❌ Download failed: $_" -ForegroundColor Red
        exit 1
    }
}

# Verify the installer exists
if (-not (Test-Path $installerPath)) {
    Write-Host "❌ Installer file not found at: $installerPath" -ForegroundColor Red
    exit 2
}

Write-Host ""
Write-Host "=== Installing Ollama ===" -ForegroundColor Cyan
Write-Host "Installer: $installerPath"
Write-Host ""

# Install the .exe with silent mode
try {
    Write-Host "Running installer (this may take a few minutes)..." -ForegroundColor Yellow
    Write-Host "Note: Ollama may install to Program Files by default" -ForegroundColor Cyan
    Write-Host ""
    
    # Try with silent flag only (standard parameter for this installer)
    $process = Start-Process -FilePath $installerPath -ArgumentList @("/S") -Wait -PassThru -NoNewWindow
    
    if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) {
        Write-Host "⚠️ Installer exited with code: $($process.ExitCode)" -ForegroundColor Yellow
        Write-Host "   Checking if installation succeeded despite exit code..." -ForegroundColor Yellow
    } else {
        Write-Host "✅ Installer completed successfully" -ForegroundColor Green
    }
} catch {
    Write-Host "❌ Failed to execute installer: $_" -ForegroundColor Red
    Write-Host "Tip: You may need to run as Administrator" -ForegroundColor Yellow
    exit 3
}

# Verify installation — check multiple locations
$ollamaExePaths = @(
    (Join-Path $ollamaDir "ollama.exe"),
    "C:\Program Files\Ollama\ollama.exe",
    "$env:APPDATA\Ollama\ollama.exe"
)

$foundPath = $null
foreach ($path in $ollamaExePaths) {
    if (Test-Path $path) {
        $foundPath = $path
        break
    }
}

if ($foundPath) {
    Write-Host "✅ Ollama executable verified at: $foundPath" -ForegroundColor Green
    
    # Get version to confirm it works
    try {
        $version = & $foundPath --version 2>&1
        Write-Host "   Version: $version" -ForegroundColor Green
    } catch {
        Write-Host "   (version check skipped)" -ForegroundColor Gray
    }
} else {
    Write-Host "⚠️ Warning: ollama.exe not found in expected locations" -ForegroundColor Yellow
    Write-Host "   Checked:" -ForegroundColor Yellow
    foreach ($path in $ollamaExePaths) {
        Write-Host "     • $path" -ForegroundColor Gray
    }
    Write-Host "   The installer may have encountered an issue." -ForegroundColor Yellow
    Write-Host "   Try running the installer manually from: $installerPath" -ForegroundColor Yellow
}

# Add ollama dir to PATH if not already present
if ($foundPath) {
    $ollamaBin = Split-Path $foundPath -Parent
    if (-not ($env:PATH.ToLower().Contains($ollamaBin.ToLower()))) {
        $env:PATH = "$ollamaBin;$env:PATH"
        Write-Host "✅ Added to PATH: $ollamaBin" -ForegroundColor Green
    } else {
        Write-Host "✅ Already in PATH: $ollamaBin" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Installation Summary ===" -ForegroundColor Green
Write-Host "Installer location: $installerPath" -ForegroundColor Green
if ($foundPath) {
    Write-Host "Ollama executable: $foundPath" -ForegroundColor Green
}
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Test: ollama --version" -ForegroundColor Cyan
Write-Host "  2. Download models:" -ForegroundColor Cyan
Write-Host "     ollama pull qwen:7b-coder" -ForegroundColor Cyan
Write-Host "     ollama pull deepseek-v2-lite" -ForegroundColor Cyan
Write-Host "  3. Start server: ollama serve" -ForegroundColor Cyan
Write-Host "  4. Odysseus will auto-detect running Ollama on localhost:11434" -ForegroundColor Cyan
Write-Host ""
exit 0
