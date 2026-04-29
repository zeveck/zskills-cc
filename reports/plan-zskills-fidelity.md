# ZSkills Fidelity Plan Run Report

## Run

- Plan: `plans/ZSKILLS_FIDELITY_PLAN.md`
- Invocation: `run-plan plans/ZSKILLS_FIDELITY_PLAN.md`
- Mode: direct, in-place documentation phase
- Phase executed: Phase 1: Baseline And Compatibility Matrix
- Freshness mode: inline self-review

## Environment Notes

This workspace is not a git repository, so the normal `/run-plan` worktree,
tracking, commit, and landing mechanics were not applicable. The phase was a
documentation/specification phase, so execution was limited to plan artifacts.

No scheduler backend was used.

## Work Completed

- Added a `Progress` table to the plan.
- Added `Appendix A: Runtime Affordance Matrix`.
- Added `Appendix B: ZSkill Runtime Dependency Inventory`.
- Added `Appendix C: Fallback Labels And Rules`.
- Marked Phase 1 as done and Phase 1.5 as next.

## Verification

- Ran the installed Codex ZSkills verifier:
  - `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed, 19 Codex ZSkills verified.
- Read the updated plan after editing to confirm the Phase 1 outputs are present.

## Remaining Work

## Phase 1.5 Run

- Phase executed: Phase 1.5: Minimal Generator And Drift Guard
- Mode: direct, in-place artifact generation
- Freshness mode: inline self-review

### Work Completed

- Added `templates/codex-compat-block.md`.
- Added `scripts/generate-codex-skills.py`.
- Added `scripts/generate-codex-skills.sh`.
- Added `scripts/verify-generated-zskills.py`.
- Added `codex-overlays/manifest.json`.
- Added declared Codex-only overlay patches for:
  - `briefing`
  - `commit`
  - `do`
  - `draft-plan`
  - `fix-issues`
  - `qe-audit`
  - `run-plan`
  - `update-zskills`
  - `verify-changes`
- Added `local-patches/clear-tracking-recursive.md` to document the dirty
  portable checkout as a reviewed local patch queue entry.
- Generated:
  - `build/codex-skills`
  - `build/claude-skills`

### Verification

- Generated Codex and Claude outputs:
  - `bash scripts/generate-codex-skills.sh --client codex --output build/codex-skills`
  - `bash scripts/generate-codex-skills.sh --client claude --output build/claude-skills`
- Verified generated outputs:
  - `python scripts/verify-generated-zskills.py --allow-local-upstream --patch-queue-entry clear-tracking-recursive`
  - Result: passed.
- Verified strict dirty-upstream guard:
  - `python scripts/verify-generated-zskills.py`
  - Result: failed as intended because `~/.codex/zskills-portable/scripts/clear-tracking.sh` is locally modified.
- Compared generated Codex skills to installed Codex skills:
  - Skill files match; only expected support-file differences remain:
    `.system`, `ZSKILLS_CODEX_COMPAT.md`, `ZSKILLS_CODEX_INTEGRATION.md`,
    `generation-manifest.json`, and `verify-zskills-codex.py`.
- Verified Claude fixture has no Codex adapter text:
  - `rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" build/claude-skills`
  - Result: no matches.

## Remaining Work

## Phase 2 Run

- Phase executed: Phase 2: Shared Helper Scripts
- Mode: direct, in-place helper implementation
- Freshness mode: inline self-review

### Work Completed

- Added `scripts/zskills-config.sh`.
  - Supports `resolve`, `get`, `export-env`, and `validate`.
  - Implements `.codex` / `.claude` precedence.
  - Detects dual-config landing/main-protection conflicts.
  - Emits machine-readable JSON or env output.
  - Uses stable exit codes for invalid args, missing config, malformed config,
    config conflict, and protected-main violation.
- Added `scripts/zskills-preflight.sh`.
  - Covers procedural checks for commit, cherry-pick, PR, merge,
    delete-worktree, and clear-tracking operations.
  - Rejects dangerous states conservatively.
- Added `tests/test-zskills-helpers.sh`.
  - Covers `.codex` only, `.claude` only, conflict, protected direct mode,
    malformed config, and basic preflight behavior.
- Did not edit installed skill prose in this phase; helper adoption remains
  deferred to Phase 3 overlays.

### Verification

- `bash tests/test-zskills-helpers.sh`
  - Result: 10 passed, 0 failed.
- `bash -n scripts/zskills-config.sh scripts/zskills-preflight.sh tests/test-zskills-helpers.sh scripts/generate-codex-skills.sh`
  - Result: passed.
