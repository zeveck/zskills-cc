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
  if "$@" >/tmp/zskills-scheduler-test.out 2>/tmp/zskills-scheduler-test.err; then
    ok "$name"
  else
    cat /tmp/zskills-scheduler-test.err
    not_ok "$name"
  fi
}

run_fail() {
  local name=$1; shift
  if "$@" >/tmp/zskills-scheduler-test.out 2>/tmp/zskills-scheduler-test.err; then
    cat /tmp/zskills-scheduler-test.out
    not_ok "$name"
  else
    ok "$name"
  fi
}

cd "$TMP"
git init -q
git config user.email test@example.com
git config user.name test
touch README.md
git add README.md
git commit -q -m init
mkdir -p scripts
cp "$ROOT/scripts/zskills-scheduler.sh" scripts/
cp "$ROOT/scripts/zskills-run-due.sh" scripts/
export ZSKILLS_CRONTAB_FILE="$TMP/fake-crontab"

printf '# unrelated user cron\n17 3 * * * echo keep-me\n' > "$ZSKILLS_CRONTAB_FILE"
run_fail "runner status fails before enable" scripts/zskills-scheduler.sh runner-status --repo-path "$TMP"
run_ok "runner enable" scripts/zskills-scheduler.sh runner-enable --repo-path "$TMP"
rg -F "echo keep-me" "$ZSKILLS_CRONTAB_FILE" >/dev/null && ok "runner enable preserves unrelated crontab" || not_ok "runner enable preserves unrelated crontab"
rg -F "zskills-run-due.sh" "$ZSKILLS_CRONTAB_FILE" >/dev/null && ok "runner enable writes due runner" || not_ok "runner enable writes due runner"
run_ok "runner enable is idempotent" scripts/zskills-scheduler.sh runner-enable --repo-path "$TMP"
[ "$(rg -c "zskills-cc scheduled runner start" "$ZSKILLS_CRONTAB_FILE")" -eq 1 ] && ok "runner enable avoids duplicate blocks" || not_ok "runner enable avoids duplicate blocks"
run_ok "runner status passes after enable" scripts/zskills-scheduler.sh runner-status --repo-path "$TMP"
sed -i 's/zskills-run-due.sh/zskills-run-due-stale.sh/' "$ZSKILLS_CRONTAB_FILE"
run_fail "runner status detects stale block" scripts/zskills-scheduler.sh runner-status --repo-path "$TMP"
run_ok "runner enable repairs stale block" scripts/zskills-scheduler.sh runner-enable --repo-path "$TMP"
run_ok "runner disable" scripts/zskills-scheduler.sh runner-disable --repo-path "$TMP"
rg -F "echo keep-me" "$ZSKILLS_CRONTAB_FILE" >/dev/null && ok "runner disable preserves unrelated crontab" || not_ok "runner disable preserves unrelated crontab"
! rg -F "zskills-run-due.sh" "$ZSKILLS_CRONTAB_FILE" >/dev/null && ok "runner disable removes managed block" || not_ok "runner disable removes managed block"
run_ok "runner install alias" scripts/zskills-scheduler.sh runner-install --repo-path "$TMP"
run_ok "runner uninstall alias" scripts/zskills-scheduler.sh runner-uninstall --repo-path "$TMP"

run_ok "add interval job" scripts/zskills-scheduler.sh add \
  --id run-plan-demo \
  --skill run-plan \
  --args "plans/DEMO.md auto" \
  --schedule 5m \
  --runner-command "printf"

run_ok "add every-hour job" scripts/zskills-scheduler.sh add \
  --id briefing-hour \
  --skill briefing \
  --args "summary" \
  --schedule "every hour" \
  --runner-command "printf"

run_ok "runner enable for active schedule" scripts/zskills-scheduler.sh runner-enable --repo-path "$TMP"
run_ok "runner disable-if-idle keeps active schedule" scripts/zskills-scheduler.sh runner-disable-if-idle --repo-path "$TMP"
rg -F "zskills-run-due.sh" "$ZSKILLS_CRONTAB_FILE" >/dev/null && ok "runner disable-if-idle keeps cron when active" || not_ok "runner disable-if-idle keeps cron when active"

[ -f .zskills/schedules/run-plan-demo.json ] && ok "schedule file written" || not_ok "schedule file written"
scripts/zskills-scheduler.sh list | rg "run-plan-demo" >/dev/null && ok "list shows job" || not_ok "list shows job"
scripts/zskills-scheduler.sh next | rg "run-plan-demo" >/dev/null && ok "next shows job" || not_ok "next shows job"

