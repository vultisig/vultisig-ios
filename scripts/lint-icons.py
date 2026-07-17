#!/usr/bin/env python3
"""Lint the asset-catalog icon set against the Swift sources.

`Icon` takes an `ImageResource`, not a `String`. Xcode generates one static
member per imageset (`chevron-down` -> `.chevronDown`), so a typo or a missed
rename in an `Icon(...)` call is a COMPILE ERROR and never reaches this script.
That removes the reason this linter originally existed, and with it the
33-wrapper SF-Symbol/asset classifier: the two namespaces are now split by type
(`ImageResource` vs the `String` that `Image(systemName:)` takes), not guessed
by regex.

What is left is the part the type system does NOT cover:

  (a) bare `Image("name")` / `UIImage(named:)` / `NSImage(named:)` string
      literals that resolve to no imageset -- would-be blank rectangles
  (b) imagesets under Icons/ that nothing references -- likely dead art
  (c) imageset names duplicated anywhere in the catalog -- silent shadowing

Run via `make lint-icons`.

-----------------------------------------------------------------------------
(a) -- STILL LIVE, AND NOW SOUND FOR WHAT IT COVERS
-----------------------------------------------------------------------------
`Icon` is type-safe, but SwiftUI's own `Image(_:)` still takes a String, and
~46 such literals remain (chain logos, banners, backgrounds -- art that is not
an `Icon`). Those cannot be made type-safe by us short of migrating each to
`Image(.symbol)`, so they keep a real linter's worth of value.

The check is now SOUND for those call sites rather than heuristic. It matches
only the three unambiguous asset APIs by name; it no longer has to guess
whether an arbitrary `foo(icon:)` label carries an asset name or an SF Symbol,
because an asset-name-carrying parameter is `ImageResource`-typed now and holds
no literal at all. `Image(systemName:)` is excluded by construction: a
different argument label, a different API.

The old standing weakness -- "a new wrapper with a new argument label escapes
silently" -- is gone for icons. A new wrapper takes `ImageResource`, so the
compiler checks it. A new wrapper taking a `String` for a bare `Image(_:)` is
the residual gap, and is why (b) exists as a backstop.

-----------------------------------------------------------------------------
(b) -- DELIBERATELY CONSERVATIVE
-----------------------------------------------------------------------------
Icon names no longer appear as string literals at all -- they appear as
`.chevronDown` symbol references. So (b) matches an imageset if EITHER its
literal name OR its generated symbol name is present in the sources.

Symbols are matched by NORMALISED comparison (lowercase, drop -/_/./space)
rather than by reimplementing Xcode's name->symbol transform. That transform is
gnarlier than it looks -- `BackupNowImage` -> `backupNow` strips a trailing
"Image", `1Inch` -> `_1Inch`, `LI.FI` -> `LI_FI` -- and reimplementing it here
would just reintroduce the unsoundness this migration removed. Normalisation is
verified to agree with the real generated symbol for all 149 Icons/ imagesets.

It stays conservative in the same direction as before: it asks whether the name
appears ANYWHERE, not whether it appears in an icon position, so it will never
call live art dead. It still has false negatives (dead art whose normalised name
collides with an unrelated identifier survives); `function.imageset` sat dead
behind `"function".localized` until a hand audit found it. Verify a (b) hit by
hand before deleting anything.

Note (b) no longer needs the INTERPOLATION-REACHED escape hatch. Its only user
was `VultDiscountTier.icon`, which built `"vult-\\(rawValue)"` at runtime and was
invisible to any static scan; it is now an explicit `switch` returning
`ImageResource`, so the vult-* tier icons are ordinary symbol references that
(b) sees directly and the compiler checks.

-----------------------------------------------------------------------------
(c) -- UNCHANGED
-----------------------------------------------------------------------------
NO Contents.json in this catalog sets `provides-namespace`, so folder groups are
purely organisational and asset names are flat and global. Two imagesets sharing
a name make the reference ambiguous, and the generator emits ONE symbol for the
pair -- so the type system cannot see this either. (c) is the only check here
that the compiler does not subsume.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_ROOT = REPO_ROOT / "VultisigApp" / "VultisigApp" / "Assets.xcassets"
ICONS_ROOT = ASSETS_ROOT / "Icons"
SWIFT_ROOT = REPO_ROOT / "VultisigApp"

STRING_LIT = re.compile(r'"([^"\\\n]*)"')
ASSET_NAME = re.compile(r"[A-Za-z0-9_-]+")
IDENTIFIER = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def normalise(name: str) -> str:
    """Fold an asset name or a Swift symbol to a comparable key."""
    return "".join(ch for ch in name.lower() if ch.isalnum())


def strip_comments(src: str) -> str:
    """Blank out // line comments and /* */ blocks, preserving offsets."""
    out = list(src)
    i, n, in_str = 0, len(src), False
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j == -1 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j == -1 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def balanced(src: str, open_idx: int) -> tuple[str, int]:
    """Text inside the parens starting at open_idx, plus the closing index."""
    depth, i, n, in_str = 0, open_idx, len(src), False
    while i < n:
        c = src[i]
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
        elif c == '"':
            in_str = True
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return src[open_idx + 1 : i], i
        i += 1
    return "", n


