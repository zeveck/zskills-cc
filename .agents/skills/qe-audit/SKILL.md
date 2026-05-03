---
name: qe-audit
disable-model-invocation: true
argument-hint: "[bash [area]] [every SCHEDULE] [now] | stop | next"
description: >-
  QE audit: check recent commits for test coverage gaps, or bash/stress-test
  features to find bugs. Supports scheduling with every/now/next/stop.
  Usage: /qe-audit [bash [area]] [every SCHEDULE] [now] | stop | next.
---

<!-- ZSKILLS_CODEX_COMPAT_START -->
## Codex Compatibility

This block applies only to the Codex-installed copy of this skill. It is an adapter layer for the original Claude slash-command instructions, not a replacement for the upstream workflow.

Invocation: in Codex, invoke this skill by naming it, for example `run-plan ...`, or by using the original slash command when the user supplied it. Treat `$ARGUMENTS` as the text after the skill name or slash command. Pass only the intended argument tail when one ZSkill calls another.

Tool mapping: if Codex exposes a subagent tool, map Claude `Agent`, `Task`, or subagent dispatch to that tool. Exploration-only work uses an explorer-style agent; implementation work uses a worker-style agent with explicit file/module ownership and instructions not to revert others work; review and devil-advocate work uses a general review agent. If no subagent tool is available, run the subtask inline, clearly label the degraded independence, and do not claim fresh-agent isolation. `Read`, `Grep`, `Glob`, and `Bash` map to shell reads, `rg`, and command execution; manual `Edit`/`Write` operations map to patch-based edits.

Skill calls: when this skill invokes another ZSkill such as `/run-plan`, `/draft-plan`, `/verify-changes`, or `/commit`, load and follow the selected skill instructions from Codex's available skills. If you must read the file directly, prefer `$PROJECT_ROOT/.agents/skills/<skill>/SKILL.md`, then `$HOME/.agents/skills/<skill>/SKILL.md`, then legacy `$HOME/.codex/skills/<skill>/SKILL.md`. Do not recursively re-enter the same skill unless the workflow explicitly requires it. Preserve `ZSKILLS_PIPELINE_ID` and related tracking environment across skill boundaries.

Tracking: tracking files belong under the main repository root at `.zskills/tracking/`, never under `~/.codex/skills`. Resolve the main root with the original `git rev-parse --git-common-dir` pattern. Keep `.zskills/tracking/` ignored. Do not delete or clear tracking except through an explicit user-requested clear-tracking workflow.

Landing modes: preserve `direct`, `cherry-pick`, and `pr`. Explicit `direct`, `pr`, or `cherry-pick` arguments win and should be stripped before downstream phase parsing. Otherwise read `.codex/zskills-config.json`, then `.claude/zskills-config.json`, then fall back to `cherry-pick`. If both config files exist and disagree on landing or main protection, stop before landing and report the conflict. `locked-main-pr` remains the preset name for PR mode with main protection.

Foreground runner bridge: Claude cron tools (`CronList`, `CronCreate`, `CronDelete`) are not the Codex implementation for `run-plan finish auto`. In Codex, `finish auto` must use a visible foreground parent runner that stays attached to the initiating REPL and launches one fresh `codex exec` child chunk per phase. Prefer `scripts/zskills-runner.sh`, then `$PROJECT_ROOT/.agents/skills/scripts/zskills-runner.sh`, then `$HOME/.agents/skills/scripts/zskills-runner.sh`, then legacy `$HOME/.codex/skills/scripts/zskills-runner.sh`. If the runner is unavailable, execute at most one phase, write the normal report/tracking handoff, and do not claim autonomous completion. Child prompts containing `RUNNER-MANAGED CHUNK` must not invoke the runner again; they execute exactly one incomplete phase and stop after durable plan/report/tracking evidence.

Hook fallback: Claude hooks are not enforced by Codex in this environment. Compensate with inline preflight checks before commits, cherry-picks, PR merge/auto-merge, worktree deletion, or tracking cleanup: inspect status, protect unrelated changes, verify branch/mode, and preserve `.zskills/tracking`.

Helper scripts: generated Codex installs include shared helpers under `.agents/skills/scripts/` for project installs or `$HOME/.agents/skills/scripts/` for user installs. Prefer project-local helpers at `$PROJECT_ROOT/scripts/` when present, otherwise use the installed helper path, with `$HOME/.codex/skills/scripts/` as a legacy fallback. `zskills-runner.sh`, `zskills-gate.sh`, and `zskills-post-run-invariants.sh` are Codex foreground-runner helpers. If a required helper is unavailable, use the explicit fallback instructions in the skill and report the degraded procedural path.

