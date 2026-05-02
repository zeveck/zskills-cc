# Real Cron Handoff Canary Plan 2

## Goal

Prove the current ZSkills cron fixes work from a clean schedule path by running
five distinct `run-plan finish auto direct` turns through real OS cron.

This canary uses fresh marker files under `reports/cron-canary-2/` so it cannot
pass by relying on the previous canary's artifacts.

## Scope

In scope:

- Automatic scheduled runner enablement from `run-plan finish auto direct`.
- Real OS cron dispatch for phases 2 through 5.
- One top-level scheduled Codex turn per phase.
- Correct cron PATH handling for Python and Codex.
- Correct use of the scheduled Codex runner command.
- `.zskills/schedules/`, `.zskills/logs/`, and `.zskills/cron-runner.log`
  evidence.
- Idle cleanup after the final phase.

Out of scope:

- Product source changes.
- GitHub PR creation.
- External network calls.
- Manually invoking `scripts/zskills-run-due.sh`.

## Safety Rules

- Only edit this plan, `reports/cron-canary-2/`, and the generated plan report.
- Do not edit source code, generated skills, helper scripts, configs, or tests.
- Do not manually call `scripts/zskills-run-due.sh` while this canary is
  running.
- If cron does not fire within two minutes of a scheduled handoff, stop and
  report `scripts/zskills-scheduler.sh list`, runner status, the relevant
  `.zskills/logs/` entry, and `.zskills/cron-runner.log`.
- If a scheduled Codex turn reports `Blocked:`, leave the job blocked and report
  the captured log path.

## Progress

| Phase | Status | Summary |
|---|---|---|
| Phase 1: Bootstrap Fresh Cron Run | Done | Created `reports/cron-canary-2/phase-1.md` and enabled the scheduled runner. |
| Phase 2: Verify First Real Handoff | Done | Created `reports/cron-canary-2/phase-2.md` from a cron-fired Codex turn. |
| Phase 3: Verify Continued Scheduling | Done | Created `reports/cron-canary-2/phase-3.md` from a cron-fired Codex turn. |
| Phase 4: Verify Penultimate Handoff | Done | Created `reports/cron-canary-2/phase-4.md` from a cron-fired Codex turn. |
| Phase 5: Verify Finish And Cleanup | Done | Created the final marker and verified idle scheduler cleanup. |

## Phase 1: Bootstrap Fresh Cron Run

Status: Done

### Objective

Start from an idle scheduler, write the first marker, and let `run-plan finish
auto direct` create the Phase 2 one-shot schedule and enable the cron runner.

### Implementation

Create:

- `reports/cron-canary-2/phase-1.md`

Content:

```markdown
# Cron Canary 2 Phase 1

status: complete
expected-next: phase-2
runner: current-session
```

Then continue with normal `run-plan finish auto direct` behavior. Do not invoke
the due runner manually.

### Acceptance Criteria

- `reports/cron-canary-2/phase-1.md` exists with the exact content above.
- The progress table marks Phase 1 `Done` and Phase 2 `Next`.
- A one-shot schedule exists for the next `run-plan <this plan> finish auto
  direct` turn.
- `scripts/zskills-scheduler.sh runner-status --repo-path .` reports the
  scheduled runner is enabled.

### Verification

Run:

```bash
test -f reports/cron-canary-2/phase-1.md
rg "runner: current-session" reports/cron-canary-2/phase-1.md
scripts/zskills-scheduler.sh runner-status --repo-path .
scripts/zskills-scheduler.sh list
```

## Phase 2: Verify First Real Handoff

Status: Done

### Objective

Prove the first scheduled handoff reached a fresh cron-fired Codex turn using
the current PATH and runner command fixes.

### Implementation

Create:

- `reports/cron-canary-2/phase-2.md`

Content:

```markdown
# Cron Canary 2 Phase 2

status: complete
expected-next: phase-3
runner: os-cron
```

### Acceptance Criteria

- Phase 1 and Phase 2 marker files exist.
- `.zskills/cron-runner.log` contains a cron invocation after Phase 1 completed.
- A `.zskills/logs/run-plan-real-cron-handoff-canary-plan-2-*` log exists for
  this scheduled turn.
- The previous one-shot schedule is stopped or complete.
- A later one-shot schedule exists for Phase 3.

### Verification

Run:

```bash
test -f reports/cron-canary-2/phase-1.md
test -f reports/cron-canary-2/phase-2.md
test -s .zskills/cron-runner.log
scripts/zskills-scheduler.sh list
```

## Phase 3: Verify Continued Scheduling

Status: Done

### Objective

Prove the scheduler can carry state across a second real cron handoff without
manual due-runner execution.

### Implementation

Create:

- `reports/cron-canary-2/phase-3.md`

Content:

```markdown
# Cron Canary 2 Phase 3

status: complete
expected-next: phase-4
runner: os-cron
```

### Acceptance Criteria

- Phase 1 through Phase 3 marker files exist.
- Phase 3 was not executed in the same top-level turn as Phase 2.
- The progress table marks Phase 3 `Done` and Phase 4 `Next`.
- The scheduled runner remains enabled while Phase 4 is pending.

### Verification

Run:

```bash
test -f reports/cron-canary-2/phase-1.md
test -f reports/cron-canary-2/phase-2.md
test -f reports/cron-canary-2/phase-3.md
scripts/zskills-scheduler.sh runner-status --repo-path .
scripts/zskills-scheduler.sh list
```

## Phase 4: Verify Penultimate Handoff

Status: Done

### Objective

Prove the fourth phase schedules exactly one final cron handoff.

### Implementation

Create:

- `reports/cron-canary-2/phase-4.md`

Content:

```markdown
# Cron Canary 2 Phase 4

status: complete
expected-next: phase-5
runner: os-cron
```

### Acceptance Criteria

- Phase 1 through Phase 4 marker files exist.
- Exactly one active schedule remains for this canary after Phase 4.
- The active schedule command points back to this plan with `finish auto`.

### Verification

Run:

```bash
test -f reports/cron-canary-2/phase-1.md
test -f reports/cron-canary-2/phase-2.md
test -f reports/cron-canary-2/phase-3.md
test -f reports/cron-canary-2/phase-4.md
scripts/zskills-scheduler.sh list
```

## Phase 5: Verify Finish And Cleanup

Status: Done

### Objective

Prove the final cron handoff completes the plan and idle cleanup removes the
managed scheduled runner.

### Implementation

Create:

- `reports/cron-canary-2/phase-5.md`

Content:

```markdown
# Cron Canary 2 Phase 5

status: complete
expected-next: none
runner: os-cron
```

### Acceptance Criteria

- Phase 1 through Phase 5 marker files exist.
- The progress table marks every phase `Done`.
- `scripts/zskills-scheduler.sh list` reports no active ZSkills schedules.
- `scripts/zskills-scheduler.sh runner-status --repo-path .` reports no
  scheduled runner is installed for this repo.
- `.zskills/logs/` contains logs for the scheduled Phase 2 through Phase 5
  turns.

### Verification

Run:

```bash
test -f reports/cron-canary-2/phase-1.md
test -f reports/cron-canary-2/phase-2.md
test -f reports/cron-canary-2/phase-3.md
test -f reports/cron-canary-2/phase-4.md
test -f reports/cron-canary-2/phase-5.md
scripts/zskills-scheduler.sh list
scripts/zskills-scheduler.sh runner-status --repo-path .; test "$?" -eq 4
find .zskills/logs -maxdepth 2 -type f | sort | rg 'real-cron-handoff-canary-plan-2'
```
