#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-config.sh resolve [--client codex|claude|auto] [--format json|env] [--mode direct|cherry-pick|pr]
  zskills-config.sh get KEY [--client codex|claude|auto]
  zskills-config.sh export-env [--client codex|claude|auto]
  zskills-config.sh validate [--client codex|claude|auto] [--mode direct|cherry-pick|pr]

Exit codes:
  0 success
  2 invalid args
  3 missing required config
  4 malformed config
  5 .codex/.claude conflict
  6 protected-main violation for requested mode
EOF
}

cmd="${1:-}"
[ -n "$cmd" ] || { usage >&2; exit 2; }
shift || true

client="auto"
format="json"
mode=""
key=""

if [ "$cmd" = "get" ]; then
  key="${1:-}"
  [ -n "$key" ] || { usage >&2; exit 2; }
  shift || true
fi

while [ "$#" -gt 0 ]; do
  case "$1" in
    --client)
      client="${2:-}"; shift 2 ;;
    --format)
      format="${2:-}"; shift 2 ;;
    --mode)
      mode="${2:-}"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      exit 2 ;;
  esac
done

case "$cmd" in
  resolve|get|export-env|validate) ;;
  *) usage >&2; exit 2 ;;
esac

case "$client" in
  codex|claude|auto) ;;
  *) echo "ERROR: invalid --client: $client" >&2; exit 2 ;;
esac

case "$format" in
  json|env) ;;
  *) echo "ERROR: invalid --format: $format" >&2; exit 2 ;;
esac

case "$mode" in
  ""|direct|cherry-pick|pr) ;;
  *) echo "ERROR: invalid --mode: $mode" >&2; exit 2 ;;
esac

python - "$cmd" "$key" "$client" "$format" "$mode" <<'PY'
import json
import os
import sys
from pathlib import Path

cmd, key, client, fmt, mode = sys.argv[1:6]
root = Path.cwd()
codex_path = root / ".codex" / "zskills-config.json"
claude_path = root / ".claude" / "zskills-config.json"


def load(path):
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        print(f"ERROR: malformed config {path}: {exc}", file=sys.stderr)
        sys.exit(4)


codex = load(codex_path)
claude = load(claude_path)

if client == "codex":
    if codex is not None:
        active_path, active, active_client = codex_path, codex, "codex"
    elif claude is not None:
        active_path, active, active_client = claude_path, claude, "claude"
    else:
        active_path, active, active_client = codex_path, None, "codex"
elif client == "claude":
    active_path, active, active_client = claude_path, claude, "claude"
else:
    if codex is not None:
        active_path, active, active_client = codex_path, codex, "codex"
    elif claude is not None:
        active_path, active, active_client = claude_path, claude, "claude"
    else:
        active_path, active, active_client = codex_path, None, "auto"

if active is None:
    active_path, active, active_client = Path(""), {}, client if client != "auto" else "auto"


def nested(data, dotted, default=None):
    cur = data
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur


if codex is not None and claude is not None:
    c_landing = nested(codex, "execution.landing", "")
    h_landing = nested(claude, "execution.landing", "")
    c_protected = nested(codex, "execution.main_protected", None)
    h_protected = nested(claude, "execution.main_protected", None)
    if (c_landing and h_landing and c_landing != h_landing) or (
        c_protected is not None and h_protected is not None and c_protected != h_protected
    ):
        print("ERROR: .codex and .claude zskills config disagree on landing/main protection", file=sys.stderr)
        sys.exit(5)

landing = nested(active, "execution.landing", "cherry-pick")
main_protected = bool(nested(active, "execution.main_protected", False))
requested_mode = mode or landing
if requested_mode == "direct" and main_protected:
    print("ERROR: direct mode is incompatible with main_protected: true", file=sys.stderr)
    sys.exit(6)

result = {
    "config_path": str(active_path),
    "client": active_client,
    "landing": landing,
    "requested_mode": requested_mode,
    "main_protected": main_protected,
    "branch_prefix": nested(active, "execution.branch_prefix", "feat/"),
    "ci_auto_fix": bool(nested(active, "ci.auto_fix", True)),
    "ci_max_attempts": int(nested(active, "ci.max_fix_attempts", 2)),
    "full_test_cmd": nested(active, "testing.full_cmd", ""),
    "unit_test_cmd": nested(active, "testing.unit_cmd", ""),
    "test_output_file": nested(active, "testing.output_file", ".test-results.txt"),
    "timezone": nested(active, "timezone", "America/New_York"),
}

if cmd == "validate":
    print("OK")
    sys.exit(0)

if cmd == "get":
    aliases = {
        "ci.auto_fix": "ci_auto_fix",
        "ci.max_fix_attempts": "ci_max_attempts",
        "testing.full_cmd": "full_test_cmd",
        "testing.unit_cmd": "unit_test_cmd",
        "execution.landing": "landing",
        "execution.main_protected": "main_protected",
        "execution.branch_prefix": "branch_prefix",
    }
    out_key = aliases.get(key, key)
    if out_key not in result:
        print(f"ERROR: unknown key: {key}", file=sys.stderr)
        sys.exit(2)
    value = result[out_key]
    if isinstance(value, bool):
        print("true" if value else "false")
    else:
        print(value)
    sys.exit(0)

if cmd == "export-env" or fmt == "env":
    for k, v in result.items():
        env_key = "ZSKILLS_" + k.upper()
        if isinstance(v, bool):
            v = "true" if v else "false"
        print(f"{env_key}={json.dumps(str(v))}")
    sys.exit(0)

print(json.dumps(result, indent=2, sort_keys=True))
PY
