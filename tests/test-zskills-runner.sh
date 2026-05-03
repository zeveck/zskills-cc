#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local repo=$1 phases=${2:-2}
  mkdir -p "$repo/plans" "$repo/reports" "$repo/scripts" "$repo/.codex"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config user.name test
  printf '.zskills/\n' > "$repo/.gitignore"
  cat > "$repo/.codex/zskills-config.json" <<'JSON'
{
  "execution": {
    "landing": "cherry-pick",
    "base_branch": "main",
    "remote": "origin"
  },
  "runner": {
    "max_chunks": 5,
    "chunk_timeout_seconds": 20,
    "idle_timeout_seconds": 10,
    "sandbox": "workspace-write",
    "approval_policy": "never",
    "allow_direct_unattended": true
  }
}
JSON
  {
    printf '# Runner Canary\n\n'
    printf '| Phase | Status |\n'
    printf '|---|---|\n'
    local i
    for i in $(seq 1 "$phases"); do
      if [ "$i" -eq 1 ]; then
        printf '| Phase %s: Step %s | Next |\n' "$i" "$i"
      else
        printf '| Phase %s: Step %s | Pending |\n' "$i" "$i"
      fi
    done
  } > "$repo/plans/CANARY.md"
  cp "$ROOT/scripts/zskills-runner.sh" "$repo/scripts/"
  cp "$ROOT/scripts/zskills-gate.sh" "$repo/scripts/"
  cp "$ROOT/scripts/zskills-post-run-invariants.sh" "$repo/scripts/"
  git -C "$repo" add .gitignore .codex/zskills-config.json plans/CANARY.md scripts
  git -C "$repo" commit -q -m init
}

write_fake_codex() {
  local path=$1
  cat > "$path" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

prompt="${@: -1}"
mode="${FAKE_CODEX_MODE:-ok}"
workdir=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "-C" ]; then
    workdir="$arg"
    break
  fi
  prev="$arg"
done
[ -n "$workdir" ] && cd "$workdir"
mkdir -p .zskills/fake-codex
printf '%q ' "$@" >> .zskills/fake-codex/argv.log
printf '\n' >> .zskills/fake-codex/argv.log

case "$*" in
  *" resume "*) echo "unexpected resume" >&2; exit 13 ;;
esac
case "$prompt" in
  *"RUNNER-MANAGED CHUNK"*) ;;
  *) echo "missing runner chunk prompt" >&2; exit 14 ;;
esac

repo=$(printf '%s\n' "$prompt" | sed -n 's/^- Repository root: //p' | head -1)
plan=$(printf '%s\n' "$prompt" | sed -n 's/^- Plan path: //p' | head -1)
report=$(printf '%s\n' "$prompt" | sed -n 's/^- Report path: //p' | head -1)
pr_worktree=$(printf '%s\n' "$prompt" | sed -n 's/^- PR worktree path: //p' | head -1)
pipeline=$(printf '%s\n' "$prompt" | sed -n 's/^- Pipeline id: //p' | head -1)
tracking_dir=$(printf '%s\n' "$prompt" | sed -n 's/^- Tracking directory: //p' | head -1)
seed=$(printf '%s\n' "$prompt" | sed -n 's/^- Tracking id: use exactly \\([^ ]*\\) for every marker written by this chunk\\.$/\\1/p' | head -1)
[ -n "$seed" ] || seed="${ZSKILLS_TRACKING_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

cd "$repo"
mkdir -p "$tracking_dir" "$(dirname "$report")"

if [[ "$prompt" == *"Resolved landing mode: pr."* ]]; then
  if [ ! -d "$pr_worktree" ]; then
    git worktree add -q "$pr_worktree" -b "feat/$seed" HEAD
  fi
  cd "$pr_worktree"
  plan="$pr_worktree/plans/CANARY.md"
  report="$pr_worktree/reports/plan-plans-canary.md"
  if [ "$mode" = "pr-wrong-tracking" ]; then
    tracking_dir="$pr_worktree/.zskills/tracking/$pipeline"
  fi
  mkdir -p "$(dirname "$report")"
fi

if [ "$mode" = "sleep" ]; then
  sleep 30
fi

if [ "$mode" = "sandbox-fail" ]; then
  echo "bwrap: No permissions to create a new namespace, likely because the kernel does not allow non-privileged user namespaces" >&2
  exit 1
fi

if [ "$mode" = "no-progress" ]; then
  echo "FAKE_CHILD_PROGRESS no progress"
  exit 0
fi

