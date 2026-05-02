---
name: playwright-cli
description: Automates browser interactions for web testing, form filling, screenshots, and data extraction. Use when the user needs to navigate websites, interact with web pages, fill forms, take screenshots, test web applications, or extract information from web pages.
allowed-tools: Bash(playwright-cli:*)
---

<!-- ZSKILLS_CODEX_COMPAT_START -->
## Codex Compatibility

This block applies only to the Codex-installed copy of this skill. It is an adapter layer for the original Claude slash-command instructions, not a replacement for the upstream workflow.

Invocation: in Codex, invoke this skill by naming it, for example `run-plan ...`, or by using the original slash command when the user supplied it. Treat `$ARGUMENTS` as the text after the skill name or slash command. Pass only the intended argument tail when one ZSkill calls another.

Tool mapping: if Codex exposes a subagent tool, map Claude `Agent`, `Task`, or subagent dispatch to that tool. Exploration-only work uses an explorer-style agent; implementation work uses a worker-style agent with explicit file/module ownership and instructions not to revert others work; review and devil-advocate work uses a general review agent. If no subagent tool is available, run the subtask inline, clearly label the degraded independence, and do not claim fresh-agent isolation. `Read`, `Grep`, `Glob`, and `Bash` map to shell reads, `rg`, and command execution; manual `Edit`/`Write` operations map to patch-based edits.

Skill calls: when this skill invokes another ZSkill such as `/run-plan`, `/draft-plan`, `/verify-changes`, or `/commit`, load and follow the selected skill instructions from Codex's available skills. If you must read the file directly, prefer `$PROJECT_ROOT/.agents/skills/<skill>/SKILL.md`, then `$HOME/.agents/skills/<skill>/SKILL.md`, then legacy `$HOME/.codex/skills/<skill>/SKILL.md`. Do not recursively re-enter the same skill unless the workflow explicitly requires it. Preserve `ZSKILLS_PIPELINE_ID` and related tracking environment across skill boundaries.

Tracking: tracking files belong under the main repository root at `.zskills/tracking/`, never under `~/.codex/skills`. Resolve the main root with the original `git rev-parse --git-common-dir` pattern. Keep `.zskills/tracking/` ignored. Do not delete or clear tracking except through an explicit user-requested clear-tracking workflow.

Landing modes: preserve `direct`, `cherry-pick`, and `pr`. Explicit `direct`, `pr`, or `cherry-pick` arguments win and should be stripped before downstream phase parsing. Otherwise read `.codex/zskills-config.json`, then `.claude/zskills-config.json`, then fall back to `cherry-pick`. If both config files exist and disagree on landing or main protection, stop before landing and report the conflict. `locked-main-pr` remains the preset name for PR mode with main protection.

Scheduler bridge: Claude cron tools (`CronList`, `CronCreate`, `CronDelete`) are unsupported unless the current Codex runtime exposes a scheduler. In Codex, prefer the project-local `scripts/zskills-scheduler.sh` and `scripts/zskills-run-due.sh`, then installed helpers under `$PROJECT_ROOT/.agents/skills/scripts/`, `$HOME/.agents/skills/scripts/`, or legacy `$HOME/.codex/skills/scripts/`. If helpers are unavailable, report scheduling as degraded and do not claim background execution. Before starting any `run-plan finish auto` phase or any recurring `every` workflow, run `zskills-scheduler.sh runner-status --repo-path "$PROJECT_ROOT"`; if no scheduled runner is enabled, run `zskills-scheduler.sh runner-enable --repo-path "$PROJECT_ROOT"` automatically and report that autonomous scheduling was enabled. If enabling fails, stop before doing work. For `run-plan finish auto`, after this preflight passes, run exactly one plan phase in the current top-level invocation; after updating the plan/report/tracking, if another phase remains, create a fresh one-shot schedule with `zskills-scheduler.sh add --one-shot` whose args omit a fixed phase number, then exit so the next `zskills-run-due.sh`/OS cron tick starts a fresh Codex turn. When a scheduled workflow is stopped, blocked, or complete, run `zskills-scheduler.sh runner-disable-if-idle --repo-path "$PROJECT_ROOT"` so this repo's OS cron entry is removed when no active schedules remain.

Hook fallback: Claude hooks are not enforced by Codex in this environment. Compensate with inline preflight checks before commits, cherry-picks, PR merge/auto-merge, worktree deletion, or tracking cleanup: inspect status, protect unrelated changes, verify branch/mode, and preserve `.zskills/tracking`.

Helper scripts: generated Codex installs include shared helpers under `.agents/skills/scripts/` for project installs or `$HOME/.agents/skills/scripts/` for user installs. Prefer project-local helpers at `$PROJECT_ROOT/scripts/` when present, otherwise use the installed helper path, with `$HOME/.codex/skills/scripts/` as a legacy fallback. If neither helper is available, use the explicit fallback instructions in the skill and report the degraded procedural path.

See `~/.codex/skills/ZSKILLS_CODEX_INTEGRATION.md` for the shared adapter contract.
<!-- ZSKILLS_CODEX_COMPAT_END -->

# Browser Automation with playwright-cli

## Quick start

```bash
# open new browser
playwright-cli open
# navigate to a page
playwright-cli goto https://playwright.dev
# interact with the page using refs from the snapshot
playwright-cli click e15
playwright-cli type "page.click"
playwright-cli press Enter
# take a screenshot (rarely used, as snapshot is more common)
playwright-cli screenshot
# close the browser
playwright-cli close
```

## Commands

### Core

