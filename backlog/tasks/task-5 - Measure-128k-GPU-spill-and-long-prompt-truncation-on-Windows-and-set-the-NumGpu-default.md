---
id: TASK-5
title: >-
  Measure 128k GPU spill and long-prompt truncation on Windows and set the
  NumGpu default
status: To Do
assignee: []
created_date: '2026-10-11 14:09'
labels: []
dependencies:
  - TASK-4
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

Split from TASK-4, which adds `-NumGpu` (default -1) and the placement report. Two questions can only be answered on the Windows machine (RTX 3090 Ti, 23027 MiB, Ollama 0.40.2), and their answers decide the `-NumGpu` default and whether the 128k context works end to end.

### Shared GPU memory spill

Forcing all layers asks for more than the free VRAM, so on Windows the NVIDIA driver may place the excess in shared system memory ("Shared GPU memory" in Task Manager). Whether that happened in the forced run is not known; it has to be checked before `num_gpu` 99 becomes the default. Ways to free VRAM instead of overcommitting: a text-only model without the vision encoder (about 1.1 GiB; check whether a model created `FROM` the base GGUF blob loads without `--mmproj`), turning off the MTP draft (about 0.7 GiB, but it speeds up generation), or a smaller `-ContextK`.

Decision rule: start the script with `-ContextK 128 -NumGpu 99`; if Task Manager "Shared GPU memory" rises by more than 0.5 GiB during the load, the excess spilled into system memory and the default stays -1; otherwise the default becomes 99.

### Long-prompt truncation

Prompt test: 8000 lines of `Line <i>: the quick brown fox jumps over the lazy dog. ` (about 15.9 tokens per line, so about 127k tokens) sent to `qwen3.8:27b-128k` with `num_gpu` 99 returned `prompt_eval_count` 65538, also with `"num_ctx": 131072` in the request; `/api/ps` reported `context_length` 131072. That run is not in the log above (the log shows an OpenCode prompt of 34440 tokens processed normally). Which `-ContextK` the server was started with at that time is unknown; the script sets `OLLAMA_CONTEXT_LENGTH` server-wide, which is 65536 at the default `-ContextK 64`.

Long-prompt check, run in a second PowerShell window on the Windows machine while the server runs:

```powershell
$api = 'http://127.0.0.1:11435'
$text = (0..7999 | ForEach-Object { "Line ${_}: the quick brown fox jumps over the lazy dog. " }) -join ''
$body = @{ model = 'qwen3.8:27b-128k'; prompt = "$text`nHow many lines were there? Answer with one number."; stream = $false; think = $false; options = @{ num_predict = 8 } } | ConvertTo-Json -Depth 3
$r = Invoke-RestMethod -Uri "$api/api/generate" -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 900
"prompt_eval_count = $($r.prompt_eval_count)"
(Invoke-RestMethod -Uri "$api/api/ps").models | Select-Object name, context_length, size, size_vram
```

Expected when the full context works: `prompt_eval_count` around 127000, not 65538.

## Order of work

1. The owner runs both checks on Windows with the TASK-4 script, records the results in this task's implementation notes (`backlog task edit <id> --append-notes ...`), and checks AC #1 and #2.
2. Then the code ACs are implemented (Ralph or interactively) from the recorded results.

## Scope

In scope:
- the two Windows checks and their recorded results;
- the `-NumGpu` default (-1 or 99) per the decision rule, and README.md stating the default with the measured reason;
- if the long prompt is still cut below 120000 tokens: the cause recorded, and either fixed in windows/start-ollama.ps1 or stated as a limit in README.md.

Out of scope:
- freeing VRAM by other means (text-only model without the vision encoder, turning off the MTP draft) beyond recording the option in README.md;
- other models, other platforms, Linux scripts; changing the default `-ContextK`; the KV cache type and Flash Attention settings; client configuration.

## Files

- `windows/start-ollama.ps1` (exists) — the `-NumGpu` default, and the truncation fix if one is needed.
- `README.md` (exists) — Windows section: the default and its reason, the long-context result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On Windows (owner run): with -ContextK 128 -NumGpu 99, Task Manager Shared GPU memory before and after the load, the placement line the script prints, and generation tokens/s are recorded in the implementation notes
- [ ] #2 On Windows (owner run): the long-prompt check is run against a server started with -ContextK 128, and its prompt_eval_count plus any server log line containing truncat are recorded in the implementation notes
- [ ] #3 The NumGpu default in windows/start-ollama.ps1 is 99 if the recorded Shared GPU memory rose by at most 0.5 GiB, otherwise it stays -1
- [ ] #4 README.md states the NumGpu default and the measured reason for it
- [ ] #5 If the recorded prompt_eval_count is below 120000, the cause is recorded in the implementation notes and either fixed in windows/start-ollama.ps1 or stated as a limit in README.md
- [ ] #6 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->