python3 - "$plan" "$report" "$tracking_dir" "$seed" "$mode" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

plan = Path(sys.argv[1])
report = Path(sys.argv[2])
tracking = Path(sys.argv[3])
tracking_id = sys.argv[4]
mode = sys.argv[5]

text = plan.read_text()
match = re.search(r"\| Phase (\d+): ([^|]+) \| Next \|", text)
if not match:
    raise SystemExit("no next phase")
phase = int(match.group(1))
title = match.group(2).strip()
print(f"FAKE_CHILD_PROGRESS phase {phase}", flush=True)

if mode == "dirty":
    Path("DIRTY.txt").write_text("dirty\n")

text = text.replace(f"| Phase {phase}: {title} | Next |", f"| Phase {phase}: {title} | Done |")
next_match = re.search(r"\| Phase %d: ([^|]+) \| Pending \|" % (phase + 1), text)
complete = next_match is None
if next_match:
    next_title = next_match.group(1).strip()
    text = text.replace(f"| Phase {phase + 1}: {next_title} | Pending |", f"| Phase {phase + 1}: {next_title} | Next |")
plan.write_text(text)

report.write_text(
    f"## Phase {phase}: {title}\n"
    "Status: complete\n\n"
    "Tests\n- fake tests run\n\n"
    "Verification\n- fake verification complete\n\n"
    "Landing\n- fake landing complete\n\n"
    "Remaining\n- " + ("none" if complete else "more phases") + "\n\n"
    "Scope Assessment\n- fake scope assessed\n"
)

tracking.mkdir(parents=True, exist_ok=True)
if mode != "stale-markers":
    for marker in [
        f"step.run-plan.{tracking_id}.implement",
        f"step.run-plan.{tracking_id}.verify",
        f"step.run-plan.{tracking_id}.report",
    ]:
        (tracking / marker).write_text(f"phase {phase}\n")

if mode not in {"missing-verifier", "stale-markers"}:
    for marker in [
        f"requires.verify-changes.{tracking_id}",
        f"step.verify-changes.{tracking_id}.tests-run",
        f"step.verify-changes.{tracking_id}.complete",
        f"fulfilled.verify-changes.{tracking_id}",
    ]:
        (tracking / marker).write_text(f"phase {phase}\n")

handoff = tracking / f"handoff.run-plan.{tracking_id}"
if mode == "stale-markers":
    pass
elif complete:
    handoff.unlink(missing_ok=True)
    (tracking / f"step.run-plan.{tracking_id}.land").write_text("ok\n")
    (tracking / f"fulfilled.run-plan.{tracking_id}").write_text("status: fulfilled\n")
elif mode != "missing-handoff":
    if mode == "premature-final":
        (tracking / f"step.run-plan.{tracking_id}.land").write_text("premature\n")
        (tracking / f"fulfilled.run-plan.{tracking_id}").write_text("premature\n")
    handoff.write_text("continue\n")

if mode != "dirty":
    subprocess.run(["git", "add", str(plan), str(report)], check=True)
    subprocess.run(["git", "commit", "-q", "-m", f"fake phase {phase}"], check=True)
PY
SH
  chmod +x "$path"
}

assert_rg() {
  local pattern=$1 file=$2
  if ! rg -- "$pattern" "$file" >/dev/null; then
    echo "missing pattern '$pattern' in $file" >&2
    cat "$file" >&2
    return 1
  fi
}

fake="$tmp/fake-codex"
write_fake_codex "$fake"

repo="$tmp/default-sandbox"
make_repo "$repo" 1
"$repo/scripts/zskills-runner.sh" status plans/CANARY.md --repo "$repo" >"$tmp/default-sandbox.status"
assert_rg "^sandbox=workspace-write$" "$tmp/default-sandbox.status"
! rg "danger-full-access" "$tmp/default-sandbox.status" >/dev/null

repo="$tmp/two-phase"
make_repo "$repo" 2
out="$tmp/two-phase.out"
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$out" 2>&1
assert_rg "chunk 1 start" "$out"
assert_rg "chunk 2 start" "$out"
assert_rg "FAKE_CHILD_PROGRESS phase 1" "$out"
assert_rg "FAKE_CHILD_PROGRESS phase 2" "$out"
assert_rg "runner_stop_reason=complete" "$out"
assert_rg "\\| Phase 1: Step 1 \\| Done \\|" "$repo/plans/CANARY.md"
assert_rg "\\| Phase 2: Step 2 \\| Done \\|" "$repo/plans/CANARY.md"
[ "$(wc -l < "$repo/.zskills/fake-codex/argv.log")" -eq 2 ]
! rg "resume" "$repo/.zskills/fake-codex/argv.log" >/dev/null
assert_rg "--sandbox workspace-write" "$repo/.zskills/fake-codex/argv.log"
! rg "danger-full-access" "$repo/.zskills/fake-codex/argv.log" >/dev/null

