---
id: TASK-5
title: >-
  Measure 128k GPU spill and long-prompt truncation on Windows and set the
  NumGpu default
status: To Do
assignee: []
created_date: '2026-10-11 14:09'
updated_date: '2026-10-11 18:12'
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
- [x] #1 On Windows (owner run): with -ContextK 128 -NumGpu 99, Task Manager Shared GPU memory before and after the load, the placement line the script prints, and generation tokens/s are recorded in the implementation notes
- [x] #2 On Windows (owner run): the long-prompt check is run against a server started with -ContextK 128, and its prompt_eval_count plus any server log line containing truncat are recorded in the implementation notes
- [ ] #3 The NumGpu default in windows/start-ollama.ps1 is 99 if the recorded Shared GPU memory rose by at most 0.5 GiB, otherwise it stays -1
- [ ] #4 README.md states the NumGpu default and the measured reason for it
- [ ] #5 If the recorded prompt_eval_count is below 120000, the cause is recorded in the implementation notes and either fixed in windows/start-ollama.ps1 or stated as a limit in README.md
- [ ] #6 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Owner run 1 (2026-10-11 17:32 MSK; Ollama 0.40.2; RTX 3090 Ti, 23027 MiB; server config OLLAMA_CONTEXT_LENGTH=131072): windows/start-ollama.ps1 from master 2ff4e61 with -ContextK 128 -NumGpu 99.
- llama-server started with -c 131072 and -ngl 99. Fit step: "projected to use 21867 MiB of device memory vs. 21037 MiB of free device memory", "need to reduce device memory by 2767 MiB", then "failed to fit params to free device memory: n_gpu_layers already set by user to 99, abort", so the load went ahead without fitting.
- load_tensors: offloaded 66/66 layers to GPU (automatic placement: 55/66). On CUDA0: model weights 15339.44 MiB, KV cache 4352 MiB (automatic placement split it 3808 GPU + 544 CPU), recurrent state 748.13 MiB, compute buffer 720.28 MiB, MTP draft KV 512 + compute 196.02 MiB, vision encoder weights 887.99 + compute 248.10 MiB.
- Device demand is about 23003 MiB (21867 projected + 1136 vision encoder) against 21037 MiB free before the load, about 1.9 GiB over. The load did not fail, so the excess went somewhere, most likely shared GPU memory; the Task Manager reading has to confirm it.
- Warm load POST /api/generate took 5.66 s. The script printed "GPU placement: 100% of the model in VRAM (16.6 GiB of 16.6 GiB)." and no warning. /api/ps reports 16.6 GiB against about 22.5 GiB of real device demand, so 100% there does not rule out a spill.
- Still missing for AC #1: Task Manager "Shared GPU memory" before and after the load, and generation tokens/s. AC #2 (long-prompt check) not run yet.

Owner run 1, Task Manager: Shared GPU memory before the load = 0.1 GB. After-load value pending.

Owner run 1, Task Manager: Shared GPU memory after the load = 2.4 GB, up 2.3 GB from 0.1 GB. That is above the 0.5 GiB threshold and close to the about 1.9 GiB the server log shows over free VRAM, so -NumGpu 99 at 128k spills into shared system memory. Decision per AC #3: the NumGpu default stays -1. Generation tokens/s for the forced load still pending (needed for AC #1 and for the README guidance on when -NumGpu 99 is worth it).

Measurements over the LAN against the owner-run server (same session as owner run 1: -ContextK 128 -NumGpu 99, server OLLAMA_CONTEXT_LENGTH=131072; /api/show confirms num_gpu 99 and num_ctx 131072 in the model). Same prompt for every rate run: "Write a 150-word paragraph about how GPUs run neural networks.", think false, num_predict 256.
- Generation, all 66 layers forced (2.3 GB spilled into shared GPU memory): 47.2 / 52.3 / 47.1 tok/s (178-220 tokens each); /api/ps 16.64 GiB, 100% in VRAM.
- Generation, num_gpu 55 per request (the split the fit step picks on its own at 128k): 14.9 / 14.6 / 14.3 tok/s; /api/ps 17.99 GiB, 13.78 GiB in VRAM, 77%; reload 7.2 s. Forcing all layers is about 3.3x faster despite the spill.
- Gotcha: options.num_gpu = -1 in a request does not override num_gpu 99 from the Modelfile (no reload, still 100%); those runs were discarded. A concrete layer count in the request does reload.
- After the measurements the model was reloaded with its default num_gpu 99 (100% in VRAM), leaving the server as found.

Long-prompt check (AC #2), same server and model:
- The 8000-line prompt from the description reproduces the cut: prompt_eval_count = 65538, prompt_eval_duration 64.5 s, response "7994".
- Measured token cost: 1000 lines = 15914 tokens, 2000 lines = 32914, so lines with 4-digit numbers cost 17 tokens each. The 8000-line prompt is therefore about 15914 + 7000 * 17 = 134914 tokens, more than the 131072-token context; the description's estimate of 127k (15.9 tokens per line) was wrong.
- 7000 lines (prediction 15914 + 6000 * 17 = 117914): prompt_eval_count = 117914, processed in full in 116.5 s (about 1010 tok/s), response "7000" (correct). The 128k context works end to end.
- Cause of 65538: when a prompt does not fit, the prompt is cut to the context, and llama-server (started with --context-shift --keep 4) then keeps n_keep plus one half-context block: 4 + (131072 - 4 - 65534) = 65538. It is a limit on prompt size, not a broken 128k context, and the script cannot change it (Ollama passes those flags). The server log lines containing "truncat" for that request were not visible remotely; the owner can confirm them in the server console.
- For README.md (AC #5): state that a prompt must fit in the context with room for the answer, otherwise about half of it is dropped; use 7000 lines, not 8000, as the long-prompt check.

For README.md (AC #4): the NumGpu default stays -1 per the decision rule (spill 2.3 GB), with -NumGpu 99 recommended for -ContextK 128 on a 24 GB card when the spill is acceptable: 47-52 tok/s against about 15 tok/s at the automatic 55-layer split.

Long-prompt check with the server log captured over the LAN through the TASK-6 log stream (server started with -ContextK 128 -NumGpu 99 -LogPort 11436):
- 8000 lines: prompt_eval_count = 65538, response "7999". Server log line containing "truncat": level=WARN source=llama_server.go:320 msg="truncating input prompt" limit=65538 prompt=134914 keep=4 new=65538. llama-server then reported "stop processing: n_tokens = 65543, truncated = 0".
- 7000 lines: prompt_eval_count = 117914, response "7000", no "truncating input prompt" line, llama-server "stop processing: n_tokens = 117919, truncated = 0". Prompt eval took 146.4 s this time (116.5 s in the earlier run; not investigated).
- Correction to the earlier cause note: the cut is made by Ollama's own runner wrapper (llama_server.go "truncating input prompt"), not by llama-server's context shift. The 8000-line prompt is 134914 tokens (exactly the 15914 + 7000 * 17 prediction), above the 131072-token context, and Ollama cuts an overflowing prompt to limit 65538, keeping the first 4 tokens and the tail. A prompt that fits is processed in full.
- For README.md (AC #5): state the limit (a prompt must fit in the -ContextK context with room for the answer; an overflowing prompt is cut to about half the context, keeping its end, and the server log shows "truncating input prompt"), and use 7000 lines as the long-prompt check.
<!-- SECTION:NOTES:END -->
