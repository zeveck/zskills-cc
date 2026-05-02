#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PYTHON_BIN="${PYTHON_BIN:-$(command -v python3 || command -v python || true)}"
[ -n "$PYTHON_BIN" ] || { echo "ERROR: python3 or python is required" >&2; exit 3; }

"$PYTHON_BIN" "$SCRIPT_DIR/generate-codex-skills.py" "$@"