repo="$tmp/explicit-danger-sandbox"
make_repo "$repo" 1
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended --sandbox danger-full-access >"$tmp/explicit-danger-sandbox.out" 2>&1
assert_rg "runner_stop_reason=complete" "$tmp/explicit-danger-sandbox.out"
assert_rg "--sandbox danger-full-access" "$repo/.zskills/fake-codex/argv.log"

repo="$tmp/sandbox-fail"
make_repo "$repo" 1
set +e
FAKE_CODEX_MODE=sandbox-fail CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/sandbox-fail.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "runner_stop_reason=sandbox-unavailable" "$tmp/sandbox-fail.out"
assert_rg "rerun explicitly with:" "$tmp/sandbox-fail.out"
assert_rg "--sandbox danger-full-access" "$tmp/sandbox-fail.out"
[ "$(wc -l < "$repo/.zskills/fake-codex/argv.log")" -eq 1 ]

repo="$tmp/pr-mode-$$"
rm -rf "/tmp/$(basename "$repo")-pr-canary"
make_repo "$repo" 2
out="$tmp/pr-mode.out"
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto pr --repo "$repo" >"$out" 2>&1
assert_rg "chunk 1 start" "$out"
assert_rg "chunk 2 start" "$out"
assert_rg "runner_stop_reason=complete" "$out"
pr_worktree=$(sed -n 's/^pr_worktree_path=//p' "$out" | head -1)
[ -d "$pr_worktree" ]
assert_rg "\\| Phase 1: Step 1 \\| Done \\|" "$pr_worktree/plans/CANARY.md"
assert_rg "\\| Phase 2: Step 2 \\| Done \\|" "$pr_worktree/plans/CANARY.md"
assert_rg "\\| Phase 1: Step 1 \\| Next \\|" "$repo/plans/CANARY.md"
git -C "$repo" worktree remove -f "$pr_worktree" >/dev/null 2>&1 || rm -rf "$pr_worktree"

repo="$tmp/pr-stale-root-$$"
rm -rf "/tmp/$(basename "$repo")-pr-canary"
make_repo "$repo" 1
"$repo/scripts/zskills-runner.sh" status plans/CANARY.md --repo "$repo" >"$tmp/pr-stale-root.status"
stale_pr=$(sed -n 's/^pr_worktree_path=//p' "$tmp/pr-stale-root.status")
mkdir -p "$stale_pr"
set +e
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto pr --repo "$repo" >"$tmp/pr-stale-root.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "stale PR artifact root exists but is not a git worktree" "$tmp/pr-stale-root.out"
[ ! -f "$repo/.zskills/fake-codex/argv.log" ]
rm -rf "$stale_pr"

repo="$tmp/pr-split-state-$$"
rm -rf "/tmp/$(basename "$repo")-pr-canary"
make_repo "$repo" 1
set +e
FAKE_CODEX_MODE=pr-wrong-tracking CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto pr --repo "$repo" >"$tmp/pr-split-state.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "artifact root" "$tmp/pr-split-state.out"
assert_rg "tracking root" "$tmp/pr-split-state.out"
pr_worktree=$(sed -n 's/^pr_worktree_path=//p' "$tmp/pr-split-state.out" | head -1)
[ -d "$pr_worktree" ] && git -C "$repo" worktree remove -f "$pr_worktree" >/dev/null 2>&1 || true

repo="$tmp/resume"
make_repo "$repo" 2
set +e
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended --max-chunks 1 >"$tmp/resume-1.out" 2>&1
rc=$?
set -e
[ "$rc" -eq 30 ]
assert_rg "runner_stop_reason=max-chunks" "$tmp/resume-1.out"
assert_rg "\\| Phase 1: Step 1 \\| Done \\|" "$repo/plans/CANARY.md"
assert_rg "\\| Phase 2: Step 2 \\| Next \\|" "$repo/plans/CANARY.md"
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/resume-2.out" 2>&1
assert_rg "runner_stop_reason=complete" "$tmp/resume-2.out"
assert_rg "\\| Phase 2: Step 2 \\| Done \\|" "$repo/plans/CANARY.md"

