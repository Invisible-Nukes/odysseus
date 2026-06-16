# install_ollama.ps1
# Download and unpack a headless Ollama distribution into the Odysseus data tree.
# Behavior:
#  - Uses $env:OLLAMA_DOWNLOAD_URL if set, otherwise requires the operator to set it.
#  - Optionally validates SHA256 via $env:OLLAMA_DOWNLOAD_SHA256.
#  - Installs to $ODYSSEUS_DATA_DIR\ollama (or ./data/ollama when ODYSSEUS_DATA_DIR unset).
#  - Adds the install dir to PATH for the current process so subsequent steps can use it.

param()

$ErrorActionPreference = "Stop"
$scriptRoot = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent

# Resolve data dir. Prefer the caller-provided ODYSSEUS_DATA_DIR; otherwise
# default to the repo-local data tree so Ollama lands under this checkout.
$dataDir = $env:ODYSSEUS_DATA_DIR
if (-not $dataDir) { $dataDir = Join-Path (Split-Path $scriptRoot -Parent) "data" }
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$dataDir = (Resolve-Path $dataDir).ProviderPath

$ollamaDir = Join-Path $dataDir "ollama"
$ollamaExe = Join-Path $ollamaDir "ollama.exe"

if (Test-Path $ollamaExe) {
    Write-Host "Ollama already present at: $ollamaExe"
    exit 0
}

# Default to the official Ollama GitHub release for Windows (v0.30.7) when the
# operator hasn't specified OLLAMA_DOWNLOAD_URL. The SHA256 below matches the
# release asset and will be used if OLLAMA_DOWNLOAD_SHA256 is not explicitly set.
$defaultDownloadUrl = "https://github.com/ollama/ollama/releases/download/v0.30.7/ollama-windows-amd64-mlx.zip"
$defaultDownloadSha = "06456221a301ae1ecdbdcc1ffe56efe2babe94367b5c8451ffcb7362265d19b8"

$downloadUrl = $env:OLLAMA_DOWNLOAD_URL
if (-not $downloadUrl) {
    Write-Host "No OLLAMA_DOWNLOAD_URL set; using official release: $defaultDownloadUrl" -ForegroundColor Cyan
    $downloadUrl = $defaultDownloadUrl
    $env:OLLAMA_DOWNLOAD_URL = $downloadUrl
}

if (-not $env:OLLAMA_DOWNLOAD_SHA256 -and $defaultDownloadSha) {
    Write-Host "No OLLAMA_DOWNLOAD_SHA256 set; using known SHA256 for the selected release." -ForegroundColor Cyan
    $env:OLLAMA_DOWNLOAD_SHA256 = $defaultDownloadSha
}

# Reuse a cached archive under the repo-managed data tree when it already
# exists, so repeated runs do not start a fresh download every time.
$archiveDir = Join-Path $dataDir "downloads"
New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
$cacheFile = Join-Path $archiveDir "ollama-windows-amd64-mlx.zip"
$tempFile = Join-Path $env:TEMP ("ollama_download_{0}.zip" -f ([System.Guid]::NewGuid().ToString()))

if (-not (Test-Path $cacheFile)) {
    Write-Host "Downloading Ollama from $downloadUrl to $cacheFile..."
    try {
        Start-BitsTransfer -Source $downloadUrl -Destination $tempFile -RetryInterval 60 -RetryTimeout 600
        Move-Item -Path $tempFile -Destination $cacheFile -Force
    } catch {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        Write-Host "BITS download failed: $_" -ForegroundColor Red
        exit 3
    }
} else {
    Write-Host "Using cached Ollama archive: $cacheFile"
}

$tempFile = $cacheFile

# Optional checksum verification
$expectedSha = $env:OLLAMA_DOWNLOAD_SHA256
if ($expectedSha) {
    if (-not (Test-Path $tempFile)) {
        Write-Host "ERROR: Archive not found at $tempFile for SHA256 verification." -ForegroundColor Red
        exit 5
    }
    Write-Host "Verifying SHA256..."
    try {
        $hashInfo = Get-FileHash -Algorithm SHA256 -LiteralPath $tempFile -ErrorAction Stop
        $actualSha = if ($hashInfo -and $hashInfo.Hash) { $hashInfo.Hash.ToLowerInvariant() } else { $null }
        $expectedShaLower = $expectedSha.ToLowerInvariant()

        if (-not $actualSha) {
            Write-Host "ERROR: SHA256 verification returned no hash for $tempFile" -ForegroundColor Red
            exit 5
        }

        if ($actualSha -ne $expectedShaLower) {
            Write-Host "ERROR: SHA256 mismatch. Expected $expectedShaLower but got $actualSha" -ForegroundColor Red
            exit 4
        }
    } catch {
        Write-Host "Failed to compute SHA256: $_" -ForegroundColor Red
        exit 5
    }
}

# Unpack — support ZIP and a single exe installer. If it's an exe, place it in the target dir.
try {
    New-Item -ItemType Directory -Path $ollamaDir -Force | Out-Null
    $ext = [IO.Path]::GetExtension($tempFile)
    if ($ext -eq ".zip") {
        if (-not (Test-Path $tempFile)) {
            Write-Host "ERROR: Archive not found at $tempFile before extraction." -ForegroundColor Red
            exit 6
        }
        Write-Host "Extracting ZIP to $ollamaDir..."
        Expand-Archive -LiteralPath $tempFile -DestinationPath $ollamaDir -Force
    } else {
        # Treat as binary installer — move it into the folder and mark as executable
        $dest = Join-Path $ollamaDir (Split-Path $downloadUrl -Leaf)
        Move-Item -Path $tempFile -Destination $dest -Force
    }
} catch {
    Write-Host "Failed to extract/install Ollama: $_" -ForegroundColor Red
    if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    exit 6
}

# Preserve the cached archive for future reruns. Only the temporary download
# file is moved into the cache path above; the cached archive itself should
# remain available after extraction.

# Add ollama dir to PATH for this process so subsequent steps see it
$ollamaBin = $ollamaDir
if (-not ($env:PATH.ToLower().Contains($ollamaBin.ToLower()))) { $env:PATH = "$ollamaBin;$env:PATH" }

Write-Host "Ollama installed to: $ollamaDir"
exit 0
