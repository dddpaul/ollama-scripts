# Requires Ollama for Windows. Quit the Ollama tray app before starting.
param(
    [ValidateRange(4, 256)]
    [int]$ContextK = 64,

    # -1 leaves layer placement to Ollama; 99 puts all 66 layers on the GPU.
    [ValidateRange(-1, 999)]
    [int]$NumGpu = -1,

    # 512 is Ollama's default and writes no num_batch line; 256 frees about 300 MiB at 128k.
    [ValidateRange(64, 2048)]
    [int]$NumBatch = 512,

    # Idle time before Ollama unloads the model: seconds ('-1' = until the server stops) or a duration such as '30m'.
    [ValidatePattern('^(-?\d{1,9}|-?(\d+(\.\d+)?(ns|us|ms|s|m|h))+)$')]
    [string]$KeepAlive = '-1',

    # 0 turns the log stream off; any other port streams the server log over TCP.
    [ValidateRange(0, 65535)]
    [ValidateScript({ if ($_ -eq 11435) { throw 'LogPort must differ from the Ollama port 11435.' }; $true })]
    [int]$LogPort = 0
)

function Get-ModelfileText {
    param(
        [Parameter(Mandatory)] [string]$BaseModel,
        [Parameter(Mandatory)] [int]$ContextTokens,
        [Parameter(Mandatory)] [int]$NumGpu,
        [int]$NumBatch = 512
    )
    $lines = @("FROM $BaseModel", "PARAMETER num_ctx $ContextTokens")
    if ($NumGpu -ne -1) { $lines += "PARAMETER num_gpu $NumGpu" }
    if ($NumBatch -ne 512) { $lines += "PARAMETER num_batch $NumBatch" }
    return ($lines -join "`n") + "`n"
}

function Get-WarmLoadBody {
    param(
        [Parameter(Mandatory)] [string]$Model,
        [Parameter(Mandatory)] [string]$KeepAlive
    )
    # The API parses a JSON string with Go's time.ParseDuration, which rejects a bare '-1', so seconds go as a number.
    $keepAliveValue = if ($KeepAlive -match '^-?\d+$') { [long]$KeepAlive } else { $KeepAlive }
    return @{ model = $Model; prompt = ''; stream = $false; keep_alive = $keepAliveValue } | ConvertTo-Json -Compress
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

function Split-LogText {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Pending,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Text
    )
    # The last part has no newline yet, so it waits in Pending for the next chunk.
    $parts = ($Pending + $Text).Split("`n")
    $lines = [string[]]::new($parts.Count - 1)
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $lines[$i] = $parts[$i] -replace "`r$", ''
    }
    return @{ Lines = $lines; Pending = $parts[-1] }
}

function Get-LogStreamHeader {
    return "HTTP/1.0 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nCache-Control: no-cache`r`n" +
        "X-Content-Type-Options: nosniff`r`nConnection: close`r`n`r`n"
}

function New-LogPumpState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Only builds an in-memory hashtable.')]
    param(
        [Parameter(Mandatory)] [string[]]$Paths,
        [System.Net.Sockets.TcpListener]$Listener
    )
    # Invalid UTF-8 becomes U+FFFD instead of throwing.
    $encoding = [System.Text.UTF8Encoding]::new($false, $false)
    $readers = foreach ($path in $Paths) {
        @{ Path = $path; Stream = $null; Decoder = $encoding.GetDecoder(); Pending = '' }
    }
    $buffer = [byte[]]::new(65536)
    return @{
        Readers = @($readers)
        Listener = $Listener
        Clients = [System.Collections.Generic.List[object]]::new()
        Encoding = $encoding
        Buffer = $buffer
        Chars = [char[]]::new($encoding.GetMaxCharCount($buffer.Length))
    }
}

function Write-Status {
    param(
        [Parameter(Mandatory)] [string]$Message,
        [AllowNull()] [hashtable]$State,
        [ValidateSet('Info', 'Warning', 'Error')] [string]$Level = 'Info'
    )
    $line = switch ($Level) {
        'Info' { $Message }
        'Warning' { "WARNING: $Message" }
        'Error' { "ERROR: $Message" }
    }
    if ($State) { Send-LogLine -State $State -Line $line }
    # An error reaches the console when the caller rethrows it.
    if ($Level -eq 'Info') { Write-Host $Message }
    if ($Level -eq 'Warning') { Write-Warning $Message }
}

function Send-LogLine {
    param(
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Line
    )
    if ($State.Clients.Count -eq 0) { return }
    $bytes = $State.Encoding.GetBytes($Line + "`n")
    $failed = @()
    foreach ($subscriber in @($State.Clients)) {
        # A send that exceeds the client's SendTimeout throws, so a slow client is dropped.
        try { $subscriber.Stream.Write($bytes, 0, $bytes.Length) } catch { $failed += $subscriber }
    }
    foreach ($subscriber in $failed) { Disconnect-LogSubscriber -State $State -Subscriber $subscriber }
}

