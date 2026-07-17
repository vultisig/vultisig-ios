#!/usr/bin/env python3
"""Lint asset-catalog icon usage.

WHAT THIS CAN AND CANNOT CATCH
------------------------------
`Icon` takes an `ImageResource`, so a misspelled or missing icon passed to `Icon(...)`
is a **compile error** — the compiler covers that case completely and this script does
not duplicate it. What the compiler cannot see is the remaining `Image("literal")`
call sites: `Image` accepts an arbitrary String and renders nothing when it misses.
Those are chain logos, banners and a few one-off assets that are legitimately
string-keyed (`Coin.logo` / `Chain.logo` are decoded from remote JSON and cannot be
compile-time symbols).

So this linter has exactly three jobs:

  (a) unknown-asset literals — `Image("foo")` where no `foo` asset exists.
      This is the class of bug that made `Icon(named: "info")` render nothing for
      months, and the reason `Image("send")` broke when the icon set was renamed.
  (b) dead art — imagesets nothing references. Icons V3 shrank the set; art that
      lost its last call site should not linger in the catalog.
  (c) duplicate imageset names — the catalog namespace is FLAT. Two imagesets with
      the same name silently shadow each other. `Icons/link` vs `Crypto/link`
      (the Chainlink token logo) is exactly this trap.

Exit code is non-zero only for (a) and (c); (b) is advisory (art can legitimately
be staged ahead of use).

usage: python3 scripts/lint-icons.py [--strict]
"""
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(REPO, "VultisigApp", "VultisigApp", "Assets.xcassets")
SRC = os.path.join(REPO, "VultisigApp")

# Assets referenced only via remote/runtime data (Coin.logo, Chain.logo) or built
# dynamically; their names never appear as literals, so (b) cannot see their use.
DYNAMIC_PREFIXES = ("vult-",)

# `terra-defi-banner` intentionally exists in two groups; the generator emits one
# symbol and both copies are the same art.
KNOWN_DUPLICATES = {"terra-defi-banner"}


def asset_names():
    """All imagesets in the catalog -> list of paths (a name with >1 path shadows)."""
    names = {}
    for dirpath, dirnames, _ in os.walk(ASSETS):
        for d in dirnames:
            if d.endswith(".imageset"):
                nm = d[: -len(".imageset")]
                names.setdefault(nm, []).append(
                    os.path.join(dirpath, d).replace(REPO + "/", "")
                )
    return names


def icon_set_names():
    """Only Assets.xcassets/Icons — the compile-time icon set.

    Dead-art detection is scoped here on purpose. Everything under Crypto/ is a chain
    or token logo resolved at runtime from `Coin.logo` / `Chain.logo` (remote JSON), so
    its name never appears in the source and static analysis would call every one of
    them dead.
    """
    icons_root = os.path.join(ASSETS, "Icons")
    out = set()
    for dirpath, dirnames, _ in os.walk(icons_root):
        for d in dirnames:
            if d.endswith(".imageset"):
                out.add(d[: -len(".imageset")])
    return out


def swift_files():
    for dirpath, _, filenames in os.walk(SRC):
        for f in filenames:
            if f.endswith(".swift"):
                yield os.path.join(dirpath, f)


# Image("literal") — deliberately NOT Image(systemName:) and NOT Icon(...)
IMAGE_LITERAL = re.compile(r'\bImage\(\s*"([^"]+)"\s*\)')


def main():
    strict = "--strict" in sys.argv
    names = asset_names()
    known = set(names)

    unknown, referenced = [], set()
    for p in swift_files():
        try:
            text = open(p, errors="ignore").read()
        except OSError:
            continue
        for i, line in enumerate(text.split("\n"), 1):
            for m in IMAGE_LITERAL.finditer(line):
                nm = m.group(1)
                referenced.add(nm)
                if nm not in known:
                    unknown.append((p.replace(REPO + "/", ""), i, nm))

    # symbols referenced as .someSymbol also count as "used" for (b)
    symbol_like = set()
    for p in swift_files():
        text = open(p, errors="ignore").read()
        for m in re.finditer(r'\.([a-z][A-Za-z0-9_]*)\b', text):
            symbol_like.add(m.group(1))

    def to_symbol(nm):
        parts = re.split(r'[-_. ]+', nm)
        out = parts[0][:1].lower() + parts[0][1:]
        for p in parts[1:]:
            out += p[:1].upper() + p[1:]
        return out

    dead = []
    for nm in sorted(icon_set_names()):
        if nm.startswith(DYNAMIC_PREFIXES):
            continue
        if nm in referenced or to_symbol(nm) in symbol_like:
            continue
        dead.append(nm)

    dupes = {n: p for n, p in names.items() if len(p) > 1 and n not in KNOWN_DUPLICATES}

    print(f"assets: {len(known)}   Image(\"…\") literals: {len(referenced)}")
    print()
    print(f"(a) unknown-asset literals : {len(unknown)}")
    for f, i, nm in unknown:
        print(f"      {f}:{i}  Image(\"{nm}\") — no such asset")
    print(f"(b) dead art (advisory)    : {len(dead)}")
    for nm in dead:
        print(f"      {nm}")
    print(f"(c) duplicate names        : {len(dupes)}")
    for nm, paths in dupes.items():
        print(f"      {nm}")
        for p in paths:
            print(f"         {p}")

    fail = bool(unknown) or bool(dupes)
    if fail:
        print("\nFAIL")
        return 1
    if strict and dead:
        print("\nFAIL (--strict: dead art)")
        return 1
    print("\nOK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
