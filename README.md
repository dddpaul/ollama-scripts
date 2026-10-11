# ollama-scripts

Helper scripts for running Ollama models, organised by platform directory.
Today the only platform directory is `windows/`.

## Scripts

| Script | Platform | Purpose |
| --- | --- | --- |
| [`windows/start-ollama.ps1`](windows/start-ollama.ps1) | Windows | Starts a LAN-reachable Ollama server on port 11435 and serves `qwen3.8:27b` with a context configurable from 4k to 256k (default 64k). |

## Windows: Qwen 3.8 launcher

Install a current Ollama for Windows and quit its tray app; `ollama.exe` must be
on `PATH`. Copy `windows/start-ollama.ps1` from this repo to the Windows
machine, then run it from the directory you copied it to:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-ollama.ps1
```

The script starts Ollama on all IPv4 interfaces at port 11435, downloads
`qwen3.8:27b` if missing, and creates `qwen3.8:27b-64k` with a 65536-token
context. It generates a temporary Modelfile and deletes it after model creation.
Leave the terminal open; Ctrl+C stops this server.

`-ContextK <N>` sets the context size in K, where 1K = 1024 tokens. It takes
any integer from 4 to 256 and defaults to 64 when omitted. The script then
creates `qwen3.8:27b-<N>k` with an `N * 1024`-token context; use that model ID
in your client. For example, for 128k context run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-ollama.ps1 -ContextK 128
```

This creates `qwen3.8:27b-128k` with a 131072-token context. For the model's
full 256k context window, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-ollama.ps1 -ContextK 256
```

This creates `qwen3.8:27b-256k` with a 262144-token context.

`-NumGpu <N>` sets how many of the model's 66 layers go to the GPU. It takes
-1 to 999 and defaults to -1, which writes no `num_gpu` parameter and leaves
placement to Ollama. Any other value adds `PARAMETER num_gpu <N>` to the
Modelfile; `-NumGpu 99` puts all layers on the GPU:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-ollama.ps1 -ContextK 128 -NumGpu 99
```

Forcing all layers can ask for more VRAM than is free. On Windows the NVIDIA
driver may then spill the excess into shared system memory ("Shared GPU memory"
in Task Manager), and a load that does not fit at all fails; the script then
stops with an error suggesting `-NumGpu -1` or a smaller `-ContextK`.

The default stays -1 because of a measured spill. On the RTX 3090 Ti with
Ollama 0.40.2, `-ContextK 128 -NumGpu 99` loaded all 66 layers, but Task
Manager "Shared GPU memory" rose from 0.1 GB to 2.4 GB during the load. The
server log showed about 1.9 GiB of device demand over the free VRAM. The spill
costs less than leaving layers on the CPU: forcing all layers generated 47-52
tokens/s, while a request forcing `num_gpu 55` in the same session generated
about 15 tokens/s (about 24 with Ollama's own automatic placement, see below;
the conditions differed). So at `-ContextK 128` on a 24 GB card, use `-NumGpu 99` if
the spill into system memory is acceptable. Other ways to free VRAM, not
handled by the script, are a text-only model without the vision encoder
(about 1.1 GiB) and turning off the MTP draft (about 0.7 GiB, at the cost of
generation speed).

A per-request `options.num_gpu = -1` does not override `num_gpu 99` from the
Modelfile (the model is not reloaded); a concrete layer count in the request
does reload it.

### GPU memory at 128k

At `-ContextK 128` with automatic placement, Ollama keeps only 55 of 66 layers
on an RTX 3090 Ti (23027 MiB total) and generation drops from about 65 to
24 tokens/s. The server log of that load breaks the demand down as follows:

