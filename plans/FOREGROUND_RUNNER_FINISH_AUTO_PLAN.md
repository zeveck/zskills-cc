# Foreground Runner Finish Auto Plan

## Goal

Make Codex `run-plan finish auto` feel continuous in the initiating REPL while
still giving each phase a semi-fresh worker context.

The default Codex path should be a foreground parent runner that launches one
fresh `codex exec` child chunk per phase, validates durable evidence after each
chunk, prints orchestration progress in the current session, and resumes from
plan/report/tracking state after interruption.

## Design Decision

Adopt a foreground runner default for Codex `run-plan finish auto`.

Remove OS cron from Codex `run-plan finish auto`. The value to preserve from
Claude is the user experience: continuous visible progress in the original
interaction. The value to preserve from chunking is implementation freshness:
each phase worker gets a new `codex exec` context so long plans do not become a
single fatigued agent loop.

The upstream Claude skill describes cron as session-scoped and says it dies when
the session dies. That means durable execution absent the REPL was not the core
ZSkills value. For Codex, an OS cron bridge preserves the mechanism less well
than it harms the experience, because later phase output leaves the initiating
REPL and must be gathered from logs.

## Non-Goals

- Do not blindly import the full `zskills-codex` repository shape.
- Do not replace zskills-cc's generated/overlay architecture.
- Do not change generated Claude skills.
- Do not make OS cron part of normal `run-plan finish auto`.
- Do not require real GitHub PR canaries in this plan.

## Compatibility Contract

Canonical support path:

- Keep zskills-cc's current support helper convention:
  - project source helpers live in `scripts/`
  - generated Codex helpers live in `.agents/skills/scripts/`
  - global Codex helpers live in `$HOME/.agents/skills/scripts/`
- Do not introduce `.agents/zskills-support/` in zskills-cc unless a later plan
  intentionally changes the install shape. The runner lookup text must match
  the generated helper path above.

Generation separation:

- Split generator support script lists into common vs Codex-only if needed.
- New runner/gate/invariant helpers are Codex-only unless proven useful and
  harmless for Claude.
- Claude generation must not receive runner-specific adapter text or helper
  requirements.

Config and landing defaults:

- Keep zskills-cc config precedence unless a separate config-migration plan
  changes it:
  - `.codex/zskills-config.json`
  - `.claude/zskills-config.json`
  - fallback defaults
- Runner reads at least:
  - `execution.landing`, default `cherry-pick`
  - `execution.branch_prefix`, default `feat/`
  - `execution.base_branch`, default `main` if absent
  - `execution.remote`, default `origin` if absent
  - `runner.max_chunks`, default `10`
  - `runner.chunk_timeout_seconds`, default suitable for tests and overrideable
  - `runner.idle_timeout_seconds`, default suitable for tests and overrideable
  - `runner.sandbox`, default `workspace-write`
  - `runner.approval_policy`, default `never`
  - `runner.allow_direct_unattended`, default `false`
- Direct unattended mode is refused unless explicitly enabled.

Identity and resume:

- Use a stable `plan_key` from normalized repo-relative plan path plus a short
  hash so same-basename plans do not collide.
- Use a human-readable `plan_slug` for report names, but do not use it alone
  for locks/tracking identity.
- Resume by reading plan/report/tracking state, not parent memory.

Durable evidence gates:

- A non-final chunk must produce or update:
  - plan progress
  - report content
  - `handoff.run-plan.<tracking-id>`
  - run-plan step markers
  - verifier requirement/completion/fulfilled markers
- A final chunk must produce or update:
  - plan completion
  - report content
  - `step.run-plan.<tracking-id>.land`
  - `fulfilled.run-plan.<tracking-id>`
  - verifier requirement/completion/fulfilled markers
- Report validation must check for:
  - `## Phase`
  - `Status:`
  - tests run
  - verification result
  - landing result
  - remaining phases
  - scope assessment
- Unexpected dirty project artifacts block continuation.

Foreground visibility:

- The parent runner must stream or relay child progress into the current REPL,
  not only write logs.
- Tests must assert child-emitted progress text appears in parent command
  output.

## Progress

| Phase | Status | Summary |
| --- | --- | --- |
| Phase 1: Runner Support Scripts | Pending | Add foreground runner/gate/invariant helpers in zskills-cc style. |
| Phase 2: Run-Plan Overlay And Adapter | Pending | Make foreground runner the Codex finish-auto path and remove cron finish-auto guidance. |
| Phase 3: Generation And Install Integration | Pending | Include runner helpers in generated Codex skills and preserve cross-client checks. |
| Phase 4: Runner Tests And Canary Harness | Pending | Add fake-child tests for foreground visibility, fresh chunks, validation, and resume. |
| Phase 5: Regenerate, Verify, And Report | Pending | Regenerate checked-in skills, run fidelity/install tests, and document the decision. |

## Phase 1: Runner Support Scripts

Status: Pending

### Objective

Add zskills-cc-native support scripts for foreground chunk orchestration and
durable evidence validation.

