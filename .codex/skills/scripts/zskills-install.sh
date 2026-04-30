#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  zskills-install.sh [--client codex|claude|both|auto] [--project-root PATH] [--codex-home PATH] [--upstream PATH] [--mirror-config] [--replace-all]

Installs generated Codex ZSkills to a Codex home and/or upstream-clean Claude
ZSkills to a project .claude directory. Project config is intentionally
client-scoped: .codex/zskills-config.json for Codex, .claude/zskills-config.json
for Claude.

By default, install preserves unrelated skills and replaces only generated
ZSkills-owned entries. Use --replace-all only when intentionally replacing the
entire destination skills directory.
EOF
}

client="auto"
project_root=""
codex_home="${CODEX_HOME:-$HOME/.codex}"
upstream="$HOME/.codex/zskills-portable"
mirror_config=0
replace_all=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --client) client="${2:-}"; shift 2 ;;
    --project-root) project_root="${2:-}"; shift 2 ;;
    --codex-home) codex_home="${2:-}"; shift 2 ;;
    --upstream) upstream="${2:-}"; shift 2 ;;
    --mirror-config) mirror_config=1; shift ;;
    --replace-all|--clean) replace_all=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$client" in
  codex|claude|both|auto) ;;
  *) echo "ERROR: invalid --client: $client" >&2; exit 2 ;;
esac

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

if [ -n "$project_root" ]; then
  project_root=$(cd "$project_root" && pwd)
elif git rev-parse --show-toplevel >/dev/null 2>&1; then
  project_root=$(git rev-parse --show-toplevel)
else
  project_root=$(pwd)
fi

if [ "$client" = "auto" ]; then
  if [ -d "$project_root/.codex" ] && [ -d "$project_root/.claude" ]; then
    client="both"
  elif [ -d "$project_root/.codex" ] || [ -d "$codex_home" ]; then
    client="codex"
  elif [ -d "$project_root/.claude" ]; then
    client="claude"
  else
    client="codex"
  fi
fi

upstream=$(cd "$upstream" && pwd)
[ -f "$upstream/CLAUDE_TEMPLATE.md" ] || { echo "ERROR: upstream does not look like zskills: $upstream" >&2; exit 3; }

default_config() {
  local target=$1
  mkdir -p "$(dirname "$target")"
  cat > "$target" <<JSON
{
  "\$schema": "./zskills-config.schema.json",
  "project_name": "$(basename "$project_root")",
  "timezone": "America/New_York",
  "execution": {
    "landing": "cherry-pick",
    "main_protected": false,
    "branch_prefix": "feat/"
  },
  "testing": {
    "unit_cmd": "",
    "full_cmd": "",
    "output_file": ".test-results.txt",
    "file_patterns": []
  },
  "dev_server": {
    "cmd": "",
    "port_script": "",
    "main_repo_path": "$project_root"
  },
  "ui": {
    "file_patterns": "",
    "auth_bypass": ""
  },
  "ci": {
    "auto_fix": true,
    "max_fix_attempts": 2
  }
}
JSON
}

copy_schema() {
  local target_dir=$1
  mkdir -p "$target_dir"
  if [ -f "$upstream/config/zskills-config.schema.json" ]; then
    cp "$upstream/config/zskills-config.schema.json" "$target_dir/zskills-config.schema.json"
  fi
}

ensure_config() {
  local target=$1
  local fallback=$2
  if [ -f "$target" ]; then
    :
  elif [ -f "$fallback" ]; then
    mkdir -p "$(dirname "$target")"
    cp "$fallback" "$target"
  else
    default_config "$target"
  fi
  copy_schema "$(dirname "$target")"
}

mirror_configs() {
  local codex_config="$project_root/.codex/zskills-config.json"
  local claude_config="$project_root/.claude/zskills-config.json"
  mkdir -p "$project_root/.codex" "$project_root/.claude"
  if [ -f "$codex_config" ] && [ -f "$claude_config" ] && ! cmp -s "$codex_config" "$claude_config"; then
    echo "Config divergence detected between .codex and .claude."
    if [ "$mirror_config" -ne 1 ]; then
      echo "ERROR: rerun with --mirror-config to intentionally mirror dual-client config." >&2
      exit 5
    fi
  fi
  if [ -f "$codex_config" ]; then
    cp "$codex_config" "$claude_config"
  elif [ -f "$claude_config" ]; then
    cp "$claude_config" "$codex_config"
  else
    default_config "$codex_config"
    cp "$codex_config" "$claude_config"
  fi
  copy_schema "$project_root/.codex"
  copy_schema "$project_root/.claude"
  echo "Mirrored dual-client config between .codex and .claude."
}

sync_generated_entries() {
  local source_dir=$1
  local dest_dir=$2
  local mode=${3:-all}

  mkdir -p "$dest_dir"
  while IFS= read -r entry; do
    local name
    name=$(basename "$entry")
    if [ "$mode" = "dirs-only" ] && [ ! -d "$entry" ]; then
      continue
    fi
    rm -rf "$dest_dir/$name"
    cp -a "$entry" "$dest_dir/"
  done < <(find "$source_dir" -mindepth 1 -maxdepth 1 ! -name scripts -print | sort)
}

install_codex() {
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  python "$repo_root/scripts/generate-codex-skills.py" \
    --client codex \
    --upstream "$upstream" \
    --output "$tmp/codex-skills" \
    --manifest "$repo_root/codex-overlays/manifest.json" \
    --adapter "$repo_root/templates/codex-compat-block.md"
  if [ "$replace_all" -eq 1 ]; then
    rm -rf "$codex_home/skills"
  fi
  sync_generated_entries "$tmp/codex-skills" "$codex_home/skills" all
  if [ -d "$tmp/codex-skills/scripts" ]; then
    rm -rf "$codex_home/skills/scripts"
    cp -a "$tmp/codex-skills/scripts" "$codex_home/skills/"
  fi
  ensure_config "$project_root/.codex/zskills-config.json" "$project_root/.claude/zskills-config.json"
  echo "Installed Codex ZSkills to $codex_home/skills"
}

install_claude() {
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' RETURN
  python "$repo_root/scripts/generate-codex-skills.py" \
    --client claude \
    --upstream "$upstream" \
    --output "$tmp/claude-skills" \
    --manifest "$repo_root/codex-overlays/manifest.json" \
    --adapter "$repo_root/templates/codex-compat-block.md"
  if [ "$replace_all" -eq 1 ]; then
    rm -rf "$project_root/.claude/skills"
  fi
  sync_generated_entries "$tmp/claude-skills" "$project_root/.claude/skills" dirs-only
  ensure_config "$project_root/.claude/zskills-config.json" "$project_root/.codex/zskills-config.json"
  echo "Installed Claude ZSkills to $project_root/.claude/skills"
}

case "$client" in
  codex)
    install_codex ;;
  claude)
    install_claude ;;
  both)
    mirror_configs
    install_codex
    install_claude ;;
esac
