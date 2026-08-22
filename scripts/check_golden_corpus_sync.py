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

Requires Python 3.9+ (builtin generics). Exit codes: 0 in sync, 1 drift,
2 unusable corpus (missing dir, unparseable file, duplicate case names).

Usage:
  check_golden_corpus_sync.py --android DIR --ios DIR --sdk DIR
"""

import argparse
import json
import sys
from pathlib import Path

# fixture filename -> case name -> pinned expected_image_hash list
Corpus = dict[str, dict[str, list[str]]]


def load_corpus(corpus_dir: Path) -> Corpus:
    corpus: Corpus = {}
    for path in sorted(corpus_dir.glob("*.json")):
        try:
            cases = json.loads(path.read_text())
            corpus[path.name] = {
                case["name"]: [h.lower() for h in (case.get("expected_image_hash") or [])]
                for case in cases
            }
        except (json.JSONDecodeError, TypeError, KeyError, AttributeError) as err:
            print(f"{path}: not a list of golden cases — {err!r}", file=sys.stderr)
            raise SystemExit(2) from None
        if len(corpus[path.name]) != len(cases):
            print(f"{path}: duplicate case names — a duplicate would go uncompared", file=sys.stderr)
            raise SystemExit(2)
    return corpus


def diff_case(label: str, hashes_by_repo: dict[str, list[str]]) -> tuple[list[str], list[str]]:
    """Compare one case across the repos that have it; return (drift, gaps)."""
    pinned = {repo: hashes for repo, hashes in hashes_by_repo.items() if hashes}
    unpinned = [repo for repo in hashes_by_repo if repo not in pinned]
    gaps = [f"{label}: no pinned hash on {', '.join(unpinned)}"] if unpinned else []
    if len(pinned) < 2 or len({tuple(h) for h in pinned.values()}) == 1:
        return [], gaps
    detail = "; ".join(f"{repo}={hashes}" for repo, hashes in sorted(pinned.items()))
    if len({tuple(sorted(h)) for h in pinned.values()}) == 1:
        label += " (same hashes, different order — runners assert ordered equality)"
    return [f"{label}\n    {detail}"], gaps


def diff_corpora(corpora: dict[str, Corpus]) -> tuple[list[str], list[str]]:
    """Return (drift, gaps) across all fixture files and cases."""
    drift: list[str] = []
    gaps: list[str] = []
    for filename in sorted({name for corpus in corpora.values() for name in corpus}):
        present = {repo: corpus[filename] for repo, corpus in corpora.items() if filename in corpus}
        absent = [repo for repo in corpora if repo not in present]
        if absent:
            gaps.append(f"{filename}: missing on {', '.join(absent)}")
        if len(present) < 2:
            continue
        for name in sorted({n for cases in present.values() for n in cases}):
            shared = {repo: cases[name] for repo, cases in present.items() if name in cases}
            missing = [repo for repo in present if repo not in shared]
            if missing:
                gaps.append(f"{filename} :: {name}: missing on {', '.join(missing)}")
            case_drift, case_gaps = diff_case(f"{filename} :: {name}", shared)
            drift += case_drift
            gaps += case_gaps
    return drift, gaps


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--android", required=True, type=Path)
    parser.add_argument("--ios", required=True, type=Path)
    parser.add_argument("--sdk", required=True, type=Path)
    args = parser.parse_args()

    corpus_dirs = {"android": args.android, "ios": args.ios, "sdk": args.sdk}
    for repo, corpus_dir in corpus_dirs.items():
        if not corpus_dir.is_dir():
            parser.error(f"--{repo}: corpus dir not found: {corpus_dir}")

    corpora = {repo: load_corpus(corpus_dir) for repo, corpus_dir in corpus_dirs.items()}
    for repo, corpus in corpora.items():
        n_cases = sum(len(cases) for cases in corpus.values())
        print(f"{repo}: {len(corpus)} fixture files, {n_cases} cases")

    drift, gaps = diff_corpora(corpora)

    if gaps:
        print(f"\n{len(gaps)} coverage warning(s) (non-fatal, tracked in issues):")
        for gap in gaps:
            print(f"  WARN  {gap}")

    if drift:
        print(f"\n{len(drift)} CROSS-REPO HASH DISAGREEMENT(S) — two platforms would sign different bytes:")
        for finding in drift:
            print(f"  DRIFT {finding}")
        print("\nAn intentional vector change must land the same hashes in all three repos.")
        return 1

    print("\nOK: every case shared between repos agrees on expected_image_hash.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
