#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-runner.sh status <plan> [--repo PATH]
  zskills-runner.sh stop <plan> [--repo PATH]
  zskills-runner.sh run-plan <plan> finish auto [direct|cherry-pick|pr] [--repo PATH] [--max-chunks N] [--chunk-timeout-seconds N] [--idle-timeout-seconds N] [--sandbox MODE] [--approval-policy POLICY] [--allow-direct-unattended]

Foreground runner for Codex run-plan finish auto. The parent process stays
visible in the current REPL and launches one fresh codex exec child per chunk.
EOF
}

die() {
  echo "zskills-runner: $*" >&2
  exit 2
}

PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[ -n "$PYTHON_BIN" ] || die "python3 or python is required"

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate_script="$script_dir/zskills-gate.sh"
invariant_script="$script_dir/zskills-post-run-invariants.sh"

cmd="${1:-}"
[ -n "$cmd" ] || { usage; exit 2; }
shift || true

case "$cmd" in
  status|stop|run-plan) ;;
  -h|--help) usage; exit 0 ;;
  *) die "unknown command: $cmd" ;;
esac

plan=""
repo="."
landing_arg=""
max_chunks=""
chunk_timeout=""
idle_timeout=""
sandbox=""
approval_policy=""
allow_direct_unattended=""
codex_bin="${CODEX_BIN:-codex}"

if [ "$cmd" = "run-plan" ]; then
  [ "$#" -ge 3 ] || die "run-plan requires: <plan> finish auto"
  plan="$1"
  [ "$2" = "finish" ] || die "only run-plan <plan> finish auto is supported"
  [ "$3" = "auto" ] || die "only run-plan <plan> finish auto is supported"
  shift 3
else
  [ "$#" -ge 1 ] || die "$cmd requires a plan"
  plan="$1"
  shift
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    direct|cherry-pick|pr) landing_arg="$1"; shift ;;
    --repo) repo="${2:-}"; shift 2 ;;
    --max-chunks) max_chunks="${2:-}"; shift 2 ;;
    --chunk-timeout-seconds) chunk_timeout="${2:-}"; shift 2 ;;
    --idle-timeout-seconds) idle_timeout="${2:-}"; shift 2 ;;
    --sandbox) sandbox="${2:-}"; shift 2 ;;
    --approval-policy) approval_policy="${2:-}"; shift 2 ;;
    --allow-direct-unattended) allow_direct_unattended=true; shift ;;
    --codex-bin) codex_bin="${2:-}"; shift 2 ;;
    --dangerously-bypass-approvals-and-sandbox) die "dangerous bypass is refused" ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if ! repo_root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null); then
  die "repo is not a git worktree: $repo"
fi
repo_root=$(cd "$repo_root" && pwd)

resolve_config_json=$("$PYTHON_BIN" - "$repo_root" "$landing_arg" "$max_chunks" "$chunk_timeout" "$idle_timeout" "$sandbox" "$approval_policy" "$allow_direct_unattended" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
landing_arg, max_chunks, chunk_timeout, idle_timeout, sandbox, approval, allow_direct = sys.argv[2:10]

def load(path):
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}

configs = []
for rel in [".codex/zskills-config.json", ".claude/zskills-config.json"]:
    path = root / rel
    if path.exists():
        configs.append((path, load(path)))

if len(configs) == 2:
    codex_cfg, claude_cfg = configs[0][1], configs[1][1]
    def nested(cfg, path):
        cur = cfg
        for part in path.split("."):
            if not isinstance(cur, dict) or part not in cur:
                return None
            cur = cur[part]
        return cur
    for key in ["execution.landing", "execution.main_protected"]:
        left, right = nested(codex_cfg, key), nested(claude_cfg, key)
        if left is not None and right is not None and left != right:
            raise SystemExit(f"config conflict between .codex and .claude for {key}")

config_path = str(configs[0][0]) if configs else ""
config = configs[0][1] if configs else {}