| Item | MiB | Log line |
| --- | --- | --- |
| Model weights | 15339 | `memory breakdown`, column model |
| KV cache, 16 attention layers, q8_0, 131072 cells | 4352 | `llama_kv_cache: size = 4352.00 MiB (131072 cells, 16 layers …)` |
| Recurrent state of the linear-attention layers | 748 | `llama_memory_recurrent: size = 748.13 MiB` |
| Compute buffer | 720 (1048 after load) | `sched_reserve: CUDA0 compute buffer size` |
| MTP draft context: KV 512 (1 layer, f16) + compute 196 | 708 | second `llama_kv_cache` and `sched_reserve` blocks |
| Vision encoder (mmproj), worst case | 1161 | `estimated worst-case memory usage of mmproj is 1161.02 MiB` |
| Free on the GPU before load | 21037 | `gpu memory … free="21.3 GiB"`, fit line |

So the 128k load needs about 21.9 GiB plus Ollama's 1.9 GiB free-memory target
against 21 GiB free. The KV cache is the largest item after the weights, so a
smaller `-ContextK` is the main way to fit everything on the GPU.

### Long prompts

The 128k context works end to end: a 117914-token prompt to
`qwen3.8:27b-128k` (`-ContextK 128`) returned `prompt_eval_count` 117914 and a
correct answer. A prompt must fit in the context with room for the answer.
When it does not, Ollama cuts it to about half the context, keeping the first
4 tokens and the end of the prompt. For a 134914-token prompt (8000 lines)
the server log showed
`msg="truncating input prompt" limit=65538 prompt=134914 keep=4 new=65538`
and `prompt_eval_count` was 65538. That is a limit of Ollama's runner, not of
the script. Check the full context with 7000 lines (each line with a 4-digit
number costs 17 tokens):

```powershell
$api = 'http://127.0.0.1:11435'
$text = (0..6999 | ForEach-Object { "Line ${_}: the quick brown fox jumps over the lazy dog. " }) -join ''
$body = @{ model = 'qwen3.8:27b-128k'; prompt = "$text`nHow many lines were there? Answer with one number."; stream = $false; think = $false; options = @{ num_predict = 8 } } | ConvertTo-Json -Depth 3
$r = Invoke-RestMethod -Uri "$api/api/generate" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 900
"prompt_eval_count = $($r.prompt_eval_count)"
```

Expect `prompt_eval_count = 117914` and the answer 7000.

### Placement report

After `ollama create` the script loads the model once (`/api/generate`, up to
600 seconds) and prints where it landed, from `/api/ps`:

```text
GPU placement: 78% of the model in VRAM (14.1 GiB of 18.0 GiB).
```

When the share is below 100%, it adds a warning that the rest runs on the CPU
and names `-NumGpu 99` and a smaller `-ContextK` as the fixes. `/api/ps`
reports less than the real footprint (18 GiB at 128k against about 21.9 GiB in
the server log), so read the percentage as the GPU share, not as a sizing figure.

It uses one parallel request (`OLLAMA_NUM_PARALLEL=1`), one loaded model
(`OLLAMA_MAX_LOADED_MODELS=1`), Flash Attention, and a q8_0 KV cache to reduce
memory demand. With the default `-NumGpu -1`, GPU placement depends on
available VRAM.

Behaviour to be aware of:

- It refuses to start when something already listens on port 11435; stop that
  server first.
- It waits up to 120 seconds for the server to answer `/api/version` and fails
  if it does not (or if the server process exits first).
- It re-runs `ollama create` for the context-specific model on every launch;
  the base model `qwen3.8:27b` is pulled only when it is missing.
- `OLLAMA_CONTEXT_LENGTH` is set server-wide to the same context (`N * 1024`
  tokens), so other models served by this instance default to it too.
- The server binds `0.0.0.0:11435`, while the script's own CLI calls go to
  `127.0.0.1:11435`.

If Windows Firewall blocks LAN access, run this once in an administrator
PowerShell window (for a Private network profile):

```powershell
New-NetFirewallRule -DisplayName 'Ollama TCP 11435 LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 11435 -Profile Private -RemoteAddress LocalSubnet
```

In a second PowerShell terminal, verify inference and placement:

```powershell
$env:OLLAMA_HOST = 'http://127.0.0.1:11435'
ollama run qwen3.8:27b-64k
ollama ps
nvidia-smi
```

For OpenAI-compatible clients such as OpenCode, use
`http://<windows-ip>:11435/v1` and model ID `qwen3.8:27b-64k`.

