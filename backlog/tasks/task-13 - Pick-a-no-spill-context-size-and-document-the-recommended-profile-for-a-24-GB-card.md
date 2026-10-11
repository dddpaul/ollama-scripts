---
id: TASK-13
title: >-
  Pick a no-spill context size and document the recommended profile for a 24 GB
  card
status: To Do
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-11 20:01'
labels: []
dependencies:
  - TASK-8
  - TASK-9
  - TASK-10
  - TASK-11
priority: medium
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

After the text-only, KV cache, batch and MTP measurements, the owner needs one documented recommendation: which settings and which -ContextK run with no spill into shared memory and at what speed, for two cases - 128k required, and 128k not required. Expected KV savings at q8_0 relative to 128k (arithmetic from the 4352 MiB at 128k, per Codex): 112k saves 544 MiB, 100k saves 952 MiB, 96k saves 1088 MiB, 64k saves 2176 MiB; other buffers have to be read from the log.

## Scope

In scope:
- measure candidate profiles with the protocol in Context: text-only + q8_0 at 96k, 100k, 112k; text-only + q4_0 + MTP at 128k; use a probe of about 90% of the tested context
- check whether the Windows machine has integrated graphics; if it has, record the free VRAM before a load with the display moved to it
- write a README.md section with both profiles, their exact command lines and measured numbers

Out of scope:
- implementing the options themselves (sibling tasks)
- editing the owner's OpenCode configuration

## Files

- `README.md` (exists) — recommended profile section

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
- [ ] #1 For every tested profile the notes record -ContextK, settings, shared GPU memory rise and prompt and generation tokens/s
- [ ] #2 README.md has a recommended-profile section with a 128k variant and a smaller-context variant, each with an exact command line and measured numbers
- [ ] #3 README.md states that the client context limit must equal ContextK x 1024 tokens and that compaction must trigger before it
- [ ] #4 The notes record whether the machine has integrated graphics and, if so, the free VRAM before a load with the display on it
- [ ] #5 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->
