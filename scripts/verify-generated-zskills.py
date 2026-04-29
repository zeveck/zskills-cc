#!/usr/bin/env python3
"""Verify generated ZSkills output and Claude/Codex separation."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def run(cmd: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def require(condition: bool, message: str, errors: list[str]) -> None:
    if not condition:
        errors.append(message)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def verify_skill_file(path: Path, client: str, errors: list[str]) -> None:
    text = path.read_text()
    match = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    require(bool(match), f"{path}: missing frontmatter", errors)
    if match:
        frontmatter = match.group(1)
        require(bool(re.search(r"^name:\s*\S+", frontmatter, re.M)), f"{path}: frontmatter missing name", errors)
        require(
            bool(re.search(r"^description:\s*(>|\S)", frontmatter, re.M)),
            f"{path}: frontmatter missing description",
            errors,
        )
    starts = text.count("<!-- ZSKILLS_CODEX_COMPAT_START -->")
    ends = text.count("<!-- ZSKILLS_CODEX_COMPAT_END -->")
    if client == "codex":
        require(starts == 1 and ends == 1, f"{path}: expected one Codex adapter block", errors)
    else:
        require(starts == 0 and ends == 0, f"{path}: Claude output contains Codex adapter block", errors)
        require("Codex Compatibility" not in text, f"{path}: Claude output contains Codex compatibility text", errors)


def verify_manifest(root: Path, upstream: Path, errors: list[str]) -> dict:
    manifest_path = root / "codex-overlays" / "manifest.json"
    require(manifest_path.exists(), f"missing overlay manifest: {manifest_path}", errors)
    if not manifest_path.exists():
        return {"overlays": []}
    try:
        manifest = json.loads(manifest_path.read_text())
    except Exception as exc:
        errors.append(f"overlay manifest is malformed JSON: {exc}")
        return {"overlays": []}
    seen: set[str] = set()
    for overlay in manifest.get("overlays", []):
        path = overlay.get("path", "")
        skill = overlay.get("skill", "")
        require(bool(skill), f"overlay missing skill: {overlay}", errors)
        require(path not in seen, f"duplicate overlay path in manifest: {path}", errors)
        seen.add(path)
        patch = root / "codex-overlays" / path
        require(patch.exists(), f"manifest references missing overlay patch: {path}", errors)
        if patch.exists():
            require(patch.read_text().startswith("--- SKILL.md\n+++ SKILL.md\n"), f"{path}: unexpected patch header", errors)
            expected = overlay.get("sha256")
            require(bool(expected), f"{path}: missing sha256", errors)
            if expected:
                require(sha256_file(patch) == expected, f"{path}: sha256 mismatch", errors)
    expected_head = manifest.get("validated_upstream_head")
    if expected_head and (upstream / ".git").exists():
        head = run(["git", "rev-parse", "HEAD"], upstream)
        require(head.returncode == 0, f"could not read upstream HEAD: {head.stderr}", errors)
        if head.returncode == 0:
            require(head.stdout.strip() == expected_head, "upstream HEAD differs from overlay manifest", errors)
    return manifest


def file_map(root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    if not root.exists():
        return result
    for path in root.rglob("*"):
        if path.is_file():
            result[str(path.relative_to(root))] = sha256_file(path)
    return result


def compare_outputs(expected: Path, actual: Path, label: str, errors: list[str]) -> None:
    if not actual.exists():
        return
    expected_map = file_map(expected)
    actual_map = file_map(actual)
    missing = sorted(set(expected_map) - set(actual_map))
    extra = sorted(set(actual_map) - set(expected_map))
    changed = sorted(p for p in expected_map.keys() & actual_map.keys() if expected_map[p] != actual_map[p])
    require(not missing, f"{label} output missing files: {missing[:10]}", errors)
    require(not extra, f"{label} output has extra files: {extra[:10]}", errors)
    require(not changed, f"{label} output drifted from generated overlays: {changed[:10]}", errors)


def verify_tracking_cleanup(root: Path, errors: list[str]) -> None:
    broad = re.compile(r"\\brm\\s+-rf\\s+[^\\n`]*\\.zskills(?!/tracking/)")
    for path in root.rglob("*"):
        if not path.is_file() or path.suffix not in {".md", ".sh", ".py"}:
            continue
        text = path.read_text(errors="ignore")
        match = broad.search(text)
        require(match is None, f"{path}: broad destructive .zskills cleanup pattern", errors)


def verify_helper_adoption(root: Path, errors: list[str]) -> None:
    required = {
        "run-plan": ["zskills-config.sh", "zskills-preflight.sh", "zskills-scheduler.sh", "zskills-run-due.sh"],
        "fix-issues": ["zskills-config.sh", "zskills-preflight.sh", "zskills-scheduler.sh", "zskills-run-due.sh"],
        "do": ["zskills-config.sh", "zskills-preflight.sh", "zskills-scheduler.sh", "zskills-run-due.sh"],
        "commit": ["zskills-preflight.sh"],
        "qe-audit": ["zskills-scheduler.sh", "zskills-run-due.sh"],
        "briefing": ["zskills-scheduler.sh", "zskills-run-due.sh"],
        "update-zskills": ["zskills-install.sh", "--client codex", "--client claude", "--client both"],
    }
    for skill, needles in required.items():
        path = root / skill / "SKILL.md"
        text = path.read_text() if path.exists() else ""
        for needle in needles:
            require(needle in text, f"{path}: missing helper adoption reference {needle}", errors)


def verify_preflight_inventory(project_root: Path, generated_root: Path, errors: list[str]) -> None:
    inventory_path = project_root / "codex-overlays" / "preflight-inventory.json"
    require(inventory_path.exists(), f"missing preflight inventory: {inventory_path}", errors)
    if not inventory_path.exists():
        return
    try:
        inventory = json.loads(inventory_path.read_text())
    except Exception as exc:
        errors.append(f"preflight inventory is malformed JSON: {exc}")
        return

    entries = inventory.get("entries", [])
    covered = {(entry.get("skill"), entry.get("operation")) for entry in entries}
    for entry in entries:
        skill = entry.get("skill", "")
        operation = entry.get("operation", "")
        status = entry.get("status", "")
        callsite = entry.get("callsite", "")
        skill_path = generated_root / skill / "SKILL.md"
        require(skill_path.exists(), f"preflight inventory references missing skill: {skill}", errors)
        require(operation in {"commit", "cherry-pick", "pr", "merge", "delete-worktree", "clear-tracking"}, f"invalid preflight operation: {operation}", errors)
        require(status in {"gated", "exempt"}, f"invalid preflight status for {skill}/{operation}: {status}", errors)
        require(bool(callsite), f"preflight inventory missing callsite for {skill}/{operation}", errors)
        if status == "exempt":
            require(bool(entry.get("reason")), f"preflight exemption missing reason for {skill}/{operation}", errors)
            continue
        text = skill_path.read_text() if skill_path.exists() else ""
        require("zskills-preflight.sh" in text, f"{skill}: gated {operation} missing zskills-preflight.sh", errors)
        require(f"--operation {operation}" in text, f"{skill}: gated {operation} missing --operation call", errors)
        require("failure as a blocker" in text or "treat failure as a blocker" in text or "failures are blockers" in text, f"{skill}: gated {operation} does not state failures are blockers", errors)

    risk_patterns = {
        "commit": re.compile(r"\bgit\s+commit\b"),
        "cherry-pick": re.compile(r"\bgit\s+cherry-pick\s+(?:<|[a-f0-9])"),
        "pr": re.compile(r"\bgh\s+pr\s+create\b"),
        "merge": re.compile(r"\bgh\s+pr\s+merge\b"),
        "delete-worktree": re.compile(r"\bgit\s+worktree\s+remove\b"),
        "clear-tracking": re.compile(r"\bclear-tracking\.sh\b"),
    }
    for skill_dir in generated_root.iterdir():
        skill_file = skill_dir / "SKILL.md"
        if not skill_file.exists():
            continue
        text = skill_file.read_text()
        for operation, pattern in risk_patterns.items():
            if pattern.search(text) and (skill_dir.name, operation) not in covered:
                errors.append(f"{skill_dir.name}: dangerous {operation} callsite is not in preflight inventory")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--upstream", type=Path, default=Path("~/.codex/zskills-portable"))
    parser.add_argument("--codex-output", type=Path, default=Path("build/codex-skills"))
    parser.add_argument("--claude-output", type=Path, default=Path("build/claude-skills"))
    parser.add_argument("--allow-local-upstream", action="store_true")
    parser.add_argument("--patch-queue-entry", default="")
    args = parser.parse_args()

    root = args.root.resolve()
    upstream = args.upstream.expanduser().resolve()
    errors: list[str] = []
    verify_manifest(root, upstream, errors)

    if (upstream / ".git").exists():
        status = run(["git", "status", "--short"], upstream)
        require(status.returncode == 0, f"could not inspect upstream git status: {status.stderr}", errors)
        if status.stdout.strip():
            if not args.allow_local_upstream or not args.patch_queue_entry:
                errors.append(
                    "upstream checkout is dirty; rerun with --allow-local-upstream "
                    "and --patch-queue-entry <name> only for a reviewed local patch:\n"
                    + status.stdout
                )

    with tempfile.TemporaryDirectory() as tmp:
        tmp_root = Path(tmp)
        codex_tmp = tmp_root / "codex"
        claude_tmp = tmp_root / "claude"
        gen = root / "scripts" / "generate-codex-skills.py"
        common = ["--upstream", str(upstream), "--manifest", "codex-overlays/manifest.json"]

        codex_run = run(["python", str(gen), "--client", "codex", "--output", str(codex_tmp), *common], root)
        require(codex_run.returncode == 0, f"Codex generation failed:\n{codex_run.stderr}", errors)

        claude_run = run(["python", str(gen), "--client", "claude", "--output", str(claude_tmp), *common], root)
        require(claude_run.returncode == 0, f"Claude generation failed:\n{claude_run.stderr}", errors)

        if not errors:
            for path in codex_tmp.glob("*/SKILL.md"):
                verify_skill_file(path, "codex", errors)
            for path in claude_tmp.glob("*/SKILL.md"):
                verify_skill_file(path, "claude", errors)

            manifest = json.loads((codex_tmp / "generation-manifest.json").read_text())
            require(len(manifest.get("skills", [])) == 19, "Codex generation did not produce 19 skills", errors)
            require((codex_tmp / "scripts" / "zskills-config.sh").exists(), "Codex generation missing zskills-config.sh", errors)
            require((codex_tmp / "scripts" / "zskills-preflight.sh").exists(), "Codex generation missing zskills-preflight.sh", errors)
            require((codex_tmp / "scripts" / "zskills-scheduler.sh").exists(), "Codex generation missing zskills-scheduler.sh", errors)
            require((codex_tmp / "scripts" / "zskills-run-due.sh").exists(), "Codex generation missing zskills-run-due.sh", errors)
            require((codex_tmp / "scripts" / "zskills-install.sh").exists(), "Codex generation missing zskills-install.sh", errors)
            verify_tracking_cleanup(codex_tmp, errors)
            verify_helper_adoption(codex_tmp, errors)
            verify_preflight_inventory(root, codex_tmp, errors)
            compare_outputs(codex_tmp, (root / args.codex_output).resolve(), "Codex", errors)
            compare_outputs(claude_tmp, (root / args.claude_output).resolve(), "Claude", errors)

    if errors:
        print("FAILED")
        for error in errors:
            print(f"- {error}")
        return 1
    print("OK: generated Codex and Claude ZSkills outputs verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
