# ZSkills Skill Canary Plan

## Goal

Build an autonomous canary suite that exercises all 22 ZSkills in a local fake
repository, with deterministic pass/fail assertions and logs. The suite should
increase confidence that the converted Claude/Codex skills behave as usable
workflows, not only as textually faithful generated files.

This plan avoids real GitHub writes, avoids mutating checked-in skill YAML, and
keeps all canary artifacts local and disposable.

## Scope

In scope:

- Project-local Codex skill loading from `.codex/skills`.
- Checked-in Claude skill presence and textual safety checks.
- Local fake repo fixtures for block-diagram, plan, issue, docs, and git
  workflows.
- Bounded Codex `exec` canaries for representative skill invocations.
- Deterministic shell assertions over files, git state, reports, and logs.
- Optional scheduler handoff canary using `zskills-scheduler.sh` without OS cron.

Out of scope:

- Real GitHub issue creation, PR creation, or merge.
- Real production repos.
- Removing or editing checked-in skill frontmatter to force model invocation.
- Native Claude execution, unless run separately by a human in Claude.

## Safety Rules

- All canary repos live under `.tmp/zskills-canaries/` or another ignored temp
  root.
- Tests must never write under `$HOME/.codex/skills` unless explicitly testing
  the installer in an isolated `CODEX_HOME`.
- Do not modify checked-in `.codex/skills` or `.claude/skills` during canaries.
- If a future test requires temporarily changing YAML/frontmatter, do it only in
  a copied fixture skill tree, write `.zskills/canaries/RESTORE_REQUIRED`, and
  make the suite fail until restoration is complete. Also schedule a one-shot
  reminder through `scripts/zskills-scheduler.sh` if the suite cannot restore
  immediately.
- Default landing mode is `direct` inside fake repos. PR and cherry-pick mode
  canaries require explicit fake remote/worktree fixtures.

## Progress

| Phase | Status | Summary |
|---|---|---|
| Phase 1: Harness And Fixtures | Next | Create the reusable fake repo and canary runner. |
| Phase 2: Static And Loader Canaries | Pending | Verify project-local skill loading and generated skill boundaries. |
| Phase 3: Low-Risk Skill Canaries | Pending | Exercise read-only/reference/planning skills with file assertions. |
| Phase 4: Workflow Skill Canaries | Pending | Exercise execution, verification, scheduling, and landing workflows locally. |
| Phase 5: Domain Add-On Canaries | Pending | Exercise block-diagram add-ons against fake block-diagram fixtures. |
| Phase 6: Reporting And CI Hookup | Pending | Produce a matrix report and wire the suite into existing fidelity checks. |

## Phase 1: Harness And Fixtures

Status: Next

### Objective

Create a reusable local canary harness that can run Codex skill invocations in a
fake repo and assert results without touching real user/project skills.

### Implementation

Add:

- `tests/test-zskills-canaries.sh`
- `tests/fixtures/canary-repo/` or generated fixture builders inside the script
- `.gitignore` entry for `.tmp/`

The harness should:

1. Create a temp fake repo under `.tmp/zskills-canaries/<run-id>/repo`.
2. Initialize git and configure local user/email.
3. Copy or symlink checked-in `.codex/skills` into the fake repo so Codex uses
   project-local skills.
4. Copy repo helper scripts into the fake repo under `scripts/`.
5. Write `.codex/zskills-config.json` with:
   - `execution.landing = direct`
   - `execution.main_protected = false`
   - fake test commands that are fast and deterministic
6. Provide helpers:
   - `run_codex_canary NAME PROMPT ASSERTION...`
   - `assert_file_contains PATH PATTERN`
   - `assert_file_exists PATH`
   - `assert_git_clean`
   - `assert_no_real_remote`
   - `record_log NAME`

### Acceptance Criteria

- Harness can create and delete a fake repo.
- Harness can run a trivial project-local `.codex/skills/project-canary` prompt
  and assert the exact response.
