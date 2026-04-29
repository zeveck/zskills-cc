# ZSkills Cross-Client Fidelity Plan

## Goal

Improve fidelity to original ZSkills intent for both Codex and Claude while
keeping the door open to changes that are objectively better for both clients.

The target outcome is:

- Claude keeps near-original fidelity by consuming upstream ZSkills with no
  Codex fallback pollution.
- Codex gains higher runtime fidelity through generated overlays, shims, and
  explicit emulation of missing Claude affordances where practical.
- Shared helper scripts and tracking behavior remain client-neutral.
- Direct, cherry-pick, and PR modes remain first-class.
- `.zskills/tracking` remains the single project-local tracking filesystem.
- Subagents and other skills are used whenever available, with honest fallback
  labels when they are not.

## Current Assessment

Current Codex fidelity is roughly 75-85%. The core operating model works:
plans, phases, worktrees, landing modes, skill chaining, and tracking are
preserved. The fidelity loss is mostly runtime affordance loss:

- Claude cron tools are not available to Codex.
- Claude hooks do not enforce Codex behavior.
- Claude Agent/Task semantics only map cleanly when Codex exposes subagents.
- Some copied skill snippets still require adapter interpretation.

Current Claude fidelity using the Codex-modified copies is roughly 85-92% if
Claude respects the Codex-only markers, but lower if Claude follows fallback
instructions literally. The safer model is not to ask Claude to consume the
Codex-modified copies directly.

## Design Principles

1. **Upstream remains canonical.**
   Do not hand-maintain a single mixed Claude/Codex skill body as the source of
   truth. Treat `zeveck/zskills` upstream as canonical for Claude behavior.

2. **Codex gets a generated overlay.**
   Generate Codex-installed skills from upstream plus a small set of explicit
   patches. The generated copies live under `~/.codex/skills`.

3. **Shared behavior moves to helper scripts.**
   Anything that must behave identically across clients, such as tracking
   cleanup, config reading, and landing mode resolution, should live in
   scripts rather than repeated prompt snippets.

4. **Runtime gaps are named, not hidden.**
   Codex should not claim native cron, hooks, or fresh-agent isolation when the
   active runtime does not provide them.

5. **Better-than-original changes require agreement.**
   Changes that alter original ZSkills behavior for Claude should be proposed
   with a clear argument, reviewed, and accepted before becoming canonical.

## Proposed Architecture

### Layer 1: Source States

Maintain three explicit states:

1. **Pristine upstream checkout** — clean `zeveck/zskills` clone, no
   uncommitted edits, used as comparison baseline.
2. **Local patch queue** — reviewed candidate improvements, each with
   rationale, tests, and intended target: upstream Claude, Codex overlay only,
   or shared after agreement.
3. **Generated install output** — `~/.codex/skills` and optional Claude
   fixtures. Generated output is never source of truth.

Keep the pristine checkout at:

```text
~/.codex/zskills-portable
```

The verifier should fail if this checkout has uncommitted local edits unless
run with an explicit `--allow-local-upstream` mode and a named patch queue
entry. The current `scripts/clear-tracking.sh` nested-tracking fix is a
candidate upstream improvement because it corrects behavior for the current
per-pipeline tracking layout.

### Layer 2: Shared Runtime Helpers

Add portable helper scripts. Codex adopts them first through generated overlays.
Claude adoption is an upstream proposal or explicit `--client both` decision,
not an automatic side effect of Codex integration:

- `scripts/zskills-config.sh`
  - Resolve active config path.
  - Read `.codex/zskills-config.json` for Codex, `.claude/zskills-config.json`
    for Claude, and support explicit dual-client checks.
  - Detect landing/main-protection conflicts.
  - Return `landing`, `main_protected`, `branch_prefix`, `ci.auto_fix`,
    `ci.max_fix_attempts`, and test commands.
  - Contract:
    - `resolve --client codex|claude|auto --format json`
    - `get KEY --client ...`
    - `export-env --client ...`
    - `validate --client ...`
    - exit `0`: success
    - exit `2`: invalid args
    - exit `3`: missing required config
    - exit `4`: malformed config
    - exit `5`: `.codex` / `.claude` conflict
    - exit `6`: protected-main violation for requested mode
    - JSON includes `config_path`, `client`, `landing`, `main_protected`,
      `branch_prefix`, `ci_auto_fix`, `ci_max_attempts`, and `full_test_cmd`.

