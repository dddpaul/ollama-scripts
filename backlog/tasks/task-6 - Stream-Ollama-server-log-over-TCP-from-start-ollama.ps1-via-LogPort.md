---
id: TASK-6
title: Stream Ollama server log over TCP from start-ollama.ps1 via -LogPort
status: Done
assignee: []
created_date: '2026-10-11 16:11'
updated_date: '2026-10-11 16:24'
labels:
  - 'feature:ollama-log-streaming'
dependencies: []
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Direction:** Option A, a single-threaded TCP listener in windows/start-ollama.ps1 that sends a minimal HTTP/1.0 text/plain header and then streams live Ollama server log lines; opt-in via -LogPort.

**Locked decisions (with rationale):**
- **Transport:** `System.Net.Sockets.TcpListener` on `0.0.0.0:<LogPort>` (all IPv4 interfaces, like Ollama itself). *Rationale:* no admin rights or URL reservation, works in Windows PowerShell 5.1, fits the existing polling loop.
- **Parameter:** `[ValidateRange(0, 65535)] [ValidateScript({ if ($_ -eq 11435) { throw 'LogPort must differ from the Ollama port 11435.' }; $true })] [int]$LogPort = 0`; 0 means off and creates no listener. *Rationale:* the owner chose opt-in; rejecting 11435 at binding gives a clear error before any Ollama lookup.
- **Port checks at start, before Ollama starts:** if `-LogPort` is already listening, throw a message naming the port; if binding fails (for example a Windows-reserved range from Hyper-V or WSL), throw a message that suggests another `-LogPort` and names `netsh int ipv4 show excludedportrange protocol=tcp`. *Rationale:* fail fast like the existing 11435 check.
- **Response:** on accept, send immediately (never wait for the request), then live lines only, each UTF-8 and terminated by `\n`, flushed per line; read and discard any bytes the client sends so the final close is clean. *Rationale:* curl, nc and browsers all work, and live-only is the owner's choice. Exact header:

```text
HTTP/1.0 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-cache\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n
```

- **Content:** everything `ollama serve` writes to stdout and stderr, plus the script's own status lines via `Write-Status`; warnings as `WARNING: <text>`; on a fatal script error an outer catch sends `ERROR: <message>` and rethrows. *Rationale:* a remote subscriber sees exactly what the console shows, including why the script stopped.
- **Capture:** always redirect `ollama serve` stdout to `%TEMP%\ollama-serve.out.log` and stderr to `%TEMP%\ollama-serve.err.log` with `Start-Process`; overwrite at each start and leave them after exit. *Rationale:* one code path whether streaming is on or off; the files keep the last run's log.
- **Pump:** `Invoke-LogPump -State <hashtable>`, called about every 200 ms in the readiness loop and in the serve loop: read new bytes from both files (FileShare.ReadWrite, one open stream each), `Split-LogText` into complete lines (partial last line kept, CR stripped, invalid UTF-8 replaced), echo each line to the console, accept pending clients without blocking (`Pending()`), send the header, broadcast lines, drop clients that closed (detected even without traffic, for example `Poll(0, SelectRead)` with `Available -eq 0`) or whose send exceeds a 500 ms `SendTimeout`. Connects and disconnects are announced via `Write-Status` as `log subscriber connected: <address>` and `log subscriber disconnected: <address>`. *Rationale:* single-threaded is safe in PowerShell 5.1, and a slow client can never stall the console or other subscribers.
- **Testable helpers** defined right after the param block, beside `Get-ModelfileText` and `Get-PlacementReport`: `Split-LogText -Pending <string> -Text <string>` returns `@{ Lines = <string[]>; Pending = <string> }`; `Get-LogStreamHeader` returns the exact header string; `New-LogPumpState -Paths <string[]> [-Listener <TcpListener>]` returns the pump state; `Invoke-LogPump -State <hashtable>` performs one pump cycle; `Write-Status` writes one status line. *Rationale:* the logic is testable in the devcontainer without Ollama, loaded the same way tests/test_start_ollama.py loads functions (parse the script AST, dot-source only the function definitions).
- **Shutdown (finally block):** final pump, then for each subscriber `Shutdown(Send)` and `Close()`, then stop the listener, stop Ollama (as today), and dispose the file streams. *Rationale:* curl ends normally instead of "connection reset", and the last lines reach subscribers.

**Scope cuts:**
- Authentication, TLS, replay of earlier lines, UDP, HTTP routes, request summaries, structured or JSON lines, log rotation, Linux scripts, token streaming.
- The Windows LAN verification (owner starts the script with `-LogPort 11436` and the firewall rule; a client on the Mac subscribes) is an owner-run follow-up, not part of this task.

