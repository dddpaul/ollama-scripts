---
id: TASK-2
title: Rewrite README.md as the ollama-scripts repo overview
status: Done
assignee: []
created_date: '2026-10-11 07:52'
updated_date: '2026-10-11 08:01'
labels: []
dependencies:
  - TASK-1
priority: medium
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README.md still reads as the doc for a single script (title "Qwen 3.8 on Windows", and it tells you to copy start-ollama.ps1 without naming its directory), but the repo is a collection of Ollama helper scripts plus Ralph agent infrastructure. Turn it into a repo-level README.

Structure:

1. Title "ollama-scripts" and a one-paragraph purpose: helper scripts for running Ollama models, organised by platform directory (currently only windows/).
2. Scripts index: one row per script with its path (as a relative link), platform, and a one-line purpose. Today that is windows/start-ollama.ps1, which starts a LAN-reachable Ollama server on port 11435 and serves qwen3.8:27b with a 64k or 128k context.
3. A "Windows: Qwen 3.8 launcher" section that keeps all existing content (install Ollama and quit the tray app, both run commands, the firewall rule, the verification commands, the OpenAI-compatible endpoint, the references), with these fixes:
   - tell the reader to copy windows/start-ollama.ps1 to the Windows machine (the run commands keep using .\start-ollama.ps1 after copying);
   - prerequisite: ollama.exe must be on PATH;
   - document behaviours the script has but the README omits:
     - it refuses to start when something already listens on port 11435;
     - it waits up to 120 seconds for the server to answer /api/version and fails otherwise;
     - it re-runs ollama create on every launch, while the base model is pulled only when missing;
     - OLLAMA_CONTEXT_LENGTH is set server-wide to the same context, so other models served by this instance default to it too;
     - the server binds 0.0.0.0:11435 while the script's own CLI calls go to 127.0.0.1:11435.
4. A short "Development" section:
   - quality checks live in CLAUDE.md under ## Project-Specific: link there, do not copy the commands (they would drift);
   - Ralph workflow: /ralph-prd, then /ralph-backlog, then /ralph-run (or ./ralph.sh --tool claude);
   - the devcontainer adds shellcheck, PowerShell and PSScriptAnalyzer, and needs CLAUDE_CODE_OAUTH_TOKEN exported on the host from ~/.zshenv (mint it with claude setup-token).

Every value the README states about the script must match windows/start-ollama.ps1: port 11435, 65536 and 131072 tokens, OLLAMA_NUM_PARALLEL=1, OLLAMA_MAX_LOADED_MODELS=1, Flash Attention, q8_0 KV cache, 120-second readiness timeout.

This task depends on the quality-gate fix task because the Done step requires Lint and Test to pass.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 README.md starts with the heading '# ollama-scripts' followed by a purpose paragraph
- [x] #2 README.md has a scripts index whose row for windows/start-ollama.ps1 is a relative link that resolves to an existing file
- [x] #3 The Windows section keeps both run commands (default 64k and -ContextK 128), the New-NetFirewallRule command, the verification commands, the /v1 endpoint line and the three docs.ollama.com references
- [x] #4 The Windows section names windows/start-ollama.ps1 as the file to copy and states that ollama.exe must be on PATH
- [x] #5 The Windows section documents the port-in-use refusal, the 120-second readiness timeout, the ollama create re-run on every launch, and the server-wide OLLAMA_CONTEXT_LENGTH
- [x] #6 A Development section links to CLAUDE.md for the quality checks without copying the Lint or Test commands, names the Ralph workflow, and states the devcontainer token prerequisite
- [x] #7 Every number README.md states about the script (11435, 65536, 131072, 120) matches windows/start-ollama.ps1
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: rewrite README.md as repo overview (title, scripts index, Windows launcher section with existing content + documented script behaviours, Development section linking CLAUDE.md). Verify every number against windows/start-ollama.ps1.

Commit: `1016801` - task-2: Rewrite README.md as the ollama-scripts repo overview

README.md rewritten as repo overview: title + purpose, scripts index (relative link to windows/start-ollama.ps1), Windows launcher section keeping all prior content plus PATH prerequisite, copy path and five documented script behaviours, Development section linking CLAUDE.md#project-specific. Lint passes, pytest exit 5 (no tests). task-reviewer APPROVED (score 10).
<!-- SECTION:NOTES:END -->