function Disconnect-LogSubscriber {
    param(
        [Parameter(Mandatory)] [hashtable]$State,
        [Parameter(Mandatory)] [hashtable]$Subscriber
    )
    if (-not $State.Clients.Remove($Subscriber)) { return }
    $Subscriber.Client.Close()
    Write-Status -State $State -Message "log subscriber disconnected: $($Subscriber.Address)"
}

function Receive-LogSubscriberInput {
    param([Parameter(Mandatory)] [hashtable]$State)
    foreach ($subscriber in @($State.Clients)) {
        $socket = $subscriber.Client.Client
        try {
            # Discard the request so closing the socket later sends FIN, not RST.
            while ($socket.Available -gt 0) {
                $null = $socket.Receive($State.Buffer, [math]::Min($socket.Available, $State.Buffer.Length), 'None')
            }
            # Readable with nothing to read means the client closed its side.
            $closed = $socket.Poll(0, [System.Net.Sockets.SelectMode]::SelectRead) -and $socket.Available -eq 0
        } catch {
            $closed = $true
        }
        if ($closed) { Disconnect-LogSubscriber -State $State -Subscriber $subscriber }
    }
}

function Invoke-LogPump {
    param([Parameter(Mandatory)] [hashtable]$State)
    while ($State.Listener -and $State.Listener.Pending()) {
        $client = $State.Listener.AcceptTcpClient()
        $client.SendTimeout = 500
        $client.NoDelay = $true
        $subscriber = @{ Client = $client; Stream = $client.GetStream(); Address = [string]$client.Client.RemoteEndPoint }
        $header = $State.Encoding.GetBytes((Get-LogStreamHeader))
        try {
            $subscriber.Stream.Write($header, 0, $header.Length)
        } catch {
            $client.Close()
            continue
        }
        $State.Clients.Add($subscriber)
        Write-Status -State $State -Message "log subscriber connected: $($subscriber.Address)"
    }
    Receive-LogSubscriberInput -State $State

    foreach ($reader in $State.Readers) {
        if (-not $reader.Stream) {
            if (-not (Test-Path -LiteralPath $reader.Path)) { continue }
            $reader.Stream = [System.IO.FileStream]::new($reader.Path, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete)
        }
        $text = [System.Text.StringBuilder]::new()
        while (($count = $reader.Stream.Read($State.Buffer, 0, $State.Buffer.Length)) -gt 0) {
            $charCount = $reader.Decoder.GetChars($State.Buffer, 0, $count, $State.Chars, 0)
            $null = $text.Append($State.Chars, 0, $charCount)
        }
        if ($text.Length -eq 0) { continue }
        $split = Split-LogText -Pending $reader.Pending -Text $text.ToString()
        $reader.Pending = $split.Pending
        foreach ($line in $split.Lines) {
            Send-LogLine -State $State -Line $line
            Write-Host $line
        }
    }
}

function Close-LogPump {
    param([Parameter(Mandatory)] [hashtable]$State)
    # Console output can fail while Ctrl+C stops the script; the subscribers must still be closed.
    try {
        Invoke-LogPump -State $State
    } catch {
        Write-Verbose "Final log pump failed: $($_.Exception.Message)"
    }
    foreach ($subscriber in @($State.Clients)) {
        $socket = $subscriber.Client.Client
        try {
            while ($socket.Available -gt 0) {
                $null = $socket.Receive($State.Buffer, [math]::Min($socket.Available, $State.Buffer.Length), 'None')
            }
            # Half-close first so the client sees a normal end of stream.
            $socket.Shutdown([System.Net.Sockets.SocketShutdown]::Send)
        } catch {
            Write-Verbose "Closing log subscriber $($subscriber.Address) failed: $($_.Exception.Message)"
        }
        $subscriber.Client.Close()
    }
    $State.Clients.Clear()
    if ($State.Listener) { $State.Listener.Stop() }
}

$ErrorActionPreference = 'Stop'
$ollamaExe = (Get-Command ollama.exe -ErrorAction Stop).Source
$modelName = "qwen3.8:27b-${ContextK}k"
$contextTokens = $ContextK * 1024
$apiUrl = 'http://127.0.0.1:11435'
$outLog = Join-Path $env:TEMP 'ollama-serve.out.log'
$errLog = Join-Path $env:TEMP 'ollama-serve.err.log'

if (Get-NetTCPConnection -LocalPort 11435 -State Listen -ErrorAction SilentlyContinue) {
    throw 'Port 11435 is already in use. Stop that server before running this script.'
}
if ($LogPort -ne 0 -and (Get-NetTCPConnection -LocalPort $LogPort -State Listen -ErrorAction SilentlyContinue)) {
    throw "Log port $LogPort is already in use. Choose another -LogPort."
}

