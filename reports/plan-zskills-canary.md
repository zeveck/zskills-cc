# ZSkills Canary Plan Report

## Phase 1: Harness And Fixtures

Status: Done

Implemented:

- Added `tests/test-zskills-canaries.sh`.
- Added `.tmp/` to `.gitignore` for disposable canary repositories and logs.
- Harness creates a fake git repo under `.tmp/zskills-canaries/<run-id>/repo`.
- Harness copies checked-in `.codex/skills` into the fake repo for project-local Codex skill loading.
- Harness copies `scripts/zskills-*.sh` helpers into the fake repo.
- Harness writes a direct-mode `.codex/zskills-config.json` and deterministic fake test command.
- Harness adds a temporary `project-canary` skill and runs `codex exec` against it.
- Harness records prompt, transcript, and answer logs under `.tmp/zskills-canaries/<run-id>/logs`.

Verification:

```bash
bash tests/test-zskills-canaries.sh --phase harness
```

Result:

- `5 passed, 0 failed`
- Project-local skill loader response matched exactly: `PROJECT_LAYER_SKILL_LOADED_49217`

Notes:

- The Codex transcript included a non-fatal `failed to record rollout items` message after completion; the command exited 0 and the asserted final answer was correct.
- No checked-in skill YAML/frontmatter was modified.
- No real git remote was configured in the fake repo.