- `scripts/zskills-scheduler.sh`
  - Manage `.zskills/schedules/*.json`.
  - Commands: `add`, `list`, `next`, `stop`, `due`, `mark-complete`,
    `mark-blocked`.
  - Does not require native Claude/Codex cron.
  - Can be driven manually or by OS cron/systemd/GitHub Actions.

- `scripts/zskills-preflight.sh`
  - Procedural replacement for hook checks in runtimes without hooks.
  - Checks branch/mode, worktree cleanliness, unrelated changes, tracking
    requirements, and protected-main constraints.

- Keep `scripts/clear-tracking.sh`
  - Ensure it recursively handles `.zskills/tracking/$PIPELINE_ID/*`.
  - Preserve `fulfilled.run-plan.*` completion history.
  - Refuse recent active `requires.*` unless forced.
  - Tracking contract:
    - markers may be nested under `.zskills/tracking/$PIPELINE_ID/`
    - `requires.*` is active until a same-directory `fulfilled.*` marker has
      `status: complete`
    - `step.*` and `phasestep.*` are bookkeeping markers
    - `fulfilled.run-plan.*` is completion history and is preserved
    - cleanup never removes files outside `.zskills/tracking`

### Layer 3: Generated Codex Overlay

Create this before adopting new helpers in skill prose. A minimal first version
only needs to insert the adapter block and apply declared overlays. Create a
generator, for example:

```text
scripts/generate-codex-skills.sh
```

Inputs:

- upstream skill directory
- structured overlays under `codex-overlays/<skill>.yaml`; raw patches only
  for unavoidable replacements
- shared adapter block template

Outputs:

- `~/.codex/skills/<skill>/SKILL.md`
- `~/.codex/skills/ZSKILLS_CODEX_INTEGRATION.md`
- `~/.codex/skills/verify-zskills-codex.py`

Rules:

- Insert one marked `ZSKILLS_CODEX_COMPAT` block after frontmatter.
- Apply only reviewed skill-specific overlays. Each overlay includes skill name,
  insertion point or replacement anchor, rationale, expected upstream context,
  and target: Codex-only, Claude-upstream proposal, or shared after agreement.
- Preserve upstream text everywhere else.
- Generate a manifest recording upstream commit, overlay patch checksums, and
  installed skill list.

### Layer 4: Optional Scheduler Runner

Codex cannot currently provide Claude-style live session cron. A pragmatic
high-fidelity alternative is:

```cron
*/5 * * * * cd /path/to/repo && scripts/zskills-run-due.sh
```

`scripts/zskills-run-due.sh` would:

1. Acquire `.zskills/scheduler.lock`.
2. Read `.zskills/schedules/*.json`.
3. Pick due jobs.
4. Invoke a configured runner command, such as:
   `codex exec "run-plan plans/X.md finish auto"`.
5. Save stdout/stderr to `.zskills/logs/<job>/<timestamp>.log`.
6. Update schedule status.
7. Stop on conflicts, failed verification, missing user approval, or unclear
   state.

Schedule job schema:

```json
{
  "id": "run-plan-feature-x",
  "client": "codex",
  "repo_path": "/path/to/repo",
  "worktree_path": null,
  "skill": "run-plan",
  "args": "plans/FEATURE_X.md finish auto",
  "original_invocation": "/run-plan plans/FEATURE_X.md finish auto",
  "pipeline_id": "run-plan.feature-x",
  "runner_command": "codex exec",
  "required_tools": ["git", "codex"],
  "concurrency": "skip-if-running",
  "interval": "5m",
  "one_shot": false,
  "next_run": "2026-04-29T18:35:00Z",
  "last_status": "pending",
  "created_by": "zskills-scheduler/v1"
}
```

