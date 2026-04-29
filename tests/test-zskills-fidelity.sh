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
run bash "$ROOT/tests/test-zskills-install.sh"

run bash -n \
  "$ROOT/scripts/zskills-config.sh" \
  "$ROOT/scripts/zskills-preflight.sh" \
  "$ROOT/scripts/zskills-scheduler.sh" \
  "$ROOT/scripts/zskills-run-due.sh" \
  "$ROOT/scripts/zskills-install.sh" \
  "$ROOT/tests/test-zskills-helpers.sh" \
  "$ROOT/tests/test-zskills-scheduler.sh" \
  "$ROOT/tests/test-zskills-install.sh" \
  "$ROOT/scripts/generate-codex-skills.sh"

run python -m py_compile \
  "$ROOT/scripts/generate-codex-skills.py" \
  "$ROOT/scripts/verify-generated-zskills.py"

run bash "$ROOT/scripts/generate-codex-skills.sh" --client codex --output "$ROOT/build/codex-skills"
run bash "$ROOT/scripts/generate-codex-skills.sh" --client claude --output "$ROOT/build/claude-skills"
run python "$ROOT/scripts/verify-generated-zskills.py" "${ALLOW_ARGS[@]}"

if rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" "$ROOT/build/claude-skills" >/tmp/zskills-fidelity-claude-leak.out; then
  cat /tmp/zskills-fidelity-claude-leak.out
  echo "FAILED: generated Claude skills contain Codex adapter text" >&2
  exit 1
fi

run bash "$UPSTREAM/tests/test-skill-conformance.sh"
run bash "$UPSTREAM/tests/test-tracking-integration.sh"

if [ -f "$HOME/.codex/skills/verify-zskills-codex.py" ]; then
  run python "$HOME/.codex/skills/verify-zskills-codex.py"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

repo="$tmp/smoke-repo"
mkdir -p "$repo/scripts" "$repo/plans"
cd "$repo"
git init -q
git config user.email test@example.com
git config user.name test
touch README.md
git add README.md
git commit -q -m init
cp "$ROOT/scripts/zskills-scheduler.sh" scripts/
cp "$ROOT/scripts/zskills-run-due.sh" scripts/

cat > scripts/fake-runner.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'PROMPT=%s\n' "${1:-}" >> .zskills/fake-runner.log
printf 'PIPELINE=%s\n' "${ZSKILLS_PIPELINE_ID:-}" >> .zskills/fake-runner.log
case "${1:-}" in
  "run-plan plans/SMOKE.md finish auto") ;;
  *) echo "unexpected prompt: ${1:-}" >&2; exit 9 ;;
esac

python - <<'PY'
import json
import re
import subprocess
from pathlib import Path

plan = Path("plans/SMOKE.md")
text = plan.read_text()
match = re.search(r"\| Phase (\d+): ([^|]+) \| Next \|", text)
if not match:
    raise SystemExit("no next phase")
phase = int(match.group(1))
text = text.replace(f"| Phase {phase}: {match.group(2)} | Next |", f"| Phase {phase}: {match.group(2)} | Done |")
next_phase = phase + 1
text = text.replace(f"| Phase {next_phase}:", f"| Phase {next_phase}:")
if f"| Phase {next_phase}:" in text:
    text = re.sub(rf"(\| Phase {next_phase}: [^|]+ \|) Pending \|", r"\1 Next |", text)
plan.write_text(text)

if f"| Phase {next_phase}:" in text:
    subprocess.run([
        "scripts/zskills-scheduler.sh",
        "add",
        "--id",
        f"run-plan-finish-auto-canary-{next_phase}",
        "--skill",
        "run-plan",
        "--args",
        "plans/SMOKE.md finish auto",
        "--schedule",
        "5m",
        "--runner-command",
        str(Path("scripts/fake-runner.sh").resolve()),
        "--pipeline-id",
        "run-plan.canary",
        "--one-shot",
    ], check=True, stdout=subprocess.DEVNULL)
    schedule = Path(f".zskills/schedules/run-plan-finish-auto-canary-{next_phase}.json")
    job = json.loads(schedule.read_text())
    job["next_run"] = "2000-01-01T00:00:00Z"
    job["last_status"] = "pending"
    schedule.write_text(json.dumps(job, indent=2, sort_keys=True) + "\n")
PY
SH
chmod +x scripts/fake-runner.sh

cat > plans/SMOKE.md <<'MD'
# Multi-Phase Smoke Plan

| Phase | Status |
|---|---|
| Phase 1: Alpha | Next |
| Phase 2: Beta | Pending |
| Phase 3: Gamma | Pending |
MD

scripts/zskills-scheduler.sh add \
  --id run-plan-finish-auto-canary-1 \
  --skill run-plan \
  --args "plans/SMOKE.md finish auto" \
  --schedule 5m \
  --runner-command "$repo/scripts/fake-runner.sh" \
  --pipeline-id run-plan.canary \
  --one-shot >/dev/null

python - <<'PY'
import json
from pathlib import Path
p = Path(".zskills/schedules/run-plan-finish-auto-canary-1.json")
j = json.loads(p.read_text())
j["next_run"] = "2000-01-01T00:00:00Z"
p.write_text(json.dumps(j, indent=2) + "\n")
PY

scripts/zskills-run-due.sh
scripts/zskills-run-due.sh
scripts/zskills-run-due.sh
rg "PROMPT=run-plan plans/SMOKE.md finish auto" .zskills/fake-runner.log >/dev/null
rg "PIPELINE=run-plan.canary" .zskills/fake-runner.log >/dev/null
[ "$(rg -c "PROMPT=run-plan plans/SMOKE.md finish auto" .zskills/fake-runner.log)" -eq 3 ]
rg "\| Phase 1: Alpha \| Done \|" plans/SMOKE.md >/dev/null
rg "\| Phase 2: Beta \| Done \|" plans/SMOKE.md >/dev/null
rg "\| Phase 3: Gamma \| Done \|" plans/SMOKE.md >/dev/null
python - <<'PY'
import json
from pathlib import Path
for phase in (1, 2, 3):
    j = json.loads(Path(f".zskills/schedules/run-plan-finish-auto-canary-{phase}.json").read_text())
    if j["last_status"] != "stopped" or not j["last_run"]:
        raise SystemExit(1)
PY

echo "OK: ZSkills fidelity suite passed"
