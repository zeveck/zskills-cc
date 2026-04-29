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
  if "$@" >/tmp/zskills-install-test.out 2>/tmp/zskills-install-test.err; then
    ok "$name"
  else
    cat /tmp/zskills-install-test.err
    not_ok "$name"
  fi
}

run_fail() {
  local name=$1 expected=$2; shift 2
  set +e
  "$@" >/tmp/zskills-install-test.out 2>/tmp/zskills-install-test.err
  rc=$?
  set -e
  if [ "$rc" -eq "$expected" ]; then
    ok "$name"
  else
    echo "expected rc $expected got $rc"
    cat /tmp/zskills-install-test.err
    not_ok "$name"
  fi
}

codex_project="$TMP/codex-project"
codex_home="$TMP/codex-home"
mkdir -p "$codex_project"
run_ok "codex install" "$ROOT/scripts/zskills-install.sh" \
  --client codex \
  --project-root "$codex_project" \
  --codex-home "$codex_home" \
  --upstream /home/vscode/.codex/zskills-portable

[ -f "$codex_home/skills/run-plan/SKILL.md" ] && ok "codex skills installed" || not_ok "codex skills installed"
rg "ZSKILLS_CODEX_COMPAT" "$codex_home/skills/run-plan/SKILL.md" >/dev/null && ok "codex adapter present" || not_ok "codex adapter present"
[ -f "$codex_project/.codex/zskills-config.json" ] && ok "codex config written" || not_ok "codex config written"
[ ! -d "$codex_project/.claude/skills" ] && ok "codex install leaves claude skills alone" || not_ok "codex install leaves claude skills alone"

claude_project="$TMP/claude-project"
mkdir -p "$claude_project"
run_ok "claude install" "$ROOT/scripts/zskills-install.sh" \
  --client claude \
  --project-root "$claude_project" \
  --codex-home "$TMP/unused-codex-home" \
  --upstream /home/vscode/.codex/zskills-portable

[ -f "$claude_project/.claude/skills/run-plan/SKILL.md" ] && ok "claude skills installed" || not_ok "claude skills installed"
! rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" "$claude_project/.claude/skills" >/tmp/zskills-install-test.out && ok "claude install has no codex adapter" || { cat /tmp/zskills-install-test.out; not_ok "claude install has no codex adapter"; }
[ -f "$claude_project/.claude/zskills-config.json" ] && ok "claude config written" || not_ok "claude config written"

both_project="$TMP/both-project"
both_home="$TMP/both-codex-home"
mkdir -p "$both_project/.codex" "$both_project/.claude"
cat > "$both_project/.codex/zskills-config.json" <<'JSON'
{"execution":{"landing":"pr","main_protected":true,"branch_prefix":"feat/"}}
JSON
cat > "$both_project/.claude/zskills-config.json" <<'JSON'
{"execution":{"landing":"direct","main_protected":false,"branch_prefix":"feat/"}}
JSON

run_fail "dual divergent config requires mirror flag" 5 "$ROOT/scripts/zskills-install.sh" \
  --client both \
  --project-root "$both_project" \
  --codex-home "$both_home" \
  --upstream /home/vscode/.codex/zskills-portable

run_ok "dual install mirrors config" "$ROOT/scripts/zskills-install.sh" \
  --client both \
  --mirror-config \
  --project-root "$both_project" \
  --codex-home "$both_home" \
  --upstream /home/vscode/.codex/zskills-portable

cmp -s "$both_project/.codex/zskills-config.json" "$both_project/.claude/zskills-config.json" && ok "dual configs mirrored" || not_ok "dual configs mirrored"
rg "ZSKILLS_CODEX_COMPAT" "$both_home/skills/run-plan/SKILL.md" >/dev/null && ok "dual codex adapter present" || not_ok "dual codex adapter present"
! rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" "$both_project/.claude/skills" >/tmp/zskills-install-test.out && ok "dual claude remains clean" || { cat /tmp/zskills-install-test.out; not_ok "dual claude remains clean"; }

echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