`every`, `now`, `next`, and `stop` preserve original skill semantics by storing
the original skill name and argument tail. Recurring jobs repeatedly invoke the
same command. One-shot jobs are used for handoffs such as `run-plan finish auto`;
the running skill creates the next due job after it updates plan/tracking state,
then the next turn re-reads the plan to select the next phase.

This does not recreate conversational feedback. It creates asynchronous
feedback through logs, reports, schedule status, PR comments, and briefing.

## Phases

## Progress

| Phase | Status | Notes |
|---|---|---|
| Phase 1: Baseline And Compatibility Matrix | Done | Added Appendix A, B, and C in this run. Verification used the installed Codex verifier. |
| Phase 1.5: Minimal Generator And Drift Guard | Done | Added generator, adapter template, overlay manifest, verifier, Codex output, Claude fixture, and local patch queue note. |
| Phase 2: Shared Helper Scripts | Done | Added `zskills-config.sh`, `zskills-preflight.sh`, and helper tests. Existing upstream tests and generated-output checks passed. |
| Phase 3: Codex Overlay Adoption | Done | Generated Codex overlays now prefer shared config/preflight helpers; manifest checksums and verifier were tightened. |
| Phase 4: Scheduler Emulation | Done | Added file-backed schedules, due-runner, scheduler tests, and Codex scheduled-mode overlays. |
| Phase 5: Hook Fidelity And Procedural Gates | Done | Added preflight inventory, verifier enforcement, and Codex gates for remaining dangerous call sites. |
| Phase 6: Cross-Client Installation Contract | Done | Added cross-client installer helper, tests, and update-zskills client-boundary overlay. |
| Phase 7: Fidelity Test Suite | Done | Added consolidated fidelity suite, multi-phase scheduled run-plan canary, and real OS cron canary. |

### Phase 1: Baseline And Compatibility Matrix

Deliverables:

- Document Claude and Codex runtime affordances:
  - subagents
  - cron/scheduler
  - hooks
  - command execution
  - file editing
  - MCP availability
  - skill discovery
- Define fidelity targets per feature:
  - native
  - emulated
  - procedural fallback
  - unsupported
- Add a plan appendix mapping every ZSkill to its runtime dependencies.
- Add a subagent dependency classification for each skill:
  - required: stop if no subagent tool is available
  - degraded: run inline and label the report
  - optional: skip or inline without changing outcome
- Define exact fallback labels:
  - `multi-agent`
  - `single-context fresh-subagent`
  - `inline self-review`
  - `unsupported-no-agent`

Acceptance criteria:

- The matrix explains where fidelity loss occurs and why.
- No proposed change claims parity where there is only fallback behavior.
- Every Agent/Task use is classified as required, degraded, or optional.

### Phase 1.5: Minimal Generator And Drift Guard

Deliverables:

- Minimal `generate-codex-skills.sh`.
- Adapter block template.
- Overlay manifest format.
- Verifier that compares output to `upstream + declared overlays`.
- Claude fixture generation that proves no Codex block is injected.

Acceptance criteria:

- Current Codex install can be regenerated deterministically.
- Undeclared edits fail verification.
- A dirty pristine upstream checkout fails verification unless explicitly
  allowed with a named patch queue entry.

### Phase 2: Shared Helper Scripts

Deliverables:

- Implement `zskills-config.sh`.
- Implement `zskills-preflight.sh`.
- Finalize recursive `clear-tracking.sh`.
- Add tests for:
  - `.codex` only config
  - `.claude` only config
  - matching dual configs
  - conflicting dual configs
  - direct/cherry-pick/pr resolution
  - nested tracking cleanup

Acceptance criteria:

- Existing upstream tests pass.
- New helper tests pass.
- No installed skill prose is hand-edited in this phase. Helper adoption in
  skills waits for generated overlays in Phase 3.