python - <<'PY'
import json
from pathlib import Path
p = Path(".zskills/schedules/run-plan-demo.json")
j = json.loads(p.read_text())
j["next_run"] = "2000-01-01T00:00:00Z"
p.write_text(json.dumps(j, indent=2) + "\n")
PY

scripts/zskills-scheduler.sh due --format json | rg "run-plan-demo" >/dev/null && ok "due returns job" || not_ok "due returns job"
run_ok "dry-run creates log" scripts/zskills-run-due.sh --dry-run
find .zskills/logs/run-plan-demo -type f -name '*.log' | rg . >/dev/null && ok "dry-run log exists" || not_ok "dry-run log exists"

run_ok "mark complete reschedules" scripts/zskills-scheduler.sh mark-complete --id run-plan-demo --message done
python - <<'PY' && ok "mark complete sets pending" || not_ok "mark complete sets pending"
import json
from pathlib import Path
j = json.loads(Path(".zskills/schedules/run-plan-demo.json").read_text())
raise SystemExit(0 if j["last_status"] == "pending" and j["last_message"] == "done" else 1)
PY

run_ok "trigger by skill" scripts/zskills-scheduler.sh trigger --skill run-plan
scripts/zskills-scheduler.sh due --format json | rg "run-plan-demo" >/dev/null && ok "trigger makes job due" || not_ok "trigger makes job due"

run_ok "stop by skill" scripts/zskills-scheduler.sh stop --skill run-plan
python - <<'PY' && ok "stop marks stopped" || not_ok "stop marks stopped"
import json
from pathlib import Path
j = json.loads(Path(".zskills/schedules/run-plan-demo.json").read_text())
raise SystemExit(0 if j["last_status"] == "stopped" else 1)
PY
run_ok "stop remaining active schedule" scripts/zskills-scheduler.sh stop --skill briefing
run_ok "runner disable-if-idle removes idle cron" scripts/zskills-scheduler.sh runner-disable-if-idle --repo-path "$TMP"
! rg -F "zskills-run-due.sh" "$ZSKILLS_CRONTAB_FILE" >/dev/null && ok "runner disable-if-idle removes cron when idle" || not_ok "runner disable-if-idle removes cron when idle"

run_ok "add missing-tool job" scripts/zskills-scheduler.sh add \
  --id missing-tool \
  --skill run-plan \
  --args "plans/DEMO.md auto" \
  --schedule 5m \
  --runner-command "definitely-missing-zskills-runner"
python - <<'PY'
import json
from pathlib import Path
p = Path(".zskills/schedules/missing-tool.json")
j = json.loads(p.read_text())
j["next_run"] = "2000-01-01T00:00:00Z"
j["required_tools"] = ["definitely-missing-zskills-runner"]
p.write_text(json.dumps(j, indent=2) + "\n")
PY
run_ok "missing tool blocks" scripts/zskills-run-due.sh
python - <<'PY' && ok "blocked status recorded" || not_ok "blocked status recorded"
import json
from pathlib import Path
j = json.loads(Path(".zskills/schedules/missing-tool.json").read_text())
raise SystemExit(0 if j["last_status"] == "blocked" and "missing required" in j["last_message"] else 1)
PY

run_ok "add one-shot job" scripts/zskills-scheduler.sh add \
  --id one-shot \
  --skill run-plan \
  --args "plans/ONE.md finish auto" \
  --schedule 5m \
  --runner-command "printf" \
  --one-shot
run_ok "add duplicate one-shot job" scripts/zskills-scheduler.sh add \
  --id one-shot \
  --skill run-plan \
  --args "plans/ONE.md finish auto" \
  --schedule 5m \
  --runner-command "printf" \
  --one-shot
[ -f .zskills/schedules/one-shot-2.json ] && ok "duplicate one-shot uses fresh id" || not_ok "duplicate one-shot uses fresh id"
run_ok "mark complete stops one-shot" scripts/zskills-scheduler.sh mark-complete --id one-shot --message done
python - <<'PY' && ok "one-shot stopped after completion" || not_ok "one-shot stopped after completion"
import json
from pathlib import Path
j1 = json.loads(Path(".zskills/schedules/one-shot.json").read_text())
j2 = json.loads(Path(".zskills/schedules/one-shot-2.json").read_text())
ok = j1["last_status"] == "stopped" and j1["next_run"] is None and j2["last_status"] == "pending"
raise SystemExit(0 if ok else 1)
PY

echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
