---
id: TASK-10
title: Add a KV cache type option and measure q4_0 against q8_0 at 128k
status: To Do
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-11 20:01'
labels: []
dependencies: []
priority: medium
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

The KV cache is the largest item after the weights: 4352 MiB at 128k with q8_0. q4_0 would save about 2 GiB and could remove the spill while keeping 128k, but the Ollama FAQ warns that q4_0 loses noticeably more precision on long contexts. Counting lines in a long prompt shows the window is complete, not that the model still uses it well, so quality needs its own check.

## Scope

In scope:
- add -KvCacheType with ValidateSet('q8_0','q4_0','f16') and default q8_0; it sets OLLAMA_KV_CACHE_TYPE for the server
- measure q8_0 and q4_0 at -ContextK 128 with num_gpu 99 using the protocol in Context
- quality check on one long context (about 110k tokens): build the 7000-line probe with three unique marker lines at about 5%, 50% and 95% of it and ask for each marker verbatim, plus two tool-call requests; compare exact matches for q8_0 and q4_0

Out of scope:
- changing the default to q4_0 without the owner's decision
- text-only, MTP, batch size (sibling tasks)

## Files

- `windows/start-ollama.ps1` (exists) — parameter and OLLAMA_KV_CACHE_TYPE
- `README.md` (exists) — option, saving and quality result

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
- [ ] #1 windows/start-ollama.ps1 declares -KvCacheType with ValidateSet('q8_0','q4_0','f16'), default q8_0, and sets OLLAMA_KV_CACHE_TYPE from it (test)
- [ ] #2 The server log of a q4_0 run shows K (q4_0) and V (q4_0) in the llama_kv_cache line; its KV size is recorded
- [ ] #3 Shared GPU memory rise and prompt and generation tokens/s are recorded for q8_0 and q4_0
- [ ] #4 The marker and tool-call results are recorded for q8_0 and q4_0 as exact matches out of the total
- [ ] #5 README.md documents -KvCacheType with the measured saving and quality result; the default stays q8_0
- [ ] #6 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->