### Phase 3: Codex Overlay Adoption

Deliverables:

- Codex overlays that call shared helpers for config resolution and preflight.
- Overlay manifest with upstream SHA and overlay checksums.
- Verifier that:
  - validates YAML frontmatter
  - confirms exactly one adapter block per skill
  - checks overlay patches are expected
  - compares generated output against `upstream + declared overlays`
  - checks no broad `.zskills` destructive cleanup
  - optionally checks remote upstream SHA when network is available

Acceptance criteria:

- Regenerating the Codex install is deterministic.
- Accidental drift inside allowlisted skills fails verification unless the
  overlay is updated.
- A generated Claude install fixture can be produced without Codex adapter
  blocks.
- The verifier fails if any Claude fixture contains `ZSKILLS_CODEX_COMPAT`.

### Phase 4: Scheduler Emulation

Deliverables:

- `.zskills/schedules/*.json` format.
- `zskills-scheduler.sh`.
- `zskills-run-due.sh`.
- Skill updates:
  - Claude: native cron remains supported.
  - Codex: `every`, `next`, `stop`, and `now` use scheduler files if enabled;
    otherwise report unsupported.
- `briefing` summarizes due, blocked, failed, and recently completed jobs.

Acceptance criteria:

- OS cron can trigger due jobs without knowing phase numbers.
- `run-plan finish auto` re-runs and finds the next incomplete phase.
- Blocked jobs preserve feedback in logs/reports/status.
- No background execution is claimed unless an actual runner is configured.
- Runner preflight validates repo path, client, runner command, required tools,
  credentials assumptions, and lock state before invoking Codex.

### Phase 5: Hook Fidelity And Procedural Gates

Deliverables:

- Keep Claude hooks as native enforcement.
- For Codex, make high-risk workflows call `zskills-preflight.sh` before:
  - commit
  - cherry-pick
  - PR merge/auto-merge
  - worktree deletion
  - tracking cleanup
- Add instructions that failures are blockers, not warnings.
- Add a call-site inventory for each skill/helper path that can:
  - commit
  - cherry-pick
  - open PRs
  - merge PRs
  - delete worktrees
  - clear tracking

Acceptance criteria:

- Static checks prove every inventory item invokes `zskills-preflight.sh` or
  has an explicit documented exemption.
- Dangerous operations have explicit preflight gates even without native hooks.

### Phase 6: Cross-Client Installation Contract

Deliverables:

- Update `update-zskills` behavior:
  - `--client claude`
  - `--client codex`
  - `--client both`
  - default detects active client conservatively.
- Claude install writes `.claude/*` and upstream skills.
- Codex install writes `.codex/*` project config and global Codex skills.
- Dual install mirrors shared config intentionally and reports divergence.

Acceptance criteria:

- Claude does not receive Codex fallback blocks unless explicitly requested.
- Codex does not rely on `.claude` config except as fallback.
- Dual-client projects have deterministic config ownership.

### Phase 7: Fidelity Test Suite

Deliverables:

- Add fidelity tests:
  - normalized upstream comparison
  - overlay manifest verification
  - config helper behavior
  - scheduler queue behavior
  - preflight behavior
  - clear-tracking nested layout
  - no Codex adapter in Claude install
  - direct/cherry-pick/pr acceptance in every skill/helper path that can land,
    commit, open PRs, merge PRs, delete worktrees, or clean tracking
- Add a canary that simulates multiple scheduled `run-plan finish auto` cycles
  with a fake runner.

Acceptance criteria:

- Tests fail on accidental upstream drift.
- Tests fail when helper behavior diverges across clients.
- Tests document known non-parity explicitly.
- Tests fail if generated Claude fixtures contain Codex adapter text.

## Decisions Requiring Agreement

These are overall improvements that should be discussed before implementation:

1. Move config resolution out of skill prose and into `scripts/zskills-config.sh`.
   Strong argument: reduces duplicated prompt snippets and improves fidelity for
   both clients.

