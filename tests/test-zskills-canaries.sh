#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PHASE="harness"

usage() {
  cat <<'EOF'
Usage:
  tests/test-zskills-canaries.sh [--phase harness]

Runs local ZSkills behavioral canaries in disposable fake repositories.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --phase) PHASE="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

pass=0
fail=0
RUN_ROOT=""
REPO=""
LOG_DIR=""

ok() { echo "PASS $1"; pass=$((pass+1)); }
not_ok() { echo "FAIL $1"; fail=$((fail+1)); }

assert_file_contains() {
  local path=$1 pattern=$2 name=$3
  if rg -q "$pattern" "$path"; then
    ok "$name"
  else
    echo "missing pattern '$pattern' in $path" >&2
    not_ok "$name"
  fi
}

assert_file_exists() {
  local path=$1 name=$2
  [ -f "$path" ] && ok "$name" || not_ok "$name"
}

assert_no_real_remote() {
  local repo=$1
  local remotes
  remotes=$(git -C "$repo" remote -v || true)
  if [ -z "$remotes" ]; then
    ok "fake repo has no remotes"
    return
  fi
  if printf '%s\n' "$remotes" | awk '{print $2}' | rg -v "^(file://|/|$ROOT|$RUN_ROOT)" >/dev/null; then
    printf '%s\n' "$remotes" >&2
    not_ok "fake repo has no real remotes"
  else
    ok "fake repo has only local remotes"
  fi
}

record_log() {
  local name=$1 source=$2
  mkdir -p "$LOG_DIR"
  cp "$source" "$LOG_DIR/$name"
}

create_fake_repo() {
  local stamp
  stamp=$(date -u +%Y%m%dT%H%M%SZ)-$$
  RUN_ROOT="$ROOT/.tmp/zskills-canaries/$stamp"
  REPO="$RUN_ROOT/repo"
  LOG_DIR="$RUN_ROOT/logs"
  mkdir -p "$REPO/.codex" "$LOG_DIR"

  mkdir -p "$REPO/.agents"
  cp -a "$ROOT/.agents/skills" "$REPO/.agents/"
  mkdir -p "$REPO/scripts"
  cp "$ROOT"/scripts/zskills-*.sh "$REPO/scripts/"
  chmod +x "$REPO"/scripts/zskills-*.sh

  cat > "$REPO/.codex/zskills-config.json" <<JSON
{
  "\$schema": "./zskills-config.schema.json",
  "project_name": "zskills-canary",
  "timezone": "Etc/UTC",
  "execution": {
    "landing": "direct",
    "main_protected": false,
    "branch_prefix": "canary/"
  },
  "testing": {
    "unit_cmd": "bash scripts/canary-test.sh",
    "full_cmd": "bash scripts/canary-test.sh",
    "output_file": ".test-results.txt",
    "file_patterns": []
  },
  "dev_server": {
    "cmd": "",
    "port_script": "",
    "main_repo_path": "$REPO"
  },
  "ui": {
    "file_patterns": "",
    "auth_bypass": ""
  },
  "ci": {
    "auto_fix": false,
    "max_fix_attempts": 0
  }
}
JSON

  cat > "$REPO/scripts/canary-test.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "canary tests passed"
SH
  chmod +x "$REPO/scripts/canary-test.sh"

  cat > "$REPO/README.md" <<'MD'
# ZSkills Canary Repo

Disposable fixture repository for local ZSkills canaries.
MD

  mkdir -p "$REPO/.agents/skills/project-canary"
  cat > "$REPO/.agents/skills/project-canary/SKILL.md" <<'MD'
---
name: project-canary
description: Use when the user asks for PROJECT_SKILL_CANARY_49217. Reply with exactly PROJECT_LAYER_SKILL_LOADED_49217 and no other text.
---

When invoked, reply with exactly:
PROJECT_LAYER_SKILL_LOADED_49217
MD

  git -C "$REPO" init -q
  git -C "$REPO" config user.email canary@example.com
  git -C "$REPO" config user.name "ZSkills Canary"
  git -C "$REPO" add .
  git -C "$REPO" commit -q -m "init canary repo"
}

run_codex_canary() {
  local name=$1 prompt=$2 expected=$3
  local transcript="$LOG_DIR/$name.transcript.log"
  local answer="$LOG_DIR/$name.answer.txt"
  printf '%s\n' "$prompt" > "$LOG_DIR/$name.prompt.txt"

  if codex exec \
    --cd "$REPO" \
    --dangerously-bypass-approvals-and-sandbox \
    --output-last-message "$answer" \
    "$prompt" \
    >"$transcript" 2>&1 </dev/null; then
    ok "$name codex exec"
  else
    cat "$transcript" >&2
    not_ok "$name codex exec"
    return
  fi

  record_log "$name.answer.copy.txt" "$answer"
  assert_file_contains "$answer" "^${expected}$" "$name expected response"
}

run_harness_phase() {
  create_fake_repo
  assert_no_real_remote "$REPO"
  assert_file_exists "$REPO/.agents/skills/run-plan/SKILL.md" "copied project codex skills"
  assert_file_exists "$REPO/scripts/zskills-config.sh" "copied helper scripts"
  run_codex_canary \
    "project-skill-loader" \
    "PROJECT_SKILL_CANARY_49217" \
    "PROJECT_LAYER_SKILL_LOADED_49217"
  printf 'Harness logs: %s\n' "$LOG_DIR"
}

case "$PHASE" in
  harness) run_harness_phase ;;
  *) echo "ERROR: unsupported phase: $PHASE" >&2; exit 2 ;;
esac

echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
