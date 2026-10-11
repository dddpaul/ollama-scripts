# Qwen 3.8 on Windows

Install a current Ollama for Windows and quit its tray app. Copy
`start-ollama.ps1` to the Windows machine, then run:

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

It uses one parallel request, one loaded model, Flash Attention, and a q8_0
KV cache to reduce memory demand. Actual GPU placement depends on available
VRAM; the script does not force all layers onto the GPU.

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