- Harness logs prompt/output to `.tmp/zskills-canaries/<run-id>/logs/`.
- Harness refuses to run if the fake repo has a non-local remote.

### Verification

Run:

```bash
bash tests/test-zskills-canaries.sh --phase harness
```

Expected:

- project-local skill canary passes
- no files outside `.tmp/` and ignored local config are modified

## Phase 2: Static And Loader Canaries

Status: Pending

### Objective

Verify the clone-ready skill distributions before running behavioral canaries.

### Implementation

Extend `tests/test-zskills-canaries.sh` with a static phase that checks:

- all 22 skill names exist in `.codex/skills`
- all 22 skill names exist in `.claude/skills`
- `.codex/skills` matches fresh `--client codex` generation
- `.claude/skills` matches fresh `--client claude` generation
- project-local Codex loading works in a temp repo
- global `$CODEX_HOME/skills` is not required for project-local canaries

### Acceptance Criteria

- Static canary fails if any skill is missing from either checked-in client.
- Static canary fails if `.codex/skills` or `.claude/skills` drift from fresh
  generated output.
- Static canary proves a project-local skill can be invoked with a clean
  temporary `CODEX_HOME` only when auth is available; otherwise it records
  `skipped-auth` clearly.

### Verification

Run:

```bash
bash tests/test-zskills-canaries.sh --phase static
```

## Phase 3: Low-Risk Skill Canaries

Status: Pending

### Objective

Exercise read-only and planning-heavy skills with bounded prompts and local file
assertions.

### Canary Matrix

| Skill | Prompt Shape | Expected Assertion |
|---|---|---|
| `briefing` | summarize fake repo state | output mentions current branch and local files |
| `plans` | rebuild/list fake plans | `.zskills` or report output lists expected plan |
| `draft-plan` | draft tiny plan for fake README edit | creates `plans/CANARY_DRAFT.md` |
| `refine-plan` | refine fake plan with one pending phase | appends review/drift notes without changing completed phases |
| `research-and-plan` | decompose tiny two-step fake task | creates sub-plan or meta-plan |
| `research-and-go` | run on a deliberately tiny fake docs-only task | creates plan/report artifacts and stops cleanly after bounded execution |
| `model-design` | review a tiny model JSON layout | output flags or confirms layout rules |
| `manual-testing` | ask for Playwright steps against fake editor page | output uses `playwright-cli` commands |
| `playwright-cli` | ask for command guidance only | output references valid CLI command shape |

### Acceptance Criteria

- Each canary has a bounded prompt and a deterministic file/output assertion.
- Failures are reported as `skill`, `prompt`, `log`, `assertion`.
- No canary requires real browser, GitHub, or network.

### Verification

Run:

```bash
bash tests/test-zskills-canaries.sh --phase low-risk
```

## Phase 4: Workflow Skill Canaries

Status: Pending

### Objective

Exercise workflow skills that modify files, use tracking, run verification, or
schedule follow-up work.

### Canary Matrix

| Skill | Fixture | Expected Assertion |
|---|---|---|
| `run-plan` | three-phase fake plan | one phase runs, report/tracking updated |
| `run-plan finish auto` | fake multi-phase plan + scheduler helper | one-shot schedules next phase and completes after due runner calls |
| `do` | fake README task | file changed and report/log written |
| `commit` | staged fake change | commits only intended file |
| `verify-changes` | fake diff + fake test command | report says tests passed |
| `investigate` | simple failing shell/test fixture | root cause appears before fix |
| `qe-audit` | fake recent commit | audit report/log written |
| `fix-issues` | fake issue list/export | skipped or local-only report, no real GitHub writes |
| `fix-report` | fake sprint report | report processing output, no real landing |

### Implementation Notes

- Use direct mode unless testing landing-specific behavior.
- For `commit`, isolate in a fake repo and verify no unrelated files are staged.
- For `fix-issues` and `fix-report`, stub `gh` in `PATH` with a fake executable
  that records calls and refuses network operations.
