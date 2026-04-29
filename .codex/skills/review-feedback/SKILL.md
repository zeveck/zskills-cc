---
name: review-feedback
description: >-
  Review exported feedback JSON from the in-app feedback panel, evaluate each
  pending entry, and selectively file GitHub issues via gh CLI. Use when the user
  says "review feedback", "triage feedback", or "file feedback issues".
---

<!-- ZSKILLS_CODEX_COMPAT_START -->
## Codex Compatibility

This block applies only to the Codex-installed copy of this skill. It is an adapter layer for the original Claude slash-command instructions, not a replacement for the upstream workflow.

Invocation: in Codex, invoke this skill by naming it, for example `run-plan ...`, or by using the original slash command when the user supplied it. Treat `$ARGUMENTS` as the text after the skill name or slash command. Pass only the intended argument tail when one ZSkill calls another.

Tool mapping: if Codex exposes a subagent tool, map Claude `Agent`, `Task`, or subagent dispatch to that tool. Exploration-only work uses an explorer-style agent; implementation work uses a worker-style agent with explicit file/module ownership and instructions not to revert others work; review and devil-advocate work uses a general review agent. If no subagent tool is available, run the subtask inline, clearly label the degraded independence, and do not claim fresh-agent isolation. `Read`, `Grep`, `Glob`, and `Bash` map to shell reads, `rg`, and command execution; manual `Edit`/`Write` operations map to patch-based edits.

Skill calls: when this skill invokes another ZSkill such as `/run-plan`, `/draft-plan`, `/verify-changes`, or `/commit`, load and follow `~/.codex/skills/<skill>/SKILL.md`. Do not recursively re-enter the same skill unless the workflow explicitly requires it. Preserve `ZSKILLS_PIPELINE_ID` and related tracking environment across skill boundaries.

Tracking: tracking files belong under the main repository root at `.zskills/tracking/`, never under `~/.codex/skills`. Resolve the main root with the original `git rev-parse --git-common-dir` pattern. Keep `.zskills/tracking/` ignored. Do not delete or clear tracking except through an explicit user-requested clear-tracking workflow.

Landing modes: preserve `direct`, `cherry-pick`, and `pr`. Explicit `direct`, `pr`, or `cherry-pick` arguments win and should be stripped before downstream phase parsing. Otherwise read `.codex/zskills-config.json`, then `.claude/zskills-config.json`, then fall back to `cherry-pick`. If both config files exist and disagree on landing or main protection, stop before landing and report the conflict. `locked-main-pr` remains the preset name for PR mode with main protection.

Scheduler bridge: Claude cron tools (`CronList`, `CronCreate`, `CronDelete`) are unsupported unless the current Codex runtime exposes a scheduler. In Codex, prefer the project-local `scripts/zskills-scheduler.sh` and `scripts/zskills-run-due.sh`, then the installed helpers under `~/.codex/skills/scripts/`. If helpers are unavailable, report scheduling as degraded and do not claim background execution. For `run-plan finish auto`, run exactly one plan phase in the current top-level invocation; after updating the plan/report/tracking, if another phase remains, create a fresh one-shot schedule with `zskills-scheduler.sh add --one-shot` whose args omit a fixed phase number, then exit so the next `zskills-run-due.sh`/OS cron tick starts a fresh Codex turn.

Hook fallback: Claude hooks are not enforced by Codex in this environment. Compensate with inline preflight checks before commits, cherry-picks, PR merge/auto-merge, worktree deletion, or tracking cleanup: inspect status, protect unrelated changes, verify branch/mode, and preserve `.zskills/tracking`.

Helper scripts: generated Codex installs include shared helpers under `~/.codex/skills/scripts/`. Prefer project-local helpers at `$PROJECT_ROOT/scripts/` when present, otherwise use the installed helper path. If neither helper is available, use the explicit fallback instructions in the skill and report the degraded procedural path.

See `~/.codex/skills/ZSKILLS_CODEX_INTEGRATION.md` for the shared adapter contract.
<!-- ZSKILLS_CODEX_COMPAT_END -->

# /review-feedback — Review and triage user feedback

Review exported feedback JSON from the in-app feedback panel, evaluate each
pending entry, and selectively file GitHub issues.

## Trigger

User says: "review feedback", "triage feedback", "file feedback issues",
or invokes `/review-feedback`.

## Input

The exported `feedback.json` file should be in the repo root (or the user
will specify the path). This file is exported from the app via
**Feedback Panel > History > Export JSON**.

## Workflow

1. **Read** the feedback JSON file:
   ```bash
   cat feedback.json
   ```
   Or run the summary helper first:
   ```bash
   node scripts/review-feedback.js feedback.json
   ```

2. **For each pending entry**, evaluate:
   - Is it a real, actionable bug or feature request?
   - Is it a duplicate of an existing GitHub issue? Check with:
     ```bash
     gh issue list --search "keyword" --state open
     ```
   - What label(s) should it get? (`bug`, `enhancement`, `ui`, `question`)

3. **Present a summary table** to the user showing your recommendations:
   | # | Title | Type | Severity | Recommendation | Reason |
   |---|-------|------|----------|----------------|--------|
   | 1 | ... | bug | high | File | Clear repro |
   | 2 | ... | feature | low | Dismiss | Too vague |

4. **Wait for user approval** before filing anything.

5. **File approved entries** as GitHub issues:
   ```bash
   gh issue create --title "Title here" --body "$(cat <<'EOF'
   **Type:** bug
   **Severity:** high
   **Reported:** 2026-03-11

   Description here.

   ### Context
   - Model: ModelName
   - Blocks: 12
   - Sim state: idle
   - Solver: ode45
   EOF
   )" --label "bug"
   ```

6. **Update the JSON file** with filed status and issue numbers:
   - Set `status: "filed"` and `githubIssue: "#NNN"` for filed entries
   - Set `status: "dismissed"` for dismissed entries
   - Write the updated JSON back to the file

7. **Tell the user** they can re-import the updated JSON in the app
   via the browser console:
   ```js
   // In browser console:
   const store = new (await import('./src/io/FeedbackStore.js')).FeedbackStore();
   store.importJSON(await (await fetch('feedback.json')).text());
   ```

## Label Mapping

| Feedback type | GitHub label |
|--------------|-------------|
| bug | `bug` |
| ui | `bug`, `ui` |
| feature | `enhancement` |
| question | `question` |

## Rules

- Never file issues without user approval
- Check for duplicates before filing
- Include the auto-captured context in the issue body
- One GitHub issue per feedback entry (don't merge entries)
- Critical severity bugs should be flagged prominently in the summary
