#!/usr/bin/env python3
"""Cross-repo golden signing corpus sync check.

The shared signing fixture corpus lives as hand-synced copies in three repos:
  vultisig-android  app/src/androidTest/assets/
  vultisig-ios      VultisigApp/VultisigAppTests/TestData/
  vultisig-sdk      packages/core/mpc/keysign/tests/fixtures/mobile/

Each repo re-derives every pre-image hash from its own payload copy and asserts
against its own pinned expected_image_hash, so cross-repo DISAGREEMENT on a
pinned hash means two platforms would sign different bytes for the same case.

This check fails (exit 1) only on that disagreement. Missing files or cases are
reported as coverage warnings, not failures — corpus rollout is staged and the
gaps are tracked in per-repo issues. Files are compared parsed, never as bytes:
the copies legitimately differ in formatting and field-name spelling.

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

REPOS = ("android", "ios", "sdk")


def load_corpus(corpus_dir: Path) -> dict[str, dict[str, list[str]]]:
    """Map fixture filename -> case name -> pinned expected_image_hash list."""
    corpus: dict[str, dict[str, list[str]]] = {}
    for path in sorted(corpus_dir.glob("*.json")):
        cases = json.loads(path.read_text())
        corpus[path.name] = {
            case["name"]: [h.lower() for h in (case.get("expected_image_hash") or [])]
            for case in cases
        }
    return corpus


def compare_case(hashes_by_repo: dict[str, list[str]]) -> str | None:
    """Return 'drift' | 'order' | 'unpinned' | None for one case across repos."""
    pinned = {repo: h for repo, h in hashes_by_repo.items() if h}
    if len(pinned) < len(hashes_by_repo):
        return "unpinned" if pinned else None
    if len({tuple(h) for h in pinned.values()}) == 1:
        return None
    if len({tuple(sorted(h)) for h in pinned.values()}) == 1:
        return "order"
    return "drift"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    for repo in REPOS:
        parser.add_argument(f"--{repo}", required=True, type=Path)
    args = parser.parse_args()

    corpora = {repo: load_corpus(getattr(args, repo)) for repo in REPOS}
    for repo in REPOS:
        n_cases = sum(len(cases) for cases in corpora[repo].values())
        print(f"{repo}: {len(corpora[repo])} fixture files, {n_cases} cases")

    drift: list[str] = []
    warnings: list[str] = []
    all_files = sorted(set().union(*(c.keys() for c in corpora.values())))
    for filename in all_files:
        present = {repo: c[filename] for repo, c in corpora.items() if filename in c}
        missing_file = [repo for repo in REPOS if repo not in present]
        if missing_file:
            warnings.append(f"{filename}: missing on {', '.join(missing_file)}")
        if len(present) < 2:
            continue
        all_cases = sorted(set().union(*(cases.keys() for cases in present.values())))
        for name in all_cases:
            shared = {repo: cases[name] for repo, cases in present.items() if name in cases}
            missing_case = [repo for repo in present if repo not in shared]
            if missing_case:
                warnings.append(f"{filename} :: {name}: missing on {', '.join(missing_case)}")
            if len(shared) < 2:
                continue
            verdict = compare_case(shared)
            if verdict == "drift":
                detail = "; ".join(f"{repo}={hashes}" for repo, hashes in sorted(shared.items()))
                drift.append(f"{filename} :: {name}\n    {detail}")
            elif verdict == "order":
                warnings.append(f"{filename} :: {name}: same hashes, different order")
            elif verdict == "unpinned":
                unpinned = [repo for repo, h in shared.items() if not h]
                warnings.append(f"{filename} :: {name}: no pinned hash on {', '.join(unpinned)}")

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
