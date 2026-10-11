---
id: TASK-4
title: Add -NumGpu and a GPU placement report to start-ollama.ps1
status: In Progress
assignee: []
created_date: '2026-10-11 13:56'
updated_date: '2026-10-11 14:19'
labels: []
dependencies: []
priority: medium
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

At `-ContextK 128` Ollama 0.40.2 keeps only 55 of 66 layers on the GPU and generation drops from about 65 to 24 tokens/s. The launcher should say where the model actually landed and offer a way to keep it on the GPU. This task adds that switch and the placement report with the default left to Ollama; the Windows measurements that decide the default and the long-prompt truncation check are the follow-up task that depends on this one.

Server log of a `-ContextK 128` load on the Windows machine (RTX 3090 Ti, 23027 MiB total; Ollama starts `llama-server.exe` with `-c 131072 --cache-type-k q8_0 --cache-type-v q8_0 --flash-attn on --spec-type draft-mtp --mmproj …`):

| Item | MiB | Log line |
| --- | --- | --- |
| Model weights | 15339 | `memory breakdown`, column model |
| KV cache, 16 attention layers, q8_0, 131072 cells | 4352 | `llama_kv_cache: size = 4352.00 MiB (131072 cells, 16 layers …)` |
| Recurrent state of the linear-attention layers | 748 | `llama_memory_recurrent: size = 748.13 MiB` |
| Compute buffer | 720 (1048 after load) | `sched_reserve: CUDA0 compute buffer size` |
| MTP draft context: KV 512 (1 layer, f16) + compute 196 | 708 | second `llama_kv_cache` and `sched_reserve` blocks |
| Vision encoder (mmproj), worst case | 1161 | `estimated worst-case memory usage of mmproj is 1161.02 MiB` |
| Free on the GPU before load | 21037 | `gpu memory … free="21.3 GiB"`, fit line |

The fit step reports: "projected to use 21867 MiB of device memory vs. 21037 MiB of free device memory", "cannot meet free memory target of 1936 MiB, need to reduce device memory by 2767 MiB", then "55 layers, 18969 MiB used, 2067 MiB free". So the 128k load needs about 21.9 GiB plus a 1.9 GiB safety target against 21 GiB free; the KV cache (4.25 GiB) is the largest item after the weights, then the vision encoder, compute buffers, recurrent state and the MTP draft.

Measured on 2026-10-11 through the HTTP API (`/api/generate` to load, `/api/ps` for `size` and `size_vram`). Note: `/api/ps` reports less than the real footprint (it showed 18.01 GiB at 128k while the log adds up to about 21.9 GiB), so use it only for the GPU share, not for sizing:

| Context | Automatic placement: GPU share in `/api/ps`, generation speed | `num_gpu` 99 in the request |
| --- | --- | --- |
| 64k | 100% | — |
| 96k | 86% | — |
| 112k | 82% | — |
| 128k | 78%, 23.7 tokens/s | 100%, 65.2 tokens/s; a 65k-token prompt processed at 780–930 tokens/s |

Forcing all layers asks for more than the free VRAM, so on Windows the NVIDIA driver may place the excess in shared system memory ("Shared GPU memory" in Task Manager). Whether that happened in the forced run is not known; it has to be checked before `num_gpu` 99 becomes the default. Ways to free VRAM instead of overcommitting: a text-only model without the vision encoder (about 1.1 GiB; check whether a model created `FROM` the base GGUF blob loads without `--mmproj`), turning off the MTP draft (about 0.7 GiB, but it speeds up generation), or a smaller `-ContextK`.

That check is the follow-up task; until it is done the default stays -1 and `-NumGpu 99` is opt-in.

## Scope

In scope:
- `-NumGpu` parameter: `[ValidateRange(-1, 999)] [int]$NumGpu = -1`; -1 writes no `num_gpu` line and leaves placement to Ollama; any other value adds `PARAMETER num_gpu <NumGpu>` to the generated Modelfile (99 means all 66 layers).
- Two pure helper functions (no I/O, no Ollama calls) defined in the script right after the param block, so the logic is testable without Ollama:
  - `Get-ModelfileText -BaseModel <string> -ContextTokens <int> -NumGpu <int>` returns the Modelfile text: the FROM line, the `PARAMETER num_ctx` line, and the `PARAMETER num_gpu` line unless NumGpu is -1;
  - `Get-PlacementReport -Size <long> -SizeVram <long>` returns the report lines: the share of the model in VRAM as a whole percentage of size, plus size and size_vram in GiB with one decimal; when the share is below 100% it adds a warning line naming `-NumGpu` and `-ContextK` as the knobs.
