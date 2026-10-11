# Requires Ollama for Windows. Quit the Ollama tray app before starting.
param(
    [ValidateRange(4, 256)]
    [int]$ContextK = 64
)

$ErrorActionPreference = 'Stop'
$ollamaExe = (Get-Command ollama.exe -ErrorAction Stop).Source
$modelName = "qwen3.8:27b-${ContextK}k"
$contextTokens = $ContextK * 1024
$apiUrl = 'http://127.0.0.1:11435'

if (Get-NetTCPConnection -LocalPort 11435 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Port 11435 is already in use. Stop that server before running this script.'
}

# These settings are inherited by the server process at launch.
$env:OLLAMA_HOST = '0.0.0.0:11435'
$env:OLLAMA_CONTEXT_LENGTH = [string]$contextTokens
$env:OLLAMA_NUM_PARALLEL = '1'
$env:OLLAMA_MAX_LOADED_MODELS = '1'
$env:OLLAMA_FLASH_ATTENTION = '1'
$env:OLLAMA_KV_CACHE_TYPE = 'q8_0'

$server = Start-Process -FilePath $ollamaExe -ArgumentList 'serve' -NoNewWindow -PassThru
try {
    # The server retains its all-interface bind; CLI commands use loopback.
    $env:OLLAMA_HOST = $apiUrl
    $ready = $false
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        if ($server.HasExited) {
            throw "Ollama exited with code $($server.ExitCode)."
        }
        try {
            $null = Invoke-RestMethod -Uri "$apiUrl/api/version" -TimeoutSec 2
            $ready = $true
            break
        } catch {
            Start-Sleep -Seconds 1
        }
    }
    if (-not $ready) { throw 'Ollama did not become ready within 120 seconds.' }

    $inventory = Invoke-RestMethod -Uri "$apiUrl/api/tags" -TimeoutSec 10
    if (@($inventory.models | Where-Object { $_.name -eq 'qwen3.8:27b' }).Count -eq 0) {
        & $ollamaExe pull 'qwen3.8:27b'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to download qwen3.8:27b.' }
    }
    $modelfile = [System.IO.Path]::GetTempFileName()
    try {
        @"
FROM qwen3.8:27b
PARAMETER num_ctx $contextTokens
"@ | Set-Content -LiteralPath $modelfile -Encoding Ascii
        & $ollamaExe create $modelName -f $modelfile
        if ($LASTEXITCODE -ne 0) { throw "Failed to create $modelName." }
    } finally {
        Remove-Item -LiteralPath $modelfile -Force -ErrorAction SilentlyContinue
    }

    Write-Host "Ollama is serving on http://0.0.0.0:11435"
    Write-Host "Model: $modelName ($contextTokens-token context)"
    Write-Host 'Press Ctrl+C to stop this server.'
    while (-not $server.HasExited) {
        Start-Sleep -Seconds 1
    }
    if ($server.ExitCode -ne 0) { throw "Ollama exited with code $($server.ExitCode)." }
} finally {
    if (-not $server.HasExited) {
        Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
    }
}
