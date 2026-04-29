# ZSkills CC

> **Compatibility preview.** This repository is a Codex-converted
> Claude/Codex compatibility version of
> [`github.com/zeveck/zskills`](https://github.com/zeveck/zskills). For the
> canonical Claude-only release, use upstream ZSkills. This repo is intended for
> testing and developing the cross-client conversion, and its checked-in
> `.claude/skills` directory is a generated distribution copy verified against
> the conversion pipeline.

This repository is a Codex-converted version of
[`zeveck/zskills`](https://github.com/zeveck/zskills). It is meant to preserve
the original ZSkills intent while making the workflows usable from both Codex
and Claude.

The project name "CC" is shorthand for Claude/Codex compatibility: one source
tree generates a Codex install with compatibility adapters and a Claude install
without Codex-specific adapter text.

This is intentionally a conversion and development harness, not just a generated
skill dump. Tracked development setup such as `.devcontainer/` is source for
reproducing the environment. The repo also checks in `.claude/skills` so a fresh
clone is immediately a Claude workspace with the converted ZSkills available.
Per-user client state such as `.claude/settings.local.json` and
`.claude/zskills-config.json` / `.codex/zskills-config.json` stays ignored and
should be recreated locally.

The goal is not to fork the skill bodies by hand. The source of truth is:

- upstream ZSkills checkout
- Codex compatibility adapter template
- declared overlay patches
- shared helper scripts
- verification tests

Generated output under `build/` is intentionally ignored and should be
regenerated as needed.

## What This Provides

- A reproducible conversion pipeline from original ZSkills to Claude/Codex
  compatible generated installs.
- Codex-compatible generated skills with a shared adapter block.
- Claude generated skills without Codex adapter text.
- Block-diagram add-on skills from upstream (`add-block`, `add-example`, and
  `model-design`) included in both generated clients.
- Shared helpers for:
  - `.codex` / `.claude` config precedence
  - direct, cherry-pick, and PR landing mode validation
  - procedural preflight checks for operations normally protected by hooks
  - file-backed schedules that can be driven by OS cron
  - cross-client installation
- Drift checks against upstream ZSkills plus declared overlays.
- Fidelity tests covering helper behavior, installation, generated output,
  upstream conformance, tracking integration, and scheduler behavior.

## Repository Layout

| Path | Purpose |
|---|---|
| `scripts/generate-codex-skills.py` | Generate Codex or Claude skill output from upstream plus overlays. |
| `scripts/zskills-*.sh` | Shared runtime helpers installed with generated Codex skills. |
| `templates/codex-compat-block.md` | Adapter text inserted into generated Codex skills. |
| `codex-overlays/` | Declared patch overlays for skills that need more than the generic adapter. |
| `tests/` | Helper, scheduler, install, and full fidelity tests. |
| `plans/` | Fidelity improvement plan. |
| `reports/` | Execution report and verification record. |
| `local-patches/` | Documented local upstream patch queue entries. |
| `.devcontainer/` | Reproducible development environment setup. |
| `.claude/skills/` | Checked-in Claude-facing generated skills for clone-ready use. |
| `.claude/README.md` | Documents local Claude state boundaries. |

## Prerequisites

- Upstream ZSkills checkout at `~/.codex/zskills-portable`.
- Python 3.12+.
- `bash`, `git`, `patch`, and `rg`.
- Codex CLI for Codex installation and scheduled Codex runs.
- Optional: `cron` for unattended due-job execution.

The current verifier allows one documented local upstream patch:
`clear-tracking-recursive`.

## Generate Skills

```bash
bash scripts/generate-codex-skills.sh \
  --client codex \
  --output build/codex-skills

bash scripts/generate-codex-skills.sh \
  --client claude \
  --output build/claude-skills
```

`build/` is generated and ignored.

## Install

Install Codex skills to `$CODEX_HOME/skills`:

```bash
bash scripts/zskills-install.sh --client codex
```

Install Claude skills into the project `.claude/skills` directory:

```bash
bash scripts/zskills-install.sh --client claude
```

Install both and intentionally mirror config:

```bash
bash scripts/zskills-install.sh --client both --mirror-config
```

Project config is client-scoped:

- Codex: `.codex/zskills-config.json`
- Claude: `.claude/zskills-config.json`

## Verify

Run the full fidelity suite:

```bash
bash tests/test-zskills-fidelity.sh
```

Useful focused checks:

```bash
bash tests/test-zskills-helpers.sh
bash tests/test-zskills-scheduler.sh
bash tests/test-zskills-install.sh
python scripts/verify-generated-zskills.py \
  --allow-local-upstream \
  --patch-queue-entry clear-tracking-recursive
python ~/.codex/skills/verify-zskills-codex.py
```

The full suite verifies:

- generated Codex and Claude outputs
- no Codex adapter text in generated Claude skills
- installed Codex skill shape
- helper behavior
- scheduler behavior
- cross-client install behavior
- upstream ZSkills conformance tests
- upstream tracking integration tests
- multi-phase scheduled `run-plan finish auto` canary

## Cron-Backed Scheduling

Codex does not provide Claude-style in-session cron tools. This integration uses
file-backed schedule state under `.zskills/schedules/` and a due runner:

```bash
cd /path/to/repo && scripts/zskills-run-due.sh
```

An OS cron entry can drive due jobs:

```cron
* * * * * cd /path/to/repo && /bin/bash scripts/zskills-run-due.sh >> .zskills/cron-driver.log 2>&1
```

Feedback is file-based:

- schedule state: `.zskills/schedules/*.json`
- run logs: `.zskills/logs/<job-id>/<timestamp>.log`
- plan reports: `reports/plan-*.md`

The real cron canary verified that OS cron can drive
`run-plan finish auto direct` across three separate Codex turns, with one-shot
handoff jobs and logs for each turn.

## Current Assurance

Verified:

- all 22 generated skills have valid frontmatter
- generated Claude skills match upstream originals exactly
- generated Codex skills differ only by adapter block or declared overlays
- direct, cherry-pick, and PR landing modes are preserved in helpers and skill
  instructions
- tracking filesystem rules are preserved and tested
- real cron-backed `run-plan finish auto direct` works end to end

Still worth canarying before relying on unattended production work:

- `run-plan finish auto cherry-pick` against a real repo
- `run-plan finish auto pr` against a real GitHub remote with `gh`
- failure handling where a phase intentionally fails verification
- recurring `every` schedules for `/do`, `/qe-audit`, or `/fix-issues`

## Notes

- `playwright-cli` is included from upstream `.claude/skills/playwright-cli`.
- Block-diagram add-ons are included from upstream `block-diagram/`.
- Local `.claude/` state is ignored.
- Generated `build/` output is ignored.