### Implementation

Create `scripts/zskills-runner.sh`.

Use `zskills-codex` as reference, but keep the first version focused:

- command shape:
  - `zskills-runner.sh run-plan <plan> finish auto [direct|cherry-pick|pr] [--repo PATH]`
  - `zskills-runner.sh status <plan> [--repo PATH]`
  - `zskills-runner.sh stop <plan> [--repo PATH]`
- foreground parent process stays attached to stdout/stderr and prints:
  - resolved plan/config
  - `chunk N start`
  - child command/log path
  - child exit status
  - validation result
  - next chunk or completion reason
- launch each phase as a fresh `codex exec` child process.
- child prompt must contain a clear `RUNNER-MANAGED CHUNK` contract.
- stream child stdout to parent output while also writing logs, or emit
  periodic child-output excerpts from the event log.
- never use `codex exec resume`.
- acquire a per-plan lock under `.zskills/runner/`.
- refuse unsafe git states before starting:
  - merge/rebase/cherry-pick residue
  - unresolved conflicts
  - unexpected dirty project artifacts, except the runner lock/log state
- implement timeout and idle-timeout stops.
- default child sandbox should be configurable, with a safe default and test
  override. Do not use dangerous bypass flags.
- write JSON/text logs under `.zskills/logs/`.
- support interruption/resume by deriving state from plan/report/tracking files,
  not parent chat memory.
- check stop marker before each chunk and exit with a distinct stop reason.
- compute stable plan identity from repo-relative path plus short hash.

Create `scripts/zskills-gate.sh`.

Minimum gate behavior:

- verify `.zskills/tracking/` is ignored if present
- verify plan file exists
- verify report file exists when expected
- verify run-plan markers for a tracking id:
  - `step.run-plan.<id>.implement`
  - `step.run-plan.<id>.verify`
  - `step.run-plan.<id>.report`
- verify verifier markers for a tracking id:
  - `requires.verify-changes.<id>`
  - `step.verify-changes.<id>.tests-run`
  - `step.verify-changes.<id>.complete`
  - `fulfilled.verify-changes.<id>`
- for continuing chunks, require `handoff.run-plan.<id>`
- for final completion, require:
  - `step.run-plan.<id>.land`
  - `fulfilled.run-plan.<id>`
- block unexpected dirty project artifacts outside ignored `.zskills/`.
- validate report substance using the durable evidence gates in the
  compatibility contract.

Create `scripts/zskills-post-run-invariants.sh` or adapt the existing
`post-run-invariants` behavior under that name.

Minimum invariant behavior:

- report exists
- no in-progress progress-table rows remain after final completion
- expected worktree/branch cleanup can be checked when data is available
- warnings, not hard failures, for remote/base freshness in offline tests

### Acceptance Criteria

- `bash -n` passes for all new scripts.
- `zskills-runner.sh --help` documents the foreground runner behavior.
- `zskills-runner.sh status <plan>` works in a minimal git repo.
- A fake `CODEX_BIN` can be used for tests without invoking real Codex.

## Phase 2: Run-Plan Overlay And Adapter

Status: Pending

### Objective

Change Codex `run-plan finish auto` instructions so foreground runner-backed
execution is the only supported autonomous finish path.

### Implementation

Update `templates/codex-compat-block.md`:

- Replace the current scheduler-default wording with:
  - `run-plan finish auto` defaults to the foreground runner.
  - the parent runner remains visible in the current REPL.
  - each phase runs in a fresh child `codex exec`.
  - child chunks must not invoke the runner recursively.
  - if no runner is available, run one phase and provide a handoff instead of
    pretending autonomous completion is available.
- Keep tracking, landing mode, subagent, and hook fallback guidance.
- Remove automatic scheduler/cron enablement from finish-auto guidance.

Update `codex-overlays/run-plan.patch`:

- In the arguments section, make `finish auto` describe foreground runner
  behavior instead of cron-fired top-level turns.
- Add explicit detection language:
  - plain `finish auto` must invoke `zskills-runner.sh`.
  - `every <schedule>`, `next`, and `stop` should no longer be described as
    part of `run-plan finish auto`. If retained elsewhere, they are separate
    scheduled workflow features, not this plan's autonomous finish path.
- Replace the Codex scheduler section with "Codex foreground runner".
- In Phase 5c:
  - replace Codex one-shot cron override with runner-managed chunk contract.
  - make stale CronCreate prose clearly Claude-only and non-authoritative for
    Codex.

Update `codex-overlays/research-and-go.patch` if needed:

- Since `research-and-go` relies on `run-plan finish auto`, remove automatic
  cron enablement.
- Ensure it delegates to the new foreground runner-backed run-plan path.

### Acceptance Criteria

- Generated Codex `run-plan/SKILL.md` states foreground runner is the default
  for plain `finish auto`.
- Generated Codex `run-plan/SKILL.md` no longer says plain `finish auto`
  auto-enables cron, uses one-shot cron jobs, or routes later phase output to
  scheduler logs.
