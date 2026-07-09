<#
.SYNOPSIS
Instantly removes all cache, downloads, install artifacts, and generated runtime
state from the Odysseus checkout.

Preserves user content: chroma vectors, uploads, personal docs, mail attachments.
Runs against the repo root automatically when invoked from this folder.
#>
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $root) { $root = (Get-Location).Path }

Write-Host ''
Write-Host '==> Resetting Odysseus runtime artifacts (cache / downloads / venv)' -ForegroundColor Cyan

$failed = @()

# 1. Stop resident Odysseus/uvicorn processes so files can be removed.
#    Scope matches to OUR venv binaries only and exclude Hermes-owned processes,
#    so the reset never kills Hermes Desktop (or other unrelated processes).
$venvScripts = Join-Path (Join-Path $root 'venv') 'Scripts'
$venvPy = Join-Path $venvScripts 'python.exe'
$venvPyLower = $venvPy.ToLowerInvariant()
$chromaExe = Join-Path $venvScripts 'chroma.exe'
$chromaExeLower = $chromaExe.ToLowerInvariant()
$hermesMarker = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent'
$hermesMarkerLower = $hermesMarker.ToLowerInvariant()
$procs = Get-CimInstance Win32_Process | Where-Object {
    $_.ProcessId -ne $PID
} | Where-Object {
    $cmd = $_.CommandLine
    if ([string]::IsNullOrEmpty($cmd)) { $false; return }
    $cmdLower = $cmd.ToLowerInvariant()
    $exe = $null
    try { $exe = $_.ExecutablePath } catch { }
    if (-not $exe) { $exe = ($cmd -split '\s+')[0] -replace '"', '' }
    $exeLower = $exe.ToLowerInvariant()
    if ($hermesMarkerLower -and $exeLower.Contains($hermesMarkerLower)) { $false; return }
    if ($cmdLower.Contains($venvPyLower) -and $cmdLower.Contains('uvicorn') -and $cmdLower.Contains('app:app')) { $true; return }
    if ($cmdLower.Contains($chromaExeLower)) { $true; return }
    $false
}
if ($procs) {
    Write-Host "Stopping $($procs.Count) resident process(es)..." -ForegroundColor Yellow
    foreach ($proc in $procs) {
        try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop } catch {
            $failed += "PID $($proc.ProcessId)"
        }
    }
    Start-Sleep -Seconds 1
} else {
    Write-Host 'No resident Odysseus processes found.' -ForegroundColor DarkGray
}

# 2. Wipe the virtualenv so pip/uvicorn state is fully gone.
$venv = Join-Path $root 'venv'
if (Test-Path $venv) {
    Write-Host 'Removing venv ...' -ForegroundColor Yellow
    try { Remove-Item -LiteralPath $venv -Recurse -Force -ErrorAction Stop } catch {
        $failed += "venv"
    }
}

$siteCustom = Join-Path $root 'venv\Lib\site-packages\sitecustomize.py'
if (Test-Path $siteCustom) {
    try { Remove-Item -LiteralPath $siteCustom -Force -ErrorAction Stop } catch {
        $failed += 'sitecustomize.py'
    }
}

# 3. Remove launcher/runtime cache, downloads, install/GPU lib bloat, logs.
$trash = @(
    'data\ollama',
    'data\downloads',
    'data\cache',
    'data\logs',
    'data\tts_cache',
    'data\generated_images',
    'data\email_urgency_cache',
    'data\deep_research',
    'data\skills'
)
foreach ($rel in $trash) {
    $p = Join-Path $root $rel
    if (Test-Path $p) {
        Write-Host "Removing $rel ..." -ForegroundColor Yellow
        try { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction Stop } catch {
            $failed += $rel
        }
    }
}

# 4. Drop temporary compose staging from mail attachments.
$compose = Join-Path $root 'data\mail-attachments\_compose'
if (Test-Path $compose) {
    Write-Host 'Removing mail-attachments compose cache ...' -ForegroundColor Yellow
    try { Remove-Item -LiteralPath $compose -Recurse -Force -ErrorAction Stop } catch {
        $failed += 'data\mail-attachments\_compose'
    }
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host ('Reset incomplete; {0} path(s) still locked or failed: {1}' -f $failed.Count, ($failed -join ', ')) -ForegroundColor Yellow
} else {
    Write-Host 'Reset complete.' -ForegroundColor Green
}
Write-Host 'Next: powershell -ExecutionPolicy Bypass -File .\launch-windows.ps1' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Close this window or press Enter to exit.' -ForegroundColor Yellow
Read-Host
