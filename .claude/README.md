# Local Claude State

This directory is intentionally present so a fresh clone is also a usable Claude
workspace with the converted ZSkills available under `.claude/skills`.

Do not commit:

- `settings.local.json`: per-user Claude Code permissions and local state.
- `zskills-config.json`: project-local runtime configuration unless the repo
  deliberately decides to publish a shared config.
- `zskills-config.schema.json`: regenerated from upstream during install.

For a fresh development checkout, use the tracked setup sources instead:

- `.devcontainer/setup.sh` installs local tool dependencies and Playwright CLI
  support.
- `.claude/skills` contains the checked-in Claude-facing generated skills.
- `scripts/zskills-install.sh --client claude` refreshes Claude skill output.
- `scripts/zskills-install.sh --client both --mirror-config` installs both
  Claude and Codex outputs when intentionally mirroring config.