- `python -m py_compile scripts/generate-codex-skills.py scripts/verify-generated-zskills.py`
  - Result: passed.
- `bash tests/test-skill-conformance.sh` in `~/.codex/zskills-portable`
  - Result: 88 passed, 0 failed.
- `bash tests/test-tracking-integration.sh` in `~/.codex/zskills-portable`
  - Result: 22 passed, 0 failed.
- `python scripts/verify-generated-zskills.py --allow-local-upstream --patch-queue-entry clear-tracking-recursive`
  - Result: passed.
- `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed.

## Remaining Work

Next phase:

- Phase 3: Codex Overlay Adoption

Key next deliverables:

- Codex overlays that call `zskills-config.sh` and `zskills-preflight.sh`.
- Overlay manifest updates.
- Generated Codex output verification against `upstream + declared overlays`.

## Phase 3 Run

- Phase executed: Phase 3: Codex Overlay Adoption
- Mode: direct, in-place overlay and verifier implementation
- Freshness mode: inline self-review

### Work Completed

- Updated `templates/codex-compat-block.md` to document generated helper
  locations and project-local helper preference.
- Updated `scripts/generate-codex-skills.py` so generated installs include:
  - `scripts/zskills-config.sh`
  - `scripts/zskills-preflight.sh`
- Updated `scripts/zskills-config.sh` so a missing config preserves original
  ZSkills fallback behavior by resolving to `cherry-pick` defaults, and so
  Codex explicitly falls back from `.codex/zskills-config.json` to
  `.claude/zskills-config.json`.
- Updated `scripts/zskills-preflight.sh` so validation failures are blockers
  even when a caller does not pass an explicit mode.
- Updated Codex overlays for:
  - `run-plan`
  - `fix-issues`
  - `do`
  - `commit`
- The updated overlays now tell Codex to prefer shared helpers for config
  resolution, branch prefix resolution, and preflight gates before commit,
  cherry-pick, PR, merge, worktree deletion, or tracking cleanup.
- Updated `codex-overlays/manifest.json` with the validated upstream SHA and
  refreshed overlay checksums.
- Tightened `scripts/verify-generated-zskills.py` to verify:
  - manifest patch checksums and expected upstream SHA
  - frontmatter presence and required fields
  - exactly one Codex adapter block in generated Codex skills
  - no Codex adapter leakage in generated Claude fixtures
  - generated output matches `upstream + declared overlays`
  - helper scripts are present in generated output
  - high-risk Codex overlays semantically reference the helper scripts
  - broad destructive `.zskills` cleanup patterns are absent
- Addressed review findings from the two read-only agents:
  - `/do` PR preflight now runs from inside `$WORKTREE_PATH` so branch checks
    see the feature branch.
  - Codex config helper calls now preserve `.claude` fallback.
  - Preflight no longer suppresses config validation failures.
  - The generator now rejects unknown overlay targets instead of applying
    typoed targets to Claude output.
  - The run-plan scheduler override now states that it takes precedence over
    later Claude `CronCreate` instructions until scheduler emulation exists.
- Regenerated:
  - `build/codex-skills`
  - `build/claude-skills`
- Synced `build/codex-skills` into `~/.codex/skills` so the installed Codex
  ZSkills now use the Phase 3 helper-aware overlays.

### Verification

- `bash tests/test-zskills-helpers.sh`
  - Result: 12 passed, 0 failed.
- `bash -n scripts/zskills-config.sh scripts/zskills-preflight.sh tests/test-zskills-helpers.sh scripts/generate-codex-skills.sh`
  - Result: passed.
- `python -m py_compile scripts/generate-codex-skills.py scripts/verify-generated-zskills.py`
  - Result: passed.
- `bash scripts/generate-codex-skills.sh --client codex --output build/codex-skills`
  - Result: passed.
- `bash scripts/generate-codex-skills.sh --client claude --output build/claude-skills`
  - Result: passed.
- `python scripts/verify-generated-zskills.py --allow-local-upstream --patch-queue-entry clear-tracking-recursive`
  - Result: passed.
- `rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" build/claude-skills`
  - Result: no matches.
- `bash tests/test-skill-conformance.sh` in `~/.codex/zskills-portable`
  - Result: 88 passed, 0 failed.
- `bash tests/test-tracking-integration.sh` in `~/.codex/zskills-portable`
  - Result: 22 passed, 0 failed.
- `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed.
- Post-sync `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed.

### Remaining Work

Next phase:

- Phase 4: Scheduler Emulation