See `~/.codex/skills/ZSKILLS_CODEX_INTEGRATION.md` for the shared adapter contract.
<!-- ZSKILLS_CODEX_COMPAT_END -->

# /qe-audit [bash [area]] [every SCHEDULE] [now] | stop | next — Quality Engineering Audit

Two modes of quality assurance:

- **Commit audit** (default) — review recent commits for test coverage gaps,
  missing tests, and bugs. Files GitHub issues for findings.
- **Bash** — adversarial stress-testing of features. Pick a specific area
  or let the agent choose under-tested areas. Try to break things with edge
  cases, unusual inputs, and unexpected workflows.

Both modes file GitHub issues and update `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`. Both are
schedulable. Together they form the quality feedback loop: audit finds gaps →
`/fix-issues` fixes them → audit validates the fixes.

**Ultrathink throughout.**

## Arguments

```
/qe-audit [bash [area]] [every SCHEDULE] [now]
/qe-audit stop | next
```

- **bash** (optional) — switch to bash/stress-test mode instead of commit audit
- **area** (optional, with bash) — specific feature or area to bash. If
  omitted, the agent picks under-tested areas based on coverage data and
  recent changes. Examples: `"undo/redo"`, `"state machine editor"`, `"solver"`,
  `"codegen"`, `"block parameters"`
- **every SCHEDULE** (optional) — self-schedule recurring runs via cron:
  - Accepts intervals: `4h`, `2h`, `30m`, `12h`
  - Accepts time-of-day: `day at 9am`, `day at 14:00`, `weekday at 9am`
  - Without `now`: schedules only, does NOT run immediately
  - With `now`: schedules AND runs immediately
  - Each run re-registers the cron (self-perpetuating)
  - Cron is session-scoped — dies when the session dies
- **now** (optional) — run immediately. When combined with `every`, runs
  immediately AND schedules. Without `every`, `now` is the default behavior
  (bare invocation always runs immediately).
- **stop** — cancel any existing `/qe-audit` cron and exit. **Takes
  precedence over all other arguments.**
- **next** — check when the next scheduled run will fire. **Takes precedence
  over all other arguments except `stop`.**

**Detection:** scan `$ARGUMENTS` for:
- `stop` (case-insensitive) — cancel cron and exit (highest precedence)
- `next` (case-insensitive) — check schedule and exit
- `bash` (case-insensitive) — bash mode (everything after `bash` until
  `every`/`now`/`stop`/`next` is the area description)
- `now` (case-insensitive) — run immediately
- `every` followed by a schedule expression — scheduling mode

Examples:
- `/qe-audit` — audit recent commits now
- `/qe-audit bash` — bash random under-tested features now
- `/qe-audit bash "undo/redo"` — bash a specific feature now
- `/qe-audit bash "solver" every 6h` — schedule solver bashing every 6h
- `/qe-audit every day at 9am` — schedule daily commit audit (first run at 9am)
- `/qe-audit every day at 9am now` — schedule daily + run now
- `/qe-audit every weekday at 9am` — weekday mornings only
- `/qe-audit bash every 12h now` — bash random features every 12h, start now
- `/qe-audit next` — when's the next audit?
- `/qe-audit stop` — cancel scheduled audits

## Now (standalone — just `now` with no mode or schedule)

**Codex scheduler implementation:** In Codex, use the file-backed scheduler when available:

```bash
ZSKILLS_SCHEDULER_HELPER="$PROJECT_ROOT/scripts/zskills-scheduler.sh"
[ -x "$ZSKILLS_SCHEDULER_HELPER" ] || ZSKILLS_SCHEDULER_HELPER="$HOME/.codex/skills/scripts/zskills-scheduler.sh"
ZSKILLS_RUN_DUE_HELPER="$PROJECT_ROOT/scripts/zskills-run-due.sh"
[ -x "$ZSKILLS_RUN_DUE_HELPER" ] || ZSKILLS_RUN_DUE_HELPER="$HOME/.codex/skills/scripts/zskills-run-due.sh"
```

