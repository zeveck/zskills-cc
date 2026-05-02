---
name: plans
disable-model-invocation: true
argument-hint: "[rebuild | next | details | work N [auto] [every SCHEDULE] [now]] | stop | next-run"
description: >-
  Plan dashboard and batch executor. View plan status, find the next
  ready plan, or work through plans automatically.
  Usage: /plans [rebuild | next | work N [auto] [every SCHEDULE]]
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

# /plans [rebuild | next | details | work N] — Plan Dashboard & Executor

Maintains `plans/PLAN_INDEX.md` — a structured index of all plan files with
their classification, status, and priority. Also supports batch execution
of ready plans (like `/fix-issues` for bugs).

**Modes:**

- **bare** `/plans` — display the current index (highlights top-priority ready plan)
- **rebuild** `/plans rebuild` — scan all plans, classify, regenerate
- **next** `/plans next` — show the highest-priority ready-to-run plan with command
- **details** `/plans details` — show every plan with a one-line description
- **work** `/plans work N [auto]` — batch-execute next N ready plans
- **stop** `/plans stop` — cancel scheduled runs
- **next-run** `/plans next-run` — when does the next scheduled run fire?

## Mode: Show (bare `/plans`)

1. Read `plans/PLAN_INDEX.md`
2. If the file does not exist, **auto-run rebuild** (Mode: Rebuild below) to
   create it, then display the newly generated index.
3. If the file exists, display a **actionable dashboard** — not a one-line
   summary. Show the actual plan names and status so the user can decide
   what to work on:

   ```
   Plans: 5 ready, 2 in progress, 10 complete

   Ready to Run:
     EDITOR_GAPS_PLAN.md              9 gaps     High
     IMPORT_GAPS_PLAN.md              4 phases   Medium
     INLINE_CHARTS.md                 5 phases   Medium

   In Progress:
     FEATURE_PLAN.md                  Phase 4b   4/8 done
     CORRECTNESS_PLAN.md              Phase 1    1/3 done

   Needs Review: 3 plans (old format, status ambiguous)

   Next: /run-plan plans/EDITOR_GAPS_PLAN.md
   ```

   Show Ready and In Progress tables with plan names, phase info, and
   priority. Collapse Complete/Reference into counts. Highlight the
   top-priority ready plan with a suggested `/run-plan` command.

4. If the file is older than 24 hours (check mtime), append:
   > ⚠️ Index is older than 24 hours. Run `/plans rebuild` to refresh.
5. **Exit.**

## Mode: Details (`/plans details`)

Show every plan with a one-line description, grouped by status. Useful
when you have many plans and can't remember what each one is about.

1. Read `plans/PLAN_INDEX.md` (auto-rebuild if missing).
2. For each plan in the index, read its `## Overview` section (first
   paragraph only) and extract a one-line blurb.
3. Display grouped by status (Ready, In Progress, Complete), with the
   blurb after each plan name:

   ```
   Ready to Run:
     DOC_GAPS_PLAN.md (5 phases, Medium)
       Fill documentation gaps: missing READMEs, stale block counts, broken links

     BLOCK_EXPANSION_PLAN.md (4 phases, Medium)
       Add 15 missing blocks via /add-block delegate phases

   In Progress:
     CORRECTNESS_PLAN.md (13 phases, 7/13 done)
       Systematic solver accuracy improvements with analytical reference tests

   Complete:
     BRIEFING_SKILL_PLAN.md (7 phases)
       Activity briefing and review dashboard with 5 modes
     ...
   ```

4. **Exit.**

## Mode: Rebuild (`/plans rebuild`)

Scan `plans/`, classify every `.md` file, and write a fresh `plans/PLAN_INDEX.md`.

### Step 1 — Inventory

```bash
ls plans/*.md
```

Get all plan files. Ignore subdirectories (e.g., `plans/blocks/`).

Also count block plan files for the coverage summary:
```bash
BLOCK_PLANS=$(find plans/blocks -name '*.md' 2>/dev/null | wc -l)
BLOCK_IMPLS=$(grep -c "    type: '" src/library/registry.js 2>/dev/null)
```
Use the registry file for the implementation count — it's the authoritative
registry. `find *Block.js` undercounts because some components (Resistor.js,
Capacitor.js, etc.) don't follow the `*Block.js` naming convention.

### Step 2 — Classify each file

For each file, read the first ~50 lines. Classify into one of three categories:

1. **Executable plan** — has `## Phase` sections (numbered phases with work
   items) OR has a Progress Tracker table (`| Phase | Status |`). These are
   plans that `/run-plan` can execute.

   **Meta-plan detection:** If the plan's phases use `### Execution: delegate
   /run-plan` directives referencing other plan files, it's a meta-plan. Record
   which sub-plan files it references. In the index, sub-plans should be
   indented under their meta-plan rather than listed independently.

2. **Issue tracker** — filename ends in `_ISSUES.md` OR has an "Issue Tracker"
   or "Issue List" heading OR is primarily a table of GitHub issue numbers.
   List separately — these are not executable by `/run-plan`.
   **Deterministic rule:** Files ending in `_ISSUES.md` are ALWAYS classified
   as issue trackers, regardless of other content (e.g., phase sections).
   The filename suffix takes precedence over content-based classification.

3. **Reference document** — everything else (research docs, overviews, gap
   analyses, block library lists). List separately.

### Step 3 — Determine status for executable plans

For each executable plan, determine its status:

1. **Read the Progress Tracker** (if present) — a table with phase rows and
   status indicators:
   - All phases marked `Done` / `Complete` / has a commit hash → **Complete**
   - Some phases done, others pending → **In Progress** (note the current
     phase name and the next incomplete phase)
   - No phases done (all `Not Started` / empty) → **Ready**

2. **No Progress Tracker?** Check for other completion signals:
   - Sections with `**Status:** Done` or `**Status:** Complete` → count as done
   - If all phase sections have completion markers → **Complete**
   - If some do → **In Progress**
   - If the plan has phases but no status indicators at all → **Needs Review**
     (old-format plan; status is ambiguous — may be complete, may not be)
   - Only classify as **Ready** if the plan clearly hasn't been started
     (e.g., freshly created by `/draft-plan`)

### Step 4 — Determine priority for "Ready to Run" plans

Rank ready plans by:

1. **Plans referenced by `/fix-issues` "too complex" skips** — check
   `SPRINT_REPORT.md` for "Skipped -- Too Complex" entries that reference a
   plan file. Those plans are highest priority (blocking batch fixes).
2. **Recently created plans** — sort by git creation date (newest first).
   Use `git log --diff-filter=A --format=%aI -- <file>` to get each file's
   initial commit date. This avoids conflating "recently written" with
   "recently touched by any edit."
3. **Alphabetical** — tiebreaker.

Assign priority labels: **High** (referenced by fix-issues skips), **Medium**
(recent), **Low** (older/alphabetical fallback).

### Step 5 — Write `plans/PLAN_INDEX.md`

Write the index file with this structure:

```markdown
# Plan Index

