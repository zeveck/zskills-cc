# Local Claude State

This directory is intentionally present as documentation, but most of its
contents are local or generated and are ignored by git.

Do not commit:

- `settings.local.json`: per-user Claude Code permissions and local state.
- `skills/`: generated or installed skill output.
- `zskills-config.json`: project-local runtime configuration unless the repo
  deliberately decides to publish a shared config.

For a fresh development checkout, use the tracked setup sources instead:

- `.devcontainer/setup.sh` installs local tool dependencies and Playwright CLI
  support.
- `scripts/zskills-install.sh --client claude` regenerates Claude skill output.
- `scripts/zskills-install.sh --client both --mirror-config` installs both
  Claude and Codex outputs when intentionally mirroring config.
