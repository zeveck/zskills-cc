#!/usr/bin/env python3
"""Verify the local Codex adapter for zeveck/zskills."""

from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

try:
    import yaml
except Exception:  # pragma: no cover - optional dependency in some runtimes
    yaml = None


PROJECT_ROOT = Path.cwd()
CODEX_SKILLS = PROJECT_ROOT / ".agents" / "skills"
if not CODEX_SKILLS.exists():
    CODEX_SKILLS = Path.home() / ".agents" / "skills"
if not CODEX_SKILLS.exists():
    CODEX_SKILLS = Path.home() / ".codex" / "skills"
UPSTREAM = Path.home() / ".codex" / "zskills-portable"
SPECIAL_SKILL_SOURCES = {
    "add-block": Path("block-diagram/add-block"),
    "add-example": Path("block-diagram/add-example"),
    "model-design": Path("block-diagram/model-design"),
    "playwright-cli": Path(".claude/skills/playwright-cli"),
}
INTENTIONAL_NON_ADAPTER = {
    "briefing",
    "commit",
    "do",
    "draft-plan",
    "fix-issues",
    "fix-report",
    "qe-audit",
    "research-and-go",
    "run-plan",
    "update-zskills",
    "verify-changes",
}


def upstream_skill(name: str) -> Path:
    rel = SPECIAL_SKILL_SOURCES.get(name, Path("skills") / name)
    return UPSTREAM / rel / "SKILL.md"


def expected_skill_names() -> set[str]:
    names = {p.parent.name for p in (UPSTREAM / "skills").glob("*/SKILL.md")}
    for name, rel in SPECIAL_SKILL_SOURCES.items():
        if (UPSTREAM / rel / "SKILL.md").exists():
            names.add(name)
    return names


def strip_codex_block(text: str) -> str:
    text = re.sub(
        r"<!-- ZSKILLS_CODEX_COMPAT_START -->.*?<!-- ZSKILLS_CODEX_COMPAT_END -->\n*",
        "",
        text,
        flags=re.S,
    )
    return re.sub(r"^(---\n.*?\n---)\n{3,}", r"\1\n\n", text, flags=re.S)


def frontmatter_ok(path: Path, text: str) -> list[str]:
    errors: list[str] = []
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not match:
        return [f"{path}: missing YAML frontmatter"]
    if yaml is not None:
        try:
            data = yaml.safe_load(match.group(1)) or {}
        except Exception as exc:
            return [f"{path}: frontmatter parse failed: {exc}"]
        for key in ("name", "description"):
            if key not in data:
                errors.append(f"{path}: missing frontmatter key {key!r}")
    return errors


def main() -> int:
    errors: list[str] = []
    warnings: list[str] = []
    diffs: list[tuple[str, str]] = []

    skill_files = sorted(p for p in CODEX_SKILLS.glob("*/SKILL.md"))
    if not skill_files:
        errors.append(f"No installed skills found under {CODEX_SKILLS}")

    actual_names = {p.parent.name for p in skill_files}
    expected_names = expected_skill_names()
    if actual_names != expected_names:
        errors.append(
            "installed skill set mismatch: "
            f"expected {sorted(expected_names)}, got {sorted(actual_names)}"
        )

    for path in skill_files:
        name = path.parent.name
        text = path.read_text()
        errors.extend(frontmatter_ok(path, text))

        start = "<!-- ZSKILLS_CODEX_COMPAT_START -->"
        end = "<!-- ZSKILLS_CODEX_COMPAT_END -->"
        if text.count(start) != 1 or text.count(end) != 1:
            errors.append(f"{name}: expected exactly one Codex compat block")
        else:
            fm_match = re.match(r"^---\n.*?\n---\n", text, re.S)
            if fm_match and text.find(start) < fm_match.end():
                errors.append(f"{name}: compat block appears inside frontmatter")

        for required in (
            "subagent tool is available",
            "Scheduler bridge",
            ".zskills/tracking",
            "never under `~/.codex/skills`",
            "direct`, `cherry-pick`, and `pr`",
        ):
            if required not in text:
                errors.append(f"{name}: missing adapter phrase {required!r}")

        if re.search(r"rm\s+-r[f]?\s+.*\.zskills|\.zskills.*rm\s+-r[f]?", text):
            errors.append(f"{name}: contains broad destructive .zskills cleanup")

        if ".zskills/tracking" in text and "git rev-parse --git-common-dir" not in text:
            errors.append(f"{name}: tracking mentioned without main-root resolution")

        src = upstream_skill(name)
        if not src.exists():
            errors.append(f"{name}: upstream source missing at {src}")
            continue

        normalized = strip_codex_block(text)
        upstream = src.read_text()
        if normalized != upstream:
            if name not in INTENTIONAL_NON_ADAPTER:
                errors.append(f"{name}: differs from upstream beyond Codex block")
            diff = "".join(
                difflib.unified_diff(
                    upstream.splitlines(True),
                    normalized.splitlines(True),
                    fromfile=str(src),
                    tofile=f"{path} normalized",
                    n=3,
                )
            )
            diffs.append((name, f"=== {name} ===\n{diff[:4000]}"))

    if not (UPSTREAM / "CLAUDE_TEMPLATE.md").exists():
        errors.append(f"portable upstream checkout missing or incomplete: {UPSTREAM}")

    if errors:
        print("FAILED")
        for err in errors:
            print(f"- {err}")
        if diffs:
            print("\nDiff samples:")
            print("\n".join(diff for _, diff in diffs[:4]))
        return 1

    print(f"OK: {len(skill_files)} Codex ZSkills verified")
    if diffs:
        print(
            "Intentional non-adapter edits:",
            ", ".join(sorted(INTENTIONAL_NON_ADAPTER & {name for name, _ in diffs})),
        )
    if warnings:
        print("\n".join(warnings))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
