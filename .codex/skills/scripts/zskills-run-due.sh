#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-run-due.sh [--dry-run]

Runs due jobs from .zskills/schedules/*.json. Intended for OS cron, systemd,
or a manual top-level Codex invocation.
EOF
}

dry_run=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  root=$(git rev-parse --show-toplevel)
else
  root=$(pwd)
fi

lock_dir="$root/.zskills/scheduler.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  echo "ZSkills scheduler already running; skipping."
  exit 0
fi
trap 'rmdir "$lock_dir"' EXIT

scheduler="$root/scripts/zskills-scheduler.sh"
[ -x "$scheduler" ] || scheduler="$HOME/.codex/skills/scripts/zskills-scheduler.sh"
[ -x "$scheduler" ] || { echo "ERROR: zskills-scheduler.sh not found" >&2; exit 3; }

due_json=$("$scheduler" due --format json)

python - "$root" "$dry_run" "$scheduler" "$due_json" <<'PY'
import json
import os
import shlex
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

root = Path(sys.argv[1])
dry_run = sys.argv[2] == "1"
scheduler = Path(sys.argv[3])
jobs = json.loads(sys.argv[4])


def timestamp() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z").replace(":", "")


def mark(command: str, job_id: str, message: str = "") -> None:
    args = [str(scheduler), command, "--id", job_id]
    if message:
        args += ["--message", message[:2000]]
    subprocess.run(args, cwd=root, check=False)


def prompt_for(job: dict, invocation: str, runner: str) -> str:
    runner_name = Path(shlex.split(runner)[0]).name if runner else ""
    if "codex" not in runner_name:
        return invocation
    return f"""You are running a scheduled ZSkills job from .zskills/schedules/{job['id']}.json.

Execute the requested skill now. Do not stop after inspecting files or reading instructions.

Skill invocation:
{invocation}

Required behavior:
- Load and follow the installed skill instructions for the invocation.
- Make the requested code or document changes for this scheduled turn.
- Run the relevant verification for the turn.
- Update the plan/report/tracking files required by the skill.
- For `run-plan finish auto`, execute exactly one incomplete phase in this top-level Codex invocation. If another phase remains, create a fresh one-shot schedule using `zskills-scheduler.sh add --one-shot` with a new job id, then exit.
- If you cannot complete the scheduled turn, exit non-zero or clearly report the blocker so the scheduler can mark the job blocked.
"""


for job in jobs:
    job_id = job["id"]
    repo = Path(job.get("repo_path") or root)
    runner = job.get("runner_command") or ""
    skill = job.get("skill") or ""
    args = job.get("args") or ""
    invocation = f"{skill} {args}".strip()
    prompt = prompt_for(job, invocation, runner)
    logs_dir = root / ".zskills" / "logs" / job_id
    logs_dir.mkdir(parents=True, exist_ok=True)
    log_path = logs_dir / f"{timestamp()}.log"

    def block(message: str) -> None:
        log_path.write_text(message + "\n")
        mark("mark-blocked", job_id, message)

    if not repo.exists():
        block(f"repo_path does not exist: {repo}")
        continue
    missing = [tool for tool in job.get("required_tools", []) if shutil.which(tool) is None]
    if missing:
        block(f"missing required tool(s): {', '.join(missing)}")
        continue
    if not runner:
        block("runner_command is empty")
        continue
    if dry_run:
        log_path.write_text(f"DRY RUN: cd {repo} && {runner} {shlex.quote(prompt)}\n")
        continue

    cmd = shlex.split(runner) + [prompt]
    env = os.environ.copy()
    if job.get("pipeline_id"):
        env["ZSKILLS_PIPELINE_ID"] = str(job["pipeline_id"])
    proc = subprocess.run(cmd, cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env)
    log_path.write_text(proc.stdout)
    if proc.returncode == 0:
        mark("mark-complete", job_id, f"completed; log={log_path}")
    else:
        mark("mark-blocked", job_id, f"runner exited {proc.returncode}; log={log_path}")
PY