2. Adopt `.zskills/schedules` as a shared scheduler state format.
   Strong argument: gives Codex a real scheduling story and can supplement
   Claude with inspectable durable state.

3. Treat recursive `clear-tracking.sh` support as an upstream fix.
   Strong argument: current skills write nested markers, so flat-only cleanup is
   objectively stale.

4. Generate Codex skills rather than editing installed copies manually.
   Strong argument: protects Claude fidelity and makes Codex drift auditable.

5. Make `update-zskills --client both` explicit rather than default.
   Strong argument: prevents accidental cross-client config pollution.

## Risks

- OS cron cannot preserve conversational feedback. Mitigation: logs, reports,
  status files, and briefing summaries.
- Scheduler runner may invoke Codex in an environment without credentials or
  correct working directory. Mitigation: preflight runner checks.
- Generated overlays add maintenance complexity. Mitigation: manifest and
  verifier.
- Moving behavior into shell helpers may reduce prompt readability. Mitigation:
  keep concise prose plus helper command examples.

## Suggested First Implementation Slice

Start with the highest value, lowest risk work:

1. Add `zskills-config.sh`.
2. Add helper tests for config precedence and conflicts.
3. Add the minimal overlay generator and manifest.
4. Update Codex overlays for `run-plan`, `fix-issues`, and `do` to call the
   helper.
5. Keep scheduler emulation as the second slice after config and generation are
   stable.

This improves fidelity immediately without committing to a full cron runner.

## Appendix A: Runtime Affordance Matrix

| Capability | Claude Fidelity | Codex Fidelity Today | Target Codex Fidelity | Notes |
|---|---|---|---|---|
| Skill invocation | Native slash commands | Emulated by skill name or slash-command text | Generated overlay preserves `$ARGUMENTS` semantics | Codex must pass only the intended argument tail across skill boundaries. |
| Subagents | Native Agent/Task tool | Available only when Codex runtime exposes subagents | Native when exposed; explicit fallback labels otherwise | Do not claim fresh-agent isolation when running inline. |
| Cron/session scheduler | Native Claude cron tools in original ZSkills | Unsupported in this Codex session | `.zskills/schedules` plus optional OS runner | External cron gives durable execution but not conversational feedback. |
| Hooks | Native `.claude/hooks` enforcement | Procedural fallback only | `zskills-preflight.sh` before dangerous operations | Codex cannot rely on Claude hook execution. |
| Config | `.claude/zskills-config.json` | `.codex` preferred, `.claude` fallback | `zskills-config.sh` owns precedence and conflicts | Dual-client conflict must stop before landing. |
| Tracking | `.zskills/tracking` | Preserved | Preserved with explicit marker schema and recursive cleanup | Tracking is project state, not skill-install state. |
| Landing modes | Direct, cherry-pick, PR | Preserved by adapter | Helper-backed across all landing paths | Tests must cover every path that commits, lands, or cleans up. |
| Skill chaining | Native slash-command call pattern | Emulated by loading installed `SKILL.md` | Generator ensures consistent adapter wording | Preserve `ZSKILLS_PIPELINE_ID` across boundaries. |
| File edits | Claude Edit/Write | Patch-based edits | Patch-based edits | Manual edits should use patch tooling in Codex. |
| Browser/manual verification | `playwright-cli` skill | Installed and available if CLI exists | Shared behavior | Verification reports must disclose freshness mode. |

## Appendix B: ZSkill Runtime Dependency Inventory