If available, `every <SCHEDULE>` stores a `qe-audit` schedule using the mode/area args with schedule tokens removed; `next` runs `zskills-scheduler.sh next --skill qe-audit`; `stop` runs `zskills-scheduler.sh stop --skill qe-audit`; standalone `now` triggers `qe-audit` and runs due jobs. If unavailable, report unsupported without claiming background work.

If `$ARGUMENTS` contains `every <schedule>`:

1. **Parse the schedule** — convert to a cron expression.

   **For interval-based schedules** (`4h`, `2h`, `30m`): use the CURRENT
   minute as the offset so the first fire is a full interval from now.
   Check the current minute with `date +%M`:
   - `4h` at minute 9 → `9 */4 * * *`
   - `12h` at minute 9 → `9 */12 * * *`
   - `30m` → `*/30 * * * *` (no offset needed for sub-hour)

   **For time-of-day schedules**: offset round minutes by a few:
   - `day at 9am` → `3 9 * * *`
   - `day at 14:00` → `3 14 * * *`
   - `weekday at 9am` → `3 9 * * 1-5`

2. **Deduplicate** — use `CronList` + `CronDelete` to remove any whose
   prompt starts with `Run /qe-audit`.

3. **Construct the cron prompt.** Always include `now` in the cron prompt
   so each cron fire runs immediately AND re-registers itself. Note: this
   `now` is for the CRON's invocation, not the current invocation:
   ```
   Run /qe-audit [bash [area]] every <schedule> now
   ```

4. **Create the cron** — use `CronCreate`:
   - `cron`: the cron expression from step 1
   - `recurring`: true
   - `prompt`: the constructed command from step 3

5. **Confirm** with wall-clock time. **Always show times in America/New_York
   (ET)** — use `TZ=America/New_York date` for conversion:

   If `now` is present:
   > QE audit scheduled every day at 9am. Running now.
   > Next audit after this one: ~9:03 AM ET tomorrow (cron ID XXXX).

   If `now` is NOT present:
   > QE audit scheduled every day at 9am.
   > First run: ~9:03 AM ET tomorrow (cron ID XXXX).
   > Use `/qe-audit next` to check, `/qe-audit stop` to cancel.

6. **If `now` is present:** proceed to the audit/bash.
   **If `now` is NOT present:** **Exit.** The cron fires later.

If `every` is NOT present, skip this phase and proceed to the audit/bash
(bare invocation always runs immediately).

## Mode: Commit Audit (default)

Run when `bash` is NOT present in arguments.

1. **Find the last audit checkpoint** — read the bottom of `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`
   for the last audited commit range and date (format: `*Last audited:
   YYYY-MM-DD — commits <hash> through <hash>*`). If the file doesn't exist
   or has no checkpoint, fall back to `git log --oneline -20`.

2. **List new commits** — `git log --oneline <last_commit>..HEAD`. Skip
   QE-generated commits (messages matching `fix: N QE issues`, `fix: QE batch`,
   `docs: QE audit`, or `test: QE batch`).

3. **If no new commits** — report "no new commits since last audit" and stop.

4. **Audit each commit** — For each commit with code changes, **dispatch
   parallel Explore agents** using the Agent tool (group 4-5 commits per
   agent). Do not audit all commits yourself — dispatch agents for fresh
   eyes on each batch:
   - Read the diff (`git show <hash>`)
   - Read related test files
   - Assess: Are tests good (testing real behavior, not no-ops)? Are there
     coverage gaps? Are there bugs?
   - Rate severity: Critical / High / Medium / Low / Very Low

5. **Create GitHub issues** — For actionable findings (Medium+ severity, or
   Low with clear fix), create issues via `gh issue create`. Include: summary,
   root cause, suggested fix/test, severity, and which commit introduced it.

6. **Update tracker** — Edit `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`:
   - Add new issues to "Open Issues" section
   - Move any resolved issues to "Resolved Issues"
   - Update the audit date and commit range at the bottom

7. **Report** — Summarize findings: issues filed, notable positives, and
   overall assessment. If a cron is active, include the next run time:
   > Audit complete. Filed N issues. Next audit in ~23h 55m (~9:03 AM ET
   > tomorrow, cron XXXX).

### Tips for commit audit
- Skip docs-only, config-only, and log-only commits
- For physics/solver commits, pay extra attention to numerical correctness
- The registration test count in `tests/blocks/registration.test.js` needs
  updating when blocks are added

## Mode: Bash (stress-test)

Run when `bash` IS present in arguments.