repo="$tmp/no-progress"
make_repo "$repo" 1
set +e
FAKE_CODEX_MODE=no-progress CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/no-progress.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "no durable progress detected" "$tmp/no-progress.out"

repo="$tmp/missing-handoff"
make_repo "$repo" 2
set +e
FAKE_CODEX_MODE=missing-handoff CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/missing-handoff.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "missing marker: handoff.run-plan" "$tmp/missing-handoff.out"

repo="$tmp/premature-final"
make_repo "$repo" 2
set +e
FAKE_CODEX_MODE=premature-final CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/premature-final.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "land marker present before plan completion" "$tmp/premature-final.out"

repo="$tmp/missing-verifier"
make_repo "$repo" 1
set +e
FAKE_CODEX_MODE=missing-verifier CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/missing-verifier.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "missing marker: requires.verify-changes" "$tmp/missing-verifier.out"

repo="$tmp/dirty"
make_repo "$repo" 1
set +e
FAKE_CODEX_MODE=dirty CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/dirty.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "unexpected dirty project artifact" "$tmp/dirty.out"

repo="$tmp/stale-markers"
make_repo "$repo" 1
"$repo/scripts/zskills-runner.sh" status plans/CANARY.md --repo "$repo" > "$tmp/stale-status.out"
pipeline=$(sed -n 's/^pipeline_id=//p' "$tmp/stale-status.out")
tracking=$(sed -n 's/^tracking_id=//p' "$tmp/stale-status.out")
mkdir -p "$repo/.zskills/tracking/$pipeline"
for marker in \
  "step.run-plan.$tracking.implement" \
  "step.run-plan.$tracking.verify" \
  "step.run-plan.$tracking.report" \
  "requires.verify-changes.$tracking" \
  "step.verify-changes.$tracking.tests-run" \
  "step.verify-changes.$tracking.complete" \
  "fulfilled.verify-changes.$tracking" \
  "step.run-plan.$tracking.land" \
  "fulfilled.run-plan.$tracking"; do
  printf 'stale\n' > "$repo/.zskills/tracking/$pipeline/$marker"
done
printf 'status: complete\n' > "$repo/.zskills/tracking/$pipeline/fulfilled.run-plan.$tracking"
set +e
FAKE_CODEX_MODE=stale-markers CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/stale-markers.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "stale marker was not updated" "$tmp/stale-markers.out"

repo="$tmp/refuse-direct"
make_repo "$repo" 1
python3 - "$repo/.codex/zskills-config.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
j = json.loads(p.read_text())
j["runner"]["allow_direct_unattended"] = False
p.write_text(json.dumps(j, indent=2) + "\n")
PY
git -C "$repo" add .codex/zskills-config.json
git -C "$repo" commit -q -m config
set +e
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" >"$tmp/refuse-direct.out" 2>&1
rc=$?
set -e
[ "$rc" -ne 0 ]
assert_rg "direct unattended execution is refused" "$tmp/refuse-direct.out"

repo="$tmp/same-basename"
make_repo "$repo" 1
mkdir -p "$repo/plans/a" "$repo/plans/b"
cp "$repo/plans/CANARY.md" "$repo/plans/a/task.md"
cp "$repo/plans/CANARY.md" "$repo/plans/b/task.md"
git -C "$repo" add plans/a/task.md plans/b/task.md
git -C "$repo" commit -q -m same-basename
"$repo/scripts/zskills-runner.sh" status plans/a/task.md --repo "$repo" > "$tmp/status-a.out"
"$repo/scripts/zskills-runner.sh" status plans/b/task.md --repo "$repo" > "$tmp/status-b.out"
key_a=$(sed -n 's/^plan_key=//p' "$tmp/status-a.out")
key_b=$(sed -n 's/^plan_key=//p' "$tmp/status-b.out")
report_a=$(sed -n 's/^report_path=//p' "$tmp/status-a.out")
report_b=$(sed -n 's/^report_path=//p' "$tmp/status-b.out")
[ "$key_a" != "$key_b" ]
[ "$report_a" != "$report_b" ]

repo="$tmp/stopped"
make_repo "$repo" 1
"$repo/scripts/zskills-runner.sh" stop plans/CANARY.md --repo "$repo" >/dev/null
CODEX_BIN="$fake" "$repo/scripts/zskills-runner.sh" run-plan plans/CANARY.md finish auto direct --repo "$repo" --allow-direct-unattended >"$tmp/stopped.out" 2>&1
assert_rg "runner_stop_reason=stopped" "$tmp/stopped.out"

echo "OK: zskills foreground runner tests passed"
