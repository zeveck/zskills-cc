# Local Patch: Recursive clear-tracking

Target: shared after agreement.

Rationale: current ZSkills tracking markers are written under
`.zskills/tracking/$PIPELINE_ID/`, but the original cleanup helper scanned only
flat files directly under `.zskills/tracking`. Recursive cleanup is an
objective fix for the active marker layout.

Evidence already gathered:

- Temp repo exercise preserved nested `fulfilled.run-plan.*`.
- Temp repo exercise cleared nested `requires.*`, `step.*`, and
  `fulfilled.draft-plan.*`.
- `tests/test-tracking-integration.sh` passed after the change.
- `tests/test-skill-conformance.sh` passed after the change.

Current status: applied locally in `~/.codex/zskills-portable` and should be
carried as a named patch queue entry until proposed upstream.
