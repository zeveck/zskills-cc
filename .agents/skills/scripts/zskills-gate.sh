#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-gate.sh --repo PATH [--tracking-root PATH] --mode pre-continue|post-land --pipeline ID --tracking-id ID --plan-file PATH --report PATH

Read-only gate for foreground run-plan chunks.
EOF
}

repo="."
tracking_root=""
mode="pre-continue"
pipeline=""
tracking_id=""
plan_file=""
report=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --tracking-root) tracking_root="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --pipeline) pipeline="${2:-}"; shift 2 ;;
    --tracking-id) tracking_id="${2:-}"; shift 2 ;;
    --plan-file) plan_file="${2:-}"; shift 2 ;;
    --report) report="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$mode" in
  pre-continue|post-land) ;;
  *) echo "ERROR: invalid --mode: $mode" >&2; exit 2 ;;
esac

[ -n "$pipeline" ] || { echo "ERROR: --pipeline required" >&2; exit 2; }
[ -n "$tracking_id" ] || { echo "ERROR: --tracking-id required" >&2; exit 2; }

if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "ERROR: repo is not a git worktree: $repo" >&2
  exit 2
fi

root=$(git -C "$repo" rev-parse --show-toplevel)
if [ -n "$tracking_root" ]; then
  tracking_root=$(git -C "$tracking_root" rev-parse --show-toplevel)
else
  tracking_root="$root"
fi
failed=0

fail() {
  echo "GATE-FAIL: $*" >&2
  failed=1
}

if [ -d "$tracking_root/.zskills/tracking" ] && ! git -C "$tracking_root" check-ignore -q "$tracking_root/.zskills/tracking" 2>/dev/null; then
  fail ".zskills/tracking/ exists but is not ignored"
fi

[ -n "$plan_file" ] || plan_file="$root/$plan_file"
case "$plan_file" in
  /*) ;;
  *) plan_file="$root/$plan_file" ;;
esac
[ -f "$plan_file" ] || fail "artifact root plan file missing: $plan_file"

case "$report" in
  "") fail "report path required" ;;
  /*) ;;
  *) report="$root/$report" ;;
esac
[ -f "$report" ] || fail "artifact root report missing: $report"

tracking="$tracking_root/.zskills/tracking/$pipeline"
[ -d "$tracking" ] || fail "tracking root directory missing: $tracking"

require_marker() {
  local marker=$1
  [ -e "$tracking/$marker" ] || fail "tracking root missing marker: $marker"
}

for suffix in implement verify report; do
  require_marker "step.run-plan.$tracking_id.$suffix"
done
for marker in \
  "requires.verify-changes.$tracking_id" \
  "step.verify-changes.$tracking_id.tests-run" \
  "step.verify-changes.$tracking_id.complete" \
  "fulfilled.verify-changes.$tracking_id"; do
  require_marker "$marker"
done

if [ "$mode" = "pre-continue" ]; then
  require_marker "handoff.run-plan.$tracking_id"
  if [ -e "$tracking/step.run-plan.$tracking_id.land" ]; then
    fail "tracking root land marker present before plan completion"
  fi
  if [ -e "$tracking/fulfilled.run-plan.$tracking_id" ]; then
    fail "tracking root fulfilled run-plan marker present before plan completion"
  fi
else
  require_marker "step.run-plan.$tracking_id.land"
  require_marker "fulfilled.run-plan.$tracking_id"
fi

if [ -f "$report" ]; then
  for pattern in \
    "^## Phase" \
    "^Status:" \
    "Tests" \
    "Verification" \
    "Landing" \
    "Remaining" \
    "Scope Assessment"; do
    grep -qiE "$pattern" "$report" || fail "report missing required content matching: $pattern"
  done
fi

status=$(git -C "$root" status --short --untracked-files=all)
if [ -n "$status" ]; then
  while IFS= read -r line; do
    path=${line#???}
    case "$path" in
      .zskills/*|.zskills-tracked) ;;
      *) fail "unexpected dirty project artifact: $line" ;;
    esac
  done <<EOF
$status
EOF
fi

if [ "$failed" -ne 0 ]; then
  echo "ZSkills gate artifact root: $root" >&2
  echo "ZSkills gate tracking root: $tracking_root" >&2
  echo "ZSkills gate failed for $mode." >&2
  exit 1
fi

echo "ZSkills gate passed for $mode."
