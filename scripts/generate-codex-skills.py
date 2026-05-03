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
    "add-block": Path("block-diagram/add-block"),
    "add-example": Path("block-diagram/add-example"),
    "model-design": Path("block-diagram/model-design"),
    "playwright-cli": Path(".claude/skills/playwright-cli"),
}

COMMON_SUPPORT_SCRIPTS = [
    Path("scripts/zskills-config.sh"),
    Path("scripts/zskills-preflight.sh"),
    Path("scripts/zskills-scheduler.sh"),
    Path("scripts/zskills-run-due.sh"),
    Path("scripts/zskills-install.sh"),
]

CODEX_SUPPORT_SCRIPTS = [
    Path("scripts/zskills-runner.sh"),
    Path("scripts/zskills-gate.sh"),
    Path("scripts/zskills-post-run-invariants.sh"),
]

CODEX_ROOT_FILES = [
    Path("scripts/verify-zskills-codex.py"),
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
        ["patch", "--silent", "--no-backup-if-mismatch", "-p0", "-i", str(patch_file.resolve())],
        cwd=skill_dir,
        check=True,
    )


def postprocess_codex_skill(skill_dir: Path, name: str) -> None:
    if name == "run-plan":
        path = skill_dir / "SKILL.md"
        text = path.read_text()
        old_finish = (
            '  Without `auto`: pauses BETWEEN phases to show results and ask "continue\n'
            '  to next phase?" With `auto`: each phase runs as its own cron-fired\n'
            '  top-level turn (~5 min between phases via one-shot crons scheduled by\n'
            '  Phase 5c). The first phase runs immediately; each subsequent phase is\n'
            '  scheduled after the prior phase lands. Preserves fresh context per\n'
            '  phase \\u2014 no late-phase fatigue.\n'
            '  Each phase still gets full verification, testing, and all safety rails.\n'
            '  If any phase fails verification or hits a conflict, stops there.\n'
            '  **`finish` and `every` are mutually exclusive.** `finish auto` schedules\n'
            '  its own ~5-min one-shot crons internally. `every N` schedules a recurring\n'
            '  cron at user-set cadence. Combining them would produce two overlapping\n'
            '  cron schedules. Use one or the other.'
        ).encode().decode("unicode_escape")
        new_finish = (
            '  Without `auto`: pauses BETWEEN phases to show results and ask "continue\n'
            '  to next phase?" With `auto`: a foreground parent runner remains attached\n'
            '  to the initiating REPL and launches one fresh `codex exec` child chunk\n'
            '  per phase. The first phase runs immediately; each subsequent phase is\n'
            '  started by the parent runner after durable plan/report/tracking\n'
            '  validation. This preserves fresh context per phase without losing\n'
            '  visible feedback.\n'
            '  Each phase still gets full verification, testing, and all safety rails.\n'
            '  If any phase fails verification or hits a conflict, stops there.\n'
            '  **`finish` and `every` are mutually exclusive.** In Codex, `finish auto`\n'
            '  uses the foreground runner. `every N` schedules a recurring cron at\n'
            '  user-set cadence. Combining them would produce overlapping autonomous\n'
            '  workflows. Use one or the other.'
        )
        text = text.replace(old_finish, new_finish)
        text = text.replace(
            "- `/run-plan plans/FEATURE_PLAN.md finish auto` \u2014 autonomous, all remaining phases (chunked, one phase per cron turn)",
            "- `/run-plan plans/FEATURE_PLAN.md finish auto` \u2014 autonomous, all remaining phases (foreground runner, fresh child chunk per phase)",
        )
        text = text.replace("scripts/post-run-invariants.sh", "scripts/zskills-post-run-invariants.sh")
        text = text.replace("`post-run-invariants.sh`", "`zskills-post-run-invariants.sh`")
        text = text.replace(" post-run-invariants.sh", " zskills-post-run-invariants.sh")
        text = text.replace(
            "0. **Idempotent re-entry check (chunked finish auto only).** If running\n"
            "   with `finish auto`, this turn may have been triggered by a cron from\n"
            "   a previous turn. Re-emit the pipeline ID first (cron-fired turns are\n"
            "   fresh sessions):",
            "0. **Idempotent re-entry check (chunked finish auto only).** If running\n"
            "   with `finish auto`, this turn may be a foreground-runner child chunk.\n"
            "   Re-emit the pipeline ID first so tracking stays tied to the parent\n"
            "   runner:",
        )
        text = text.replace(
            '   TRACKING_ID=$(basename "$PLAN_FILE" .md | tr \'[:upper:]_\' \'[:lower:]-\')\n'
            '   echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"',
            '   TRACKING_ID="${ZSKILLS_TRACKING_ID:-$(basename "$PLAN_FILE" .md | tr \'[:upper:]_\' \'[:lower:]-\')}"\n'
            '   PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"\n'
            '   echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"',
        )
        text = text.replace(
            '     echo "ZSKILLS_PIPELINE_ID=run-plan.$TRACKING_ID"',
            '     PIPELINE_ID="${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}"\n'
            '     echo "ZSKILLS_PIPELINE_ID=$PIPELINE_ID"',
        )
        text = text.replace(
            '     printf \'%s\\n\' "run-plan.$TRACKING_ID" > "<worktree-path>/.zskills-tracked"',
            '     printf \'%s\\n\' "${ZSKILLS_PIPELINE_ID:-run-plan.$TRACKING_ID}" > "<worktree-path>/.zskills-tracked"',
        )
        text = text.replace(
            "     Where `$TRACKING_ID` is the plan slug (e.g., `thermal-domain`). This file associates the worktree agent with this pipeline for hook enforcement.",
            "     Where `$TRACKING_ID` is the runner-provided id when present, otherwise the plan slug. This file associates the worktree agent with this pipeline for hook enforcement.",
        )
        final_verify_start = "   On attempt 1, schedule the verify cron (~5 min from now)."
        final_verify_end = '   - `prompt`: `"Run /run-plan <plan-file> finish auto"`\n'
        if final_verify_start in text and final_verify_end in text:
            before, rest = text.split(final_verify_start, 1)
            _, after = rest.split(final_verify_end, 1)
            text = before + (
                "   In Codex foreground-runner mode, do not schedule verify or re-entry\n"
                "   one-shots with Claude CronCreate. Keep this phase in the visible\n"
                "   runner flow: dispatch `/verify-changes branch tracking-id=$TRACKING_ID`,\n"
                "   wait for its result, write the final verification marker, and let the\n"
                "   parent runner validate before launching any next child chunk.\n"
            ) + after
        start = "## Phase 5c \\u2014 Chunked finish auto transition (CRITICAL for finish auto mode)".encode().decode("unicode_escape")
        end = "\n## Phase 6 \\u2014 Land".encode().decode("unicode_escape")
        if start in text and end in text:
            before, rest = text.split(start, 1)
            _, after = rest.split(end, 1)
            replacement = """## Phase 5c - Codex foreground finish-auto transition

**This section applies when running `/run-plan <plan> finish auto` in Codex.**

Codex does not use the Claude CronCreate flow for `finish auto`. The
foreground parent `zskills-runner.sh` owns chunking, starts a fresh
`codex exec` child for each phase, streams child output back to the initiating
REPL, and validates durable plan/report/tracking evidence between chunks.

When a prompt contains `RUNNER-MANAGED CHUNK`, execute exactly one incomplete
phase and stop. Do not invoke `zskills-runner.sh`, do not create one-shot cron
jobs, and do not loop into the next phase. If another phase remains, write the
handoff marker required by the runner. If the plan is complete, write the final
land and fulfillment markers required by the runner.

If the foreground runner helper is unavailable, run at most one phase and
report the exact next `run-plan <plan> finish auto` command. Do not claim
autonomous completion.
"""
            text = before + replacement + end + after
        invariant_start = "### Post-run invariants check (mandatory"
        invariant_end = "\n## Failure Protocol"
        if invariant_start in text and invariant_end in text:
            before, rest = text.split(invariant_start, 1)
            _, after = rest.split(invariant_end, 1)
            replacement = """### Post-run invariants check (mandatory - mechanical gate)

For Codex `finish auto`, the foreground parent runner invokes
`scripts/zskills-post-run-invariants.sh` after final plan completion. Child
chunks do not call this helper directly; they write durable plan/report/tracking
evidence and then stop so the parent can validate the final state.

The helper name and argument contract are:

```bash
bash scripts/zskills-post-run-invariants.sh \\
  --repo "$ACTIVE_ARTIFACT_ROOT" \\
  --plan-file "$PLAN_FILE" \\
  --report "$REPORT_PATH" \\
  --final
```

Non-zero exit from the script means one or more invariants failed. When that
happens: STOP. Do not advance to another phase. Report the specific failures to
the user; they need to investigate and fix before another run.
"""
            text = before + replacement + invariant_end + after
        path.write_text(text)
    elif name == "research-and-go":
        path = skill_dir / "SKILL.md"
        text = path.read_text()
        text = text.replace(
            "This executes all implementation phases sequentially -- each delegating\n"
            "to `/run-plan` on the corresponding sub-plan via chunked cron-fired turns.\n"
            "Full verification, testing, and landing at each phase.",
            "This executes all implementation phases sequentially through Codex's\n"
            "foreground `/run-plan finish auto` runner. Each phase still runs in a\n"
            "fresh child Codex context, with full verification, testing, and landing.",
        )
        text = text.replace(
            "The pipeline will end with a top-level `/verify-changes branch` invocation\n"
            "that runs as a cron-fired turn after the meta-plan execution completes.",
            "The pipeline will end with a top-level `/verify-changes branch` invocation\n"
            "coordinated by the foreground `/run-plan finish auto` runner after the\n"
            "meta-plan execution completes.",
        )
        start = "## Step 3 \\u2014 Final cross-branch verification (scheduled by /run-plan, not here)".encode().decode("unicode_escape")
        end = "\n## Key Rules"
        if start in text and end in text:
            before, rest = text.split(start, 1)
            _, after = rest.split(end, 1)
            replacement = """## Step 3 - Final cross-branch verification

The Codex foreground `/run-plan finish auto` runner is responsible for final
cross-branch verification as part of its visible orchestration. Do not schedule
background cron jobs from `/research-and-go`.

### Pipeline Cleanup

Under foreground finish-auto, `/research-and-go` hands execution to
`/run-plan` and remains visible through that runner's output. Tracking cleanup
is still explicit: run `bash scripts/clear-tracking.sh` only after the user has
confirmed the pipeline finished. Do NOT auto-wipe tracking records.

**Codex preflight:** before running `bash scripts/clear-tracking.sh`, run the
shared procedural preflight helper and treat failure as a blocker:

```bash
ZSKILLS_PREFLIGHT_HELPER="$PROJECT_ROOT/scripts/zskills-preflight.sh"
[ -x "$ZSKILLS_PREFLIGHT_HELPER" ] || ZSKILLS_PREFLIGHT_HELPER="$HOME/.codex/skills/scripts/zskills-preflight.sh"
[ -x "$ZSKILLS_PREFLIGHT_HELPER" ] && "$ZSKILLS_PREFLIGHT_HELPER" --operation clear-tracking --client codex
```

If the pipeline failed at any point, tracking is preserved for inspection and
re-run. See Step 0 Re-run Handling for the resume protocol.
"""
            text = before + replacement + end + after
        path.write_text(text)


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
            postprocess_codex_skill(dst, name)
            insert_adapter(dst / "SKILL.md", adapter)
        installed.append({"name": name, "sha256": sha256_file(dst / "SKILL.md")})

    support_scripts: list[dict] = []
    scripts_output = output / "scripts"
    support_script_paths = list(COMMON_SUPPORT_SCRIPTS)
    if args.client == "codex":
        support_script_paths.extend(CODEX_SUPPORT_SCRIPTS)
    for rel in support_script_paths:
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
        for rel in CODEX_ROOT_FILES:
            src = Path.cwd() / rel
            if src.exists():
                dst = output / src.name
                shutil.copyfile(src, dst)
                dst.chmod(0o755)

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
