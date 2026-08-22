#!/usr/bin/env python3
"""Cross-repo golden signing corpus sync check.

The shared signing fixture corpus lives as hand-synced copies in three repos:
  vultisig-android  app/src/androidTest/assets/
  vultisig-ios      VultisigApp/VultisigAppTests/TestData/
  vultisig-sdk      packages/core/mpc/keysign/tests/fixtures/mobile/

Each repo asserts only its own pinned expected_image_hash, so cross-repo
disagreement on a shared case means two platforms would sign different bytes —
that fails this check (exit 1). Missing files or cases only warn: corpus
rollout is staged and the gaps are tracked in per-repo issues. Files are
compared parsed, never as bytes — the copies legitimately differ in formatting.

Copies of this script live in vultisig-android, vultisig-ios and vultisig-sdk —
keep them identical.

Usage:
  check_golden_corpus_sync.py --android DIR --ios DIR --sdk DIR
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# fixture filename -> case name -> pinned expected_image_hash list
Corpus = dict[str, dict[str, list[str]]]


def load_corpus(corpus_dir: Path) -> Corpus:
    corpus: Corpus = {}
    for path in sorted(corpus_dir.glob("*.json")):
        cases = json.loads(path.read_text())
        corpus[path.name] = {
            case["name"]: [h.lower() for h in (case.get("expected_image_hash") or [])]
            for case in cases
        }
        if len(corpus[path.name]) != len(cases):
            sys.exit(f"{path}: duplicate case names — a duplicate would go uncompared")
    return corpus


def diff_case(label: str, hashes_by_repo: dict[str, list[str]]) -> tuple[list[str], list[str]]:
    """Compare one case across the repos that have it; return (drift, warnings)."""
    pinned = {repo: hashes for repo, hashes in hashes_by_repo.items() if hashes}
    unpinned = [repo for repo in hashes_by_repo if repo not in pinned]
    warnings = [f"{label}: no pinned hash on {', '.join(unpinned)}"] if unpinned and pinned else []
    if len(pinned) < 2 or len({tuple(h) for h in pinned.values()}) == 1:
        return [], warnings
    if len({tuple(sorted(h)) for h in pinned.values()}) == 1:
        return [], warnings + [f"{label}: same hashes, different order"]
    detail = "; ".join(f"{repo}={hashes}" for repo, hashes in sorted(pinned.items()))
    return [f"{label}\n    {detail}"], warnings


def diff_corpora(corpora: dict[str, Corpus]) -> tuple[list[str], list[str]]:
    """Return (drift, warnings) across all fixture files and cases."""
    drift: list[str] = []
    warnings: list[str] = []
    for filename in sorted(set().union(*(c.keys() for c in corpora.values()))):
        present = {repo: c[filename] for repo, c in corpora.items() if filename in c}
        absent = [repo for repo in corpora if repo not in present]
        if absent:
            warnings.append(f"{filename}: missing on {', '.join(absent)}")
        if len(present) < 2:
            continue
        for name in sorted(set().union(*(cases.keys() for cases in present.values()))):
            shared = {repo: cases[name] for repo, cases in present.items() if name in cases}
            missing = [repo for repo in present if repo not in shared]
            if missing:
                warnings.append(f"{filename} :: {name}: missing on {', '.join(missing)}")
            case_drift, case_warnings = diff_case(f"{filename} :: {name}", shared)
            drift += case_drift
            warnings += case_warnings
    return drift, warnings


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--android", required=True, type=Path)
    parser.add_argument("--ios", required=True, type=Path)
    parser.add_argument("--sdk", required=True, type=Path)
    args = parser.parse_args()

    for repo in ("android", "ios", "sdk"):
        if not getattr(args, repo).is_dir():
            parser.error(f"--{repo}: corpus dir not found: {getattr(args, repo)}")

    corpora = {
        "android": load_corpus(args.android),
        "ios": load_corpus(args.ios),
        "sdk": load_corpus(args.sdk),
    }
    for repo, corpus in corpora.items():
        n_cases = sum(len(cases) for cases in corpus.values())
        print(f"{repo}: {len(corpus)} fixture files, {n_cases} cases")

    drift, warnings = diff_corpora(corpora)

    if warnings:
        print(f"\n{len(warnings)} coverage warning(s) (non-fatal, tracked in issues):")
        for warning in warnings:
            print(f"  WARN  {warning}")

    if drift:
        print(f"\n{len(drift)} CROSS-REPO HASH DISAGREEMENT(S) — two platforms would sign different bytes:")
        for entry in drift:
            print(f"  DRIFT {entry}")
        print("\nAn intentional vector change must land the same hashes in all three repos.")
        return 1

    print("\nOK: every case shared between repos agrees on expected_image_hash.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