```bash
playwright-cli open
# open and navigate right away
playwright-cli open https://example.com/
playwright-cli goto https://playwright.dev
playwright-cli type "search query"
playwright-cli click e3
playwright-cli dblclick e7
playwright-cli fill e5 "user@example.com"
playwright-cli drag e2 e8
playwright-cli hover e4
playwright-cli select e9 "option-value"
playwright-cli upload ./document.pdf
playwright-cli check e12
playwright-cli uncheck e12
playwright-cli snapshot
playwright-cli snapshot --filename=after-click.yaml
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
playwright-cli dialog-accept
playwright-cli dialog-accept "confirmation text"
playwright-cli dialog-dismiss
playwright-cli resize 1920 1080
playwright-cli close
```

### Navigation

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

### Keyboard

```bash
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli keydown Shift
playwright-cli keyup Shift
```

### Mouse

```bash
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mousedown right
playwright-cli mouseup
playwright-cli mouseup right
playwright-cli mousewheel 0 100
```

### Save as

```bash
playwright-cli screenshot
playwright-cli screenshot e5
playwright-cli screenshot --filename=page.png
playwright-cli pdf --filename=page.pdf
```

### Tabs

```bash
playwright-cli tab-list
playwright-cli tab-new
playwright-cli tab-new https://example.com/page
playwright-cli tab-close
playwright-cli tab-close 2
playwright-cli tab-select 0
```

### Storage

```bash
playwright-cli state-save
playwright-cli state-save auth.json
playwright-cli state-load auth.json

# Cookies
playwright-cli cookie-list
playwright-cli cookie-list --domain=example.com
playwright-cli cookie-get session_id
playwright-cli cookie-set session_id abc123
playwright-cli cookie-set session_id abc123 --domain=example.com --httpOnly --secure
playwright-cli cookie-delete session_id
playwright-cli cookie-clear

# LocalStorage
playwright-cli localstorage-list
playwright-cli localstorage-get theme
playwright-cli localstorage-set theme dark
playwright-cli localstorage-delete theme
playwright-cli localstorage-clear

# SessionStorage
playwright-cli sessionstorage-list
playwright-cli sessionstorage-get step
playwright-cli sessionstorage-set step 3
playwright-cli sessionstorage-delete step
playwright-cli sessionstorage-clear
```

### Network

```bash
playwright-cli route "**/*.jpg" --status=404
playwright-cli route "https://api.example.com/**" --body='{"mock": true}'
playwright-cli route-list
playwright-cli unroute "**/*.jpg"
playwright-cli unroute
```

### DevTools

```bash
playwright-cli console
playwright-cli console warning
playwright-cli network
playwright-cli run-code "async page => await page.context().grantPermissions(['geolocation'])"
playwright-cli tracing-start
playwright-cli tracing-stop
playwright-cli video-start
playwright-cli video-stop video.webm
```

## Open parameters
```bash
# Use specific browser when creating session
playwright-cli open --browser=chrome
playwright-cli open --browser=firefox
playwright-cli open --browser=webkit
playwright-cli open --browser=msedge
# Connect to browser via extension
playwright-cli open --extension

# Use persistent profile (by default profile is in-memory)
playwright-cli open --persistent
# Use persistent profile with custom directory
playwright-cli open --profile=/path/to/profile

# Start with config file
playwright-cli open --config=my-config.json

# Close the browser
playwright-cli close
# Delete user data for the default session
playwright-cli delete-data
```

## Snapshots

After each command, playwright-cli provides a snapshot of the current browser state.

```bash
> playwright-cli goto https://example.com
### Page
- Page URL: https://example.com/
- Page Title: Example Domain
### Snapshot
[Snapshot](.playwright-cli/page-2026-02-14T19-22-42-679Z.yml)
```

You can also take a snapshot on demand using `playwright-cli snapshot` command.

If `--filename` is not provided, a new snapshot file is created with a timestamp. Default to automatic file naming, use `--filename=` when artifact is a part of the workflow result.

## Browser Sessions

```bash
# create new browser session named "mysession" with persistent profile
playwright-cli -s=mysession open example.com --persistent
# same with manually specified profile directory (use when requested explicitly)
playwright-cli -s=mysession open example.com --profile=/path/to/profile
playwright-cli -s=mysession click e6
playwright-cli -s=mysession close  # stop a named browser
playwright-cli -s=mysession delete-data  # delete user data for persistent session

playwright-cli list
# Close all browsers
playwright-cli close-all
# Forcefully kill all browser processes
playwright-cli kill-all
```

## Local installation

In some cases user might want to install playwright-cli locally. If running globally available `playwright-cli` binary fails, use `npx playwright-cli` to run the commands. For example:

```bash
npx playwright-cli open https://example.com
npx playwright-cli click e1
```

## Example: Form submission

```bash
playwright-cli open https://example.com/form
playwright-cli snapshot

playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e3
playwright-cli snapshot
playwright-cli close
```

## Example: Multi-tab workflow

```bash
playwright-cli open https://example.com
playwright-cli tab-new https://example.com/other
playwright-cli tab-list
playwright-cli tab-select 0
playwright-cli snapshot
playwright-cli close
```

## Example: Debugging with DevTools

```bash
playwright-cli open https://example.com
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli console
playwright-cli network
playwright-cli close
```

```bash
playwright-cli open https://example.com
playwright-cli tracing-start
playwright-cli click e4
playwright-cli fill e7 "test"
playwright-cli tracing-stop
playwright-cli close
```

## Specific tasks

* **Request mocking** [references/request-mocking.md](references/request-mocking.md)
* **Running Playwright code** [references/running-code.md](references/running-code.md)
* **Browser session management** [references/session-management.md](references/session-management.md)
* **Storage state (cookies, localStorage)** [references/storage-state.md](references/storage-state.md)
* **Test generation** [references/test-generation.md](references/test-generation.md)
* **Tracing** [references/tracing.md](references/tracing.md)
* **Video recording** [references/video-recording.md](references/video-recording.md)
