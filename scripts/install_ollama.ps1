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

function Test-OllamaRuntime {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OllamaExe
    )

    Write-Host "Running post-install Ollama verification scan..." -ForegroundColor Cyan

    $versionText = (& $OllamaExe --version 2>$null | Out-String).Trim()
    if ($LASTEXITCODE -ne 0) {
        throw "Ollama binary failed its version probe: $versionText"
    }
    if ($versionText -match '(\d+\.\d+\.\d+(?:\.\d+)?)') {
        $versionText = $matches[1]
    }

    $serveProcess = $null
    try {
        $serveProcess = Start-Process -FilePath $OllamaExe -ArgumentList "serve" -PassThru -WindowStyle Hidden
        $deadline = (Get-Date).AddSeconds(30)
        $apiResponded = $false
        $apiPayload = $null

        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 1
            try {
                $apiPayload = Invoke-RestMethod -Uri "http://127.0.0.1:11434/api/tags" -Method Get -TimeoutSec 10
                $apiResponded = $true
                break
            } catch {
                if ($serveProcess.HasExited) {
                    throw "Ollama server exited before the API probe could complete."
                }
            }
        }

        if (-not $apiResponded) {
            throw "Ollama server did not answer /api/tags within 30 seconds."
        }

        return [pscustomobject]@{
            Version = $versionText
            ApiModels = @($apiPayload.models)
            ApiReady = $true
        }
    } finally {
        if ($serveProcess -and -not $serveProcess.HasExited) {
            Stop-Process -Id $serveProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }
}

# Resolve data dir. Prefer the caller-provided ODYSSEUS_DATA_DIR; otherwise
# default to the repo-local data tree so Ollama lands under this checkout.
$dataDir = $env:ODYSSEUS_DATA_DIR
if (-not $dataDir) { $dataDir = Join-Path (Split-Path $scriptRoot -Parent) "data" }
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Path $dataDir -Force | Out-Null }
$dataDir = (Resolve-Path $dataDir).ProviderPath

$ollamaDir = Join-Path $dataDir "ollama"
$ollamaExe = Join-Path $ollamaDir "ollama.exe"
$alreadyPresent = Test-Path $ollamaExe

if ($alreadyPresent) {
    Write-Host "Ollama already present at: $ollamaExe" -ForegroundColor Cyan
}

# Default to the official standalone Windows CLI archive for Ollama (v0.30.7)
# when the operator hasn't specified OLLAMA_DOWNLOAD_URL. This is the base
# package the Odysseus launcher expects, and the SHA256 below matches the
# published release asset.
$defaultDownloadUrl = "https://github.com/ollama/ollama/releases/download/v0.30.7/ollama-windows-amd64.zip"
$defaultDownloadSha = "ce8169abfe48e05a865958391729ff14f297513ae67fdb4ec7b11a37b9c5b715"

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
$cacheFile = Join-Path $archiveDir "ollama-windows-amd64.zip"
$tempFile = Join-Path $env:TEMP ("ollama_download_{0}.zip" -f ([System.Guid]::NewGuid().ToString()))

# Remove prior Ollama archive artifacts so the next run starts from a clean state.
Get-ChildItem -Path $archiveDir -Filter "ollama-windows-amd64*.zip" -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

if (-not $alreadyPresent -and -not (Test-Path $cacheFile)) {
    Write-Host "Downloading Ollama from $downloadUrl to $cacheFile via BITS..."
    try {
        $bitsJob = Start-BitsTransfer -Source $downloadUrl -Destination $tempFile -Asynchronous -RetryInterval 60 -RetryTimeout 600
        do {
            Start-Sleep -Seconds 2
            $bitsJob = Get-BitsTransfer -JobId $bitsJob.JobId -ErrorAction Stop
        } while ($bitsJob.JobState -in @('Connecting', 'Transferring', 'Queued'))

        if ($bitsJob.JobState -ne 'Transferred') {
            throw "BITS transfer finished in state '$($bitsJob.JobState)'."
        }

        Complete-BitsTransfer -BitsJob $bitsJob -ErrorAction Stop
        Move-Item -Path $tempFile -Destination $cacheFile -Force
    } catch {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
        if ($bitsJob) { Remove-BitsTransfer -BitsJob $bitsJob -ErrorAction SilentlyContinue }
        Write-Host "BITS download failed: $_" -ForegroundColor Red
        exit 3
    }
} elseif (-not $alreadyPresent) {
    Write-Host "Using cached Ollama archive: $cacheFile"
}

$tempFile = $cacheFile

# Optional checksum verification
$expectedSha = $env:OLLAMA_DOWNLOAD_SHA256
if (-not $alreadyPresent -and $expectedSha) {
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
if (-not $alreadyPresent) {
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
}

# Preserve the cached archive for future reruns. Only the temporary download
# file is moved into the cache path above; the cached archive itself should
# remain available after extraction.

# Add ollama dir to PATH for this process so subsequent steps see it
$ollamaBin = $ollamaDir
if (-not ($env:PATH.ToLower().Contains($ollamaBin.ToLower()))) { $env:PATH = "$ollamaBin;$env:PATH" }

Write-Host "Ollama installed to: $ollamaDir" -ForegroundColor Green

try {
    $verification = Test-OllamaRuntime -OllamaExe $ollamaExe
    Write-Host "" 
    Write-Host "Verification scan complete." -ForegroundColor Green
    Write-Host ("  Binary: " + $ollamaExe) -ForegroundColor White
    Write-Host ("  Version: " + $verification.Version) -ForegroundColor White
    Write-Host ("  API reachable at http://127.0.0.1:11434/api/tags") -ForegroundColor White
    Write-Host ("  Installed models reported by Ollama: " + ($verification.ApiModels.Count)) -ForegroundColor White
    Write-Host ""
    Write-Host "This confirms the local Ollama setup is present and responding." -ForegroundColor Cyan
} catch {
    Write-Host ""
    Write-Host "Verification scan did not complete cleanly: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "The binary was installed, but the runtime check failed. Please inspect the terminal output and rerun the setup if needed." -ForegroundColor Yellow
}
exit 0
