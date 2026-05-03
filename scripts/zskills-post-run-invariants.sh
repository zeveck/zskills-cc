#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-post-run-invariants.sh --repo PATH --plan-file PATH --report PATH [--final]

Checks final foreground run-plan invariants.
EOF
}

repo="."
plan_file=""
report=""
final=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo) repo="${2:-}"; shift 2 ;;
    --plan-file) plan_file="${2:-}"; shift 2 ;;
    --report) report="${2:-}"; shift 2 ;;
    --final) final=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "ERROR: repo is not a git worktree: $repo" >&2
  exit 2
fi

root=$(git -C "$repo" rev-parse --show-toplevel)
case "$plan_file" in
  /*) ;;
  *) plan_file="$root/$plan_file" ;;
esac
case "$report" in
  /*) ;;
  *) report="$root/$report" ;;
esac

[ -f "$report" ] || { echo "INVARIANT-FAIL: report missing: $report" >&2; exit 1; }

if [ "$final" -eq 1 ] && [ -f "$plan_file" ]; then
  if grep -qE '^\|.*(In Progress|🟡)' "$plan_file"; then
    echo "INVARIANT-FAIL: plan still has in-progress rows: $plan_file" >&2
    exit 1
  fi
fi

echo "Post-run invariants passed."
