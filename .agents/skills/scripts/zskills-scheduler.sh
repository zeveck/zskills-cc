#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-scheduler.sh add --id ID --skill SKILL --args ARGS --schedule SCHEDULE [--client codex|claude] [--repo-path PATH] [--runner-command CMD] [--pipeline-id ID] [--one-shot]
  zskills-scheduler.sh list [--format text|json]
  zskills-scheduler.sh next [--skill SKILL]
  zskills-scheduler.sh stop [--id ID|--skill SKILL]
  zskills-scheduler.sh trigger [--id ID|--skill SKILL]
  zskills-scheduler.sh due [--format json]
  zskills-scheduler.sh mark-complete --id ID [--message TEXT]
  zskills-scheduler.sh mark-blocked --id ID --message TEXT
  zskills-scheduler.sh runner-status [--repo-path PATH]
  zskills-scheduler.sh runner-enable [--repo-path PATH]
  zskills-scheduler.sh runner-disable [--repo-path PATH]
  zskills-scheduler.sh runner-disable-if-idle [--repo-path PATH]

Stores jobs in .zskills/schedules/*.json under the repository root.
runner-enable manages only this repo's marked OS cron block and preserves
unrelated crontab entries. runner-install and runner-uninstall remain aliases
for compatibility.
EOF
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage >&2; exit 2; }
shift || true

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[ -n "$PYTHON_BIN" ] || { echo "ERROR: python3 or python is required" >&2; exit 3; }

format="text"
id=""
skill=""
args=""
schedule=""
client="codex"
repo_path=""
runner_command=""
pipeline_id=""
message=""
one_shot=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --format) format="${2:-}"; shift 2 ;;
    --id) id="${2:-}"; shift 2 ;;
    --skill) skill="${2:-}"; shift 2 ;;
    --args) args="${2:-}"; shift 2 ;;
    --schedule) schedule="${2:-}"; shift 2 ;;
    --client) client="${2:-}"; shift 2 ;;
    --repo-path) repo_path="${2:-}"; shift 2 ;;
    --runner-command) runner_command="${2:-}"; shift 2 ;;
    --pipeline-id) pipeline_id="${2:-}"; shift 2 ;;
    --message) message="${2:-}"; shift 2 ;;
    --one-shot) one_shot=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$cmd" in
  add|list|next|stop|trigger|due|mark-complete|mark-blocked|runner-status|runner-enable|runner-disable|runner-disable-if-idle|runner-install|runner-uninstall) ;;
  *) usage >&2; exit 2 ;;
esac

case "$format" in
  text|json) ;;
  *) echo "ERROR: invalid --format: $format" >&2; exit 2 ;;
esac

case "$client" in
  codex|claude) ;;
  *) echo "ERROR: invalid --client: $client" >&2; exit 2 ;;
esac

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  root=$(git rev-parse --show-toplevel)
else
  root=$(pwd)
fi

repo_path="${repo_path:-$root}"
repo_path=$(cd "$repo_path" && pwd)

runner_start_marker="# zskills-cc scheduled runner start: $repo_path"
runner_end_marker="# zskills-cc scheduled runner end: $repo_path"
repo_shell_path=$(printf '%q' "$repo_path")
runner_path=$(printf '%q' "${ZSKILLS_CRON_PATH:-/usr/local/share/nvm/current/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}")
runner_line="* * * * * cd $repo_shell_path && PATH=$runner_path /bin/bash scripts/zskills-run-due.sh >> .zskills/cron-runner.log 2>&1"

crontab_read() {
  if [ -n "${ZSKILLS_CRONTAB_FILE:-}" ]; then
    [ -f "$ZSKILLS_CRONTAB_FILE" ] && cat "$ZSKILLS_CRONTAB_FILE"
    return 0
  fi
  if ! command -v crontab >/dev/null 2>&1; then
    echo "ERROR: crontab command not found; install cron or run scripts/zskills-run-due.sh from another scheduler." >&2
    return 127
  fi
  crontab -l 2>/dev/null || true
}

crontab_write() {
  if [ -n "${ZSKILLS_CRONTAB_FILE:-}" ]; then
    mkdir -p "$(dirname "$ZSKILLS_CRONTAB_FILE")"
    cat > "$ZSKILLS_CRONTAB_FILE"
    return 0
  fi
  if ! command -v crontab >/dev/null 2>&1; then
    echo "ERROR: crontab command not found; install cron or run scripts/zskills-run-due.sh from another scheduler." >&2
    return 127
  fi
  crontab -
}

remove_managed_runner_block() {
  awk -v start="$runner_start_marker" -v end="$runner_end_marker" '
    $0 == start { skip = 1; next }
    $0 == end { skip = 0; next }
    !skip { print }
  '
}

runner_block() {
  printf '%s\n%s\n%s\n' "$runner_start_marker" "$runner_line" "$runner_end_marker"
}

runner_status() {
  local current
  current=$(crontab_read) || return $?
  if [[ "$current" != *"$runner_start_marker"* ]]; then
    echo "No ZSkills scheduled runner is installed for $repo_path."
    echo "Enable it with: scripts/zskills-scheduler.sh runner-enable --repo-path \"$repo_path\""
    return 4
  fi
  if [[ "$current" != *"$runner_line"* || "$current" != *"$runner_end_marker"* ]]; then
    echo "ZSkills scheduled runner for $repo_path is incomplete or stale."
    echo "Repair it with: scripts/zskills-scheduler.sh runner-enable --repo-path \"$repo_path\""
    return 5
  fi
  echo "ZSkills scheduled runner installed for $repo_path."
}

active_schedule_count() {
  "$PYTHON_BIN" - "$root" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
schedules_dir = root / ".zskills" / "schedules"
count = 0
for path in schedules_dir.glob("*.json"):
    try:
        job = json.loads(path.read_text())
    except Exception:
        continue
    if job.get("last_status") not in {"stopped", "blocked"} and job.get("next_run"):
        count += 1
print(count)
PY
}

runner_enable() {
  local current
  current=$(crontab_read) || exit $?
  {
    printf '%s\n' "$current" | remove_managed_runner_block
    runner_block
  } | awk 'NF || previous_nonempty { print; previous_nonempty = NF }' | crontab_write
  echo "Enabled ZSkills scheduled runner for $repo_path."
}

runner_disable() {
  local current
  current=$(crontab_read) || exit $?
  printf '%s\n' "$current" | remove_managed_runner_block | crontab_write
  echo "Disabled ZSkills scheduled runner for $repo_path."
}

case "$cmd" in
  runner-status)
    runner_status
    exit $?
    ;;
  runner-enable|runner-install)
    runner_enable
    ;;
  runner-disable|runner-uninstall)
    runner_disable
    ;;
  runner-disable-if-idle)
    active_count=$(active_schedule_count)
    if [ "$active_count" -eq 0 ]; then
      runner_disable
    else
      echo "Kept ZSkills scheduled runner for $repo_path; $active_count active schedule(s) remain."
    fi
    ;;
esac

case "$cmd" in
  runner-enable|runner-disable|runner-disable-if-idle|runner-install|runner-uninstall)
    exit 0
    ;;
esac

"$PYTHON_BIN" - "$cmd" "$format" "$id" "$skill" "$args" "$schedule" "$client" "$repo_path" "$runner_command" "$pipeline_id" "$message" "$one_shot" <<'PY'
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

cmd, fmt, job_id, skill, args, schedule, client, repo_path, runner_command, pipeline_id, message, one_shot_arg = sys.argv[1:13]
root = Path.cwd()
try:
    import subprocess
    top = subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True, stderr=subprocess.DEVNULL).strip()
    root = Path(top)
except Exception:
    pass

schedules_dir = root / ".zskills" / "schedules"
schedules_dir.mkdir(parents=True, exist_ok=True)


def now() -> datetime:
    return datetime.now(timezone.utc).replace(microsecond=0)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def parse_iso(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def slug(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip()).strip("-").lower()
    return value[:120] or "job"


def parse_schedule(expr: str) -> tuple[int, str]:
    raw = expr.strip()
    if re.match(r"^every\s+hour$", raw, re.I):
        return 3600, raw
    every_match = re.match(r"^(?:every\s+)?(\d+)\s*([mhd])$", raw, re.I)
    if every_match:
        amount = int(every_match.group(1))
        unit = every_match.group(2).lower()
        mult = {"m": 60, "h": 3600, "d": 86400}[unit]
        return amount * mult, raw
    day_match = re.match(r"^(weekday|day)\s+at\s+(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$", raw, re.I)
    if day_match:
        kind, hour_s, minute_s, ampm = day_match.groups()
        hour = int(hour_s)
        minute = int(minute_s or "0")
        if ampm:
            ampm = ampm.lower()
            if hour == 12:
                hour = 0
            if ampm == "pm":
                hour += 12
        if hour > 23 or minute > 59:
            raise SystemExit("ERROR: invalid time in schedule")
        candidate = now().replace(hour=hour, minute=minute, second=0)
        if candidate <= now():
            candidate += timedelta(days=1)
        if kind.lower() == "weekday":
            while candidate.weekday() >= 5:
                candidate += timedelta(days=1)
        seconds = max(60, int((candidate - now()).total_seconds()))
        return seconds, raw
    raise SystemExit(f"ERROR: unsupported schedule expression: {expr}")


def path_for(job_id: str) -> Path:
    return schedules_dir / f"{slug(job_id)}.json"


def load_jobs() -> list[dict]:
    jobs = []
    for path in sorted(schedules_dir.glob("*.json")):
        try:
            job = json.loads(path.read_text())
            job["_path"] = str(path)
            jobs.append(job)
        except Exception:
            continue
    return jobs


def save(job: dict) -> None:
    out = dict(job)
    out.pop("_path", None)
    path_for(job["id"]).write_text(json.dumps(out, indent=2, sort_keys=True) + "\n")


if cmd == "add":
    if not job_id or not skill or not args or not schedule:
        raise SystemExit("ERROR: add requires --id, --skill, --args, and --schedule")
    interval_seconds, normalized_schedule = parse_schedule(schedule)
    runner = runner_command or ("codex exec --sandbox danger-full-access" if client == "codex" else "")
    final_job_id = slug(job_id)
    if one_shot_arg == "1":
        base_job_id = final_job_id
        suffix = 2
        while path_for(final_job_id).exists():
            final_job_id = f"{base_job_id}-{suffix}"
            suffix += 1
    job = {
        "id": final_job_id,
        "client": client,
        "repo_path": str(Path(repo_path).resolve()),
        "worktree_path": None,
        "skill": skill,
        "args": args,
        "original_invocation": f"/{skill} {args}",
        "pipeline_id": pipeline_id or f"{skill}.{slug(args)}",
        "runner_command": runner,
        "required_tools": ["git"] + (["codex"] if client == "codex" and runner.startswith("codex") else []),
        "concurrency": "skip-if-running",
        "schedule": normalized_schedule,
        "interval_seconds": interval_seconds,
        "next_run": iso(now() + timedelta(seconds=interval_seconds)),
        "last_status": "pending",
        "last_message": "",
        "last_run": None,
        "one_shot": one_shot_arg == "1",
        "created_at": iso(now()),
        "updated_at": iso(now()),
        "created_by": "zskills-scheduler/v1",
    }
    save(job)
    print(json.dumps(job, indent=2, sort_keys=True) if fmt == "json" else f"Scheduled {job['id']} next at {job['next_run']}")
    raise SystemExit(0)

jobs = load_jobs()

if cmd == "list":
    active = [j for j in jobs if j.get("last_status") != "stopped"]
    if fmt == "json":
        print(json.dumps(active, indent=2, sort_keys=True))
    else:
        if not active:
            print("No active ZSkills schedules.")
        for j in active:
            print(f"{j['id']}: {j['skill']} {j.get('args','')} next {j.get('next_run')} status {j.get('last_status')}")
    raise SystemExit(0)

if cmd == "next":
    active = [j for j in jobs if j.get("last_status") != "stopped" and (not skill or j.get("skill") == skill)]
    active.sort(key=lambda j: j.get("next_run") or "")
    if fmt == "json":
        print(json.dumps(active[:1], indent=2, sort_keys=True))
    else:
        print("No active ZSkills schedules." if not active else f"{active[0]['id']}: next at {active[0].get('next_run')}")
    raise SystemExit(0)

if cmd in {"stop", "trigger"}:
    if not job_id and not skill:
        raise SystemExit(f"ERROR: {cmd} requires --id or --skill")
    changed = []
    for j in jobs:
        if (job_id and j.get("id") == slug(job_id)) or (skill and j.get("skill") == skill):
            if cmd == "stop":
                j["last_status"] = "stopped"
                j["last_message"] = message or "stopped"
            else:
                j["last_status"] = "pending"
                j["last_message"] = message or "triggered"
                j["next_run"] = iso(now())
            j["updated_at"] = iso(now())
            save(j)
            changed.append(j["id"])
    verb = "Stopped" if cmd == "stop" else "Triggered"
    print(json.dumps(changed) if fmt == "json" else f"{verb} {len(changed)} ZSkills schedule(s): {', '.join(changed)}")
    raise SystemExit(0)

if cmd == "due":
    current = now()
    due = [
        j for j in jobs
        if j.get("last_status") not in {"stopped", "running", "blocked"}
        and j.get("next_run")
        and parse_iso(j["next_run"]) <= current
    ]
    print(json.dumps(due, indent=2, sort_keys=True))
    raise SystemExit(0)

if cmd in {"mark-complete", "mark-blocked"}:
    if not job_id:
        raise SystemExit(f"ERROR: {cmd} requires --id")
    target = None
    for j in jobs:
        if j.get("id") == slug(job_id):
            target = j
            break
    if target is None:
        raise SystemExit(f"ERROR: schedule not found: {job_id}")
    target["last_run"] = iso(now())
    target["updated_at"] = iso(now())
    target["last_message"] = message
    if cmd == "mark-blocked":
        target["last_status"] = "blocked"
    else:
        if target.get("one_shot"):
            target["last_status"] = "stopped"
            target["next_run"] = None
        else:
            target["last_status"] = "pending"
            target["next_run"] = iso(now() + timedelta(seconds=int(target.get("interval_seconds", 300))))
    save(target)
    print(json.dumps(target, indent=2, sort_keys=True) if fmt == "json" else f"{target['id']}: {target['last_status']}")
PY
