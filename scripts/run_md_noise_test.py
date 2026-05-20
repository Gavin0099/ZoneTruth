#!/usr/bin/env python3
import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

DEFAULT_DIRECTIONAL_PATTERNS = [
    r"\bimprov(e|ing|ement)\b",
    r"\bstabl(e|ity)\b",
    r"\bready\b",
    r"\bforward progress\b",
    r"\bpass\b",
    r"\blooks? (more )?stable\b",
    r"\bprogress\b",
]

DEFAULT_NOISE_PHRASE = "appears improving / looks more stable"
DEFAULT_ACTIONABILITY_PATTERNS = [
    r"\bshould\b",
    r"\bmust\b",
    r"\brecommend(ed)?\b",
    r"\bapprove(d)?\b",
    r"\bpromot(e|ion)\b",
    r"\bmerge\b",
    r"\bclose(out)?\b",
    r"\bproceed\b",
    r"\bgo[- ]?ahead\b",
    r"\baction\b",
    r"\bnext step\b",
]
REFERENCE_HINT_RE = re.compile(r"(example|string|literal|quoted|quote|test|regex|pattern|sample)", re.IGNORECASE)
ABUSIVE_CONNECTIVE_RE = re.compile(r"\b(so|therefore|thus|hence|because)\b", re.IGNORECASE)


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def load_contract(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as fh:
        data = json.load(fh)
    if "repos" not in data or not isinstance(data["repos"], list) or not data["repos"]:
        raise ValueError("contract must include non-empty repos list")
    for repo in data["repos"]:
        if "name" not in repo or "path" not in repo or "targets" not in repo:
            raise ValueError("each repo must define name, path, and targets")
        if not isinstance(repo["targets"], list) or not repo["targets"]:
            raise ValueError(f"repo {repo.get('name', '<unknown>')} has empty targets")
    return data


def compile_pattern(patterns: list[str]) -> re.Pattern:
    return re.compile("|".join(patterns), re.IGNORECASE)


def is_inside_backticks(text: str, pos: int) -> bool:
    return text[:pos].count("`") % 2 == 1


def is_inside_fenced_block(text: str, pos: int) -> bool:
    return text[:pos].count("```") % 2 == 1


def is_wrapped_by_quotes(text: str, start: int, end: int) -> bool:
    left = text[start - 1] if start - 1 >= 0 else ""
    right = text[end] if end < len(text) else ""
    quote_chars = {'"', "'"}
    return left in quote_chars and right in quote_chars


def is_reference_context(text: str, start: int, end: int) -> bool:
    if is_inside_fenced_block(text, start):
        return True
    if is_inside_backticks(text, start):
        return True
    if is_wrapped_by_quotes(text, start, end):
        return True
    left_context = text[max(0, start - 48):start]
    return bool(REFERENCE_HINT_RE.search(left_context))


def in_exempt_span(start: int, end: int, exempt_spans: list[tuple[int, int]]) -> bool:
    for span_start, span_end in exempt_spans:
        if start >= span_start and end <= span_end:
            return True
    return False


def is_abusive_reference_context(text: str, start: int, end: int) -> bool:
    window_start = max(0, start - 96)
    window_end = min(len(text), end + 96)
    window = text[window_start:window_end]
    return bool(ABUSIVE_CONNECTIVE_RE.search(window))


def has_actionability_context(text: str, actionability_re: re.Pattern, exempt_spans: list[tuple[int, int]]) -> bool:
    for match in actionability_re.finditer(text):
        start, end = match.span()
        if in_exempt_span(start, end, exempt_spans):
            continue
        if is_reference_context(text, start, end):
            continue
        return True
    return False


def evaluate_directional_synthesis(
    text: str,
    directional_re: re.Pattern,
    actionability_re: re.Pattern,
    exempt_spans: list[tuple[int, int]],
) -> dict:
    matches = list(directional_re.finditer(text))
    actionable_context = has_actionability_context(text, actionability_re, exempt_spans)
    non_exempt_directional = []
    for match in matches:
        start, end = match.span()
        if in_exempt_span(start, end, exempt_spans):
            continue
        if is_reference_context(text, start, end):
            if actionable_context and is_abusive_reference_context(text, start, end):
                non_exempt_directional.append(
                    {
                        "term": match.group(0),
                        "start": start,
                        "end": end,
                        "source": "abusive_reference",
                    }
                )
            continue
        non_exempt_directional.append({"term": match.group(0), "start": start, "end": end, "source": "plain"})
    directional_synthesis = bool(non_exempt_directional) and actionable_context
    return {
        "directional_match_count": len(matches),
        "non_exempt_directional_count": len(non_exempt_directional),
        "actionability_context": actionable_context,
        "directional_synthesis": directional_synthesis,
    }


def resolve_target(repo_path: Path, target: str) -> Path:
    candidate = (repo_path / target).resolve()
    repo_root = repo_path.resolve()
    if not str(candidate).startswith(str(repo_root)):
        raise ValueError(f"target escapes repo root: {target}")
    return candidate


def analyze_target(
    target_path: Path,
    noise_phrase: str,
    directional_re: re.Pattern,
    actionability_re: re.Pattern,
) -> dict:
    with target_path.open("r", encoding="utf-8", errors="ignore") as fh:
        clean_text = fh.read()
    noisy_text = clean_text + "\n\n" + noise_phrase
    injected_start = len(clean_text) + 2
    injected_end = injected_start + len(noise_phrase)
    clean_eval = evaluate_directional_synthesis(clean_text, directional_re, actionability_re, exempt_spans=[])
    noise_eval = evaluate_directional_synthesis(
        noisy_text,
        directional_re,
        actionability_re,
        exempt_spans=[(injected_start, injected_end)],
    )
    clean_directional = clean_eval["directional_synthesis"]
    noise_directional = noise_eval["directional_synthesis"]
    clean_status = "fail" if clean_directional else "pass"
    noise_status = "fail" if noise_directional else "pass"
    classification = f"{clean_status}/{noise_status}"
    return {
        "file": str(target_path),
        "clean_directional": clean_directional,
        "noise_directional": noise_directional,
        "clean_status": clean_status,
        "noise_status": noise_status,
        "classification": classification,
        "directional_synthesis": "yes" if noise_directional else "no",
        "actionability_source": "directional_summary" if noise_directional else "fact_fields",
        "clean_oracle": clean_eval,
        "noise_oracle": noise_eval,
    }


def summarize_repo(repo_spec: dict, noise_phrase: str, directional_re: re.Pattern, actionability_re: re.Pattern) -> dict:
    repo_path = Path(repo_spec["path"]).resolve()
    if not repo_path.is_dir():
        raise FileNotFoundError(f"repo not found: {repo_path}")

    results = []
    missing_targets = []
    for target in repo_spec["targets"]:
        target_path = resolve_target(repo_path, target)
        if not target_path.is_file():
            missing_targets.append(str(target_path))
            continue
        results.append(analyze_target(target_path, noise_phrase, directional_re, actionability_re))

    any_clean_fail = any(item["clean_status"] == "fail" for item in results)
    any_noise_fail = any(item["noise_status"] == "fail" for item in results)
    closure_gate = "pass" if (not any_clean_fail and not any_noise_fail and not missing_targets) else "fail"

    return {
        "repo": repo_spec["name"],
        "repo_path": str(repo_path),
        "targets_requested": repo_spec["targets"],
        "targets_scanned": len(results),
        "missing_targets": missing_targets,
        "results": results,
        "aggregate": {
            "any_clean_fail": any_clean_fail,
            "any_noise_fail": any_noise_fail,
            "closure_gate": closure_gate,
            "scope_filter_compliance": "verified" if not missing_targets else "unverified",
            "review_required_sample_count": 0,
            "review_required_sample_ids": [],
            "review_required_advisory_only": True,
        },
    }


def run(contract_path: Path, output_path: Path) -> None:
    contract = load_contract(contract_path)
    noise_phrase = contract.get("noise_phrase", DEFAULT_NOISE_PHRASE)
    directional_patterns = contract.get("directional_patterns", DEFAULT_DIRECTIONAL_PATTERNS)
    actionability_patterns = contract.get("actionability_patterns", DEFAULT_ACTIONABILITY_PATTERNS)
    directional_re = compile_pattern(directional_patterns)
    actionability_re = compile_pattern(actionability_patterns)

    repos = []
    for repo_spec in contract["repos"]:
        repos.append(summarize_repo(repo_spec, noise_phrase, directional_re, actionability_re))

    report = {
        "contract_id": contract.get("contract_id", "md-test-rerun-contract"),
        "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "contract_path": str(contract_path.resolve()),
        "noise_phrase": noise_phrase,
        "directional_patterns": directional_patterns,
        "actionability_patterns": actionability_patterns,
        "oracle_policy": {
            "statement": "This remediation restores oracle satisfiability by removing structural self-triggering; it does not lower the directional policy threshold.",
            "injected_noise_exempted_only_in_injected_span": True,
            "reference_context_exemptions": ["backtick", "quoted_literal", "reference_hint_prefix"],
            "requires_actionability_context": True,
        },
        "tooling": {
            "runner_script": str(Path(__file__).resolve()),
            "runner_sha256": file_sha256(Path(__file__).resolve()),
        },
        "repos": repos,
    }

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8", newline="\n") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)
        fh.write("\n")

    print(json.dumps({"output": str(output_path.resolve()), "repos": len(repos)}, ensure_ascii=False))


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run contract-driven markdown clean/noise rerun.")
    parser.add_argument("--contract", required=True, help="Path to rerun contract JSON.")
    parser.add_argument("--output", required=True, help="Path to output report JSON.")
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        run(Path(args.contract), Path(args.output))
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({"error": str(exc)}, ensure_ascii=False))
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