def get(path, default):
    cur = config
    for part in path.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur

result = {
    "config_path": config_path,
    "landing": landing_arg or get("execution.landing", "cherry-pick"),
    "branch_prefix": get("execution.branch_prefix", "feat/"),
    "base_branch": get("execution.base_branch", "main"),
    "remote": get("execution.remote", "origin"),
    "max_chunks": int(max_chunks or get("runner.max_chunks", 10)),
    "chunk_timeout_seconds": int(chunk_timeout or get("runner.chunk_timeout_seconds", 900)),
    "idle_timeout_seconds": int(idle_timeout or get("runner.idle_timeout_seconds", 180)),
    "sandbox": sandbox or get("runner.sandbox", "workspace-write"),
    "approval_policy": approval or get("runner.approval_policy", "never"),
    "allow_direct_unattended": (allow_direct == "true") or bool(get("runner.allow_direct_unattended", False)),
}
print(json.dumps(result))
PY
)

value() {
  "$PYTHON_BIN" - "$resolve_config_json" "$1" <<'PY'
import json, sys
data = json.loads(sys.argv[1])
value = data.get(sys.argv[2], "")
if isinstance(value, bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

landing=$(value landing)
branch_prefix=$(value branch_prefix)
base_branch=$(value base_branch)
remote=$(value remote)
max_chunks=$(value max_chunks)
chunk_timeout=$(value chunk_timeout_seconds)
idle_timeout=$(value idle_timeout_seconds)
sandbox=$(value sandbox)
approval_policy=$(value approval_policy)
allow_direct_unattended=$(value allow_direct_unattended)

case "$landing" in direct|cherry-pick|pr) ;; *) die "invalid landing mode: $landing" ;; esac
case "$sandbox" in read-only|workspace-write|danger-full-access) ;; *) die "invalid sandbox: $sandbox" ;; esac
case "$approval_policy" in never|on-request|untrusted) ;; *) die "invalid approval policy: $approval_policy" ;; esac

rel_plan=$("$PYTHON_BIN" - "$repo_root" "$plan" <<'PY'
import os, sys
root, plan = sys.argv[1:3]
path = plan if os.path.isabs(plan) else os.path.join(root, plan)
print(os.path.relpath(os.path.abspath(path), root))
PY
)
plan_path="$repo_root/$rel_plan"
[ -f "$plan_path" ] || die "plan file not found: $plan_path"

plan_info=$("$PYTHON_BIN" - "$rel_plan" <<'PY'
import hashlib, re, sys
rel = sys.argv[1].replace("\\", "/")
stem = re.sub(r"\.md$", "", rel, flags=re.I)
slug = re.sub(r"[^A-Za-z0-9]+", "-", stem).strip("-").lower() or "plan"
tracking = re.sub(r"[^A-Za-z0-9]+", "-", rel.rsplit("/", 1)[-1].rsplit(".", 1)[0]).strip("-").lower() or "plan"
key = f"{slug}-{hashlib.sha256(rel.encode()).hexdigest()[:8]}"
print(slug)
print(key)
print(tracking)
PY
)
plan_slug=$(printf '%s\n' "$plan_info" | sed -n '1p')
plan_key=$(printf '%s\n' "$plan_info" | sed -n '2p')
tracking_id=$(printf '%s\n' "$plan_info" | sed -n '3p')
pipeline_id="run-plan.$plan_key"
project_name=$(basename "$repo_root")
pr_worktree_path="/tmp/${project_name}-pr-${tracking_id}"
report_rel="reports/plan-$plan_slug.md"
report_path="$repo_root/$report_rel"
tracking_dir="$repo_root/.zskills/tracking/$pipeline_id"
stop_marker="$repo_root/.zskills/runner/$plan_key.stop"
lock_dir="$repo_root/.zskills/runner/$plan_key.lock"

