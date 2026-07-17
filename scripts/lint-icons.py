#!/usr/bin/env python3
"""Lint the asset-catalog icon set against the Swift sources.

Icons are referenced by string literal (`Icon(named: "chevron-down")`), so a
typo or a missed rename compiles cleanly and renders a blank rectangle at
runtime. Only a handful of snapshot tests exist, so CI catches none of it.
This script recovers most of what a type-safe API would have given us.

It reports three things:

  (a) icon-name literals that resolve to no imageset  -- would-be blank rectangles
  (b) imagesets under Icons/ whose name appears in NO string literal -- likely dead art
  (c) imageset names duplicated anywhere in the catalog -- silent shadowing

Run via `make lint-icons`.

(c) exists because NO Contents.json in this catalog sets `provides-namespace`, so
folder groups are purely organisational and **asset names are flat and global
across all 385 imagesets** -- that is why `Image("vult-bronze")` resolves despite
living under Icons/vult-tiers/. The consequence is that two imagesets sharing a
name in different folders make `Image(name)` ambiguous. Direction (a) cannot catch
this: the name resolves fine, just possibly to the wrong art. Renaming an icon to
a name the Crypto/ token logos already own is the concrete way to hit it.

=============================================================================
HONESTY NOTE -- THIS SCRIPT IS ~95% ACCURATE AND IS *NOT* SOUND.
=============================================================================

Direction (b) is deliberately CONSERVATIVE. It asks whether the name appears as
ANY string literal anywhere -- not whether it appears in an *icon position*. So
it has no false positives (it will never call live art dead), but it does have
false negatives: dead art whose name collides with any other string survives.
`function.imageset` sat dead behind `"function".localized` (a localization key,
not an icon) until a hand audit found it.

DO NOT "fix" this by checking icon-position refs instead. The looseness is
load-bearing: five live icons are reached only in ways the matcher cannot see --
`Icon(named: isSelected ? "folder-filled" : "folder")` and its ternary siblings
(chevron-left, eye-closed), and `[(title, subtitle, icon)]` tuple arrays (lock,
signature). Tightening (b) reports all five as dead and invites deleting real
art. Verify a (b) hit by hand before removing anything.

Direction (a) is the valuable direction and cannot be made sound. The blocker
is fundamental: **Swift has no type distinguishing an icon-name String from
any other String**, so no static scan can decide in general whether `foo("bar")`
passes an icon name. Consequences, stated plainly:

  * A NEW WRAPPER WITH A NEW ARGUMENT LABEL ESCAPES SILENTLY. Icon positions
    are recognised via ICON_LABELS (hand-maintained) plus the auto-classifier
    below. `MyThing(glyph: "typo")` is invisible here until `glyph` is added.
    This is the standing weakness and it has no static fix.
  * Names built at runtime cannot be checked. `"vult-\\(rawValue)"` is opaque
    to any grep. Such imagesets are reported as INTERPOLATION-REACHED rather
    than dead, and are covered *soundly* instead by a CaseIterable runtime
    assertion in the test suite (IconAssetResolutionTests) -- the right tool
    for that job, and self-maintaining as the enum grows.
  * SF Symbol names and asset names overlap ("percent", "gauge" and "calendar"
    are both). Telling them apart requires knowing which API the string reaches,
    so the classifier below resolves each wrapper to SF-Symbol or asset. A
    wrapper whose param flows somewhere the classifier cannot follow is a blind
    spot.

Use this as a net, not a proof. It reduces risk; it does not eliminate it.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ASSETS_ROOT = REPO_ROOT / "VultisigApp" / "VultisigApp" / "Assets.xcassets"
ICONS_ROOT = ASSETS_ROOT / "Icons"
SWIFT_ROOT = REPO_ROOT / "VultisigApp"

# Argument labels whose string literal is an asset name -- unless the call is to
# a type/function the classifier proved is an SF-Symbol wrapper. HAND-MAINTAINED.
# NOTE: `named:` is deliberately NOT here. It is far too generic -- NSColor(named:),
# playAHAPFile(named:) and others all use it. The asset-bearing `named:` calls
# (Icon/UIImage/NSImage) are matched precisely by DIRECT_API below instead.
ICON_LABELS = [
    "icon", "image", "iconName", "imageName", "leadingIcon",
    "trailingIcon", "buttonIcon", "featureIcon", "bgImage", "networkImage",
    "coinImage",
]

STRING_LIT = re.compile(r'"([^"\\\n]*)"')
ASSET_NAME = re.compile(r"[A-Za-z0-9_-]+")


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


def block_after(src: str, start: int) -> str:
    """The {...} block that follows start."""
    brace = src.find("{", start)
    if brace == -1:
        return ""
    depth, i, n = 0, brace, len(src)
    while i < n:
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[brace : i + 1]
        i += 1
    return ""


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


def classify_wrappers(sources: dict[Path, str]) -> tuple[set[str], set[str]]:
    """Split components AND local funcs into SF-Symbol wrappers and asset wrappers.

    SF Symbol names and asset names overlap ("percent", "gauge" and "calendar" are
    all both), so an `icon:` label alone does not tell you which API the string
    reaches. This resolves it structurally: a declaration whose icon-ish String
    parameter flows into `Image(systemName:)` takes SF Symbol names and its call
    sites must NEVER be touched by an asset rename; one that flows into
    Icon(named:)/Image(_)/UIImage(named:) takes asset names, so renames DO
    propagate there.

    Both types (`SettingToggleCell(icon:)`) and functions (`infoRow(icon:)`) are
    classified -- a view-builder func forwarding to systemName is just as common.
    """
    sf: set[str] = set()
    asset: set[str] = set()
    decl = re.compile(r"\b(?:struct|class|enum|func)\s+(\w+)")
    for src in sources.values():
        for sm in decl.finditer(src):
            tname, start = sm.group(1), sm.start()
            nxt = re.search(r"\n\s*(?:struct|class|enum|extension|func)\s+\w+", src[start + 1 :])
            body = src[start : start + 1 + nxt.start()] if nxt else src[start:]
            props = {
                m.group(1)
                for m in re.finditer(r"\b(\w+)\s*:\s*String\b\??", body)
                if re.search(r"icon|image", m.group(1), re.I)
            }
            for prop in props:
                p = re.escape(prop)
                if re.search(rf"Image\s*\(\s*systemName\s*:\s*{p}\b", body):
                    sf.add(tname)
                if re.search(rf"Icon\s*\(\s*named\s*:\s*{p}\b", body) or \
                   re.search(rf"Image\s*\(\s*{p}\s*\)", body) or \
                   re.search(rf"(?:UI|NS)Image\s*\(\s*named\s*:\s*{p}\b", body):
                    asset.add(tname)
    # A type doing both is treated as an asset wrapper (fail loud, not silent).
    return sf - asset, asset


def sf_call_spans(src: str, sf_types: set[str]) -> list[tuple[int, int]]:
    """Character ranges of calls whose icon string is an SF Symbol, not an asset.

    Two kinds: calls to a proven SF-Symbol wrapper, and calls to a DUAL-MODE
    wrapper that has been switched into SF-Symbol mode at this site.
    `DefiButton(icon:isSystemIcon:)` forwards to `Icon(named:isSystem:)`, so the
    very same parameter is an asset name at one call site and an SF Symbol at the
    next -- only the flag tells them apart.
    """
    spans = []
    pats = [re.compile(r"\b(\w+)\s*\(")] if not sf_types else [
        re.compile(r"\b(" + "|".join(sorted(map(re.escape, sf_types))) + r")\s*\("),
    ]
    for m in pats[0].finditer(src):
        inner, end = balanced(src, m.end() - 1)
        spans.append((m.start(), end))
    # Any call explicitly asking for a system symbol, whatever its type.
    for m in re.finditer(r"\b\w+\s*\(", src):
        inner, end = balanced(src, m.end() - 1)
        if inner and re.search(r"\bisSystem(?:Icon)?\s*:\s*true\b", inner):
            spans.append((m.start(), end))
    return spans


def collect(sources: dict[Path, str], sf_types: set[str]):
    """Return (icon-position refs, every literal seen anywhere)."""
    refs: list[tuple[str, Path, int]] = []
    all_literals: set[str] = set()
    label_re = re.compile(r"\b(" + "|".join(ICON_LABELS) + r")\s*:\s*\"([^\"\\\n]*)\"")
    # Computed String members / funcs whose name is icon-ish. `String?` counts:
    # SettingsOption.icon is `var icon: String?` and drives five icon names.
    decl_re = re.compile(
        r"\b(?:var|func)\s+(\w*(?:[Ii]con|[Ii]mage)\w*)\s*(?:\([^)]*\))?\s*(?::|->)\s*String\??\s*\{"
    )
    # Icon-ish array literals: `let stepIcons = ["a", "b"]`, `icons.append(contentsOf: [...])`
    arr_re = re.compile(r"\b(?:let|var)\s+\w*(?:[Ii]cons?|[Ii]mages?)\b[^=\n]*=\s*\[([^\]\n]*)\]")
    app_re = re.compile(r"\b\w*(?:[Ii]cons?|[Ii]mages?)\b\s*\.\s*append(?:\(contentsOf:)?\s*\(?\s*\[?([^\]\)\n]*)")

    for path, src in sources.items():
        all_literals.update(m.group(1) for m in STRING_LIT.finditer(src))
        spans = sf_call_spans(src, sf_types)
        in_sf = lambda i: any(a <= i <= b for a, b in spans)
        line = lambda i: src.count("\n", 0, i) + 1

        # Direct asset APIs.
        for m in re.finditer(r"(?<![\w.])(Icon|Image|UIImage|NSImage)\s*\(", src):
            inner, _ = balanced(src, m.end() - 1)
            if not inner or re.search(r"\bisSystem\s*:\s*true\b", inner):
                continue
            if re.search(r"\bsystemName\s*:", inner):
                continue
            head = inner.split(",")[0]
            hm = STRING_LIT.search(head)
            if hm and (m.group(1) != "Icon" or "named" in head):
                # Report the LITERAL's line, not the call's: these calls wrap, so
                # `Icon(` and `named: "..."` are routinely on different lines.
                refs.append((hm.group(1), path, line(m.end() + hm.start(1))))

        # Labelled args on wrapper components (skipping proven SF-Symbol sites).
        for m in label_re.finditer(src):
            if in_sf(m.start()):
                continue
            # A literal glued to a `+` is a PREFIX, not a whole name:
            # `ChainIconView(icon: "chain-" + chainIcon)` builds the name at runtime.
            if re.match(r'\s*\+', src[m.end():m.end() + 4]):
                continue
            refs.append((m.group(2), path, line(m.start())))

        # Icon-ish computed members: take literals in RETURN POSITION.
        # Everything in such a body is a candidate EXCEPT local bindings, because
        # those hold lookup tables rather than icon names -- DeviceInfo.iconName
        # opens with `let laptopSigners = ["windows", "extension", "mac"]` and
        # only then returns "laptop"/"phone".
        # Skipping `let`/`var` lines and taking the rest covers every real shape:
        # `return "x"`, `case .a: "x"`, the literal alone on its own line under a
        # `case` (CoinAction.buttonIcon), and -- the one that bit us -- a bare
        # ternary implicit return, `isFastVault ? "bolt" : "shield"`.
        for m in decl_re.finditer(src):
            body = block_after(src, m.end() - 1)
            base = src.find(body, m.end() - 1)
            off = 0
            for bline in body.split("\n"):
                s = bline.strip()
                if not re.match(r'\b(?:let|var|guard)\b', s):
                    for lm in STRING_LIT.finditer(bline):
                        refs.append((lm.group(1), path, line(base + off + lm.start())))
                off += len(bline) + 1

        for rx in (arr_re, app_re):
            for m in rx.finditer(src):
                for lm in STRING_LIT.finditer(m.group(1)):
                    refs.append((lm.group(1), path, line(m.start(1) + lm.start())))

    return refs, all_literals


def interpolation_prefixes(sources: dict[Path, str]) -> set[str]:
    """Static prefixes of interpolated/concatenated asset-shaped literals.

    `"vult-\\(rawValue)"` and `"chain-" + x` both yield a prefix. Any imageset
    starting with one may be reached at runtime and must not be called dead.
    """
    out: set[str] = set()
    pats = [re.compile(r'"([a-zA-Z0-9_-]+)\\\('), re.compile(r'"([a-zA-Z0-9_-]+)"\s*\+\s*\w')]
    for src in sources.values():
        for pat in pats:
            for m in pat.finditer(src):
                pref = m.group(1)
                if len(pref) >= 3 and ("-" in pref or "_" in pref):
                    out.add(pref)
    return out


def main() -> int:
    catalog = imagesets(ASSETS_ROOT)  # flat, global namespace (no provides-namespace)
    icons = imagesets(ICONS_ROOT)
    sources = {
        p: strip_comments(p.read_text(encoding="utf-8", errors="replace"))
        for p in swift_files()
    }
    sf_types, asset_types = classify_wrappers(sources)
    refs, all_literals = collect(sources, sf_types)
    prefixes = interpolation_prefixes(sources)

    # (a) icon-position literals resolving to nothing.
    unresolved: dict[str, set[tuple[Path, int]]] = {}
    for name, path, ln in refs:
        if not name or name in catalog:
            continue
        if not ASSET_NAME.fullmatch(name):  # SF Symbols ("a.b"), sentences, hex, etc.
            continue
        unresolved.setdefault(name, set()).add((path, ln))

    # (b) Icons/ imagesets nothing references.
    interp, dead = [], []
    for name in sorted(icons):
        if name in all_literals:
            continue
        (interp if any(name.startswith(p) for p in prefixes) else dead).append(name)

    print(f"scanned {len(sources)} Swift files | {len(icons)} Icons/ imagesets | "
          f"{len(catalog)} imagesets catalog-wide")
    print(f"classified {len(sf_types)} SF-Symbol wrappers (excluded) and "
          f"{len(asset_types)} asset wrappers")
    print(f"found {len(refs)} icon-position literals ({len(set(r[0] for r in refs))} distinct)")

    status = 0
    if unresolved:
        status = 1
        print(f"\n[FAIL] {len(unresolved)} icon name(s) resolve to no imageset -- "
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
              f"namespace is flat, so Image(name) silently picks one:")
        for name, paths in sorted(dupes.items()):
            print(f'  "{name}"')
            for p in paths:
                print(f"      {p.relative_to(ASSETS_ROOT)}")
        print("       Renaming an icon onto a name Crypto/ already owns lands here.")
        print("       terra-defi-banner is a known pre-existing duplicate, tracked separately.")

    if interp:
        used = sorted({p for p in prefixes if any(n.startswith(p) for n in interp)})
        print(f"\n[info] {len(interp)} imageset(s) reached only by runtime interpolation "
              f"(prefixes: {', '.join(used)}).")
        print("       Not statically provable -- covered soundly by IconAssetResolutionTests.")
        for name in interp:
            print(f"  {name}")

    if status == 0:
        print("\n[OK] every icon literal resolves, and every Icons/ imageset is referenced.")
    return status


if __name__ == "__main__":
    sys.exit(main())
