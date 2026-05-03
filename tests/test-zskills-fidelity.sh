#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM=${ZSKILLS_UPSTREAM:-/home/vscode/.codex/zskills-portable}
ALLOW_ARGS=(--allow-local-upstream --patch-queue-entry clear-tracking-recursive)

run() {
  echo "==> $*"
  "$@"
}

run bash "$ROOT/tests/test-zskills-helpers.sh"
run bash "$ROOT/tests/test-zskills-scheduler.sh"
run bash "$ROOT/tests/test-zskills-runner.sh"
run bash "$ROOT/tests/test-zskills-install.sh"

run bash -n \
  "$ROOT/scripts/zskills-config.sh" \
  "$ROOT/scripts/zskills-preflight.sh" \
  "$ROOT/scripts/zskills-scheduler.sh" \
  "$ROOT/scripts/zskills-run-due.sh" \
  "$ROOT/scripts/zskills-runner.sh" \
  "$ROOT/scripts/zskills-gate.sh" \
  "$ROOT/scripts/zskills-post-run-invariants.sh" \
  "$ROOT/scripts/zskills-install.sh" \
  "$ROOT/tests/test-zskills-helpers.sh" \
  "$ROOT/tests/test-zskills-scheduler.sh" \
  "$ROOT/tests/test-zskills-runner.sh" \
  "$ROOT/tests/test-zskills-install.sh" \
  "$ROOT/scripts/generate-codex-skills.sh"

run python -m py_compile \
  "$ROOT/scripts/generate-codex-skills.py" \
  "$ROOT/scripts/verify-generated-zskills.py" \
  "$ROOT/scripts/verify-zskills-codex.py"

run bash "$ROOT/scripts/generate-codex-skills.sh" --client codex --output "$ROOT/build/codex-skills"
run bash "$ROOT/scripts/generate-codex-skills.sh" --client claude --output "$ROOT/build/claude-skills"
rg "zskills-runner.sh" "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
rg "RUNNER-MANAGED CHUNK" "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
rg "foreground zskills-runner.sh bridge" "$ROOT/build/codex-skills/research-and-go/SKILL.md" >/dev/null
rg "scripts/zskills-post-run-invariants.sh" "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
! rg "scripts/post-run-invariants.sh" "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
rg 'RUNNER_PLAN_FILE="\$\{PLAN_FILE:-\}"' "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
! rg -- "--landed-status" "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
! rg "runner-enable|runner-status --repo-path" "$ROOT/build/codex-skills/run-plan/SKILL.md" >/dev/null
! rg "cron-fired|one phase per cron|one-shot crons internally|chunked cron-fired" "$ROOT/build/codex-skills/run-plan/SKILL.md" "$ROOT/build/codex-skills/research-and-go/SKILL.md" >/dev/null
run python "$ROOT/scripts/verify-generated-zskills.py" "${ALLOW_ARGS[@]}"

if [ -d "$ROOT/.claude/skills" ]; then
  tmp_claude=$(mktemp -d)
  run bash "$ROOT/scripts/generate-codex-skills.sh" --client claude --output "$tmp_claude"
  if ! diff -qr \
    --exclude generation-manifest.json \
    --exclude scripts \
    "$tmp_claude" "$ROOT/.claude/skills" >/tmp/zskills-fidelity-claude-drift.out; then
    cat /tmp/zskills-fidelity-claude-drift.out
    echo "FAILED: checked-in .claude/skills drifted from generated Claude skills" >&2
    exit 1
  fi
fi

if [ -d "$ROOT/.agents/skills" ]; then
  tmp_codex=$(mktemp -d)
  run bash "$ROOT/scripts/generate-codex-skills.sh" --client codex --output "$tmp_codex"
  if ! diff -qr "$tmp_codex" "$ROOT/.agents/skills" >/tmp/zskills-fidelity-codex-drift.out; then
    cat /tmp/zskills-fidelity-codex-drift.out
    echo "FAILED: checked-in .agents/skills drifted from generated Codex skills" >&2
    exit 1
  fi
fi

if rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" "$ROOT/build/claude-skills" >/tmp/zskills-fidelity-claude-leak.out; then
  cat /tmp/zskills-fidelity-claude-leak.out
  echo "FAILED: generated Claude skills contain Codex adapter text" >&2
  exit 1
fi

run bash "$UPSTREAM/tests/test-skill-conformance.sh"
run bash "$UPSTREAM/tests/test-tracking-integration.sh"

if [ -f "$ROOT/.agents/skills/verify-zskills-codex.py" ]; then
  run python "$ROOT/.agents/skills/verify-zskills-codex.py"
fi

echo "OK: ZSkills fidelity suite passed"