| Skill | Primary Function | Runtime Dependencies | Subagent Classification | Scheduler Dependency | Landing/Tracking Dependency |
|---|---|---|---|---|---|
| `briefing` | Summarize project, reports, worktrees, schedules | git, reports, worktrees, optional cron state | Optional | Degraded: scheduler summaries only if backend/state exists | Reads `.landed` and reports; no landing. |
| `commit` | Safe commit, push, PR, land | git, optional gh, tests | Degraded for staged diff review | None | High: commit/PR/cherry-pick paths need preflight. |
| `do` | Lightweight task dispatcher | git, worktrees, gh for PR, tests | Degraded for implementation/review | Degraded: `every/next/stop/now` need scheduler state | High: direct/worktree/PR modes and tracking. |
| `doc` | Documentation audit/fix | git, project docs/tests | Optional | None | Low: may commit only through separate commit workflow. |
| `draft-plan` | Adversarial plan drafting | git, plans, research files | Degraded: inline labeled passes acceptable | None | Writes tracking marker when repo exists. |
| `fix-issues` | Batch issue fixing | gh, git, worktrees, tests, reports | Required/degraded by mode: batch fix quality depends heavily on agents | Degraded: sprint scheduling needs scheduler state | High: direct/cherry-pick/PR and `.landed` markers. |
| `fix-report` | Review sprint results and land/close | gh, git, reports, worktrees | Optional | None | High: landing/closing decisions need preflight. |
| `investigate` | Root-cause debugging | git, tests, source inspection | Degraded | None | Medium: may produce fixes, uses normal commit flow. |
| `manual-testing` | Browser/manual verification | dev server, playwright-cli | Optional | None | Writes verification evidence only. |
| `plans` | Plan dashboard/executor | plans index, run-plan | Optional | Degraded when work scheduling requested | Delegates to run-plan. |
| `playwright-cli` | Browser automation reference | playwright-cli executable | Optional | None | No landing. |
| `qe-audit` | Quality audit / feature bashing | git, tests, gh issues optional | Degraded: audit breadth improves with agents | Degraded: recurring audit needs scheduler state | Usually files issues, does not land. |
| `refine-plan` | Refine existing plans | plans, git, review passes | Degraded | None | Plan edits only. |
| `research-and-go` | Decompose, plan, execute | research-and-plan, draft-plan, run-plan | Required/degraded: broad orchestration relies on agents | Degraded through run-plan finish auto | High: delegates to run-plan tracking/landing. |
| `research-and-plan` | Meta-plan decomposition | plans, git, research passes | Degraded | None | Produces plans; no direct landing. |
| `review-feedback` | Triage feedback JSON/issues | feedback export, gh | Optional | None | May file issues; no landing. |
| `run-plan` | Execute plan phases | git, worktrees, tests, gh for PR, reports | Required/degraded: implementation and verification quality depend on agents | Degraded: `every` and `finish auto` need scheduler state | Highest: direct/cherry-pick/PR, tracking, cleanup. |
| `update-zskills` | Install/update infrastructure | git, filesystem, scripts, config | Optional | None | Owns config/install boundaries. |
| `verify-changes` | Verify diffs/tests/UI | git, tests, playwright-cli | Degraded: fresh verification preferred | None | Writes tracking fulfillment markers. |

Subagent classification meanings:

- `Required`: if no subagent tool exists, stop or ask before continuing when the workflow's assurance would be materially false.
- `Degraded`: inline execution is allowed if the report clearly labels reduced independence.
- `Optional`: subagents improve breadth or speed but are not central to the workflow.

## Appendix C: Fallback Labels And Rules

Use these exact labels in reports and status files:

- `multi-agent`: the workflow dispatched independent subagents for implementation, review, verification, or research.
- `single-context fresh-subagent`: the current agent was itself invoked as a fresh subagent and did not perform the implementation being verified.
- `inline self-review`: no subagent tool was available, so the workflow ran in the same context; assurance is lower.
- `unsupported-no-agent`: the workflow requires subagent isolation for a specific operation and stopped because the active runtime could not provide it.

Rules:

- Never use `multi-agent` unless independent subagents were actually spawned.
- `run-plan`, `fix-issues`, and `research-and-go` must explicitly choose
  between `multi-agent`, `inline self-review`, and `unsupported-no-agent` for
  implementation and verification phases.
- `commit` and `verify-changes` may continue as `inline self-review`, but must
  disclose the weaker assurance before committing or reporting success.
- Scheduler fallback labels are separate: `native-scheduler`,
  `zskills-scheduler`, and `unsupported-no-scheduler`.
