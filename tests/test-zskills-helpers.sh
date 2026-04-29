#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0
fail=0

ok() { echo "PASS $1"; pass=$((pass+1)); }
not_ok() { echo "FAIL $1"; fail=$((fail+1)); }

run_ok() {
  local name=$1; shift
  if "$@" >/tmp/zskills-helper-test.out 2>/tmp/zskills-helper-test.err; then ok "$name"; else cat /tmp/zskills-helper-test.err; not_ok "$name"; fi
}

run_fail() {
  local name=$1 expected=$2; shift 2
  set +e
  "$@" >/tmp/zskills-helper-test.out 2>/tmp/zskills-helper-test.err
  rc=$?
  set -e
  if [ "$rc" -eq "$expected" ]; then ok "$name"; else echo "expected rc $expected got $rc"; cat /tmp/zskills-helper-test.err; not_ok "$name"; fi
}

in_dir() {
  local dir=$1
  shift
  pushd "$dir" >/dev/null
  "$@"
  popd >/dev/null
}

write_config() {
  local path=$1 landing=$2 protected=$3
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<JSON
{
  "project_name": "demo",
  "timezone": "America/New_York",
  "execution": {
    "landing": "$landing",
    "main_protected": $protected,
    "branch_prefix": "feat/"
  },
  "testing": {
    "unit_cmd": "npm test",
    "full_cmd": "npm run test:all",
    "output_file": ".test-results.txt"
  },
  "ci": {
    "auto_fix": false,
    "max_fix_attempts": 3
  }
}
JSON
}

case_dir="$TMP/codex-only"
mkdir -p "$case_dir"
write_config "$case_dir/.codex/zskills-config.json" pr false
in_dir "$case_dir" run_ok "codex config resolves" "$ROOT/scripts/zskills-config.sh" resolve --client codex
in_dir "$case_dir" bash -c "[ \"\$(\"$ROOT/scripts/zskills-config.sh\" get execution.landing --client auto)\" = pr ]" && ok "auto prefers codex" || not_ok "auto prefers codex"
in_dir "$case_dir" bash -c "[ \"\$(\"$ROOT/scripts/zskills-config.sh\" get ci.auto_fix --client codex)\" = false ]" && ok "ci auto_fix parsed" || not_ok "ci auto_fix parsed"

case_dir="$TMP/claude-only"
mkdir -p "$case_dir"
write_config "$case_dir/.claude/zskills-config.json" cherry-pick false
in_dir "$case_dir" bash -c "[ \"\$(\"$ROOT/scripts/zskills-config.sh\" get execution.landing --client auto)\" = cherry-pick ]" && ok "auto falls back claude" || not_ok "auto falls back claude"
in_dir "$case_dir" bash -c "[ \"\$(\"$ROOT/scripts/zskills-config.sh\" get execution.landing --client codex)\" = cherry-pick ]" && ok "codex falls back claude" || not_ok "codex falls back claude"

case_dir="$TMP/no-config"
mkdir -p "$case_dir"
in_dir "$case_dir" bash -c "[ \"\$(\"$ROOT/scripts/zskills-config.sh\" get execution.landing --client auto)\" = cherry-pick ]" && ok "no config defaults cherry-pick" || not_ok "no config defaults cherry-pick"
in_dir "$case_dir" run_ok "validate cherry-pick mode" "$ROOT/scripts/zskills-config.sh" validate --client auto --mode cherry-pick
in_dir "$case_dir" run_ok "validate pr mode" "$ROOT/scripts/zskills-config.sh" validate --client auto --mode pr
in_dir "$case_dir" run_ok "validate direct mode without protected main" "$ROOT/scripts/zskills-config.sh" validate --client auto --mode direct

case_dir="$TMP/conflict"
mkdir -p "$case_dir"
write_config "$case_dir/.codex/zskills-config.json" pr false
write_config "$case_dir/.claude/zskills-config.json" direct false
in_dir "$case_dir" run_fail "dual config conflict" 5 "$ROOT/scripts/zskills-config.sh" resolve --client auto

case_dir="$TMP/protected"
mkdir -p "$case_dir"
write_config "$case_dir/.codex/zskills-config.json" direct true
in_dir "$case_dir" run_fail "direct protected rejected" 6 "$ROOT/scripts/zskills-config.sh" validate --client codex --mode direct

case_dir="$TMP/bad-json"
mkdir -p "$case_dir/.codex"
printf '{bad\n' > "$case_dir/.codex/zskills-config.json"
in_dir "$case_dir" run_fail "malformed config rejected" 4 "$ROOT/scripts/zskills-config.sh" resolve --client codex

case_dir="$TMP/preflight"
mkdir -p "$case_dir"
cd "$case_dir"
git init -q
git config user.email test@example.com
git config user.name test
write_config "$case_dir/.codex/zskills-config.json" cherry-pick false
touch README.md
git add README.md
git commit -q -m init
run_ok "preflight commit in repo" "$ROOT/scripts/zskills-preflight.sh" --operation commit --client codex
run_fail "preflight pr rejects main" 5 "$ROOT/scripts/zskills-preflight.sh" --operation pr --client codex
mkdir -p .zskills/tracking/demo
printf 'x\n' > .zskills/tracking/demo/requires.verify.demo
run_fail "preflight clear-tracking sees active marker" 7 "$ROOT/scripts/zskills-preflight.sh" --operation clear-tracking --client codex
git switch -q -c feature/delete-check
mkdir -p subdir
touch subdir/dirty.txt
run_fail "preflight delete-worktree rejects dirty target" 4 "$ROOT/scripts/zskills-preflight.sh" --operation delete-worktree --client codex --worktree "$case_dir"

echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
