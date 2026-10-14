# PSIT OAS Launcher - Native PowerShell Key Diagnostic Runner
# Runs Python test_keys.py if available, or tests Gemini endpoints natively

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "         PSIT OAS Launcher - API Key Diagnostic & Health Suite" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$pyScript = Join-Path $scriptDir "test_keys.py"

if (Get-Command python -ErrorAction SilentlyContinue) {
    & python $pyScript @args
    exit $LASTEXITCODE
}

Write-Host "[i] Python not detected in PATH, running native PowerShell test..." -ForegroundColor Yellow

$keysFile = Join-Path $scriptDir "keys.txt"
if (-not (Test-Path $keysFile)) {
    Write-Host "[!] keys.txt not found at $keysFile" -ForegroundColor Red
    exit 1
}

$keys = @()
Get-Content $keysFile | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } | ForEach-Object {
    $parts = $_.Trim() -split ':', 2
    if ($parts.Count -eq 2) {
        $keys += [PSCustomObject]@{ Provider = $parts[0].Trim().ToLower(); Key = $parts[1].Trim() }
    }
}

Write-Host "Found $($keys.Count) key(s) in keys.txt`n" -ForegroundColor Gray

$models = @('gemini-flash-lite-latest', 'gemini-flash-latest', 'gemini-2.5-flash-lite', 'gemini-3.8-flash', 'gemini-2.5-flash')
$idx = 1
$active = 0

foreach ($k in $keys) {
    $masked = if ($k.Key.Length -gt 8) { $k.Key.Substring(0,4) + '...' + $k.Key.Substring($k.Key.Length - 4) } else { '***' }
    if ($k.Provider -ne 'gemini') {
        Write-Host "[$idx] Provider $($k.Provider) ($masked): Native test only supports gemini (use Python for groq/openrouter/notion)" -ForegroundColor Gray
        $idx++
        continue
    }

    $pass = $false
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    foreach ($m in $models) {
        try {
            [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12 -bor [System.Net.SecurityProtocolType]::Tls13
            $url = "https://generativelanguage.googleapis.com/v1beta/models/$($m):generateContent?key=$($k.Key)"
            $body = @{ contents = @(@{ parts = @(@{ text = "PONG" }) }) } | ConvertTo-Json -Depth 4
            $req = [System.Net.HttpWebRequest]::Create($url)
            $req.Method = "POST"; $req.ContentType = "application/json"; $req.Timeout = 8000
            $b = [System.Text.Encoding]::UTF8.GetBytes($body); $req.ContentLength = $b.Length
            $s = $req.GetRequestStream(); $s.Write($b, 0, $b.Length); $s.Close()
            $hr = $req.GetResponse()
            $sr = New-Object System.IO.StreamReader($hr.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $raw = $sr.ReadToEnd(); $sr.Close(); $hr.Close()
            $sw.Stop()
            Write-Host "[$idx] GEMINI ($masked) -> [PASS] in $($sw.ElapsedMilliseconds)ms with model $m" -ForegroundColor Green
            $pass = $true
            $active++
            break
        } catch {
            continue
        }
    }
    if (-not $pass) {
        Write-Host "[$idx] GEMINI ($masked) -> [FAIL / QUOTA / BUSY]" -ForegroundColor Red
    }
    $idx++
}

Write-Host "`nSummary: $active/$($keys.Count) active key(s)" -ForegroundColor Cyan
if ($active -gt 0) { exit 0 } else { exit 1 }
