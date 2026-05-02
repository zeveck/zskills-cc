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
mkdir -p "$codex_project/.agents/skills/existing" "$codex_project/.agents/skills/run-plan" "$codex_home/skills/global-existing"
cat > "$codex_project/.agents/skills/existing/SKILL.md" <<'MD'
---
name: existing
description: Existing unrelated project Codex skill.
---

# Existing
MD
cat > "$codex_home/skills/global-existing/SKILL.md" <<'MD'
---
name: global-existing
description: Existing unrelated global Codex skill.
---

# Global Existing
MD
printf 'stale\n' > "$codex_project/.agents/skills/run-plan/OLD"
run_ok "codex install" "$ROOT/scripts/zskills-install.sh" \
  --client codex \
  --project-root "$codex_project" \
  --codex-home "$codex_home" \
  --upstream /home/vscode/.codex/zskills-portable

[ -f "$codex_project/.agents/skills/run-plan/SKILL.md" ] && ok "codex project skills installed" || not_ok "codex project skills installed"
rg "ZSKILLS_CODEX_COMPAT" "$codex_project/.agents/skills/run-plan/SKILL.md" >/dev/null && ok "codex project adapter present" || not_ok "codex project adapter present"
[ -f "$codex_project/.codex/zskills-config.json" ] && ok "codex config written" || not_ok "codex config written"
[ ! -d "$codex_project/.claude/skills" ] && ok "codex install leaves claude skills alone" || not_ok "codex install leaves claude skills alone"
[ -f "$codex_project/.agents/skills/existing/SKILL.md" ] && ok "codex project install preserves unrelated skill" || not_ok "codex project install preserves unrelated skill"
[ ! -e "$codex_project/.agents/skills/run-plan/OLD" ] && ok "codex project install removes stale files in owned skill" || not_ok "codex project install removes stale files in owned skill"
[ -f "$codex_home/skills/global-existing/SKILL.md" ] && ok "codex project install leaves global skills alone" || not_ok "codex project install leaves global skills alone"
[ ! -e "$codex_home/skills/run-plan/SKILL.md" ] && ok "codex project install does not write global skills" || not_ok "codex project install does not write global skills"

global_project="$TMP/global-project"
global_home="$TMP/global-codex-home"
mkdir -p "$global_project" "$global_home/skills/existing" "$global_home/skills/run-plan"
cat > "$global_home/skills/existing/SKILL.md" <<'MD'
---
name: existing
description: Existing unrelated global Codex skill.
---

# Existing
MD
printf 'stale\n' > "$global_home/skills/run-plan/OLD"
run_ok "codex global install" "$ROOT/scripts/zskills-install.sh" \
  --client codex \
  --codex-scope global \
  --project-root "$global_project" \
  --codex-home "$global_home" \
  --upstream /home/vscode/.codex/zskills-portable

[ -f "$global_home/skills/run-plan/SKILL.md" ] && ok "codex global skills installed" || not_ok "codex global skills installed"
rg "ZSKILLS_CODEX_COMPAT" "$global_home/skills/run-plan/SKILL.md" >/dev/null && ok "codex global adapter present" || not_ok "codex global adapter present"
[ -f "$global_home/skills/existing/SKILL.md" ] && ok "codex global install preserves unrelated skill" || not_ok "codex global install preserves unrelated skill"
[ ! -e "$global_home/skills/run-plan/OLD" ] && ok "codex global install removes stale files in owned skill" || not_ok "codex global install removes stale files in owned skill"

claude_project="$TMP/claude-project"
mkdir -p "$claude_project/.claude/skills/existing" "$claude_project/.claude/skills/run-plan"
cat > "$claude_project/.claude/skills/existing/SKILL.md" <<'MD'
---
name: existing
description: Existing unrelated Claude skill.
---

# Existing
MD
printf 'stale\n' > "$claude_project/.claude/skills/run-plan/OLD"
run_ok "claude install" "$ROOT/scripts/zskills-install.sh" \
  --client claude \
  --project-root "$claude_project" \
  --codex-home "$TMP/unused-codex-home" \
  --upstream /home/vscode/.codex/zskills-portable

[ -f "$claude_project/.claude/skills/run-plan/SKILL.md" ] && ok "claude skills installed" || not_ok "claude skills installed"
! rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" "$claude_project/.claude/skills" >/tmp/zskills-install-test.out && ok "claude install has no codex adapter" || { cat /tmp/zskills-install-test.out; not_ok "claude install has no codex adapter"; }
[ -f "$claude_project/.claude/zskills-config.json" ] && ok "claude config written" || not_ok "claude config written"
[ -f "$claude_project/.claude/skills/existing/SKILL.md" ] && ok "claude install preserves unrelated skill" || not_ok "claude install preserves unrelated skill"
[ ! -e "$claude_project/.claude/skills/run-plan/OLD" ] && ok "claude install removes stale files in owned skill" || not_ok "claude install removes stale files in owned skill"

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
rg "ZSKILLS_CODEX_COMPAT" "$both_project/.agents/skills/run-plan/SKILL.md" >/dev/null && ok "dual project codex adapter present" || not_ok "dual project codex adapter present"
[ ! -e "$both_home/skills/run-plan/SKILL.md" ] && ok "dual install does not write global codex skills by default" || not_ok "dual install does not write global codex skills by default"
! rg "ZSKILLS_CODEX_COMPAT|Codex Compatibility|Codex-installed|Codex adapter" "$both_project/.claude/skills" >/tmp/zskills-install-test.out && ok "dual claude remains clean" || { cat /tmp/zskills-install-test.out; not_ok "dual claude remains clean"; }

echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
