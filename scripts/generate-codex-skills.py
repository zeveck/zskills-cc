#!/usr/bin/env python3
"""Generate Codex or Claude ZSkills installs from upstream plus overlays."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path


SPECIAL_SKILL_SOURCES = {
    "playwright-cli": Path(".claude/skills/playwright-cli"),
}

SUPPORT_SCRIPTS = [
    Path("scripts/zskills-config.sh"),
    Path("scripts/zskills-preflight.sh"),
    Path("scripts/zskills-scheduler.sh"),
    Path("scripts/zskills-run-due.sh"),
    Path("scripts/zskills-install.sh"),
]


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def git_head(path: Path) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", str(path), "rev-parse", "HEAD"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
    except Exception:
        return "unknown"


def git_dirty(path: Path) -> bool:
    try:
        status = subprocess.check_output(
            ["git", "-C", str(path), "status", "--short"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return False
    return bool(status.strip())


def skill_source(upstream: Path, name: str) -> Path:
    rel = SPECIAL_SKILL_SOURCES.get(name, Path("skills") / name)
    return upstream / rel


def discover_skills(upstream: Path) -> list[str]:
    names = {p.parent.name for p in (upstream / "skills").glob("*/SKILL.md")}
    for name, rel in SPECIAL_SKILL_SOURCES.items():
        if (upstream / rel / "SKILL.md").exists():
            names.add(name)
    return sorted(names)


def insert_adapter(skill_file: Path, adapter: str) -> None:
    text = skill_file.read_text()
    if "<!-- ZSKILLS_CODEX_COMPAT_START -->" in text:
        raise RuntimeError(f"{skill_file} already contains Codex adapter")
    match = re.match(r"^---\n.*?\n---\n", text, re.S)
    if not match:
        raise RuntimeError(f"{skill_file} missing YAML frontmatter")
    skill_file.write_text(text[: match.end()] + "\n" + adapter.rstrip() + "\n" + text[match.end() :])


def apply_patch_file(skill_dir: Path, patch_file: Path) -> None:
    subprocess.run(
        ["patch", "--silent", "-p0", "-i", str(patch_file.resolve())],
        cwd=skill_dir,
        check=True,
    )


def load_manifest(path: Path) -> dict:
    if not path.exists():
        return {"overlays": []}
    return json.loads(path.read_text())


def overlay_map(manifest: dict) -> dict[str, list[dict]]:
    result: dict[str, list[dict]] = {}
    for overlay in manifest.get("overlays", []):
        result.setdefault(overlay["skill"], []).append(overlay)
    return result


def copy_skill(upstream: Path, output: Path, name: str) -> Path:
    src = skill_source(upstream, name)
    if not src.exists():
        raise RuntimeError(f"missing upstream skill source for {name}: {src}")
    dst = output / name
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    return dst


def generate(args: argparse.Namespace) -> int:
    upstream = args.upstream.expanduser().resolve()
    output = args.output.expanduser().resolve()
    manifest_path = args.manifest.resolve()
    adapter_path = args.adapter.resolve()

    if not (upstream / "CLAUDE_TEMPLATE.md").exists():
        raise RuntimeError(f"upstream checkout does not look like zskills: {upstream}")
    if args.fail_on_dirty_upstream and git_dirty(upstream):
        raise RuntimeError(f"upstream checkout has uncommitted edits: {upstream}")

    manifest = load_manifest(manifest_path)
    overlays = overlay_map(manifest)
    adapter = adapter_path.read_text() if args.client == "codex" else ""

    if output.exists():
        shutil.rmtree(output)
    output.mkdir(parents=True)

    installed: list[dict] = []
    allowed_targets = {"codex-only", "claude-only", "shared", "both"}
    for name in discover_skills(upstream):
        dst = copy_skill(upstream, output, name)
        for overlay in overlays.get(name, []):
            target = overlay.get("target", "codex-only")
            if target not in allowed_targets:
                raise RuntimeError(f"unknown overlay target for {name}: {target}")
            if args.client == "claude" and target not in {"claude-only", "shared", "both"}:
                continue
            if args.client == "codex" and target == "claude-only":
                continue
            patch = (manifest_path.parent / overlay["path"]).resolve()
            expected = overlay.get("sha256")
            actual = sha256_file(patch)
            if expected and actual != expected:
                raise RuntimeError(f"overlay checksum mismatch for {patch}")
            apply_patch_file(dst, patch)
        if args.client == "codex":
            insert_adapter(dst / "SKILL.md", adapter)
        installed.append({"name": name, "sha256": sha256_file(dst / "SKILL.md")})

    support_scripts: list[dict] = []
    scripts_output = output / "scripts"
    for rel in SUPPORT_SCRIPTS:
        src = Path.cwd() / rel
        if not src.exists():
            continue
        scripts_output.mkdir(exist_ok=True)
        dst = scripts_output / src.name
        shutil.copyfile(src, dst)
        dst.chmod(0o755)
        support_scripts.append({"path": str(rel), "sha256": sha256_file(dst)})

    if args.client == "codex":
        shutil.copyfile(adapter_path, output / "ZSKILLS_CODEX_COMPAT.md")

    generation_manifest = {
        "client": args.client,
        "upstream": str(upstream),
        "upstream_head": git_head(upstream),
        "source_manifest": str(manifest_path),
        "adapter": str(adapter_path) if args.client == "codex" else None,
        "support_scripts": support_scripts,
        "skills": installed,
    }
    (output / "generation-manifest.json").write_text(json.dumps(generation_manifest, indent=2) + "\n")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--client", choices=["codex", "claude"], default="codex")
    parser.add_argument("--upstream", type=Path, default=Path("~/.codex/zskills-portable"))
    parser.add_argument("--output", type=Path, default=Path("build/codex-skills"))
    parser.add_argument("--manifest", type=Path, default=Path("codex-overlays/manifest.json"))
    parser.add_argument("--adapter", type=Path, default=Path("templates/codex-compat-block.md"))
    parser.add_argument("--fail-on-dirty-upstream", action="store_true")
    args = parser.parse_args()
    try:
        return generate(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
