---
id: TASK-11
title: Add an MTP draft option and measure it at 128k
status: To Do
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-11 20:01'
labels: []
dependencies: []
priority: medium
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

The MTP speculative draft costs about 708 MiB at 128k (512 MiB KV + 196 MiB compute). Turning it off may be slower or may even be faster if it removes the spill, because its gain depends on how many draft tokens are accepted. Per Codex, draft_num_predict is a model option in Ollama v0.40.2 (api/types.go:549-556, default 4 at :1110) and at 0 appendDraftArgs in llm/llama_server.go:748-763 adds no --spec-type.

## Scope

In scope:
- add -DraftTokens with ValidateRange(0, 16) and default 4, written as PARAMETER draft_num_predict to the Modelfile; 0 turns the draft off
- measure 4 and 0 at -ContextK 128 with num_gpu 99 using the protocol in Context

Out of scope:
- other speculative decoding settings
- text-only, KV cache type, batch size (sibling tasks)

## Files

- `windows/start-ollama.ps1` (exists) — parameter and Modelfile line
- `README.md` (exists) — option and measured trade-off

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
- [ ] #1 windows/start-ollama.ps1 declares -DraftTokens with ValidateRange(0, 16), default 4, and writes PARAMETER draft_num_predict (test)
- [ ] #2 With 0, the llama-server command line in the log has no --spec-type and the log has no second llama_context block for the draft (recorded)
- [ ] #3 Shared GPU memory rise, generation tokens/s on a short prompt (three runs) and prompt tokens/s on the 7000-line probe are recorded for 4 and 0
- [ ] #4 README.md documents -DraftTokens with the measured trade-off
- [ ] #5 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->
