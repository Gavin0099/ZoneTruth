from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence


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
    status = _run_git(submodule_repo, ["status", "--short"]).stdout
    if status:
        raise SubmoduleUpdateError(
            f"nested submodule checkout is dirty: {submodule_repo}"
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


def _resolve_head(repo: Path, ref: str) -> str:
    return _run_git(repo, ["rev-parse", ref]).stdout


def _staged_files(repo: Path) -> list[str]:
    output = _run_git(repo, ["diff", "--cached", "--name-only"]).stdout
    return [line.strip() for line in output.splitlines() if line.strip()]


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
                staged_files=[],
                committed=False,
                commit_hash=None,
                message="submodule already at target; no files modified",
                errors=[],
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

        if stage or commit:
            _run_git(repo, ["add", "--", submodule_path])
            staged = _staged_files(repo)
            if staged != [submodule_path]:
                raise SubmoduleUpdateError(
                    f"staged files are not path-limited to {submodule_path}: {staged}"
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
        )
    except SubmoduleUpdateError as exc:
        errors.append(str(exc))
        before = ""
        after = ""
        try:
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
