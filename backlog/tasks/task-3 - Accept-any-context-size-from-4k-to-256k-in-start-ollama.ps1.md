---
id: TASK-3
title: Accept any context size from 4k to 256k in start-ollama.ps1
status: Done
assignee: []
created_date: '2026-10-11 08:07'
updated_date: '2026-10-11 08:09'
labels: []
dependencies: []
priority: medium
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
windows/start-ollama.ps1 accepts only -ContextK 64 or 128 (ValidateSet), but qwen3.8:27b has a 256K context window (ollama.com library page: "256K context window"). Users need other sizes: smaller to save VRAM, in-between values, or the full 256k.

Change the parameter to accept any integer number of K from 4 to 256, default unchanged at 64:

```powershell
param(
    [ValidateRange(4, 256)]
    [int]$ContextK = 64
)
```

Everything else already derives from $ContextK and must keep doing so: model name qwen3.8:27b-<N>k, num_ctx = N * 1024, OLLAMA_CONTEXT_LENGTH = the same value. Do not add other parameters.

Update README.md, Windows section and scripts index:
- replace the 64k-or-128k framing with: -ContextK <N> takes any integer from 4 to 256, where 1K = 1024 tokens; default 64; it creates qwen3.8:27b-<N>k with an N * 1024-token context; keep the 128 example command and add a 256 example;
- the scripts-index purpose cell says the context is configurable from 4k to 256k (default 64k);
- the OLLAMA_CONTEXT_LENGTH behaviour bullet gives the value as N * 1024 tokens instead of listing 65536 or 131072;
- add one sentence: larger contexts need more VRAM for the KV cache, Ollama may then place some layers on the CPU, and ollama ps shows the actual split.

How to exercise the parameter without Ollama (pwsh in the devcontainer): parameter binding runs before the script body, so an out-of-range value fails with a validation error, while an in-range value gets past binding and then fails on the ollama.exe lookup, because Ollama is not installed in the container:

```bash
pwsh -NoProfile -File windows/start-ollama.ps1 -ContextK 300   # expect: Cannot validate argument on parameter 'ContextK' ... maximum allowed range of 256
pwsh -NoProfile -File windows/start-ollama.ps1 -ContextK 96    # expect: ollama.exe not recognized (CommandNotFoundException), no validation error
```
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 windows/start-ollama.ps1 declares [ValidateRange(4, 256)] on ContextK, keeps the default 64, and contains no ValidateSet
- [x] #2 In the devcontainer, running the script with -ContextK 3 and with -ContextK 300 each fails with a ContextK parameter validation error
- [x] #3 In the devcontainer, running the script with -ContextK 4, 96 and 256 each gets past parameter validation and fails only on the ollama.exe lookup
- [x] #4 README.md documents -ContextK as any integer from 4 to 256 (1K = 1024 tokens, default 64), the qwen3.8:27b-<N>k model name, and keeps the 128 example plus a new 256 example
- [x] #5 README.md scripts index and OLLAMA_CONTEXT_LENGTH bullet no longer limit the context to 64k or 128k
- [x] #6 README.md states that larger contexts need more VRAM for the KV cache and that ollama ps shows the CPU/GPU split
- [x] #7 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: swap ValidateSet(64,128) for ValidateRange(4,256) in windows/start-ollama.ps1; rewrite README scripts-index cell, Windows section -ContextK paragraph (4..256, 1K=1024, default 64, qwen3.8:27b-<N>k, 128+256 examples), OLLAMA_CONTEXT_LENGTH bullet (N * 1024), add VRAM/KV-cache/ollama ps sentence; verify binding with pwsh -ContextK 3/300/4/96/256.

Commit: `8717ad3` - task-3: Accept any ContextK from 4 to 256 in start-ollama.ps1

Implemented: ValidateRange(4,256) on ContextK (default 64). README documents -ContextK 4..256 (1K=1024), qwen3.8:27b-<N>k, 128 and 256 examples, N*1024 OLLAMA_CONTEXT_LENGTH, VRAM/KV-cache + ollama ps note. Verified in devcontainer pwsh: 3/300 fail ContextK validation; 4/96/256 fail only on ollama.exe lookup. Lint+test exit 0. task-reviewer APPROVED (score 10).
<!-- SECTION:NOTES:END -->
