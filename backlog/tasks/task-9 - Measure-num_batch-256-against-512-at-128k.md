---
id: TASK-9
title: Measure num_batch 256 against 512 at 128k
status: To Do
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-11 20:01'
labels: []
dependencies: []
priority: medium
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

The compute buffer is 720-1048 MiB at the default batch of 512. Per Codex, num_batch sets both -b and -ub for llama-server in Ollama v0.40.2 (llm/llama_server.go:544-555), so a smaller batch may shrink the buffer at some cost in prompt processing speed; the saving is not necessarily linear. This is a cheap experiment before touching cache precision.

## Scope

In scope:
- measure num_batch 512 and 256 at -ContextK 128 with num_gpu 99, using per-request options.num_batch (it reloads the model) and the protocol in Context
- add a -NumBatch parameter (Modelfile PARAMETER num_batch) only if the measured memory saving is worth the speed cost; record the decision either way

Out of scope:
- other sizes beyond 512 and 256 unless the first result calls for them
- KV cache type, MTP, text-only (sibling tasks)

## Files

- `windows/start-ollama.ps1` (exists) — only if the parameter is added
- `README.md` (exists) — result and, if added, the option

## Context (shared by this task and its sibling optimisation handoffs)

Setup: the Windows server started by `windows/start-ollama.ps1` (Ollama 0.40.2, RTX 3090 Ti with 23027 MiB, about 21037 MiB free before a load), reachable on the LAN at `http://<windows-ip>:11435`; started with `-LogPort 11436` it streams its log over TCP (README "Server log stream"). Current model `qwen3.8:27b-128k`: `num_ctx` 131072, `num_gpu` 99, `draft_num_predict` 4, vision projector attached (`/api/show` lists two `FROM` blobs and the `vision` capability); server-wide KV cache q8_0, Flash Attention on, `num_batch` 512.

Baseline to compare against is the forced `num_gpu 99` load at 128k, not the automatic 55/66 split: all 66 layers in VRAM per `/api/ps`, Task Manager "Shared GPU memory" up 2.3 GB over idle (TASK-5), generation 47-52 tokens/s (TASK-5) and 76.5 tokens/s on a short prompt (2026-10-11 evening), a 117,937-token prompt processed in full at 807-1010 tokens/s.

Memory demand at 128k (README "GPU memory at 128k"): weights 15339 MiB, KV cache 4352, recurrent state 748, compute buffer 720-1048, MTP draft 708, vision encoder about 1136 - about 23003 MiB (22.5 GiB) against 21037 MiB (20.5 GiB) free, a deficit of about 1.9 GiB.

Measurement protocol: change one setting at a time; record the Ollama version, the model, the llama-server command line from the log and whether the prompt cache was warm; run each case three times. Memory = the rise of Task Manager "Shared GPU memory" over its idle value during a long prompt and during generation (the owner reads it on Windows), plus the memory breakdown in the server log; `/api/ps` "100% in VRAM" alone proves nothing. Speed = prompt and generation tokens/s from `/api/generate` (`prompt_eval_*`, `eval_*`). Long-prompt probe: 7000 lines of `Line <i>: the quick brown fox jumps over the lazy dog. ` (117,914 tokens; 8000 lines overflow 128k). Claims marked "per Codex" come from a peer agent's reading of the Ollama v0.40.2 sources and docs; verify them before relying on them.

Do not put private details into the repo: no internal host names, Confluence URLs, tokens or personal paths in README.md or code.

## Source

Source: inbound handoff from another local project (path and commit removed).
Source design doc (read-only context, do NOT modify): none — this description carries the full context.

## Before starting (destination Claude validation checklist)

Before running this task, verify:
1. All `(exists)` file paths in the Files section still exist in this repo.
2. Each AC is objectively pass/fail (a grep, test invocation, build command, or visible behavior — not "works correctly").
3. All dependencies in the task's frontmatter are status=Done.
4. Out-of-scope items are not accidentally pulled in by ambiguous AC.

If anything is unclear or any check fails: STOP and ask the user. Do NOT start work blindly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The llama-server command line for num_batch 256 shows -b 256 and -ub 256 (recorded from the log)
- [ ] #2 For 512 and 256, the compute buffer size from the log, the shared GPU memory rise, prompt tokens/s on the 7000-line probe and generation tokens/s on a short prompt (three runs each) are recorded
- [ ] #3 The decision is recorded: -NumBatch added with a validated range and default 512, or not added with the measured reason
- [ ] #4 If -NumBatch is added, a devcontainer test covers its Modelfile line and README.md documents it
- [ ] #5 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->