Key next deliverables:

- `.zskills/schedules/*.json` format.
- `zskills-scheduler.sh`.
- `zskills-run-due.sh`.
- Codex `every`, `next`, `stop`, and `now` behavior backed by scheduler files
  when enabled.

## Phase 4 Run

- Phase executed: Phase 4: Scheduler Emulation
- Mode: direct, in-place helper and overlay implementation
- Freshness mode: inline self-review

### Work Completed

- Added `scripts/zskills-scheduler.sh`.
  - Stores schedules under `.zskills/schedules/*.json`.
  - Supports `add`, `list`, `next`, `stop`, `trigger`, `due`,
    `mark-complete`, and `mark-blocked`.
  - Supports interval schedules such as `5m`, `2h`, `1d`, `every 2h`, and
    `every hour`, plus `day at 9am` and `weekday at 9am`.
  - Records runner command, required tools, repo path, pipeline id, status,
    next run, and feedback message.
- Added `scripts/zskills-run-due.sh`.
  - Acquires `.zskills/scheduler.lock`.
  - Reads due jobs without knowing phase numbers.
  - Validates repo path, runner command, required tools, and lock state before
    execution.
  - Preserves feedback in `.zskills/logs/<job>/<timestamp>.log`.
  - Marks jobs complete and reschedules them, or marks them blocked with a
    status message.
- Updated generated-support script handling so Codex installs include:
  - `zskills-config.sh`
  - `zskills-preflight.sh`
  - `zskills-scheduler.sh`
  - `zskills-run-due.sh`
- Updated Codex overlays for:
  - `run-plan`
  - `fix-issues`
  - `do`
  - `qe-audit`
  - `briefing`
- Codex scheduled modes now use file-backed scheduler helpers when available:
  - `every <SCHEDULE>` stores a schedule file.
  - `next` reads schedule state.
  - `stop` marks matching schedules stopped.
  - `now` triggers matching schedules and runs due jobs where applicable.
  - If helpers are unavailable, the skills report unsupported and do not claim
    background execution.
- Updated `briefing` overlay to include a scheduler status bucket summarizing
  active, due, blocked, failed, and recently completed jobs.
- Added `tests/test-zskills-scheduler.sh`.
- Tightened generated-output verification so required scheduler helpers are
  present and high-risk overlays reference them.
- Regenerated:
  - `build/codex-skills`
  - `build/claude-skills`
- Synced `build/codex-skills` into `~/.codex/skills`.

### Verification

- `bash tests/test-zskills-helpers.sh`
  - Result: 12 passed, 0 failed.
- `bash tests/test-zskills-scheduler.sh`
  - Result: 17 passed, 0 failed.
- `bash -n scripts/zskills-config.sh scripts/zskills-preflight.sh scripts/zskills-scheduler.sh scripts/zskills-run-due.sh tests/test-zskills-helpers.sh tests/test-zskills-scheduler.sh scripts/generate-codex-skills.sh`
  - Result: passed.
- `python -m py_compile scripts/generate-codex-skills.py scripts/verify-generated-zskills.py`
  - Result: passed.
- `bash scripts/generate-codex-skills.sh --client codex --output build/codex-skills`
  - Result: passed.
- `bash scripts/generate-codex-skills.sh --client claude --output build/claude-skills`
  - Result: passed.
- `python scripts/verify-generated-zskills.py --allow-local-upstream --patch-queue-entry clear-tracking-recursive`
  - Result: passed.
- `rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" build/claude-skills`
  - Result: no matches.
- `bash tests/test-skill-conformance.sh` in `~/.codex/zskills-portable`
  - Result: 88 passed, 0 failed.
- `bash tests/test-tracking-integration.sh` in `~/.codex/zskills-portable`
  - Result: 22 passed, 0 failed.