- For scheduler canaries, call `scripts/zskills-run-due.sh` manually rather than
  OS cron.

### Acceptance Criteria

- At least one canary per workflow skill passes.
- `fix-issues` and `fix-report` prove they do not call real `gh`.
- Scheduler canary proves each phase is fired through the scheduler path, not by
  directly invoking phase code.

### Verification

Run:

```bash
bash tests/test-zskills-canaries.sh --phase workflow
```

## Phase 5: Domain Add-On Canaries

Status: Pending

### Objective

Exercise block-diagram and documentation skills against a fake but realistic
block-diagram project tree.

### Fixture

Create minimal files:

- `src/engine/blocks/Block.js`
- `src/library/block-registry.js`
- `src/ui/block-explorer-data.js`
- `examples/README.md`
- `getting-started/BLOCK_LIBRARY.md`
- `plans/blocks/math/12-gain.md`
- fake `package.json` with deterministic `test:all`

### Canary Matrix

| Skill | Prompt Shape | Expected Assertion |
|---|---|---|
| `add-block` | add tiny fake `Clamp` block from existing plan | creates/edits expected block files or stops with missing-plan report |
| `add-example` | create example for fake `Gain` block | writes example model or report with exact registry-derived params |
| `doc blocks` | audit fake block docs | reports missing docs/examples for known fake block |
| `review-feedback` | triage local exported feedback JSON | creates local triage report; fake `gh` records no unintended writes |
| `update-zskills` | dry local update in fake repo | installs/preserves skill/config boundaries |

### Acceptance Criteria

- Add-on canaries do not need a real block-diagram app.
- If a skill correctly stops because fixture requirements are incomplete, the
  assertion must verify the stop reason and required next file.
- `update-zskills` must preserve unrelated fake skills, mirroring the installer
  safety tests.

### Verification

Run:

```bash
bash tests/test-zskills-canaries.sh --phase domain
```

## Phase 6: Reporting And CI Hookup

Status: Pending

### Objective

Make the canary suite maintainable and visible without making the normal
fidelity suite too slow by default.

### Implementation

Add:

- `reports/zskills-canary-matrix.md` generated by the test script
- `tests/test-zskills-canaries.sh --list`
- `tests/test-zskills-canaries.sh --phase all`
- Optional integration into `tests/test-zskills-fidelity.sh` behind
  `ZSKILLS_RUN_CANARIES=1`

The report should include:

- skill name
- client scope tested (`codex-project`, `claude-static`, or both)
- canary type
- status
- log path
- skipped reason, if any

### Acceptance Criteria

- `bash tests/test-zskills-canaries.sh --list` prints all 22 skills.
- `ZSKILLS_RUN_CANARIES=1 bash tests/test-zskills-fidelity.sh` runs the canary
  suite after existing checks.
- Default `bash tests/test-zskills-fidelity.sh` remains reasonably fast and does
  not run expensive model canaries unless explicitly enabled.

## Recommended First Canary Batch

Start with:

1. Phase 1 harness.
2. Phase 2 static/loader checks.
3. A tiny `briefing`, `plans`, `draft-plan`, `model-design`, and
   `run-plan finish auto` canary.

Do not start with all 22 skills. The first batch should prove the harness,
logging, skip handling, and scheduler assertions before spending tokens on the
larger matrix.

## Open Questions

- Should expensive model-backed canaries be run only manually, or also in a
  nightly local cron?
- Should canaries use a fresh `CODEX_HOME` and API auth, or the user's current
  Codex home?
- Do we want a separate Claude manual checklist for `.claude/skills`, or is
  generated-output fidelity enough for now?

## Completion Criteria

The plan is complete when:

- every skill has at least one canary entry
- each canary is deterministic or clearly marked `skipped-*`
- checked-in `.codex/skills` and `.claude/skills` still pass drift checks
- the suite can be run from a fresh clone without deleting unrelated skills
- generated reports make failures easy to reproduce from a single log path
