---
id: TASK-14
title: Document and verify OpenCode client settings for the local model
status: In Progress
assignee: []
created_date: '2026-10-11 19:06'
updated_date: '2026-10-13 06:03'
labels: []
dependencies: []
priority: high
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

Response time in OpenCode depends on more than the server: every request carries the schemas of all MCP tools (mcp-atlassian exposes Confluence and Jira tools, read and write), and qwen3.8 thinks by default. Per Codex, mcp-atlassian supports READ_ONLY_MODE and ENABLED_TOOLS (docs/tools-reference.mdx in sooperset/mcp-atlassian); READ_ONLY_MODE alone still leaves Jira reads, so both are needed, and the OpenCode config uses the OpenAI-compatible /v1 endpoint, so a native think:false may not reach the model - reasoning_effort "none" has to be checked on the actual request. The owner applies client settings himself; this repo documents them and records the evidence.

## Scope

In scope:
- check on the server whether reasoning_effort "none" on /v1/chat/completions turns thinking off for qwen3.8 (compare with the field absent; read supported values from /api/show)
- find the installed mcp-atlassian version and confirm the READ_ONLY_MODE and ENABLED_TOOLS names and the tool names confluence_search, confluence_get_page, confluence_get_page_children in its docs
- add a README.md section for OpenCode: provider snippet with model id and limits matching -ContextK, mcp-atlassian environment with placeholders, version pin, reasoning setting
- owner run: the same short Confluence task in a new OpenCode session before and after the settings

Out of scope:
- editing ~/.config/opencode or any file outside this repo
- real URLs, tokens or user names in README.md

## Files

- `README.md` (exists) — new OpenCode client section

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
- [x] #1 The notes record a /v1/chat/completions request with reasoning_effort "none" and one without it: whether each response contains reasoning and its completion token count
- [ ] #2 The notes record the installed mcp-atlassian version and a link to the doc that confirms READ_ONLY_MODE, ENABLED_TOOLS and the three tool names
- [ ] #3 README.md has an OpenCode section with the provider snippet, the mcp-atlassian environment and version pin, and the reasoning setting, using placeholders only: a case-insensitive grep of README.md for the company's internal domain (run by the owner, who knows it) finds nothing, and no real token or user name appears
- [ ] #4 Owner run recorded: for the same short Confluence task before and after, the number of tools sent, prompt_eval_count of the first request, time to the first tool call and to the answer
- [ ] #5 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: AC #1 measured from the Mac over the LAN against the Windows server (qwen3.8:27b-128k); AC #2-#4 need the owner's OpenCode/mcp-atlassian environment.

AC #1 (2026-10-12, over the LAN, Ollama 0.40.2, qwen3.8:27b-128k): /api/show reports capabilities [completion, vision, tools, thinking] and "thinking": {"values": [false, "low", "medium", "xhigh"], "default": "medium"}. POST /v1/chat/completions with "What is 17 * 23? Reply with the number only.", max_tokens 2048, stream false, two runs each: without reasoning_effort -> completion_tokens 63 and 42, the message carries reasoning (115 and 43 chars), content "391"; with "reasoning_effort": "none" -> completion_tokens 4 and 4, no reasoning in the message, content "391". So reasoning_effort "none" does turn thinking off through the OpenAI-compatible endpoint, although "none" is not among the advertised values. The first request (6.6 s) included a model reload.

Reasoning-mode input from the source project session (2026-10-12): recommendation is thinking ON for Confluence research through OpenCode (medium now, measure "low" as the candidate default, never "none"), because correctness of tool results matters more than latency there (1-5 min turns are acceptable). The fabricated-page answer reported earlier happened at the server default (OpenCode config sets no reasoning or sampling options, so presumably medium; to be confirmed on the wire); the cause acted on was bundling several searches into one message, and one search or one page per message has avoided it since. Agreed plan: the source session replays three prompt shapes (A single search, B single page with a deliberately absent item, C three searches compared, also at ~48k context) for none/low/medium, interleaved, scoring fabricated page ids (ids not returned by the turn's tools) and the B absence check; this session captures the server side through the -LogPort stream (requests, prompt and generated tokens, tok/s, sampler params). Decision rule: take "low" if it matches "medium" on zero fabricated ids and the B check, else keep "medium"; sampling per Qwen thinking profile (0.6 / 0.95 / 20 / 0) for TASK-15.

reasoning_effort levels on /v1 (2026-10-12, over the LAN): a bundle-pricing word problem with the correct answer 325, temperature 0.6, top_p 0.95, seeds 1 and 2: none -> 4 completion tokens, no reasoning, answers 670 and 100 (wrong); low -> 233 / 223 tokens, 325; medium -> 263 / 327 tokens, 325; xhigh -> 233 / 162 tokens, 325 (2.4-3.8 s each). Any thinking level solves it; "none" fails it. "low" is accepted and differs from "medium"; token counts do not scale monotonically with the level on this prompt.

Reasoning-level replay (2026-10-13; OpenCode 1.18.35, Ollama 0.40.2, qwen3.8:27b-128k; server side from the -LogPort 11436 stream, client side from the source session's opencode.db). The level is set per agent in the OpenCode config (agent.build / agent.general: model, variant, temperature 0.6, top_p 0.95): OpenCode resolves a prompt's variant as prompt.variant ?? agent.variant (agent.variant only when agent.model matches), plugin-posted prompts carry no variant, and the TUI keeps its own last-selected variant. Each level switch is a config edit plus an OpenCode restart.
Runs (fresh session per run; C-48k continues the C session), requests / generated tokens / reasoning characters:
- A low 3 / 417 / 201; A medium 3 / 507 / 358
- B medium 3 / 840 / 1557; B low 3 / 780 / 1100
- C low 11 / 3015 / 4454 (one reply sent twice); C medium 11 / 1974 / 1829
- C-48k low 11 / 2952 / 4425 (789-token reasoning step after the reply); C-48k medium 11 / 1762 / 1386
Scores: 0 fabricated page ids in all 8 runs, B absence check passes at both levels, no compaction, tool calls exactly as asked. Single-search messages are indistinguishable between levels (within about 10% once the duplicated reply is excluded); the differences sit in the compare steps and in the two low-only anomalies (one sample per cell, temperature 0.6). Decision rule result: low matches medium on both scores but is not cheaper; the source session recommends keeping medium with an explicit variant; owner decision pending.
Server side: all 56 run requests logged temp 0.600, top_p 0.950, top_k 20, min_p 0; no truncation; generation about 80 tok/s at 31-34k context, about 70 at 40k, 65-75 at 49k. The reasoning level is rendered at the top of the prompt (longest common prefix 3 tokens between a low and a medium prompt), so the first prompt at a new level re-reads the whole ~31k-token system and tools prefix (31,455 tokens in 26.4 s); llama-server keeps one cached prompt per level, so later switches stay warm. An idle unload (5 minutes) empties that cache: the first request after a break costs a ~5 s reload plus ~27 s of prefill (see TASK-12, -KeepAlive).
<!-- SECTION:NOTES:END -->
