#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-preflight.sh --operation commit|cherry-pick|pr|merge|delete-worktree|clear-tracking [--mode direct|cherry-pick|pr] [--client codex|claude|auto] [--worktree PATH] [--allow-dirty]

Conservative procedural preflight for runtimes without native ZSkills hooks.
EOF
}

operation=""
mode=""
client="auto"
worktree=""
allow_dirty=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --operation) operation="${2:-}"; shift 2 ;;
    --mode) mode="${2:-}"; shift 2 ;;
    --client) client="${2:-}"; shift 2 ;;
    --worktree) worktree="${2:-}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$operation" ] || { usage >&2; exit 2; }

case "$operation" in
  commit|cherry-pick|pr|merge|delete-worktree|clear-tracking) ;;
  *) echo "ERROR: invalid operation: $operation" >&2; exit 2 ;;
esac

case "$mode" in
  ""|direct|cherry-pick|pr) ;;
  *) echo "ERROR: invalid mode: $mode" >&2; exit 2 ;;
esac

if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
  echo "ERROR: zskills preflight requires a git repository" >&2
  exit 3
fi

root=$(git rev-parse --show-toplevel)
common_dir=$(git rev-parse --git-common-dir)
main_root=$(cd "$common_dir/.." && pwd)
branch=$(git branch --show-current 2>/dev/null || true)

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
if [ -n "$mode" ]; then
  "$script_dir/zskills-config.sh" validate --client "$client" --mode "$mode" >/dev/null
else
  "$script_dir/zskills-config.sh" validate --client "$client" >/dev/null
fi

if [ "$allow_dirty" -ne 1 ]; then
  case "$operation" in
    cherry-pick|merge|delete-worktree)
      if [ -n "$(git status --porcelain)" ]; then
        echo "ERROR: working tree has uncommitted changes; refusing $operation" >&2
        exit 4
      fi
      ;;
  esac
fi

case "$operation" in
  commit)
    if git diff --cached --quiet 2>/dev/null; then
      : # no staged changes is acceptable for a preflight check
    fi
    ;;
  cherry-pick)
    if [ "$branch" != "main" ] && [ "$branch" != "master" ]; then
      echo "ERROR: cherry-pick landing should run from main/master, current branch is ${branch:-unknown}" >&2
      exit 5
    fi
    ;;
  pr)
    if [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ -z "$branch" ]; then
      echo "ERROR: PR mode requires a feature branch" >&2
      exit 5
    fi
    ;;
  delete-worktree)
    [ -n "$worktree" ] || { echo "ERROR: --worktree required for delete-worktree" >&2; exit 2; }
    if [ ! -d "$worktree" ]; then
      echo "ERROR: worktree path does not exist: $worktree" >&2
      exit 6
    fi
    if [ "$allow_dirty" -ne 1 ] && [ -n "$(git -C "$worktree" status --porcelain 2>/dev/null)" ]; then
      echo "ERROR: target worktree has uncommitted changes; refusing delete-worktree: $worktree" >&2
      exit 4
    fi
    ;;
  clear-tracking)
    tracking_dir="$main_root/.zskills/tracking"
    if [ -d "$tracking_dir" ]; then
      recent_active=$(find "$tracking_dir" -type f -name 'requires.*' -mmin -360 -print -quit)
      if [ -n "$recent_active" ]; then
        echo "ERROR: recent active tracking marker exists: $recent_active" >&2
        exit 7
      fi
    fi
    ;;
esac

echo "OK: preflight $operation passed for $root"