print_status() {
  cat <<EOF
mode=$cmd
repo=$repo_root
plan=$rel_plan
plan_path=$plan_path
plan_slug=$plan_slug
plan_key=$plan_key
tracking_id=$tracking_id
pipeline_id=$pipeline_id
tracking_dir=$tracking_dir
report_path=$report_path
pr_worktree_path=$pr_worktree_path
landing=$landing
base_branch=$base_branch
remote=$remote
max_chunks=$max_chunks
sandbox=$sandbox
approval_policy=$approval_policy
allow_direct_unattended=$allow_direct_unattended
EOF
}

if [ "$cmd" = "status" ]; then
  print_status
  exit 0
fi

if [ "$cmd" = "stop" ]; then
  mkdir -p "$(dirname "$stop_marker")"
  printf 'plan=%s\nstopped_at=%s\n' "$rel_plan" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$stop_marker"
  echo "stop marker written: $stop_marker"
  exit 0
fi

command -v "$codex_bin" >/dev/null 2>&1 || die "codex executable not found: $codex_bin"

dirty_project_state() {
  git -C "$repo_root" status --short --untracked-files=all | grep -v '^?? .zskills/' || true
}

if [ "$landing" = "direct" ] && [ "$allow_direct_unattended" != "true" ]; then
  die "direct unattended execution is refused unless --allow-direct-unattended or runner.allow_direct_unattended is set"
fi
if [ "$landing" = "pr" ] && [ -d "$pr_worktree_path" ]; then
  if ! git -C "$pr_worktree_path" rev-parse --show-toplevel >/dev/null 2>&1; then
    die "stale PR artifact root exists but is not a git worktree for this repo: $pr_worktree_path"
  fi
  repo_common=$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)
  pr_common=$(git -C "$pr_worktree_path" rev-parse --path-format=absolute --git-common-dir)
  if [ "$repo_common" != "$pr_common" ]; then
    die "stale PR artifact root belongs to a different git repository: $pr_worktree_path"
  fi
  if [ ! -f "$pr_worktree_path/$rel_plan" ]; then
    die "stale PR artifact root is missing expected plan file $rel_plan: $pr_worktree_path"
  fi
fi
if [ -n "$(dirty_project_state)" ]; then
  die "foreground auto execution requires a clean working tree before launching child chunks"
fi
if [ "$landing" = "pr" ] && [ -d "$pr_worktree_path" ] && [ -n "$(git -C "$pr_worktree_path" status --short --untracked-files=all | grep -v '^?? .zskills/' || true)" ]; then
  die "foreground auto execution requires a clean PR worktree before launching child chunks: $pr_worktree_path"
fi

git_dir=$(git -C "$repo_root" rev-parse --absolute-git-dir)
for residue in CHERRY_PICK_HEAD MERGE_HEAD REBASE_HEAD; do
  [ ! -e "$git_dir/$residue" ] || die "unsafe git state: $residue present"
done
[ ! -d "$git_dir/rebase-merge" ] || die "unsafe git state: rebase-merge present"
[ ! -d "$git_dir/rebase-apply" ] || die "unsafe git state: rebase-apply present"
[ -z "$(git -C "$repo_root" diff --name-only --diff-filter=U)" ] || die "unsafe git state: unresolved conflicts present"

mkdir -p "$repo_root/.zskills/runner"
if ! mkdir "$lock_dir" 2>/dev/null; then
  die "runner lock already exists: $lock_dir"
fi
trap 'rm -rf "$lock_dir"' EXIT
printf 'pid=%s\nplan=%s\nstarted_at=%s\n' "$$" "$rel_plan" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$lock_dir/owner"

artifact_root() {
  if [ "$landing" = "pr" ] && [ -d "$pr_worktree_path" ]; then
    printf '%s\n' "$pr_worktree_path"
  else
    printf '%s\n' "$repo_root"
  fi
}

active_plan_path() {
  printf '%s/%s\n' "$(artifact_root)" "$rel_plan"
}

