---
id: TASK-8
title: Add a text-only model option without the vision encoder
status: To Do
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-11 20:01'
labels: []
dependencies: []
priority: high
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

OpenCode and the other clients send no images, yet every load reserves about 1.1 GiB for the vision encoder (887.99 MiB weights + 248.10 MiB compute in the TASK-5 log). Dropping it is the cheapest memory saving with no quality cost for text work. Per Codex, creating a model FROM the main GGUF blob alone may not be enough: Ollama v0.40.2 can attach a projector embedded in the model on its own (llm/llama_server.go:804-832), so the manifest and GGUF structure have to be checked first.

## Scope

In scope:
- find how `qwen3.8:27b` attaches the projector (the two `FROM` blobs in `/api/show`, manifest layers, any projector embedded in the main GGUF) and how to build a variant without it
- add a `-TextOnly` switch to `windows/start-ollama.ps1` that creates a text-only variant of the context-specific model (name per repo conventions) while keeping the chat template, tool calling and thinking
- measure the variant against the baseline with the protocol in Context and document the result in README.md

Out of scope:
- KV cache type, MTP, batch size, keep-alive (sibling tasks)
- changing the default model to text-only

## Files

- `windows/start-ollama.ps1` (exists) — `-TextOnly` switch and model creation
- `README.md` (exists) — option and measured saving
- tests under the repo's existing test layout — Modelfile builder cases

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
- [ ] #1 windows/start-ollama.ps1 has a -TextOnly switch; without it the generated Modelfile is unchanged (test)
- [ ] #2 With -TextOnly the generated Modelfile or create request carries no projector (test in the devcontainer)
- [ ] #3 On the server, /api/show of the text-only model lists no vision capability and keeps tools and thinking (recorded in notes)
- [ ] #4 The server log of a text-only load shows no --mmproj on the llama-server command line and no clip_model_loader lines (recorded)
- [ ] #5 A /api/chat request with one tool definition gets a tool_calls entry from the text-only model (recorded)
- [ ] #6 Shared GPU memory rise, log memory breakdown, and prompt and generation tokens/s on the 7000-line probe are recorded for the text-only model against the baseline
- [ ] #7 README.md documents -TextOnly with the measured saving
- [ ] #8 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->
