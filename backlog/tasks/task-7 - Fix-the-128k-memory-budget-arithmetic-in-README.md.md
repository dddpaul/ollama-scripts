---
id: TASK-7
title: Fix the 128k memory budget arithmetic in README.md
status: In Progress
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-11 20:02'
labels: []
dependencies: []
priority: low
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

README.md "GPU memory at 128k" says "the 128k load needs about 21.9 GiB plus Ollama's 1.9 GiB free-memory target against 21 GiB free". 21867 is MiB, not GiB (21.35 GiB), and it leaves out the vision encoder: the demand is 21867 + 1136 = 23003 MiB (about 22.5 GiB) against 21037 MiB (about 20.5 GiB) free, a deficit of about 1.9 GiB. The 1936 MiB free-memory target is a margin the fit step tries to keep, not memory the model allocates. The wrong figure came from the TASK-4 handoff text.

## Scope

In scope:
- correct that paragraph of README.md as stated above

Out of scope:
- any change to windows/start-ollama.ps1
- new measurements

## Files

- `README.md` (exists) — the paragraph after the memory table in "GPU memory at 128k"

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
- [ ] #1 README.md no longer contains "about 21.9 GiB"
- [ ] #2 README.md states the 128k demand as 23003 MiB (about 22.5 GiB) including the vision encoder, against 21037 MiB (about 20.5 GiB) free, a deficit of about 1.9 GiB
- [ ] #3 README.md describes the 1936 MiB free-memory target as a margin the fit step tries to keep, not memory the model allocates
- [ ] #4 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: handoff checklist green (README.md exists, ACs grep/command-checkable, no deps). Rewrite the paragraph after the memory table: 21867 MiB projected by the fit step + 1136 MiB vision encoder as loaded (887.99 weights + 248.10 compute, TASK-5 log) = 23003 MiB (about 22.5 GiB) vs 21037 MiB (about 20.5 GiB) free, deficit about 1.9 GiB; 1936 MiB free-memory target described as a margin the fit step tries to keep (21867 + 1936 - 21037 = 2767 MiB 'need to reduce'). AC #1 is file-wide, so the Placement report sentence quoting 'about 21.9 GiB' becomes 'about 22.5 GiB' too.
<!-- SECTION:NOTES:END -->
