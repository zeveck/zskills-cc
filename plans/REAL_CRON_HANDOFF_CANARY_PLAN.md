# Real Cron Handoff Canary Plan

## Goal

Prove that `run-plan finish auto direct` can enable the ZSkills scheduled
runner, hand off across real OS cron ticks, execute five separate phases, write
logs/report state, and disable the repo cron entry when no active schedules
remain.

This is intentionally small. Each phase writes one tracked marker file under
`reports/cron-canary/` so success is visible in git history and easy to revert
after the canary.

## Scope

In scope:

- Real OS cron dispatch through `scripts/zskills-scheduler.sh runner-enable`.
- `run-plan finish auto direct` handoff between phases.
- One phase per top-level scheduled turn.
- `.zskills/schedules/` state changes and `.zskills/cron-runner.log` evidence.
- Automatic `runner-disable-if-idle` behavior after completion.

Out of scope:

- GitHub PR creation or merge.
- Product code changes.
- Long-running tests.
- External network dependencies.

## Safety Rules

- Only edit files under `reports/cron-canary/` and this plan/report state.
- Do not edit source code, generated skills, helper scripts, configs, or tests.
- Do not manually call `scripts/zskills-run-due.sh` while this canary is
  running; the point is to prove OS cron fires it.
- If cron does not fire within two minutes of a scheduled handoff, stop and
  report the schedule file, runner status, and `.zskills/cron-runner.log`.
- If the plan fails or is stopped, run
  `scripts/zskills-scheduler.sh runner-disable-if-idle --repo-path .` only after
  confirming no active schedules remain.

## Progress

| Phase | Status | Summary |
|---|---|---|
| Phase 1: Runner Bootstrap Marker | Done | Created `reports/cron-canary/phase-1.md` and enabled the scheduled runner. |
| Phase 2: First Cron Handoff Marker | Done | Created `reports/cron-canary/phase-2.md` after cron handoff reached this retry turn. |
| Phase 3: Middle Handoff Marker | Done | Created `reports/cron-canary/phase-3.md` after the second cron-driven handoff. |
| Phase 4: Penultimate Handoff Marker | Next | Prove the fourth scheduled turn still sees correct plan state. |
| Phase 5: Completion And Idle Cleanup Marker | Pending | Create final marker and verify idle cleanup evidence. |

## Phase 1: Runner Bootstrap Marker

Status: Done

### Objective

Start the canary with `run-plan finish auto direct`, allow the skill to enable
the scheduled runner automatically, and write the first tracked marker.

### Implementation

Create:

- `reports/cron-canary/phase-1.md`

Content:

```markdown
# Cron Canary Phase 1

status: complete
expected-next: phase-2
```

Then continue with normal `run-plan finish auto direct` behavior. Do not invoke
the due runner manually.

### Acceptance Criteria

- `reports/cron-canary/phase-1.md` exists with the exact content above.
- The plan progress table marks Phase 1 `Done` and Phase 2 `Next`.
- A one-shot schedule exists for the next `run-plan <this plan> finish auto
  direct` turn.
- `scripts/zskills-scheduler.sh runner-status --repo-path .` reports the
  scheduled runner is enabled.

### Verification

Run:

```bash
test -f reports/cron-canary/phase-1.md
rg "status: complete" reports/cron-canary/phase-1.md
scripts/zskills-scheduler.sh runner-status --repo-path .
scripts/zskills-scheduler.sh list
```

## Phase 2: First Cron Handoff Marker

Status: Done

### Objective

Prove the first scheduled cron handoff reached a fresh top-level `run-plan`
turn and selected the next incomplete phase.

### Implementation

Create:

- `reports/cron-canary/phase-2.md`

Content:

```markdown
# Cron Canary Phase 2

status: complete
expected-next: phase-3
```

### Acceptance Criteria

- `reports/cron-canary/phase-1.md` still exists unchanged.
- `reports/cron-canary/phase-2.md` exists with the exact content above.
- `.zskills/cron-runner.log` exists and contains at least one cron runner
  invocation after Phase 1 completed.
- The Phase 1 one-shot schedule is stopped or complete, and a later one-shot
  schedule exists for Phase 3.

### Verification

Run:

```bash
test -f reports/cron-canary/phase-1.md
test -f reports/cron-canary/phase-2.md
test -s .zskills/cron-runner.log
scripts/zskills-scheduler.sh list
```

## Phase 3: Middle Handoff Marker

Status: Done

### Objective

Prove the auto pipeline survives a second cron-driven handoff and continues to
read the plan state correctly.

### Implementation

Create:

- `reports/cron-canary/phase-3.md`

Content:

```markdown
# Cron Canary Phase 3

status: complete
expected-next: phase-4
```

### Acceptance Criteria

- Phase 1, Phase 2, and Phase 3 marker files exist.
- Phase 3 was not executed in the same top-level turn as Phase 2.
- The plan progress table marks Phase 3 `Done` and Phase 4 `Next`.
- The scheduled runner remains enabled while Phase 4 is pending.

### Verification

Run:

```bash
test -f reports/cron-canary/phase-1.md
test -f reports/cron-canary/phase-2.md
test -f reports/cron-canary/phase-3.md
scripts/zskills-scheduler.sh runner-status --repo-path .
scripts/zskills-scheduler.sh list
```

## Phase 4: Penultimate Handoff Marker

Status: Pending

### Objective

Prove the fourth cron-driven turn still lands cleanly and schedules the final
phase exactly once.

### Implementation

Create:

- `reports/cron-canary/phase-4.md`

Content:

```markdown
# Cron Canary Phase 4

status: complete
expected-next: phase-5
```

### Acceptance Criteria

- Phase 1 through Phase 4 marker files exist.
- Exactly one active schedule remains for this canary after Phase 4.
- The next active schedule points back to this plan with `finish auto`.

### Verification

Run:

```bash
test -f reports/cron-canary/phase-4.md
scripts/zskills-scheduler.sh list
rg "REAL_CRON_HANDOFF_CANARY_PLAN.md finish auto" .zskills/schedules -g '*.json'
```

## Phase 5: Completion And Idle Cleanup Marker

Status: Pending

### Objective

Complete the canary, verify all marker files exist, and confirm the scheduled
runner is removed once there are no active schedules left.

### Implementation

Create:

- `reports/cron-canary/phase-5.md`

Content:

```markdown
# Cron Canary Phase 5

status: complete
expected-next: none
```

After normal final plan completion, run or confirm the run-plan cleanup step:

```bash
scripts/zskills-scheduler.sh runner-disable-if-idle --repo-path .
```

### Acceptance Criteria

- Phase 1 through Phase 5 marker files exist.
- The plan progress table marks all five phases `Done`.
- No active schedule remains for this canary.
- `scripts/zskills-scheduler.sh runner-status --repo-path .` returns missing
  runner status after idle cleanup.
- `.zskills/cron-runner.log` exists and shows cron fired during the canary.

### Verification

Run:

```bash
for n in 1 2 3 4 5; do test -f "reports/cron-canary/phase-$n.md"; done
scripts/zskills-scheduler.sh list
scripts/zskills-scheduler.sh runner-status --repo-path .; test "$?" -eq 4
test -s .zskills/cron-runner.log
```

## Completion Criteria

The canary is complete when:

- all five phases are `Done`
- `reports/cron-canary/phase-1.md` through `phase-5.md` exist
- every phase after Phase 1 was reached by OS cron handoff, not a manual
  `zskills-run-due.sh` call
- no active canary schedules remain
- the managed repo cron entry has been disabled because the scheduler is idle
