# PSIT OAS - Instant 3-Dots Overlay Launcher
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
if (-not $scriptDir) { $scriptDir = "C:\extracted" }
$targetFile = Join-Path $scriptDir "ScreenCapture.ps1"

# Terminate any previously running overlay process to avoid duplicate dots or stale memory state
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*ScreenCapture*" -and $_.ProcessId -ne $PID } |
    ForEach-Object { try { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } catch {} }

# Launch purely the three dots overlay in hidden background mode
$pInfo = New-Object System.Diagnostics.ProcessStartInfo
$pInfo.FileName = "powershell.exe"
$pInfo.Arguments = "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$targetFile`""
$pInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$pInfo.CreateNoWindow = $true
$pInfo.UseShellExecute = $false
[System.Diagnostics.Process]::Start($pInfo) | Out-Null

Write-Host "[OK] Three dots overlay is now running on your screen!" -ForegroundColor Green