- Post-sync `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed.

### Remaining Work

Next phase:

- Phase 5: Hook Fidelity And Procedural Gates

Key next deliverables:

- Add or verify preflight gates for all remaining dangerous operations.
- Create the call-site inventory for commit, cherry-pick, PR, merge,
  worktree deletion, and tracking cleanup paths.

## Phase 5 Run

- Phase executed: Phase 5: Hook Fidelity And Procedural Gates
- Mode: direct, in-place overlay, helper, and verifier implementation
- Freshness mode: inline self-review

### Work Completed

- Added `codex-overlays/preflight-inventory.json`.
  - Inventories call sites for `commit`, `cherry-pick`, `pr`, `merge`,
    `delete-worktree`, and `clear-tracking`.
  - Marks each call site as `gated` or `exempt`.
  - Requires exemption reasons for non-executing/manual-only references.
- Added Codex-only overlays for:
  - `fix-report`
  - `research-and-go`
- Updated existing Codex overlays for:
  - `commit`
  - `do`
- New and updated overlays explicitly say preflight failures are blockers, not
  warnings.
- Added missing preflight gates for:
  - `fix-report` approved cherry-picks
  - `fix-report` safe worktree removals
  - `research-and-go` interactive `clear-tracking.sh`
- Updated `scripts/zskills-preflight.sh` so `delete-worktree` checks the target
  worktree path for uncommitted changes before removal.
- Added helper coverage for dirty target worktrees in
  `tests/test-zskills-helpers.sh`.
- Tightened `scripts/verify-generated-zskills.py` so it:
  - reads `codex-overlays/preflight-inventory.json`
  - verifies each gated inventory entry references `zskills-preflight.sh`
  - verifies each gated inventory entry includes the expected `--operation`
  - verifies gated entries state failures are blockers
  - flags dangerous generated Codex call sites that are missing from the
    inventory
- Regenerated:
  - `build/codex-skills`
  - `build/claude-skills`
- Synced `build/codex-skills` into `~/.codex/skills`.
- Updated the installed Codex verifier allowlist for the new intentional
  Codex-only overlays in `fix-report` and `research-and-go`.

### Verification

- `bash tests/test-zskills-helpers.sh`
  - Result: 13 passed, 0 failed.
- `bash tests/test-zskills-scheduler.sh`
  - Result: 17 passed, 0 failed.
- `bash -n scripts/zskills-config.sh scripts/zskills-preflight.sh scripts/zskills-scheduler.sh scripts/zskills-run-due.sh tests/test-zskills-helpers.sh tests/test-zskills-scheduler.sh scripts/generate-codex-skills.sh`
  - Result: passed.
- `python -m py_compile scripts/generate-codex-skills.py scripts/verify-generated-zskills.py`
  - Result: passed.
- `python scripts/verify-generated-zskills.py --allow-local-upstream --patch-queue-entry clear-tracking-recursive`
  - Result: passed.
- `rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" build/claude-skills`
  - Result: no matches.
- `bash tests/test-skill-conformance.sh` in `~/.codex/zskills-portable`
  - Result: 88 passed, 0 failed.
- `bash tests/test-tracking-integration.sh` in `~/.codex/zskills-portable`
  - Result: 22 passed, 0 failed.
- Post-sync `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed.

### Remaining Work

Next phase:

- Phase 6: Cross-Client Installation Contract

Key next deliverables:

- Add `--client claude`, `--client codex`, and `--client both` install
  semantics to the update path.
- Keep Claude install upstream-clean and Codex install generated-overlay based.
- Report config divergence clearly for dual installs.

## Phase 6 Run

- Phase executed: Phase 6: Cross-Client Installation Contract
- Mode: direct, in-place installer, overlay, and test implementation
- Freshness mode: inline self-review

### Work Completed

- Added `scripts/zskills-install.sh`.
  - Supports `--client codex`, `--client claude`, `--client both`, and
    `--client auto`.
  - Supports `--project-root`, `--codex-home`, `--upstream`, and
    `--mirror-config`.
  - Codex install generates overlay-based global skills under
    `$CODEX_HOME/skills` or `~/.codex/skills` and writes/preserves
    `.codex/zskills-config.json`.
  - Claude install generates upstream-clean project-local skills under
    `.claude/skills` and writes/preserves `.claude/zskills-config.json`.
  - Dual install intentionally mirrors `.codex` and `.claude` config. If both
    configs already exist and diverge, it stops unless `--mirror-config` is
    explicit.
- Updated generated-support script handling so Codex installs include
  `zskills-install.sh`.
- Updated the Codex-only `update-zskills` overlay to document:
  - `--client codex`
  - `--client claude`
  - `--client both`
  - `--client auto`
  - `--mirror-config`
- Updated generated-output verification to require `zskills-install.sh` and
  require `update-zskills` to mention the client contract.
- Added `tests/test-zskills-install.sh`.
  - Verifies Codex install leaves `.claude/skills` untouched.
  - Verifies Claude install has no Codex adapter text.
  - Verifies dual divergent config fails without `--mirror-config`.
  - Verifies dual install mirrors config and keeps Claude skills clean.
- Regenerated:
  - `build/codex-skills`
  - `build/claude-skills`
- Synced `build/codex-skills` into `~/.codex/skills`.

### Verification

- `bash tests/test-zskills-helpers.sh`
  - Result: 13 passed, 0 failed.
- `bash tests/test-zskills-scheduler.sh`
  - Result: 17 passed, 0 failed.
- `bash tests/test-zskills-install.sh`
  - Result: 14 passed, 0 failed.
- `bash -n scripts/zskills-config.sh scripts/zskills-preflight.sh scripts/zskills-scheduler.sh scripts/zskills-run-due.sh scripts/zskills-install.sh tests/test-zskills-helpers.sh tests/test-zskills-scheduler.sh tests/test-zskills-install.sh scripts/generate-codex-skills.sh`
  - Result: passed.
- `python -m py_compile scripts/generate-codex-skills.py scripts/verify-generated-zskills.py`
  - Result: passed.
- `python scripts/verify-generated-zskills.py --allow-local-upstream --patch-queue-entry clear-tracking-recursive`
  - Result: passed.
- `rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" build/claude-skills`
  - Result: no matches.