active_report_path() {
  printf '%s/%s\n' "$(artifact_root)" "$report_rel"
}

plan_complete() {
  "$PYTHON_BIN" - "$(active_plan_path)" <<'PY'
import re, sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except FileNotFoundError:
    raise SystemExit(1)
rows = []
for line in text.splitlines():
    if not line.startswith("|") or "---" in line or "Phase" not in line:
        continue
    cells = [c.strip() for c in line.strip("|").split("|")]
    if len(cells) >= 2 and cells[0].lower() != "phase":
        rows.append(cells)
if rows and all(re.search(r"(done|✅)", row[1], re.I) for row in rows):
    raise SystemExit(0)
if not rows and not re.search(r"(Pending|Not Started|Next|In Progress|⬜|🟡)", text, re.I):
    raise SystemExit(0)
raise SystemExit(1)
PY
}

hash_file() {
  [ -f "$1" ] && sha256sum "$1" | awk '{print $1}' || printf '<missing>\n'
}

tracking_markers() {
  if [ -d "$tracking_dir" ]; then
    find "$tracking_dir" -maxdepth 1 -type f -printf '%f\n' | sort | paste -sd, -
  fi
}

tracking_hashes() {
  if [ -d "$tracking_dir" ]; then
    (cd "$tracking_dir" && find . -maxdepth 1 -type f -printf '%f\n' | sort | while read -r f; do printf '%s:%s\n' "$f" "$(sha256sum "$f" | awk '{print $1}')"; done | paste -sd, -)
  fi
}

latest_marker_suffix() {
  local prefix=$1
  if [ -d "$tracking_dir" ]; then
    find "$tracking_dir" -maxdepth 1 -type f -name "$prefix*" -printf '%f\n' | sort | tail -1 | sed "s/^$prefix//"
  fi
}

run_child() {
  local chunk=$1 run_dir=$2 prompt_file=$3 stdout_file=$4 events_file=$5
  ZSKILLS_PIPELINE_ID="$pipeline_id" ZSKILLS_TRACKING_ID="$tracking_id" "$PYTHON_BIN" - "$chunk_timeout" "$idle_timeout" "$events_file" "$stdout_file" "$codex_bin" "exec" "-C" "$repo_root" "--sandbox" "$sandbox" "-c" "approval_policy=\"$approval_policy\"" "$(cat "$prompt_file")" <<'PY'
import json, os, queue, subprocess, sys, threading, time

timeout_s = int(sys.argv[1])
idle_s = int(sys.argv[2])
events_file = sys.argv[3]
stdout_file = sys.argv[4]
argv = sys.argv[5:]
start = time.time()
last = start
q = queue.Queue()
env = os.environ.copy()
proc = subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, env=env)

def reader():
    assert proc.stdout is not None
    for line in proc.stdout:
        q.put(line)

threading.Thread(target=reader, daemon=True).start()
timed_out = False
idle_timed_out = False
with open(events_file, "w", encoding="utf-8") as events, open(stdout_file, "w", encoding="utf-8") as out:
    events.write(json.dumps({"event": "start", "argv": argv, "time": start}) + "\n")
    while True:
        try:
            line = q.get(timeout=0.2)
            last = time.time()
            print(line, end="", flush=True)
            out.write(line)
            out.flush()
            events.write(json.dumps({"event": "output", "time": last, "line": line.rstrip("\n")}) + "\n")
            events.flush()
        except queue.Empty:
            pass
        now = time.time()
        if proc.poll() is not None:
            break
        if timeout_s > 0 and now - start > timeout_s:
            timed_out = True
            proc.kill()
            break
        if idle_s > 0 and now - last > idle_s:
            idle_timed_out = True
            proc.kill()
            break
    rc = proc.wait()
    while True:
        try:
            line = q.get_nowait()
        except queue.Empty:
            break
        print(line, end="", flush=True)
        out.write(line)
    if timed_out:
        rc = 124
    elif idle_timed_out:
        rc = 125
    events.write(json.dumps({"event": "end", "exit_code": rc, "timed_out": timed_out, "idle_timed_out": idle_timed_out, "time": time.time()}) + "\n")
