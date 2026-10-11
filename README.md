# ollama-scripts

Helper scripts for running Ollama models, organised by platform directory.
Today the only platform directory is `windows/`.

## Scripts

| Script | Platform | Purpose |
| --- | --- | --- |
| [`windows/start-ollama.ps1`](windows/start-ollama.ps1) | Windows | Starts a LAN-reachable Ollama server on port 11435 and serves `qwen3.8:27b` with a 64k or 128k context. |

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

For 128k context, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\start-ollama.ps1 -ContextK 128
```

This creates `qwen3.8:27b-128k` with a 131072-token context. Use that model ID
in your client. The default remains 64k when `-ContextK` is omitted.

It uses one parallel request (`OLLAMA_NUM_PARALLEL=1`), one loaded model
(`OLLAMA_MAX_LOADED_MODELS=1`), Flash Attention, and a q8_0 KV cache to reduce
memory demand. Actual GPU placement depends on available VRAM; the script does
not force all layers onto the GPU.

Behaviour to be aware of:

- It refuses to start when something already listens on port 11435; stop that
  server first.
- It waits up to 120 seconds for the server to answer `/api/version` and fails
  if it does not (or if the server process exits first).
- It re-runs `ollama create` for the context-specific model on every launch;
  the base model `qwen3.8:27b` is pulled only when it is missing.
- `OLLAMA_CONTEXT_LENGTH` is set server-wide to the same context (65536 or
  131072 tokens), so other models served by this instance default to it too.
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