# These settings are inherited by the server process at launch.
$env:OLLAMA_HOST = '0.0.0.0:11435'
$env:OLLAMA_CONTEXT_LENGTH = [string]$contextTokens
$env:OLLAMA_NUM_PARALLEL = '1'
$env:OLLAMA_MAX_LOADED_MODELS = '1'
$env:OLLAMA_FLASH_ATTENTION = '1'
$env:OLLAMA_KV_CACHE_TYPE = 'q8_0'
$env:OLLAMA_KEEP_ALIVE = $KeepAlive

$listener = $null
$server = $null
$state = $null
try {
    if ($LogPort -ne 0) {
        $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $LogPort)
        try {
            $listener.Start()
        } catch {
            $listener = $null
            throw "Cannot listen on log port $LogPort ($($_.Exception.Message)). Choose another -LogPort; " +
                'Windows may reserve the port, check: netsh int ipv4 show excludedportrange protocol=tcp'
        }
    }
    # The pump echoes both files to the console and to log subscribers.
    $server = Start-Process -FilePath $ollamaExe -ArgumentList 'serve' -NoNewWindow -PassThru `
        -RedirectStandardOutput $outLog -RedirectStandardError $errLog
    $state = New-LogPumpState -Paths $outLog, $errLog -Listener $listener
    if ($listener) { Write-Status -State $state -Message "Streaming the server log on tcp://0.0.0.0:$LogPort" }

    # The server retains its all-interface bind; CLI commands use loopback.
    $env:OLLAMA_HOST = $apiUrl
    $ready = $false
    $deadline = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $deadline) {
        Invoke-LogPump -State $state
        if ($server.HasExited) {
            throw "Ollama exited with code $($server.ExitCode)."
        }
        try {
            $null = Invoke-RestMethod -Uri "$apiUrl/api/version" -TimeoutSec 2
            $ready = $true
            break
        } catch {
            Start-Sleep -Milliseconds 200
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
        Get-ModelfileText -BaseModel 'qwen3.8:27b' -ContextTokens $contextTokens -NumGpu $NumGpu -NumBatch $NumBatch |
            Set-Content -LiteralPath $modelfile -Encoding Ascii
        & $ollamaExe create $modelName -f $modelfile
        if ($LASTEXITCODE -ne 0) { throw "Failed to create $modelName." }
    } finally {
        Remove-Item -LiteralPath $modelfile -Force -ErrorAction SilentlyContinue
    }
    Invoke-LogPump -State $state

    # Load the model once so /api/ps shows where its layers landed.
    $loadBody = Get-WarmLoadBody -Model $modelName -KeepAlive $KeepAlive
    try {
        $null = Invoke-RestMethod -Method Post -Uri "$apiUrl/api/generate" -Body $loadBody `
            -ContentType 'application/json' -TimeoutSec 600
    } catch {
        throw "Failed to load $modelName ($($_.Exception.Message)). " +
            'Retry with -NumGpu -1 or a smaller -ContextK.'
    }
    Invoke-LogPump -State $state
    $running = Invoke-RestMethod -Uri "$apiUrl/api/ps" -TimeoutSec 10
    $entry = @($running.models | Where-Object { $_.name -eq $modelName }) | Select-Object -First 1
    if (-not $entry) { throw "$modelName is not listed in /api/ps after loading." }
    $report = @(Get-PlacementReport -Size $entry.size -SizeVram $entry.size_vram)
    Write-Status -State $state -Message $report[0]
    $report | Select-Object -Skip 1 | ForEach-Object { Write-Status -State $state -Level Warning -Message $_ }

    Write-Status -State $state -Message 'Ollama is serving on http://0.0.0.0:11435'
    Write-Status -State $state -Message "Model: $modelName ($contextTokens-token context)"
    Write-Status -State $state -Message 'Press Ctrl+C to stop this server.'
    while (-not $server.HasExited) {
        Invoke-LogPump -State $state
        Start-Sleep -Milliseconds 200
    }
    if ($server.ExitCode -ne 0) { throw "Ollama exited with code $($server.ExitCode)." }
} catch {
    if ($state) {
        # Pump first so the server's last lines, often the cause, precede the error.
        $failure = $_
        try { Invoke-LogPump -State $state } catch { Write-Verbose "Log pump failed: $($_.Exception.Message)" }
        Write-Status -State $state -Level Error -Message $failure.Exception.Message
    }
    throw
} finally {
    if ($state) {
        Close-LogPump -State $state
    } elseif ($listener) {
        $listener.Stop()
    }
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -ErrorAction SilentlyContinue
    }
    if ($state) {
        foreach ($reader in $state.Readers) {
            if ($reader.Stream) { $reader.Stream.Dispose() }
        }
    }
}