sys.exit(rc)
PY
}

explain_child_failure() {
  local rc=$1 stdout_file=$2
  if grep -qiE 'bwrap|bubblewrap|user namespace|new namespace|No permissions to create a new namespace|Operation not permitted' "$stdout_file" 2>/dev/null; then
    cat >&2 <<EOF
runner_stop_reason=sandbox-unavailable
Codex child failed while starting the configured sandbox mode: $sandbox.
This environment appears to block bubblewrap/user-namespace sandbox setup.
The runner will not retry with danger-full-access automatically.
If this is a trusted disposable/dev-container environment, rerun explicitly with:
  --sandbox danger-full-access
Otherwise fix user-namespace/bubblewrap support and keep the default sandbox.
EOF
  else
    echo "runner_stop_reason=child-exit-$rc" >&2
  fi
}

validate_chunk() {
  local before_plan=$1 before_report=$2 before_markers=$3 before_hashes=$4 complete=$5 expected_tracking_id=$6
  local after_plan after_report after_markers after_hashes tracking_id mode gate_repo gate_plan gate_report
  gate_repo=$(artifact_root)
  gate_plan=$(active_plan_path)
  gate_report=$(active_report_path)
  after_plan=$(hash_file "$gate_plan")
  after_report=$(hash_file "$gate_report")
  after_markers=$(tracking_markers)
  after_hashes=$(tracking_hashes)
  if [ "$before_plan" = "$after_plan" ] && [ "$before_report" = "$after_report" ] && [ "$before_hashes" = "$after_hashes" ]; then
    echo "validation_failed=no durable progress detected" >&2
    return 20
  fi
  if [ "$complete" = "true" ]; then
    tracking_id="$expected_tracking_id"
    mode="post-land"
  else
    tracking_id="$expected_tracking_id"
    mode="pre-continue"
  fi
  [ -n "$tracking_id" ] || { echo "validation_failed=tracking id missing" >&2; return 21; }
  "$gate_script" --repo "$gate_repo" --tracking-root "$repo_root" --mode "$mode" --pipeline "$pipeline_id" --tracking-id "$tracking_id" --plan-file "$gate_plan" --report "$gate_report"
  marker_changed() {
    local marker=$1 before_hash current_hash
    before_hash=$(printf '%s\n' "$before_hashes" | tr ',' '\n' | awk -F: -v marker="$marker" '$1 == marker {print $2; exit}')
    current_hash=$(sha256sum "$tracking_dir/$marker" | awk '{print $1}')
    [ "$before_hash" != "$current_hash" ]
  }
  for marker in \
    "step.run-plan.$tracking_id.implement" \
    "step.run-plan.$tracking_id.verify" \
    "step.run-plan.$tracking_id.report" \
    "requires.verify-changes.$tracking_id" \
    "step.verify-changes.$tracking_id.tests-run" \
    "step.verify-changes.$tracking_id.complete" \
    "fulfilled.verify-changes.$tracking_id"; do
    marker_changed "$marker" || { echo "validation_failed=stale marker was not updated: $marker" >&2; return 22; }
  done
  if [ "$complete" = "true" ]; then
    for marker in "step.run-plan.$tracking_id.land" "fulfilled.run-plan.$tracking_id"; do
      marker_changed "$marker" || { echo "validation_failed=stale marker was not updated: $marker" >&2; return 22; }
    done
  else
    marker_changed "handoff.run-plan.$tracking_id" || { echo "validation_failed=stale marker was not updated: handoff.run-plan.$tracking_id" >&2; return 22; }
  fi
  if [ "$complete" = "true" ]; then
    "$invariant_script" --repo "$gate_repo" --plan-file "$gate_plan" --report "$gate_report" --final
  fi
  echo "validation_result=passed"
  echo "validated_tracking_id=$tracking_id"
}

