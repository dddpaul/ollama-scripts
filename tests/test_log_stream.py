"""Tests for the -LogPort parameter and the log stream helpers in windows/start-ollama.ps1."""

import base64
import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

import pytest

SCRIPT = Path(__file__).resolve().parent.parent / "windows" / "start-ollama.ps1"
PWSH = shutil.which("pwsh")

pytestmark = pytest.mark.skipif(PWSH is None, reason="pwsh is not on PATH")

# Dot-sources only the function definitions, so the script body (ollama.exe lookup, server start) never runs.
LOAD_FUNCTIONS = f"""
$ErrorActionPreference = 'Stop'
$ast = [System.Management.Automation.Language.Parser]::ParseFile('{SCRIPT}', [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({{ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }}, $false)) {{
    . ([scriptblock]::Create($f.Extent.Text))
}}
"""

HEADER = (
    "HTTP/1.0 200 OK\r\n"
    "Content-Type: text/plain; charset=utf-8\r\n"
    "Cache-Control: no-cache\r\n"
    "X-Content-Type-Options: nosniff\r\n"
    "Connection: close\r\n"
    "\r\n"
)

# Reads exactly $Count bytes from a TcpClient, failing after 5 seconds instead of hanging.
READ_BYTES = """
function Read-Bytes {
    param([System.Net.Sockets.TcpClient]$Client, [int]$Count)
    $Client.ReceiveTimeout = 5000
    $buffer = [byte[]]::new($Count)
    $total = 0
    while ($total -lt $Count) {
        $n = $Client.GetStream().Read($buffer, $total, $Count - $total)
        if ($n -eq 0) { throw "Stream ended after $total of $Count bytes." }
        $total += $n
    }
    return [System.Text.Encoding]::UTF8.GetString($buffer)
}
"""


