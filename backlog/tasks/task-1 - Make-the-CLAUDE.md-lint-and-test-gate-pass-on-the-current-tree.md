---
id: TASK-1
title: Make the CLAUDE.md lint and test gate pass on the current tree
status: Done
assignee: []
created_date: '2026-10-11 07:52'
updated_date: '2026-10-11 07:59'
labels: []
dependencies: []
priority: high
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Lint and Test commands in CLAUDE.md (## Project-Specific) were written at ralph-init time and fail on the current tree for reasons no task introduced, so no task can reach Done:

1. shellcheck lints Ralph-managed scripts (.claude/hooks/*.sh, .devcontainer/init-firewall.sh, ralph.sh, refine.sh) and reports 4 SC2016 notes in .claude/hooks. Ralph upgrade overwrites those files, so exclude them from the lint; do not edit them.
2. PSScriptAnalyzer reports PSAvoidUsingWriteHost three times in windows/start-ollama.ps1 (lines 62-64). Write-Host is intended there: the script is an interactive launcher printing console status. Suppress that one rule through a repo-root settings file; do not rewrite the script.
3. There is no Python yet and no pyproject, so uv run ruff / mypy / pytest have nothing installed; mypy exits 2 when no .py files exist; pytest exits 5 when no tests are collected. ruff exits 0 with no Python files.

Verified while writing this task: the exclude pathspec below lists no .sh files on today's tree but still lists a new root-level script.

Target Lint command (replace the Lint line in CLAUDE.md with exactly this):

```bash
uv run ruff check . && git ls-files -co --exclude-standard -z -- '*.py' | xargs -0 -r uv run mypy && git ls-files -co --exclude-standard -z -- '*.sh' ':(exclude).claude/**' ':(exclude).devcontainer/**' ':(exclude)ralph.sh' ':(exclude)refine.sh' | xargs -0 -r shellcheck && pwsh -NoProfile -Command '$r = git ls-files -co --exclude-standard "*.ps1" "*.psm1" | ForEach-Object { Invoke-ScriptAnalyzer -Path $_ -Settings ./PSScriptAnalyzerSettings.psd1 }; $r; exit [int]($r.Count -gt 0)'
```

Target Test command (exit 5 = no tests collected is accepted; any real failure still fails):

```bash
uv run pytest; rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 5 ]
```

New file at repo root, PSScriptAnalyzer settings:

```text
PSScriptAnalyzerSettings.psd1
```

```powershell
@{
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
```

New file at repo root, a non-package uv project carrying the dev tools; lock it with uv lock and commit the lockfile:

```text
pyproject.toml
uv.lock
```

```toml
[project]
name = "ollama-scripts"
version = "0.1.0"
requires-python = ">=3.14"

[dependency-groups]
dev = ["ruff", "mypy", "pytest"]

[tool.uv]
package = false
```

Also update the CLAUDE.md Conventions bullet about lint scoping so it says Ralph-managed scripts are excluded from shellcheck and that PSScriptAnalyzer reads the repo-root settings file.

pwsh and shellcheck exist only in the devcontainer image (and shellcheck on the macOS host), so run the full Lint command inside the devcontainer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLAUDE.md Project-Specific Lint and Test lines equal the target commands in the description
- [x] #2 Repo-root PSScriptAnalyzer settings file exists and excludes only PSAvoidUsingWriteHost
- [x] #3 pyproject declares ruff, mypy and pytest in the dev dependency group and uv lock --check exits 0 with the lockfile committed
- [x] #4 Inside the devcontainer the Lint command exits 0 on the task branch
- [x] #5 Inside the devcontainer the Test command exits 0 on the task branch
- [x] #6 Gate still bites: an untracked scratch shell script echoing an unquoted $1 makes Lint exit non-zero, and an untracked scratch ps1 assigning an unused variable makes Lint exit non-zero; both scratch files are removed afterwards
- [x] #7 git diff master --stat -- .claude/hooks .devcontainer ralph.sh refine.sh prints nothing
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Plan: add pyproject.toml (dev group ruff/mypy/pytest, package=false) + uv lock; add PSScriptAnalyzerSettings.psd1 excluding PSAvoidUsingWriteHost; replace CLAUDE.md Lint/Test lines with target commands and update the Conventions bullet; verify lint/test exit 0 in devcontainer, gate-bites checks with scratch .sh/.ps1, and no diff in Ralph-managed files.

Commit: `a3c025b` - task-1: Make lint and test gate pass on the current tree

Verification (devcontainer, task-1 branch): Lint line from CLAUDE.md exit 0 (ruff 'All checks passed!', mypy skipped: no .py, shellcheck skipped: no non-Ralph .sh, PSScriptAnalyzer clean on windows/start-ollama.ps1 with settings). Test line exit 0 (Python 3.14.7, pytest 9.1.1, 0 collected -> rc 5 accepted). uv lock --check exit 0 (14 packages). Gate bites: scratch .sh 'echo $1' -> lint exit 123 (SC2086); scratch .ps1 '$unused = 1' -> lint exit 1 (PSUseDeclaredVarsMoreThanAssignment); both removed. git diff master --stat on .claude/hooks .devcontainer ralph.sh refine.sh empty.

Review: task-reviewer APPROVED (score 10). Final lint+test exit 0. pyproject is non-package (package=false); Ralph-managed scripts excluded from shellcheck rather than edited; PSAvoidUsingWriteHost suppressed via repo-root PSScriptAnalyzerSettings.psd1.
<!-- SECTION:NOTES:END -->