run_root="$repo_root/.zskills/logs/run-plan-$plan_key-$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$run_root" "$tracking_dir" "$(dirname "$report_path")"
echo "zskills-runner: foreground run-plan finish auto"
print_status

chunk=1
while [ "$chunk" -le "$max_chunks" ]; do
  if [ -f "$stop_marker" ]; then
    echo "runner_stop_reason=stopped"
    exit 0
  fi
  if plan_complete; then
    echo "runner_stop_reason=complete"
    exit 0
  fi
  chunk_label=$(printf 'chunk-%03d' "$chunk")
  chunk_dir="$run_root/$chunk_label"
  mkdir -p "$chunk_dir"
  before_plan=$(hash_file "$(active_plan_path)")
  before_report=$(hash_file "$(active_report_path)")
  before_markers=$(tracking_markers)
  before_hashes=$(tracking_hashes)
  seed_tracking=$(printf '%s-chunk-%03d' "$(date -u +%Y%m%dT%H%M%SZ)" "$chunk")
  prompt_file="$chunk_dir/prompt.txt"
  cat > "$prompt_file" <<EOF
run-plan $rel_plan finish auto $landing

RUNNER-MANAGED CHUNK: You are running under zskills-runner.sh. Do not invoke zskills-runner.sh again. Execute exactly one incomplete phase, then stop after writing the required report, tracking markers, and landing evidence.

External ZSkills runner contract for this chunk:
- Repository root: $repo_root
- Active artifact root: $(artifact_root)
- Plan path: $(active_plan_path)
- Report path: $(active_report_path)
- PR worktree path: $pr_worktree_path
- Pipeline id: $pipeline_id
- Tracking directory: $tracking_dir
- Tracking id: use exactly $tracking_id for every marker written by this chunk.
- Environment: ZSKILLS_PIPELINE_ID=$pipeline_id and ZSKILLS_TRACKING_ID=$tracking_id are exported to this child process.
- Resolved landing mode: $landing.
- Base branch: $base_branch
- Remote: $remote
- Write run-plan markers: step.run-plan.<tracking-id>.implement, step.run-plan.<tracking-id>.verify, step.run-plan.<tracking-id>.report.
- Write verifier markers: requires.verify-changes.<tracking-id>, step.verify-changes.<tracking-id>.tests-run, step.verify-changes.<tracking-id>.complete, fulfilled.verify-changes.<tracking-id>.
- If another phase remains, write handoff.run-plan.<tracking-id> and do not write final run-plan markers.
- If the plan is complete, write step.run-plan.<tracking-id>.land and fulfilled.run-plan.<tracking-id>, and remove stale handoff.run-plan.<tracking-id>.
- The report must include a Phase heading, Status line, Tests, Verification, Landing, Remaining, and Scope Assessment.
- Leave no dirty project artifacts outside ignored .zskills state before exiting.
EOF
  echo "chunk $chunk start"
  echo "chunk_log=$chunk_dir/stdout.txt"
  set +e
  run_child "$chunk" "$chunk_dir" "$prompt_file" "$chunk_dir/stdout.txt" "$chunk_dir/events.jsonl"
  rc=$?
  set -e
  echo "chunk $chunk exit=$rc"
  [ "$rc" -eq 0 ] || { explain_child_failure "$rc" "$chunk_dir/stdout.txt"; exit "$rc"; }
  if plan_complete; then
    complete=true
  else
    complete=false
  fi
  validate_chunk "$before_plan" "$before_report" "$before_markers" "$before_hashes" "$complete" "$tracking_id"
  if [ "$complete" = "true" ]; then
    echo "runner_stop_reason=complete"
    exit 0
  fi
  chunk=$((chunk + 1))
done

echo "runner_stop_reason=max-chunks" >&2
exit 30
