---
id: TASK-15
title: Set OpenCode sampling to the model's recommended values
status: To Do
assignee: []
created_date: '2026-10-12 06:02'
updated_date: '2026-10-12 19:33'
labels: []
dependencies:
  - TASK-14
priority: medium
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

OpenCode requests to the local model run hotter than the model's recommended sampling. The llama-server "sampler params" line in the server log for all 18 OpenCode requests on 2026-10-12 showed `top_k = 20, top_p = 1.000, min_p = 0.000, temp = 1.000`, while the `qwen3.8:27b-128k` Modelfile has `top_p 0.95`: OpenCode sends its own values over the model's. Qwen's model cards recommend about temperature 0.6, top_p 0.95, top_k 20, min_p 0 in thinking mode and about 0.7 / 0.8 / 20 / 0 without thinking (check the qwen3.8 card for its exact values). In the same session OpenCode, at about 48k tokens of context and in an answer that combined six searches, named a Confluence page and pageId that no search had returned, and retracted it in its next answer. A lower temperature reduces such slips but does not remove them; greedy decoding (temperature 0) is not an option, Qwen warns it leads to repetition.

## Scope

In scope:
- find which OpenCode setting controls temperature and top_p for this provider and model in the installed OpenCode version (agent-level `temperature` / `top_p`, model `options`, or other), and confirm it in that version's docs or source;
- add the snippet to the README.md OpenCode section (created by TASK-14), with the values matching the reasoning mode chosen in TASK-14;
- owner run: apply the snippet to the owner's OpenCode config, then confirm in the server log stream that the "sampler params" line of OpenCode requests shows the new temperature and top_p.

Out of scope:
- editing ~/.config/opencode from this repo (the owner applies the snippet);
- Modelfile sampling defaults for other clients;
- any claim that the change prevents fabricated answers.

## Files

- `README.md` (exists) — OpenCode section from TASK-14: sampling snippet and the log check.

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
- [ ] #1 The notes name the OpenCode setting that controls temperature and top_p for this provider and model, with a link to the docs or source of the installed version
- [ ] #2 The notes record the qwen3.8 recommended sampling values with a link to the model card
- [ ] #3 README.md OpenCode section contains the sampling snippet with temperature, top_p and top_k values matching the reasoning mode from TASK-14
- [ ] #4 Owner run: after applying the snippet, the server log "sampler params" line of an OpenCode request shows the new temperature and top_p; the line is recorded in the notes
- [ ] #5 The CLAUDE.md Lint and Test commands exit 0 in the devcontainer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Findings 2026-10-12 (OpenCode 1.18.35 per the source project session; server-side checks over the LAN against Ollama 0.40.2):
- OpenCode provider "ollama" uses @ai-sdk/openai-compatible against the /v1 endpoint. Its reasoning setting is reasoningEffort (sent as reasoning_effort), settable in provider.ollama.models["qwen3.8:27b-128k"].options or, switchable at runtime (ctrl+t), in that model entry's variants block; OpenCode generates no variants for qwen ids, so they must be declared. temperature and top_p are agent settings (agent.<name>.temperature / top_p); the SDK drops topK, and unknown keys in model options are sent verbatim in the request body. Source: the bundled @ai-sdk/openai-compatible getArgs and the config schema in the installed binary (read by the source session; docs not fetched).
- Ollama /v1/chat/completions honours temperature and top_p but ignores top_k and min_p sent as extra body fields: a request with temperature 0.6, top_p 0.95, top_k 7, min_p 0.05 logged "top_k = 20, top_p = 0.950, min_p = 0.000 ... temp = 0.600" (the Modelfile values for top_k and min_p). A request without sampling fields logged "top_k = 20, top_p = 1.000, min_p = 0.000 ... temp = 1.000": the /v1 endpoint defaults top_p and temperature to 1.0 over the Modelfile top_p 0.95, so the client must send both.
- Consequence for AC #3: the snippet only needs temperature and top_p (agent level); top_k 20 and min_p 0 already come from the Modelfile and match the Qwen recommendation.
<!-- SECTION:NOTES:END -->