**Acceptance criteria (sketch):**
- In the devcontainer, running the script with `-LogPort 70000`, `-LogPort -1` and `-LogPort 11435` each fails with a LogPort parameter validation error, while `-LogPort 11436` and the default get past validation and fail only on the ollama.exe lookup.
- A pytest test shows `Split-LogText` returns complete lines and keeps an unfinished last line as Pending, strips CR from CRLF lines, handles several lines in one chunk, and returns no lines for empty input.
- A pytest test shows `Get-LogStreamHeader` returns exactly the header above, ending in a blank line.
- A pytest test with real sockets in one pwsh process (two temp files, a `TcpListener` on 127.0.0.1 with a free port, a `TcpClient`) shows: the first `Invoke-LogPump` call accepts the client and the client receives the header; lines appended to either file reach the client after the next call, exactly and in order; after the client closes, the next call removes it from the state.
- A pytest test shows `Invoke-LogPump` with a state that has no listener (`-LogPort 0`) echoes lines and opens no port.
- The script starts `ollama serve` with stdout and stderr redirected to the two `%TEMP%` files, calls `Invoke-LogPump` in the readiness loop and the serve loop at about 200 ms, sends status lines through `Write-Status`, sends `ERROR: <message>` on a fatal error, and runs the shutdown sequence in its finally block.
- README.md documents `-LogPort` (default 0 = off), a firewall rule for the log port mirroring the 11435 rule (Private profile, LocalSubnet), client examples (`curl -sN`, `curl -sN --max-time 120`, `nc`, background capture to a file), what the log contains (model names, request lines, Windows paths with the username; no prompt text at the default log level), the security note, and the two `%TEMP%` log files.
- The CLAUDE.md Lint and Test commands exit 0 in the devcontainer, and the Test run executes the new tests instead of skipping them.

**Implementation checklist:**
- Add the `-LogPort` parameter with the range and 11435 checks.
- Add `Split-LogText`, `Get-LogStreamHeader`, `New-LogPumpState`, `Invoke-LogPump` and `Write-Status` after the param block.
- Replace `Start-Process ... -NoNewWindow` for `ollama serve` with redirection to the two `%TEMP%` files; open both for shared reading.
- When `-LogPort` is non-zero: check the port is free, start the `TcpListener` (clear errors on failure), and pass it to `New-LogPumpState`.
- Call `Invoke-LogPump` in the readiness loop and the serve loop with 200 ms sleeps; route status lines and the placement warning through `Write-Status`.
- Add an outer catch that sends `ERROR: <message>` and rethrows; extend the finally block with the shutdown sequence.
- Add the pytest tests (reuse the function-loading approach from tests/test_start_ollama.py).
- Update README.md (Windows section) as listed in the acceptance criteria.
- Run the CLAUDE.md Lint and Test commands in the devcontainer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In the devcontainer, running the script with `-LogPort 70000`, `-LogPort -1` and `-LogPort 11435` each fails with a LogPort parameter validation error, while `-LogPort 11436` and the default get past validation and fail only on the ollama.exe lookup.
- [x] #2 A pytest test shows `Split-LogText` returns complete lines and keeps an unfinished last line as Pending, strips CR from CRLF lines, handles several lines in one chunk, and returns no lines for empty input.
- [x] #3 A pytest test shows `Get-LogStreamHeader` returns exactly the header above, ending in a blank line.
- [x] #4 A pytest test with real sockets in one pwsh process (two temp files, a `TcpListener` on 127.0.0.1 with a free port, a `TcpClient`) shows: the first `Invoke-LogPump` call accepts the client and the client receives the header; lines appended to either file reach the client after the next call, exactly and in order; after the client closes, the next call removes it from the state.
- [x] #5 A pytest test shows `Invoke-LogPump` with a state that has no listener (`-LogPort 0`) echoes lines and opens no port.
- [x] #6 The script starts `ollama serve` with stdout and stderr redirected to the two `%TEMP%` files, calls `Invoke-LogPump` in the readiness loop and the serve loop at about 200 ms, sends status lines through `Write-Status`, sends `ERROR: <message>` on a fatal error, and runs the shutdown sequence in its finally block.
- [x] #7 README.md documents `-LogPort` (default 0 = off), a firewall rule for the log port mirroring the 11435 rule (Private profile, LocalSubnet), client examples (`curl -sN`, `curl -sN --max-time 120`, `nc`, background capture to a file), what the log contains (model names, request lines, Windows paths with the username; no prompt text at the default log level), the security note, and the two `%TEMP%` log files.
- [x] #8 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer, and the Test run executes the new tests instead of skipping them.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: add -LogPort param (range + 11435 ValidateScript); add Split-LogText, Get-LogStreamHeader, New-LogPumpState, Invoke-LogPump, Write-Status after the param block; redirect ollama serve stdout/stderr to %TEMP% files; optional TcpListener with port-in-use and bind-failure errors; pump every 200 ms in readiness/serve loops; outer catch sends ERROR:, finally does final pump + subscriber Shutdown(Send)/Close + listener stop + Ollama stop + stream dispose; pytest tests in tests/test_log_stream.py using the AST loader; README Windows section.

Commit: `6f36281` - task-6: Stream the Ollama server log over TCP via -LogPort

Commit: `0a08a3a` - task-6: Pump the server log before sending the ERROR line

Implemented -LogPort (ValidateRange 0-65535, 11435 rejected), helpers Split-LogText/Get-LogStreamHeader/New-LogPumpState/Invoke-LogPump/Write-Status plus private Send-LogLine/Disconnect-LogSubscriber/Receive-LogSubscriberInput/Close-LogPump. ollama serve output redirected to %TEMP%\ollama-serve.{out,err}.log; pump every 200 ms in readiness and serve loops; outer catch pumps, then sends ERROR:, then rethrows; finally runs Close-LogPump (final pump, Shutdown(Send)+Close, listener stop), Stop-Process, stream dispose. Tests in tests/test_log_stream.py (12, real loopback sockets). Gotcha: a TcpClient's LocalEndPoint is dual-stack ([::ffff:127.0.0.1]:p), so the test takes the address from the server-side subscriber. Not pumped during pull/create/model load (lines queue). Windows LAN verification remains an owner follow-up. task-reviewer: APPROVED.
<!-- SECTION:NOTES:END -->
