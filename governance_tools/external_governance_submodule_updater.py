from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Sequence


DEFAULT_SUBMODULE_PATH = "ai-governance-framework"


@dataclass
class CommandResult:
    command: list[str]
    returncode: int
    stdout: str
    stderr: str


@dataclass
class UpdateResult:
    ok: bool
    mode: str
    update_mode: str
    fast_forward: bool | None
    repo: str
    submodule_path: str
    before_head: str
    target_head: str
    after_head: str
    staged_files: list[str]
    committed: bool
    commit_hash: str | None
    message: str
    errors: list[str]
    full_update_stage_report: dict[str, Any]


class SubmoduleUpdateError(RuntimeError):
    pass


def _run_git(
    repo: Path,
    args: Sequence[str],
    *,
    check: bool = True,
) -> CommandResult:
    command = ["git", "-C", str(repo), *args]
    env = _git_env()
    completed = subprocess.run(
        command,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    result = CommandResult(
        command=command,
        returncode=completed.returncode,
        stdout=(completed.stdout or "").strip(),
        stderr=(completed.stderr or "").strip(),
    )
    if check and result.returncode != 0:
        detail = result.stderr or result.stdout or f"exit {result.returncode}"
        raise SubmoduleUpdateError(f"{' '.join(command)} failed: {detail}")
    return result


def _git_env() -> dict[str, str]:
    env = os.environ.copy()
    git_path = shutil.which("git")
    if not git_path:
        return env

    git_exe = Path(git_path)
    candidates = [
        git_exe.parent.parent / "usr" / "bin",
        git_exe.parent.parent / "mingw64" / "bin",
    ]
    existing = [str(path) for path in candidates if path.exists()]
    if existing:
        env["PATH"] = os.pathsep.join([*existing, env.get("PATH", "")])
    return env


def _require_clean_nested(submodule_repo: Path) -> None:
    # Only block on tracked-file changes; untracked files in the submodule
    # checkout (e.g. runtime artifacts, DB files) should not prevent a pointer
    # update since they won't be staged or committed by the updater.
    status = _run_git(submodule_repo, ["status", "--short", "--untracked-files=no"]).stdout
    if status:
        raise SubmoduleUpdateError(
            f"nested submodule checkout has tracked-file changes: {submodule_repo}"
        )


def _require_no_initial_staged_files(repo: Path) -> None:
    staged = _run_git(repo, ["diff", "--cached", "--name-only"]).stdout
    if staged:
        raise SubmoduleUpdateError(
            "consuming repo has pre-existing staged files; refusing to mix scopes"
        )


def _require_registered_submodule(repo: Path, submodule_path: str) -> None:
    result = _run_git(
        repo,
        ["submodule", "status", "--", submodule_path],
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        raise SubmoduleUpdateError(
            f"submodule not registered or not initialized: {submodule_path}"
        )


def _is_initialized_git_checkout(repo: Path) -> bool:
    result = _run_git(repo, ["rev-parse", "--show-toplevel"], check=False)
    if result.returncode != 0 or not result.stdout:
        return False
    try:
        return Path(result.stdout).resolve() == repo.resolve()
    except OSError:
        return False


def _require_initialized_git_checkout(submodule_repo: Path) -> None:
    if not _is_initialized_git_checkout(submodule_repo):
        raise SubmoduleUpdateError(
            f"submodule path is not an initialized git checkout: {submodule_repo}"
        )


def _resolve_head(repo: Path, ref: str) -> str:
    return _run_git(repo, ["rev-parse", ref]).stdout


def _staged_files(repo: Path) -> list[str]:
    output = _run_git(repo, ["diff", "--cached", "--name-only"]).stdout
    return [line.strip() for line in output.splitlines() if line.strip()]


def _read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _write_text_if_changed(path: Path, text: str) -> bool:
    if path.exists() and _read_text(path) == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return True


def _write_bytes_if_changed(path: Path, payload: bytes) -> bool:
    if path.exists() and path.read_bytes() == payload:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    return True


def _extract_agents_update_section(source_agents: Path) -> str | None:
    text = _read_text(source_agents)
    start_marker = "## AI Governance Update Intent Rule"
    end_marker = "## Repo-Specific Risk Levels"
    start = text.find(start_marker)
    end = text.find(end_marker)
    if start == -1 or end == -1 or end <= start:
        return None
    return text[start:end].strip() + "\n"


def _memory_workflow_router_section() -> str:
    return (
        "## AI Governance Memory Workflow Router\n\n"
        "<!-- governance:key=memory_workflow -->\n"
        "- Before claiming completion for any change touching `memory/**`, run "
        "`python -m governance_tools.memory_workflow --check --repo .`.\n"
        "- For memory completion claims, run "
        "`python -m governance_tools.memory_workflow --check --repo . --run-guard` "
        "and report blockers before claiming DONE.\n"
        "- Use the canonical memory writer for session-derived memory; do not edit "
        "memory records as ordinary markdown.\n"
        "- Canonical writer signal: `governance_tools.memory_record` / "
        "`memory_record.py`.\n"
    )


def _ensure_memory_workflow_router(repo: Path) -> dict[str, Any]:
    agents = repo / "AGENTS.md"
    if not agents.exists():
        return {
            "status": "missing",
            "changed_files": [],
            "errors": [f"missing AGENTS.md: {agents}"],
        }
    current = _read_text(agents)
    if "governance:key=memory_workflow" in current and "memory_workflow" in current:
        return {"status": "verified", "changed_files": [], "errors": []}
    updated = current.rstrip() + "\n\n" + _memory_workflow_router_section()
    changed = _write_text_if_changed(agents, updated)
    return {
        "status": "updated" if changed else "verified",
        "changed_files": ["AGENTS.md"] if changed else [],
        "errors": [],
    }


def _refresh_repo_local_instructions(repo: Path, submodule_repo: Path) -> dict[str, Any]:
    source_base = submodule_repo / "baselines" / "repo-min" / "AGENTS.base.md"
    source_agents = submodule_repo / "baselines" / "repo-min" / "AGENTS.md"
    target_base = repo / "AGENTS.base.md"
    target_agents = repo / "AGENTS.md"
    changed: list[str] = []
    errors: list[str] = []

    if not source_base.exists():
        errors.append("missing source baselines/repo-min/AGENTS.base.md")
    else:
        if _write_text_if_changed(target_base, _read_text(source_base)):
            changed.append("AGENTS.base.md")

    if not source_agents.exists():
        errors.append("missing source baselines/repo-min/AGENTS.md")
    else:
        source_text = _read_text(source_agents)
        section = _extract_agents_update_section(source_agents)
        if not target_agents.exists():
            if _write_text_if_changed(target_agents, source_text):
                changed.append("AGENTS.md")
        elif section is None:
            errors.append("missing AI Governance update section in source AGENTS.md")
        else:
            current = _read_text(target_agents)
            start_marker = "## AI Governance Update Intent Rule"
            end_marker = "## Repo-Specific Risk Levels"
            start = current.find(start_marker)
            end = current.find(end_marker)
            if start != -1 and end != -1 and end > start:
                updated = current[:start] + section + "\n" + current[end:]
            elif section.strip() in current:
                updated = current
            else:
                suffix = "" if current.endswith("\n") else "\n"
                updated = current + suffix + "\n" + section
            if _write_text_if_changed(target_agents, updated):
                changed.append("AGENTS.md")

    router_report = _ensure_memory_workflow_router(repo)
    for changed_file in router_report["changed_files"]:
        if changed_file not in changed:
            changed.append(changed_file)
    errors.extend(router_report["errors"])

    if errors:
        status = "blocked"
    elif changed:
        status = "updated"
    else:
        status = "already_current"
    return {
        "status": status,
        "changed_files": changed,
        "errors": errors,
        "memory_workflow_router": router_report,
    }


def _check_memory_writer_coverage(repo: Path) -> str:
    agents = repo / "AGENTS.md"
    if not agents.exists():
        return "missing"
    text = _read_text(agents)
    if (
        "governance:key=memory_workflow" in text
        and "memory_workflow" in text
        and ("governance_tools.memory_record" in text or "memory_record.py" in text)
    ):
        return "verified"
    return "missing"


def _ensure_hook_advisory(repo: Path, submodule_repo: Path) -> dict[str, Any]:
    source_hook_dir = submodule_repo / "scripts" / "hooks"
    hook_dir = repo / ".git" / "hooks"
    changed: list[str] = []
    errors: list[str] = []

    if not hook_dir.is_dir():
        return {
            "status": "missing",
            "changed_files": [],
            "errors": [f"missing git hooks directory: {hook_dir}"],
        }
    if not source_hook_dir.is_dir():
        return {
            "status": "missing",
            "changed_files": [],
            "errors": [f"missing framework hooks source: {source_hook_dir}"],
        }

    for hook_name in ("pre-commit", "pre-push"):
        source = source_hook_dir / hook_name
        target = hook_dir / hook_name
        if not source.is_file():
            errors.append(f"missing source hook: {source}")
            continue
        if _write_bytes_if_changed(target, source.read_bytes()):
            changed.append(str(target))

    config = hook_dir / "ai-governance-framework-root"
    if _write_text_if_changed(config, f"{submodule_repo}\n"):
        changed.append(str(config))

    if errors:
        status = "missing"
    elif _check_hook_validator_enforcement(repo) == "verified":
        status = "updated" if changed else "verified"
    else:
        status = "missing"
    return {"status": status, "changed_files": changed, "errors": errors}


def _check_hook_validator_enforcement(repo: Path) -> str:
    hook_candidates = [repo / ".git" / "hooks" / "pre-commit", repo / ".githooks" / "pre-commit"]
    for candidate in hook_candidates:
        if not candidate.exists() or candidate.stat().st_size == 0:
            continue
        text = candidate.read_text(encoding="utf-8", errors="replace")
        if "MEMORY_WORKFLOW_TOOL" in text and "memory_workflow" in text:
            return "verified"
    return "missing"


def _check_existing_memory_normalization(repo: Path) -> str:
    memory_dir = repo / "memory"
    if not memory_dir.exists():
        return "not_applicable"
    if any(memory_dir.glob("*.md")):
        return "not_verified"
    return "not_applicable"


def _final_full_update_status(report: dict[str, Any]) -> str:
    framework = report["framework_pointer"]
    repo_local = report["repo_local_instruction"]
    memory = report["memory_writer_coverage"]
    hook = report["hook_validator_enforcement"]
    normalization = report["existing_memory_normalization"]
    if "blocked" in {framework, repo_local, memory, hook, normalization}:
        return "blocked"
    if framework == "not_present":
        return "not_submodule_consumer"
    if "not_verified" in {framework, repo_local, memory, hook, normalization}:
        return "not_verified"
    if "missing" in {repo_local, memory, hook} or normalization == "needed":
        return "partially_updated"
    completed_values = {"updated", "already_current", "verified", "completed", "not_applicable"}
    if {framework, repo_local, memory, hook, normalization} <= completed_values:
        if framework == "already_current" and repo_local == "already_current":
            return "already_current"
        return "full_update_completed"
    return "partially_updated"


def _build_full_update_stage_report(
    *,
    framework_pointer: str,
    repo_local_instruction: str = "not_verified",
    memory_writer_coverage: str = "not_verified",
    hook_validator_enforcement: str = "not_verified",
    existing_memory_normalization: str = "not_verified",
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    report: dict[str, Any] = {
        "framework_pointer": framework_pointer,
        "repo_local_instruction": repo_local_instruction,
        "memory_writer_coverage": memory_writer_coverage,
        "hook_validator_enforcement": hook_validator_enforcement,
        "existing_memory_normalization": existing_memory_normalization,
        "details": details or {},
    }
    report["final_status"] = _final_full_update_status(report)
    return report


def update_governance_submodule(
    *,
    repo: Path,
    submodule_path: str = DEFAULT_SUBMODULE_PATH,
    target_ref: str = "origin/main",
    fetch_remote: str = "origin",
    fetch_ref: str = "main",
    dry_run: bool = True,
    stage: bool = False,
    commit: bool = False,
    allow_detached_target_checkout: bool = False,
    commit_message: str = "chore(governance): update ai governance submodule",
) -> UpdateResult:
    repo = repo.resolve()
    submodule_repo = (repo / submodule_path).resolve()
    errors: list[str] = []

    try:
        _run_git(repo, ["rev-parse", "--is-inside-work-tree"])
        _require_registered_submodule(repo, submodule_path)
        _require_initialized_git_checkout(submodule_repo)
        _require_no_initial_staged_files(repo)
        _require_clean_nested(submodule_repo)

        before_head = _resolve_head(submodule_repo, "HEAD")

        if fetch_ref:
            if dry_run:
                fetch_result = _run_git(
                    submodule_repo,
                    ["ls-remote", fetch_remote, fetch_ref],
                )
                if not fetch_result.stdout:
                    raise SubmoduleUpdateError(
                        f"target ref not found: {fetch_remote}/{fetch_ref}"
                    )
                target_head = fetch_result.stdout.split()[0]
            else:
                _run_git(submodule_repo, ["fetch", fetch_remote, fetch_ref])
                target_head = _resolve_head(submodule_repo, "FETCH_HEAD")
        else:
            target_head = _resolve_head(submodule_repo, target_ref)

        if not dry_run and before_head == target_head:
            instruction_report = _refresh_repo_local_instructions(repo, submodule_repo)
            hook_report = _ensure_hook_advisory(repo, submodule_repo)
            full_update_stage_report = _build_full_update_stage_report(
                framework_pointer="already_current",
                repo_local_instruction=instruction_report["status"],
                memory_writer_coverage=_check_memory_writer_coverage(repo),
                hook_validator_enforcement=hook_report["status"],
                existing_memory_normalization=_check_existing_memory_normalization(repo),
                details={
                    "repo_local_instruction": instruction_report,
                    "hook_validator_enforcement": hook_report,
                },
            )
            if stage or commit:
                allowed = {submodule_path, "AGENTS.base.md", "AGENTS.md"}
                _run_git(repo, ["add", "--", "AGENTS.base.md", "AGENTS.md"])
                staged = _staged_files(repo)
                if not set(staged) <= allowed:
                    raise SubmoduleUpdateError(
                        f"staged files are outside F-7 full update scope: {staged}"
                    )
            else:
                staged = []
            committed = False
            commit_hash: str | None = None
            if commit and staged:
                _run_git(repo, ["commit", "-m", commit_message])
                committed = True
                commit_hash = _resolve_head(repo, "HEAD")
            return UpdateResult(
                ok=True,
                mode="apply",
                update_mode="already_current",
                fast_forward=True,
                repo=str(repo),
                submodule_path=submodule_path,
                before_head=before_head,
                target_head=target_head,
                after_head=before_head,
                staged_files=staged,
                committed=committed,
                commit_hash=commit_hash,
                message="submodule already at target; no files modified",
                errors=[],
                full_update_stage_report=full_update_stage_report,
            )

        if dry_run:
            fast_forward = (
                _run_git(
                    submodule_repo,
                    ["merge-base", "--is-ancestor", before_head, target_head],
                    check=False,
                ).returncode
                == 0
            )
            return UpdateResult(
                ok=True,
                mode="dry_run",
                update_mode="dry_run",
                fast_forward=fast_forward,
                repo=str(repo),
                submodule_path=submodule_path,
                before_head=before_head,
                target_head=target_head,
                after_head=before_head,
                staged_files=[],
                committed=False,
                commit_hash=None,
                message="dry run complete; no files modified",
                errors=[],
                full_update_stage_report=_build_full_update_stage_report(
                    framework_pointer=(
                        "already_current" if before_head == target_head else "not_verified"
                    ),
                    details={"dry_run": True},
                ),
            )

        merge_result = _run_git(
            submodule_repo,
            ["merge", "--ff-only", target_ref],
            check=False,
        )
        if merge_result.returncode == 0:
            update_mode = "fast_forward"
            fast_forward = True
        elif allow_detached_target_checkout:
            _run_git(submodule_repo, ["checkout", target_head])
            update_mode = "detached_target_checkout"
            fast_forward = False
        else:
            detail = (
                merge_result.stderr
                or merge_result.stdout
                or f"exit {merge_result.returncode}"
            )
            raise SubmoduleUpdateError(
                f"{' '.join(merge_result.command)} failed: {detail}"
            )
        after_head = _resolve_head(submodule_repo, "HEAD")

        if after_head != target_head:
            raise SubmoduleUpdateError(
                f"after_head {after_head} does not match target_head {target_head}"
            )

        instruction_report = _refresh_repo_local_instructions(repo, submodule_repo)
        hook_report = _ensure_hook_advisory(repo, submodule_repo)
        full_update_stage_report = _build_full_update_stage_report(
            framework_pointer="updated",
            repo_local_instruction=instruction_report["status"],
            memory_writer_coverage=_check_memory_writer_coverage(repo),
            hook_validator_enforcement=hook_report["status"],
            existing_memory_normalization=_check_existing_memory_normalization(repo),
            details={
                "repo_local_instruction": instruction_report,
                "hook_validator_enforcement": hook_report,
            },
        )

        if stage or commit:
            allowed = {submodule_path, "AGENTS.base.md", "AGENTS.md"}
            _run_git(repo, ["add", "--", submodule_path, "AGENTS.base.md", "AGENTS.md"])
            staged = _staged_files(repo)
            if not set(staged) <= allowed:
                raise SubmoduleUpdateError(
                    f"staged files are outside F-7 full update scope: {staged}"
                )
        else:
            staged = []

        committed = False
        commit_hash: str | None = None
        if commit:
            _run_git(repo, ["commit", "-m", commit_message])
            committed = True
            commit_hash = _resolve_head(repo, "HEAD")

        return UpdateResult(
            ok=True,
            mode="apply",
            update_mode=update_mode,
            fast_forward=fast_forward,
            repo=str(repo),
            submodule_path=submodule_path,
            before_head=before_head,
            target_head=target_head,
            after_head=after_head,
            staged_files=staged,
            committed=committed,
            commit_hash=commit_hash,
            message="submodule pointer update complete",
            errors=[],
            full_update_stage_report=full_update_stage_report,
        )
    except SubmoduleUpdateError as exc:
        errors.append(str(exc))
        before = ""
        after = ""
        try:
            if _is_initialized_git_checkout(submodule_repo):
                before = _resolve_head(submodule_repo, "HEAD")
                after = before
        except Exception:
            pass
        return UpdateResult(
            ok=False,
            mode="dry_run" if dry_run else "apply",
            update_mode="failed",
            fast_forward=None,
            repo=str(repo),
            submodule_path=submodule_path,
            before_head=before,
            target_head="",
            after_head=after,
            staged_files=[],
            committed=False,
            commit_hash=None,
            message="submodule pointer update failed",
            errors=errors,
            full_update_stage_report=_build_full_update_stage_report(
                framework_pointer=(
                    "not_present"
                    if errors and "submodule not registered" in errors[0]
                    else "blocked"
                ),
                details={"errors": errors},
            ),
        )


def format_human(result: UpdateResult) -> str:
    lines = [
        f"ok={result.ok}",
        f"mode={result.mode}",
        f"update_mode={result.update_mode}",
        f"fast_forward={result.fast_forward if result.fast_forward is not None else '-'}",
        f"repo={result.repo}",
        f"submodule_path={result.submodule_path}",
        f"before_head={result.before_head}",
        f"target_head={result.target_head}",
        f"after_head={result.after_head}",
        f"staged_files={','.join(result.staged_files) if result.staged_files else '-'}",
        f"committed={result.committed}",
        f"commit_hash={result.commit_hash or '-'}",
        f"message={result.message}",
        "full_update_stage_report:",
        f"- framework_pointer={result.full_update_stage_report.get('framework_pointer')}",
        f"- repo_local_instruction={result.full_update_stage_report.get('repo_local_instruction')}",
        f"- memory_writer_coverage={result.full_update_stage_report.get('memory_writer_coverage')}",
        f"- hook_validator_enforcement={result.full_update_stage_report.get('hook_validator_enforcement')}",
        f"- existing_memory_normalization={result.full_update_stage_report.get('existing_memory_normalization')}",
        f"- final_status={result.full_update_stage_report.get('final_status')}",
    ]
    if result.errors:
        lines.append("errors:")
        lines.extend(f"- {error}" for error in result.errors)
    return "\n".join(lines)


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Update an external repo ai-governance-framework submodule with path-limited staging."
    )
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--submodule-path", default=DEFAULT_SUBMODULE_PATH)
    parser.add_argument("--target-ref", default="origin/main")
    parser.add_argument("--fetch-remote", default="origin")
    parser.add_argument("--fetch-ref", default="main")
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--stage", action="store_true")
    parser.add_argument("--commit", action="store_true")
    parser.add_argument(
        "--allow-detached-target-checkout",
        action="store_true",
        help=(
            "Allow non-fast-forward updates by checking out the fetched target "
            "commit in the nested submodule. Default is ff-only refusal."
        ),
    )
    parser.add_argument(
        "--commit-message",
        default="chore(governance): update ai governance submodule",
    )
    parser.add_argument("--format", choices=["human", "json"], default="human")
    args = parser.parse_args(argv)

    result = update_governance_submodule(
        repo=args.repo,
        submodule_path=args.submodule_path,
        target_ref=args.target_ref,
        fetch_remote=args.fetch_remote,
        fetch_ref=args.fetch_ref,
        dry_run=not args.apply,
        stage=args.stage,
        commit=args.commit,
        allow_detached_target_checkout=args.allow_detached_target_checkout,
        commit_message=args.commit_message,
    )

    if args.format == "json":
        print(json.dumps(asdict(result), indent=2))
    else:
        print(format_human(result))

    return 0 if result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