- Script body: build the Modelfile with `Get-ModelfileText`; after `ollama create`, load the model once (`POST /api/generate` with the model name, an empty prompt, `stream` false, and `-TimeoutSec 600`), read `GET /api/ps`, take the entry whose name is the created model, and print the `Get-PlacementReport` lines (`Write-Host` for the normal lines, `Write-Warning` for the warning line).
- When the load request fails (exception or timeout, for example out of memory at 256k with `-NumGpu 99`), throw an error whose message suggests `-NumGpu -1` or a smaller `-ContextK`; the script must not hang.
- Tests: a pytest module that runs pwsh, loads only the function definitions from the script (the script body must not run), and checks both functions; it is skipped when pwsh is not on PATH (the macOS host), so it runs in the devcontainer. Path:

```text
tests/test_start_ollama.py
```

- README.md Windows section: document `-NumGpu` (default -1 = Ollama decides placement; 99 = all layers on the GPU, which may need more VRAM than is free), add the memory breakdown table from this description, describe the placement line the script prints, and replace the sentences "Larger contexts need more VRAM for the KV cache, so Ollama may then place some layers on the CPU" and "the script does not force all layers onto the GPU". Both sentences are wrapped across lines in README.md, so check their removal with whitespace collapsed.

Out of scope:
- the Windows measurements (shared GPU memory spill at 128k, long-prompt truncation) and changing the `-NumGpu` default: the follow-up task;
- other models, other platforms, Linux scripts;
- changing the default `-ContextK` (stays 64);
- the KV cache type and Flash Attention settings (already `q8_0` and on);
- client configuration (OpenCode and others).

Loading only the functions from the script in pwsh (verified in the devcontainer image: the functions load and a `throw` in the script body does not run):

```powershell
$ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path 'windows/start-ollama.ps1'), [ref]$null, [ref]$null)
foreach ($f in $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false)) {
    . ([scriptblock]::Create($f.Extent.Text))
}
Get-ModelfileText -BaseModel 'qwen3.8:27b' -ContextTokens 131072 -NumGpu 99
```

Checking the README sentence removal with whitespace collapsed (must print 0):

```bash
tr -s '[:space:]' ' ' < README.md | grep -c 'does not force all layers onto the GPU'
```

## Files

- `windows/start-ollama.ps1` (exists) — new `-NumGpu` parameter, the two helper functions, warm load and placement report after `ollama create`.
- `README.md` (exists) — Windows section: `-NumGpu`, memory breakdown table, placement line.
- the new pytest module named in Scope.

## Source

Source: inbound handoff from another local project (path and commit removed).
Source design doc (read-only context, do NOT modify): none — the measurements above come from the source session and are the full context.

## Before starting (destination Claude validation checklist)

Before running this task, verify:
1. All `(exists)` file paths in the Files section still exist in this repo.
2. Each AC is objectively pass/fail (a grep, test invocation, build command, or visible behavior — not "works correctly").
3. All dependencies in the task's frontmatter are status=Done.
4. Out-of-scope items are not accidentally pulled in by ambiguous AC.

If anything is unclear or any check fails: STOP and ask the user. Do NOT start work blindly.

Note: Ollama and the GPU are not available in the devcontainer. The helper functions carry the testable logic; the end-to-end run on the Windows machine belongs to the follow-up task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In the devcontainer, running the script with -NumGpu 1000 and with -NumGpu -2 each fails with a NumGpu parameter validation error, while -NumGpu -1 and -NumGpu 99 get past validation and fail only on the ollama.exe lookup
- [x] #2 windows/start-ollama.ps1 declares [ValidateRange(-1, 999)] on a new NumGpu parameter with default -1
- [x] #3 A pytest test in the devcontainer shows Get-ModelfileText emits PARAMETER num_gpu 99 for 99 and PARAMETER num_gpu 0 for 0, no num_gpu line for -1, and always the FROM and num_ctx lines
- [x] #4 A pytest test in the devcontainer shows Get-PlacementReport reports 100 percent with no warning when size_vram equals size, and 78 percent plus a warning line naming -NumGpu and -ContextK when size_vram is 78 percent of size, with sizes in GiB
- [x] #5 The script body builds the Modelfile with Get-ModelfileText and, after ollama create, posts /api/generate with -TimeoutSec, reads /api/ps and prints the Get-PlacementReport lines for the created model
- [x] #6 A failed load request throws an error whose message names -NumGpu -1 and a smaller -ContextK
- [x] #7 README.md documents -NumGpu with default -1, includes the memory breakdown table, describes the placement line, and the whitespace-collapsed check for 'does not force all layers onto the GPU' prints 0
- [x] #8 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer, and the Test run executes the new pytest module instead of skipping it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Handoff checklist green: windows/start-ollama.ps1 and README.md exist, no deps, ACs objectively testable, default -NumGpu stays -1 (no external default change).
Plan: add -NumGpu param + Get-ModelfileText/Get-PlacementReport after param block; body uses them, warm-loads via /api/generate (-TimeoutSec 600), reads /api/ps, prints report; load failure throws suggesting -NumGpu -1 / smaller -ContextK. tests/test_start_ollama.py loads function ASTs via pwsh. README Windows section updated.

Commit: `775c5aa` - task-4: Add -NumGpu and a GPU placement report to start-ollama.ps1
<!-- SECTION:NOTES:END -->