Auto-generated by `/plans rebuild`. Last rebuilt: YYYY-MM-DD HH:MM ET.

## Ready to Run

| Plan | Phases | Next Phase | Priority | Notes |
|------|--------|------------|----------|-------|
| [EXAMPLE_PLAN.md](EXAMPLE_PLAN.md) | 5 | 1 -- Setup | High | Referenced by fix-issues skip #NNN |

## In Progress

| Plan | Phases | Current Phase | Next Phase | Notes |
|------|--------|---------------|------------|-------|
| [FEATURE_PLAN.md](FEATURE_PLAN.md) | 8 | 4b -- Phase B | 4c -- Phase C | 4 of 8 phases done |

## Needs Review

Old-format plans without progress trackers. Status is ambiguous — may be
complete, partially done, or not started. Triage these once: mark as
Complete, move to Ready, or rewrite with `/draft-plan plans/FILE.md`.

| Plan | Phases | Issue | Notes |
|------|--------|-------|-------|
| [BETTER_SCOPE_PLAN.md](BETTER_SCOPE_PLAN.md) | 3 | No progress tracker | Check if scope overhaul was implemented |

## Complete

| Plan | Phases | Notes |
|------|--------|-------|
| [RUNTIME_PARITY_META.md](RUNTIME_PARITY_META.md) | 4 | Meta-plan — all sub-plans done |
|   ↳ [RUNTIME_SIGNAL_FLOW_BLOCKS.md](RUNTIME_SIGNAL_FLOW_BLOCKS.md) | 3 | Sub-plan of RUNTIME_PARITY_META |
|   ↳ [RUNTIME_DEPLOY_SERIALIZATION.md](RUNTIME_DEPLOY_SERIALIZATION.md) | 2 | Sub-plan of RUNTIME_PARITY_META |
| [CODEGEN_PLAN.md](CODEGEN_PLAN.md) | 3 | All phases done |

## Reference (not executable)

| File | Type | Description |
|------|------|-------------|
| [OVERVIEW.md](OVERVIEW.md) | Reference | Project overview |
| [ISSUES_PLAN.md](ISSUES_PLAN.md) | Issue Tracker | Master issue index |
| Block Plans (`plans/blocks/`) | Reference | {BLOCK_IMPLS}/{BLOCK_PLANS} implemented |
```

**Notes for each section:**
- If a section would be empty, include the table header with a single row:
  `| (none) | | | | |`
- Use relative links (just the filename, since index is in `plans/`)
- Count phases by counting `## Phase` headings (or progress tracker rows)
- For "In Progress" plans, identify both the current phase (last done) and
  the next phase (first incomplete)
- **Meta-plan grouping:** If a plan is a meta-plan (has `delegate /run-plan`
  phases referencing other plan files), indent its sub-plans beneath it
  with `↳` prefix. Sub-plans should NOT appear as separate top-level entries.
  This makes the hierarchy visible — e.g., RUNTIME_PARITY_META owns
  RUNTIME_SIGNAL_FLOW_BLOCKS and RUNTIME_DEPLOY_SERIALIZATION.

## Mode: Next (`/plans next`)

1. Read `plans/PLAN_INDEX.md`
2. If the file does not exist, **auto-run rebuild** to create it first.
3. Find the first entry in the "Ready to Run" table (highest priority)
4. If found, output:
   > **Next plan to run:** `EXAMPLE_PLAN.md`
   > Phases: 5, starting at Phase 1 -- Setup
   > Priority: High (referenced by fix-issues skip #NNN)
   >
   > Run with: `/run-plan plans/EXAMPLE_PLAN.md`
5. If the "Ready to Run" table is empty or has only `(none)`:
   > No plans ready to run. All executable plans are either in progress or complete.
   > Check "In Progress" plans in the index for plans that need attention.
6. **Exit.**

## Key Rules

- **Rebuild is idempotent** — running it twice produces the same result
  (assuming no plan files changed between runs).
- **Never modify plan files** — the index is read-only metadata. It reads
  plans but never changes them.
- **Skip `plans/blocks/` subdirectories** — those are block-specific plan
  files managed by `/add-block`, not executable plans.
- **Skip `PLAN_INDEX.md` itself** — don't index the index.
- **Relative links** — since the index lives in `plans/`, links are just
  filenames (e.g., `[FOO.md](FOO.md)`), not `plans/FOO.md`.
- **Timezone** — always use America/New_York (ET) for the "Last rebuilt"
  timestamp.
