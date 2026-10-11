# Requires Ollama for Windows. Quit the Ollama tray app before starting.
param(
    [ValidateRange(4, 256)]
    [int]$ContextK = 64,

    # -1 leaves layer placement to Ollama; 99 puts all 66 layers on the GPU.
    [ValidateRange(-1, 999)]
    [int]$NumGpu = -1
)

function Get-ModelfileText {
    param(
        [Parameter(Mandatory)] [string]$BaseModel,
        [Parameter(Mandatory)] [int]$ContextTokens,
        [Parameter(Mandatory)] [int]$NumGpu
    )
    $lines = @("FROM $BaseModel", "PARAMETER num_ctx $ContextTokens")
    if ($NumGpu -ne -1) { $lines += "PARAMETER num_gpu $NumGpu" }
    return ($lines -join "`n") + "`n"
}

function Get-PlacementReport {
    param(
        [Parameter(Mandatory)] [long]$Size,
        [Parameter(Mandatory)] [long]$SizeVram
    )
    if ($Size -le 0) { throw "Model size must be positive, got $Size." }
    # Floor keeps a partial spill (e.g. 99.6%) from printing as 100%.
    $percent = [math]::Floor(100 * $SizeVram / $Size)
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $vramGiB = ($SizeVram / 1GB).ToString('F1', $culture)
    $sizeGiB = ($Size / 1GB).ToString('F1', $culture)
    $lines = @("GPU placement: $percent% of the model in VRAM ($vramGiB GiB of $sizeGiB GiB).")
    if ($SizeVram -lt $Size) {
        $lines += "Only $percent% of the model is in VRAM; the rest runs on the CPU and generation is slower. " +
            'Use -NumGpu 99 to keep all layers on the GPU, or a smaller -ContextK.'
    }
    return $lines
}

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
        Get-ModelfileText -BaseModel 'qwen3.8:27b' -ContextTokens $contextTokens -NumGpu $NumGpu |
            Set-Content -LiteralPath $modelfile -Encoding Ascii
        & $ollamaExe create $modelName -f $modelfile
        if ($LASTEXITCODE -ne 0) { throw "Failed to create $modelName." }
    } finally {
        Remove-Item -LiteralPath $modelfile -Force -ErrorAction SilentlyContinue
    }

    # Load the model once so /api/ps shows where its layers landed.
    $loadBody = @{ model = $modelName; prompt = ''; stream = $false } | ConvertTo-Json
    try {
        $null = Invoke-RestMethod -Method Post -Uri "$apiUrl/api/generate" -Body $loadBody `
            -ContentType 'application/json' -TimeoutSec 600
    } catch {
        throw "Failed to load $modelName ($($_.Exception.Message)). " +
            'Retry with -NumGpu -1 or a smaller -ContextK.'
    }
    $running = Invoke-RestMethod -Uri "$apiUrl/api/ps" -TimeoutSec 10
    $entry = @($running.models | Where-Object { $_.name -eq $modelName }) | Select-Object -First 1
    if (-not $entry) { throw "$modelName is not listed in /api/ps after loading." }
    $report = @(Get-PlacementReport -Size $entry.size -SizeVram $entry.size_vram)
    Write-Host $report[0]
    $report | Select-Object -Skip 1 | ForEach-Object { Write-Warning $_ }

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