def imagesets(root: Path) -> dict[str, Path]:
    return {p.name[: -len(".imageset")]: p for p in sorted(root.rglob("*.imageset"))}


def duplicate_names(root: Path) -> dict[str, list[Path]]:
    """Imageset names defined more than once anywhere under root."""
    seen: dict[str, list[Path]] = {}
    for p in sorted(root.rglob("*.imageset")):
        seen.setdefault(p.name[: -len(".imageset")], []).append(p)
    return {n: ps for n, ps in seen.items() if len(ps) > 1}


def swift_files() -> list[Path]:
    return [
        p for p in sorted(SWIFT_ROOT.rglob("*.swift"))
        if ".build" not in p.parts and "DerivedData" not in p.parts
    ]


def collect(sources: dict[Path, str]):
    """Return (bare-Image literal refs, every normalised token seen anywhere).

    The token set feeds (b) and is deliberately broad: every string literal and
    every identifier, normalised. Broad = conservative = no false dead art.
    """
    refs: list[tuple[str, Path, int]] = []
    tokens: set[str] = set()

    for path, src in sources.items():
        for m in STRING_LIT.finditer(src):
            tokens.add(normalise(m.group(1)))
        for m in IDENTIFIER.finditer(src):
            tokens.add(normalise(m.group(0)))

        line = lambda i: src.count("\n", 0, i) + 1

        # The three unambiguous asset-by-name APIs. `Image(systemName:)` has a
        # different label and is skipped; `Icon` takes an ImageResource and
        # cannot carry a literal at all.
        for m in re.finditer(r"(?<![\w.])(Image|UIImage|NSImage)\s*\(", src):
            inner, _ = balanced(src, m.end() - 1)
            if not inner or re.search(r"\bsystemName\s*:", inner):
                continue
            head = inner.split(",")[0]
            if m.group(1) in ("UIImage", "NSImage") and "named" not in head:
                continue
            hm = STRING_LIT.search(head)
            if hm:
                refs.append((hm.group(1), path, line(m.end() + hm.start(1))))

    return refs, tokens


def main() -> int:
    catalog = imagesets(ASSETS_ROOT)  # flat, global namespace (no provides-namespace)
    icons = imagesets(ICONS_ROOT)
    sources = {
        p: strip_comments(p.read_text(encoding="utf-8", errors="replace"))
        for p in swift_files()
    }
    refs, tokens = collect(sources)

    # (a) bare Image(...) literals resolving to nothing.
    unresolved: dict[str, set[tuple[Path, int]]] = {}
    for name, path, ln in refs:
        if not name or name in catalog:
            continue
        if not ASSET_NAME.fullmatch(name):  # sentences, hex, format strings, etc.
            continue
        unresolved.setdefault(name, set()).add((path, ln))

    # (b) Icons/ imagesets nothing references, by literal name or by symbol.
    dead = [name for name in sorted(icons) if normalise(name) not in tokens]

    print(f"scanned {len(sources)} Swift files | {len(icons)} Icons/ imagesets | "
          f"{len(catalog)} imagesets catalog-wide")
    print(f"found {len(refs)} bare Image(...) name literals "
          f"({len(set(r[0] for r in refs))} distinct); Icon(...) is ImageResource-typed "
          f"and checked by the compiler")

    status = 0
    if unresolved:
        status = 1
        print(f"\n[FAIL] {len(unresolved)} image name(s) resolve to no imageset -- "
              f"these render as BLANK RECTANGLES at runtime:")
        for name in sorted(unresolved):
            print(f'  "{name}"')
            for path, ln in sorted(unresolved[name])[:8]:
                print(f"      {path.relative_to(REPO_ROOT)}:{ln}")

    if dead:
        status = 1
        print(f"\n[FAIL] {len(dead)} imageset(s) under Icons/ have no reference -- dead art:")
        for name in dead:
            print(f"  {name}")

    dupes = duplicate_names(ASSETS_ROOT)
    if dupes:
        print(f"\n[warn] {len(dupes)} imageset name(s) are defined twice. The catalog "
              f"namespace is flat, so the reference silently picks one -- and the "
              f"generator emits a single symbol for the pair, so the compiler "
              f"cannot see this either:")
        for name, paths in sorted(dupes.items()):
            print(f'  "{name}"')
            for p in paths:
                print(f"      {p.relative_to(ASSETS_ROOT)}")
        print("       Renaming an icon onto a name Crypto/ already owns lands here.")
        print("       terra-defi-banner is a known pre-existing duplicate, tracked separately.")

    if status == 0:
        print("\n[OK] every bare image literal resolves, and every Icons/ imageset is referenced.")
    return status


if __name__ == "__main__":
    sys.exit(main())
