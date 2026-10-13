---
id: TASK-12
title: Keep the model loaded between client requests
status: In Progress
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-13 17:32'
labels: []
dependencies: []
priority: medium
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

The script warms the model without keep_alive and sets no OLLAMA_KEEP_ALIVE, so Ollama unloads it after its default five minutes idle (Ollama FAQ). The next request then pays the load (about 5.7 s in TASK-5) and loses the warm prompt cache. The server is dedicated to one model and is stopped with Ctrl+C, so keeping the model loaded until the server stops costs nothing.

## Scope

In scope:
- add -KeepAlive (string, default '-1' = keep until the server stops) that sets OLLAMA_KEEP_ALIVE and the keep_alive of the warm-load request
- measure a request right after the warm load and again after more than five minutes idle

Out of scope:
- other server-wide settings
- client-side keep_alive in OpenCode

## Files

- `windows/start-ollama.ps1` (exists) — parameter, environment and warm-load body
- `README.md` (exists) — option

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
- [x] #1 windows/start-ollama.ps1 declares -KeepAlive with default '-1', sets OLLAMA_KEEP_ALIVE from it and passes it as keep_alive in the warm-load request (test)
- [ ] #2 On the server, the same request right after the warm load and after more than five minutes idle shows no reload: the model stays in /api/ps, load_duration stays small and the log has no new "starting llama-server" line (recorded)
- [x] #3 README.md documents -KeepAlive
- [x] #4 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: add [string]$KeepAlive='-1' (validated as whole seconds or a Go duration), set OLLAMA_KEEP_ALIVE from it, build the warm-load body in a testable Get-WarmLoadBody helper. Ollama's API Duration parses a JSON string with time.ParseDuration (a bare '-1' fails: missing unit), while OLLAMA_KEEP_ALIVE also accepts integer seconds, so the helper sends integer values as a JSON number and durations as strings. AC #2 needs the owner's Windows server over the LAN (address not in the repo, not reachable from the autonomous run) and stays open.
<!-- SECTION:NOTES:END -->