1. **Select target area:**
   - If area specified (e.g., `bash "undo/redo"`): use that area
   - If no area specified: pick under-tested areas based on:
     - Files with low test-to-code ratio
     - Features with recent bug fixes (fragile areas)
     - Complex code paths (solver, codegen, state machine engine)
     - Areas not recently audited

2. **Research the target area:**
   - Read the source code for the selected feature
   - Read existing tests — what's already covered?
   - Identify edge cases, boundary conditions, unusual inputs
   - Think adversarially: what could break? What assumptions are fragile?
   - Identify what types of testing apply (see step 3)

3. **Test the area thoroughly** — use ALL applicable methods, not just
   unit tests. The goal is to exercise the feature the way a user would,
   plus adversarial edge cases:

   **a. Manual UI testing** (for editor, UI, interaction features):
   - Use `/manual-testing` recipes with playwright-cli
   - Exercise real workflows: add blocks, connect ports, run simulations,
     edit parameters, undo/redo, drag, resize, delete
   - Test edge cases manually: rapid clicks, empty inputs, overlapping
     elements, browser resize during interaction
   - Take screenshots as evidence of bugs found

   **b. Codegen & deployment testing** (for codegen, solver, block changes):
   - Pick relevant example models from `examples/`
   - Deploy: generate Rust → `cargo build` → run binary
   - Compare Rust output against JS simulation (same model, same params)
   - Test with multiple example models, not just one
   - For bulk sweeps, dispatch parallel agents (~10 models per agent)

   **c. Adversarial unit tests** (for all areas):
   - Edge cases (empty inputs, zero values, NaN, Infinity, negative numbers)
   - Boundary conditions (max array size, deeply nested structures)
   - Race conditions (rapid undo/redo, concurrent operations)
   - Invalid state (corrupted model data, missing references)
   - Unusual workflows (delete while editing, paste into readonly)

   **d. Integration testing** (for cross-cutting features):
   - Full workflows end-to-end: create model → configure → simulate →
     export → deploy → verify output
   - Cross-feature interactions: state machine chart inside subsystem,
     physics module with controlled sources, etc.

4. **Run automated tests:**
   ```bash
   npm run test:all
   ```
   - Tests that PASS: the feature handles the edge case correctly. Good.
   - Tests that FAIL: found a bug. File a GitHub issue.
   - Tests that CRASH: found a serious bug. File a high-severity issue.

5. **File GitHub issues** for each failure (from any testing method):
   - Include: what was tested, expected vs actual behavior, test code,
     severity rating, suggested fix
   - Tag with appropriate labels

6. **Update `the QE issues tracker (e.g., `plans/QE_ISSUES.md`)`** with new findings.

7. **Clean up test files:**
   - Keep passing adversarial tests (they're valuable regression tests)
   - Keep failing tests too — do NOT remove or comment them out. CLAUDE.md
     says "NEVER weaken tests." A failing bash test is evidence of a real
     bug. Mark them with `{ todo: 'Bug found by QE bash — see #NNN' }` so
     they're skipped but preserved, and file a GitHub issue for each.
   - **ONLY use `todo` for bugs you just DISCOVERED during this bash
     session.** NEVER use `todo` to skip a test that was passing before
     and now fails due to your changes — that's weakening, not discovery.
   - Run `npm run test:all` before committing — all suites must pass
     (todo-skipped tests are acceptable)
   - Commit all tests (passing + skipped) with descriptive message

8. **Report** — Summarize:
   - Area bashed
   - Testing methods used (manual UI, codegen deployment, adversarial
     unit tests, integration)
   - Scenarios tested (count per method)
   - Bugs found (count, severity, method that found them)
   - Issues filed (numbers)
   - Passing tests committed
   - Example models deployed and verified (if applicable)
   - Screenshots taken (if manual testing)
   - If a cron is active, include the next run time

## Key Rules

- **Never weaken tests** — if a bash test reveals a real bug, file an issue.
  Don't make the test pass by loosening assertions.
- **`every` implies autonomous operation** — scheduled audits run without
  user approval.
- **Deduplicate crons** — always remove existing `/qe-audit` crons before
  creating a new one.
- **Crons are session-scoped** — they expire when the session dies.
- **File issues, don't fix inline** — QE audit finds problems. `/fix-issues`
  fixes them. Keep the separation clean.
- **Ultrathink** — use careful, thorough reasoning. Read code, understand
  what changed and why, verify correctness.