- `bash tests/test-skill-conformance.sh` in `~/.codex/zskills-portable`
  - Result: 88 passed, 0 failed.
- `bash tests/test-tracking-integration.sh` in `~/.codex/zskills-portable`
  - Result: 22 passed, 0 failed.
- Post-sync `python /home/vscode/.codex/skills/verify-zskills-codex.py`
  - Result: passed.

### Remaining Work

Next phase:

- Phase 7: Fidelity Test Suite

Key next deliverables:

- Consolidate the current helper, scheduler, installer, generated-output, and
  upstream conformance checks into a single fidelity test suite.
- Add the scheduled `run-plan finish auto` fake-runner canary.

## Phase 7 Run

- Phase executed: Phase 7: Fidelity Test Suite
- Mode: direct, in-place test-suite implementation
- Freshness mode: inline self-review

### Work Completed

- Added `tests/test-zskills-fidelity.sh`.
  - Runs helper behavior tests.
  - Runs scheduler queue tests.
  - Runs cross-client installer tests.
  - Runs shell syntax checks.
  - Runs Python compile checks.
  - Regenerates Codex and Claude fixtures.
  - Runs generated-output verification against upstream plus declared overlays.
  - Fails if generated Claude fixtures contain Codex adapter text.
  - Runs upstream skill conformance tests.
  - Runs upstream tracking integration tests, including nested tracking layout.
  - Runs the installed Codex verifier when available.
  - Simulates three scheduled `run-plan plans/SMOKE.md finish auto` cycles with
    a fake runner, validating prompt fidelity, `ZSKILLS_PIPELINE_ID`, scheduler
    handoff state, stopped one-shot completion state, and log/status feedback.
- Expanded `tests/test-zskills-helpers.sh` to validate direct, cherry-pick, and
  PR mode acceptance explicitly.
- Added one-shot scheduler support for `finish auto` handoffs. A completed
  one-shot job is marked stopped with `next_run: null`; the running skill can
  create a fresh due one-shot job for the next top-level phase turn.
- Hardened one-shot scheduling after real cron testing:
  - Duplicate one-shot `add` calls now allocate a fresh suffixed job id instead
    of overwriting an existing one-shot job.
  - `zskills-run-due.sh` now wraps Codex runner prompts with explicit
    scheduled-job execution instructions so cron-launched Codex turns execute
    the requested skill instead of only inspecting it.
- Ran a real OS cron canary in a disposable git repo:
  - Installed and started `cron` in the container.
  - Added a temporary user crontab entry that ran
    `scripts/zskills-run-due.sh` once per minute.
  - Verified three separate cron-fired Codex turns completed Phase 1, Phase 2,
    and Phase 3 in order.
  - Verified three `.zskills/logs/<job>/...log` files were written.
  - Verified three one-shot schedule files ended with `last_status: stopped`,
    `next_run: null`, and populated `last_run`.
  - Removed the temporary crontab entry after verification.

### Verification

- `bash tests/test-zskills-fidelity.sh`
  - Result: passed.
  - Included:
    - helper tests: 16 passed, 0 failed
    - scheduler tests: 22 passed, 0 failed
    - install tests: 14 passed, 0 failed
    - generated Codex/Claude verifier: passed
    - generated Claude Codex-leak grep: no matches
    - upstream conformance: 88 passed, 0 failed
    - upstream tracking integration: 22 passed, 0 failed
    - installed Codex verifier: passed
    - scheduled multi-phase `run-plan finish auto` canary: passed
    - real OS cron `run-plan finish auto` canary: passed

### Remaining Work

All planned phases are complete.