def run_pwsh(command: str) -> str:
    """Run a pwsh command after loading the script's functions and return its stdout.

    Args:
        command: PowerShell code to run once the functions are defined.

    Returns:
        The command's standard output.
    """
    assert PWSH is not None
    result = subprocess.run(
        [PWSH, "-NoProfile", "-NonInteractive", "-Command", LOAD_FUNCTIONS + command],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    assert result.returncode == 0, result.stderr
    return result.stdout


def run_script(*args: str) -> subprocess.CompletedProcess[str]:
    """Run the whole script with the given arguments and return the finished process."""
    assert PWSH is not None
    return subprocess.run(
        [PWSH, "-NoProfile", "-NonInteractive", "-File", str(SCRIPT), *args],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )


def split_log_text(pending: str, text: str) -> dict[str, Any]:
    """Return Split-LogText's result for the given inputs, passed base64-encoded to keep CR and LF intact."""
    pending64 = base64.b64encode(pending.encode()).decode()
    text64 = base64.b64encode(text.encode()).decode()
    out = run_pwsh(
        f"$p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{pending64}'))\n"
        f"$t = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('{text64}'))\n"
        "$r = Split-LogText -Pending $p -Text $t\n"
        "@{ Lines = @($r.Lines); Pending = $r.Pending } | ConvertTo-Json -Compress"
    )
    result = json.loads(out)
    assert isinstance(result, dict)
    return result


@pytest.mark.parametrize("port", ["70000", "-1", "11435"])
def test_log_port_rejected_at_binding(port: str) -> None:
    """Ports outside 0-65535 and the Ollama port itself fail parameter validation before any Ollama lookup."""
    result = run_script("-LogPort", port)
    assert result.returncode != 0
    assert "LogPort" in result.stderr
    assert "ollama.exe" not in result.stderr


@pytest.mark.parametrize("args", [["-LogPort", "11436"], []])
def test_valid_log_port_reaches_ollama_lookup(args: list[str]) -> None:
    """A free port and the default pass validation and stop only at the ollama.exe lookup."""
    result = run_script(*args)
    assert result.returncode != 0
    assert "ollama.exe" in result.stderr
    assert "LogPort" not in result.stderr


def test_split_log_text_keeps_unfinished_line_pending() -> None:
    """Complete lines are returned and the text after the last newline waits as Pending."""
    assert split_log_text("", "first\nsecond") == {"Lines": ["first"], "Pending": "second"}


def test_split_log_text_joins_pending_with_next_chunk() -> None:
    """Pending text is prepended to the next chunk."""
    assert split_log_text("sec", "ond\n") == {"Lines": ["second"], "Pending": ""}


def test_split_log_text_strips_cr_and_handles_several_lines() -> None:
    """CRLF lines lose their CR, and one chunk can carry several lines."""
    result = split_log_text("", "one\r\ntwo\nthree\r\n")
    assert result == {"Lines": ["one", "two", "three"], "Pending": ""}


def test_split_log_text_empty_input_has_no_lines() -> None:
    """Empty input yields no lines and an empty Pending."""
    assert split_log_text("", "") == {"Lines": [], "Pending": ""}


def test_log_stream_header_is_exact() -> None:
    """The header is a minimal HTTP/1.0 text/plain response ending in a blank line."""
    out = run_pwsh("[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes((Get-LogStreamHeader)))")
    header = base64.b64decode(out.strip()).decode()
    assert header == HEADER
    assert header.endswith("\r\n\r\n")


def test_pump_streams_both_files_to_a_subscriber(tmp_path: Path) -> None:
    """A real subscriber gets the header, then lines from either file in order, and is dropped after closing."""
    out_log = tmp_path / "out.log"
    err_log = tmp_path / "err.log"
    out_log.write_bytes(b"")
    err_log.write_bytes(b"")
    command = READ_BYTES + f"""
$out = '{out_log}'
$err = '{err_log}'
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$state = New-LogPumpState -Paths $out, $err -Listener $listener
$client = [System.Net.Sockets.TcpClient]::new('127.0.0.1', $listener.LocalEndpoint.Port)
$console = @()

$console += Invoke-LogPump -State $state 6>&1 | ForEach-Object {{ "$_" }}
$afterAccept = $state.Clients.Count
$address = $state.Clients[0].Address
$expected1 = (Get-LogStreamHeader) + "log subscriber connected: $address`n"
$first = Read-Bytes -Client $client -Count ([Text.Encoding]::UTF8.GetByteCount($expected1))

[IO.File]::AppendAllText($out, "out one`nout two`n")
[IO.File]::AppendAllText($err, "err one`r`nerr par")
$console += Invoke-LogPump -State $state 6>&1 | ForEach-Object {{ "$_" }}
[IO.File]::AppendAllText($err, "tial`n")
$console += Invoke-LogPump -State $state 6>&1 | ForEach-Object {{ "$_" }}
$expected2 = "out one`nout two`nerr one`nerr partial`n"
$second = Read-Bytes -Client $client -Count ([Text.Encoding]::UTF8.GetByteCount($expected2))
Start-Sleep -Milliseconds 100
$extra = $client.Available

$client.Close()
Start-Sleep -Milliseconds 200
$console += Invoke-LogPump -State $state 6>&1 | ForEach-Object {{ "$_" }}
$afterClose = $state.Clients.Count
$listener.Stop()
foreach ($reader in $state.Readers) {{ $reader.Stream.Dispose() }}

@{{
    AfterAccept = $afterAccept; AfterClose = $afterClose; Extra = $extra; Address = $address
    First = $first; Second = $second; Console = @($console)
}} | ConvertTo-Json -Compress
"""
    result = json.loads(run_pwsh(command))
    assert result["AfterAccept"] == 1
    assert result["Address"].startswith("127.0.0.1:")
    assert result["First"] == HEADER + f"log subscriber connected: {result['Address']}\n"
    assert result["Second"] == "out one\nout two\nerr one\nerr partial\n"
    assert result["Extra"] == 0
    assert result["AfterClose"] == 0
    assert result["Console"] == [
        f"log subscriber connected: {result['Address']}",
        "out one",
        "out two",
        "err one",
        "err partial",
        f"log subscriber disconnected: {result['Address']}",
    ]


def test_pump_without_listener_echoes_and_opens_no_port(tmp_path: Path) -> None:
    """With -LogPort 0 the state has no listener: lines still reach the console and no port starts listening."""
    out_log = tmp_path / "out.log"
    err_log = tmp_path / "err.log"
    out_log.write_text("server started\n")
    err_log.write_text("llama loaded\n")
    command = f"""
$props = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties()
$before = @($props.GetActiveTcpListeners() | ForEach-Object {{ [string]$_ }}) | Sort-Object
$state = New-LogPumpState -Paths '{out_log}', '{err_log}'
$console = @(Invoke-LogPump -State $state 6>&1 | ForEach-Object {{ "$_" }})
$after = @($props.GetActiveTcpListeners() | ForEach-Object {{ [string]$_ }}) | Sort-Object
foreach ($reader in $state.Readers) {{ $reader.Stream.Dispose() }}
@{{
    Console = $console; HasListener = $null -ne $state.Listener; Clients = $state.Clients.Count
    SamePorts = ($before -join ',') -eq ($after -join ',')
}} | ConvertTo-Json -Compress
"""
    result = json.loads(run_pwsh(command))
    assert result["Console"] == ["server started", "llama loaded"]
    assert result["HasListener"] is False
    assert result["Clients"] == 0
    assert result["SamePorts"] is True