- Generated Claude skills contain no Codex adapter text.
- The overlay manifest hashes are updated.

## Phase 3: Generation And Install Integration

Status: Pending

### Objective

Make the foreground runner available wherever zskills-cc installs generated
Codex skills, without changing Claude installs.

### Implementation

Update `scripts/generate-codex-skills.py`:

- include new runner/gate/invariant helper scripts in Codex support output.
- avoid copying Codex-only runner helpers into generated Claude output unless
  tests prove they remain inert and adapter-free there.
- keep Claude output clean.
- include the new helper hashes in `generation-manifest.json`.

Update `scripts/zskills-install.sh` if needed:

- ensure project `.agents/skills/scripts/` receives the new scripts.
- preserve unrelated user/project skills as before.

Update `scripts/verify-generated-zskills.py` and
`tests/test-zskills-fidelity.sh`:

- assert generated Codex output includes `zskills-runner.sh`.
- assert generated `run-plan` mentions foreground runner.
- stop asserting that `run-plan finish auto` requires `runner-status`.
- assert generated Claude output does not mention foreground runner, runner
  managed chunks, or Codex-only runner helper requirements.

Update README:

- explain why foreground runner is the default:
  - continuous visible orchestration in the initiating REPL
  - fresh child context per phase
  - durable validation between chunks
- document explicit background scheduler mode only if retained.
- remove cron from the recommended `finish auto` path.

### Acceptance Criteria

- `bash tests/test-zskills-install.sh` passes.
- Generated `.agents/skills` matches fresh generated Codex output.
- `.claude/skills` remains upstream-clean.

## Phase 4: Runner Tests And Canary Harness

Status: Pending

### Objective

Prove the foreground runner behavior mechanically without relying on a long
real Codex canary first.

### Implementation

Add `tests/test-zskills-runner.sh`.

Use a temporary git repo plus a fake `codex` executable. The fake child should
read the runner-managed prompt and mutate plan/report/tracking state in a
controlled way.

Test cases:

- `status` prints resolved plan/report/tracking paths.
- same-basename plan paths get distinct plan keys, tracking directories, locks,
  and report paths.
- config precedence and defaults resolve predictably.
- direct unattended mode is refused by default.
- direct unattended with dirty tree is refused even when explicitly enabled.
- direct two-phase run:
  - parent output includes `chunk 1` and `chunk 2`
  - parent output includes fake child progress text, not only runner summaries
  - fake child is invoked twice with no `resume`
  - each child receives `RUNNER-MANAGED CHUNK`
  - plan and report update after each chunk
  - tracking has handoff after non-final chunk
  - tracking has final fulfilled marker after final chunk
  - runner exits complete
- resume after interruption:
  - first invocation runs one chunk and stops via max-chunks or stop marker
  - second invocation resumes and completes the next phase from durable state
- no-progress failure:
  - fake child exits zero but does not change plan/report/tracking
  - runner blocks and does not claim completion
- missing handoff failure:
  - non-final chunk lacks `handoff.run-plan.*`
  - runner blocks
- missing verifier failure:
  - chunk lacks verifier markers
  - runner blocks
- missing report/scope failure:
  - chunk lacks required report content
  - runner blocks
- premature final marker failure:
  - non-final chunk writes final run-plan marker
  - runner blocks
- dirty artifact failure:
  - child leaves an unexpected untracked file
  - runner blocks
- timeout/idle timeout path using fake child sleep.
- stop marker:
  - `stop <plan>` writes marker
  - runner sees it before the next chunk and exits with stopped status
- scheduler separation:
  - plain `finish auto` tests must not install, enable, or require cron.
  - if scheduler helpers remain for other skills, their tests stay separate
    from `run-plan finish auto`.

### Acceptance Criteria

- `bash tests/test-zskills-runner.sh` passes.
- `bash tests/test-zskills-scheduler.sh` still passes if retained.
- The fake runner logs prove each phase used a fresh child invocation.
- The runner output is visible in the parent command output.

## Phase 5: Regenerate, Verify, And Report

Status: Pending

### Objective

Regenerate checked-in skills, run the full suite, and produce a clear final
report.

### Implementation

- Regenerate Codex skills into `.agents/skills`.
- Regenerate/check Claude skills as needed.
- Run:
  - `bash tests/test-zskills-runner.sh`
  - `bash tests/test-zskills-scheduler.sh` if retained
  - `bash tests/test-zskills-install.sh`
  - `bash tests/test-zskills-fidelity.sh`
  - `python .agents/skills/verify-zskills-codex.py`
- Optionally run a real disposable Codex canary after fake tests pass:
  - two or three tiny cherry-pick phases
  - foreground runner default
  - `--sandbox danger-full-access` only in a disposable repo if required by
    this container
  - direct canary only as an explicit override test, not as the main proof

### Acceptance Criteria

- Full test suite passes.
- Checked-in generated skill output has no drift.
- README states the design decision and user-facing behavior.
- Final report includes:
  - design choice
  - pros/cons
  - files changed
  - verification commands
  - remaining risks