### Server log stream

The script always redirects `ollama serve` output to two files and echoes
their lines to the console: stdout goes to `%TEMP%\ollama-serve.out.log` and
stderr to `%TEMP%\ollama-serve.err.log`. Both are overwritten at each start
and left in place after the server stops, so they keep the last run's log.

`-LogPort <N>` also streams those lines over TCP to any client on the LAN. It
takes 0 to 65535 and defaults to 0, which is off and opens no port; 11435 is
rejected because Ollama uses it. For example:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-ollama.ps1 -LogPort 11436
```

Before Ollama starts, the script stops with an error if the log port is already
in use or cannot be bound. Hyper-V and WSL reserve port ranges on Windows; list
them with `netsh int ipv4 show excludedportrange protocol=tcp` and pick another
`-LogPort` outside them.

Allow the log port through Windows Firewall the same way as port 11435 (once,
in an administrator PowerShell window, Private profile, local subnet only):

```powershell
New-NetFirewallRule -DisplayName 'Ollama log TCP 11436 LAN' -Direction Inbound -Action Allow -Protocol TCP -LocalPort 11436 -Profile Private -RemoteAddress LocalSubnet
```

Each connection gets a minimal HTTP/1.0 `200 text/plain` header straight away,
then live lines only (no replay of earlier lines), one UTF-8 line per `\n`,
until the client disconnects or the script stops. Subscribe before triggering
the request you want to watch. From another machine:

```sh
# Follow the log until Ctrl+C or the server stops.
curl -sN http://<windows-ip>:11436/

# Capture a fixed two-minute window.
curl -sN --max-time 120 http://<windows-ip>:11436/

# Raw TCP; the HTTP header comes first.
nc <windows-ip> 11436

# Capture to a file in the background, e.g. for an agent to read later.
curl -sN http://<windows-ip>:11436/ > ollama.log 2>&1 &
```

The stream carries everything `ollama serve` writes to stdout and stderr, plus
the script's own status lines (the placement report, the serving banner,
`log subscriber connected: <address>` and `log subscriber disconnected:
<address>`). Warnings arrive as `WARNING: <text>`, and when the script stops on
an error it sends `ERROR: <message>` before closing the stream. Server lines
include model names, request lines (method, path, status, client address,
duration) and Windows paths that contain the username; at Ollama's default log
level they carry no prompt text.

Security: like Ollama's own port 11435, the stream has no authentication and
no TLS; anyone who can reach the port can read the log. Keep it off unless you
need it and limit the firewall rule to the Private profile and the local
subnet.

The script pumps the files about every 200 ms while it waits for the server and
while it serves. During `ollama pull`, `ollama create` and the initial model
load it does not pump; their server lines queue in the files and are sent right
after. A subscriber whose send takes longer than 500 ms is dropped so that it
cannot stall the console or other subscribers.

References:
- https://docs.ollama.com/windows
- https://docs.ollama.com/modelfile
- https://docs.ollama.com/faq

## Development

- Quality checks (lint and test commands) are defined in
  [CLAUDE.md](CLAUDE.md#project-specific) under `## Project-Specific`; run them
  from there rather than from a copy.
- Changes go through the Ralph workflow: `/ralph-prd`, then `/ralph-backlog`,
  then `/ralph-run` (or `./ralph.sh --tool claude`).
- The devcontainer adds shellcheck, PowerShell and PSScriptAnalyzer. It needs
  `CLAUDE_CODE_OAUTH_TOKEN` exported on the host from `~/.zshenv`; mint the
  token with `claude setup-token`.
