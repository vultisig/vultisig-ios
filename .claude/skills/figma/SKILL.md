---
name: figma
description: Implement UI from Figma designs via MCP with a closed-loop pixel-parity check. Extract exact values (never eyeball), translate to SwiftUI, then render→diff→fix against the Figma export until it matches. Use when implementing or auditing UI against Figma.
---

# Figma → SwiftUI parity workflow

Open-loop translation (read design → write SwiftUI → ship) reliably drifts on **gradients, shadows, component states, and icons**, because nothing compares the rendered pixels to the design. This skill closes that loop: extract exact values, build, then **render → diff against the Figma export → read the heatmap → fix the biggest deltas → repeat**.

## 0. Golden rules

- **Extract, don't eyeball.** Pull exact colors/fonts (`get_variable_defs`), layout + effects + gradient CSS (`get_design_context`), and positions/sizes (`get_metadata`). Guessing a hex, angle, or padding is the #1 source of drift.
- **Slice small.** Call `get_design_context` on the smallest node that answers your question (a card, a button) — large frames truncate.
- **Verify with the harness, every time.** A screen isn't done because it "looks right" — it's done when the diff says so. See §5.
- **Match Figma even when it conflicts with house style.** If the design uses a non-token hex or a non-`price` font for numbers, match it for parity and note the deviation in the PR. (Add a token if the value is reused.)
- **Enumerate ALL layers, including background/decoration.** List the frame's direct children — an ambient glow or gradient *behind* the content is easy to miss because a flat background "looks fine", but the diff will flag it. Small chips/pills too: extract their exact corner radius + border (the border is often the same colour as the fill, not a border token) — don't infer "reasonable" values.
- **Drill into every red region in the heatmap — even low-contrast ones.** "Looks fine to me" is the exact failure mode the loop exists to catch. If a band scores low and it isn't text, suspect a missing layer, a wrong per-state colour, or an un-exported icon.

## 1. Extract the design

```
get_metadata(fileKey, nodeId)          # node tree, sizes, positions (find child node ids)
get_variable_defs(fileKey, nodeId)     # exact color + font tokens
get_design_context(fileKey, nodeId)    # per-component: layout, effects, gradient CSS, asset URLs
get_screenshot(fileKey, nodeId)        # visual reference
```
`get_metadata` returns parent-relative x/y per node — use it to derive stack spacing and paddings exactly (e.g. a VStack `spacing` = childₙ.y − (childₙ₋₁.y + childₙ₋₁.h)).

## 2. Gradients (Figma → SwiftUI)

A Figma gradient = `gradientStops` (position 0–1 + RGBA) + a `gradientTransform` (affine over the shape's normalized [0,1]² space). Easiest reliable path:

1. Take the CSS from `get_design_context`, e.g. `linear-gradient(269.18deg, #c9d6e8 0%, #7d8b9e 97.8%)`.
2. CSS angle → SwiftUI `startPoint`/`endPoint`. CSS 0°=up, 90°=right, 180°=down, 270°=left. The `0%` color sits at the **start** (opposite the angle direction). For ~269° (≈left): start = `.trailing` (`#c9d6e8`), end = `.leading` (`#7d8b9e`).
3. Use `LinearGradient(stops: [.init(color:location:)…], startPoint:, endPoint:)` with the exact stop locations.
- Conic → `AngularGradient(gradient:center:angle:)`; radial → `RadialGradient(...)`. Let the diff confirm direction — if reversed, swap start/end.
- **Gradients are often state/variant-dependent** — extract the gradient for *each* state, don't reuse one (e.g. a progress fill coloured for the *next* tier differs on every tier's screen).

## 3. Shadows (Figma → SwiftUI)

Figma `DROP_SHADOW` = color (RGBA) + offset {x,y} + **radius (=blur)** + **spread**.
- SwiftUI `.shadow(color:radius:x:y:)`: **radius ≈ Figma blur ÷ 2** (Figma/CSS blur ≈ 2× the σ SwiftUI's radius approximates), `x = offset.x`, `y = offset.y`.
- **Spread**: SwiftUI has none. For spread ≠ 0, put a padded, blurred background shape behind the view (custom `dropShadow` modifier) or inset the shape.
- **Inner shadow** (e.g. `inset 0 4 8 rgba(255,255,255,.09)` top highlight): overlay a rounded-rect **stroke** masked by a gradient (white→clear), blurred — see `Features/VultDiscountTiers/View/VultDiscountTierView.swift` `footerInnerShadow`.
- Tune the residual with the diff loop.

## 4. Icons & art — export decision tree

1. **A system symbol matches** → SF Symbol via `Icon(named:isSystem:true)` (cheapest, themeable).
2. **Flat vector, no system match** → `download_assets(format:"svg")` → asset catalog as a vector imageset with **Preserve Vector Data** (see `Crypto/*.imageset/*.svg`). Don't re-draw paths.
3. **Complex raster art** (3D orbs, gradient badges, coins) → `download_assets(format:"png", defaultScale:3)` → 3× imageset. Approximating with a gradient will never match.
4. **Skeuomorphic icon chip** (fixed dark chip + top highlight + drop shadow, holding a gradient glyph): **build the chip in SwiftUI** (`RoundedRectangle` fill + a top-highlight stroke gradient + `.shadow`) and export **only the glyph**. Do NOT export the chip+glyph as one image — that bakes a background you can't recolor or reuse, and it's what a reviewer will reject. The chip is fixed/reusable; only the glyph varies (and is gradient-filled).
   - Find the glyph node with **`get_metadata`, not `get_design_context`** — effect-heavy nodes are *flattened to a single `<img>`* by `get_design_context`, hiding the real layer tree. `get_metadata` shows the children (e.g. a 32pt `Vector` chip + a 22pt `fi_…` glyph); export the glyph node with `download_assets`.
   - If one glyph is itself flattened with no isolatable node, fall back to a tinted SF Symbol for that one.
   - Match the **Figma text frame width**, not the cell width, or wrapping differs (a badge title in an 80pt frame wraps to 2 lines even though a 104pt cell wouldn't).
5. **Node with heavy effects exports oversized** (glow/shadow expands bounds well beyond the node). Do NOT alpha-trim — a soft shadow spans the whole canvas at low alpha, so trimming does nothing. If you must place a pre-baked effect-heavy raster, read the node's `inset-[...%]` from `get_design_context` (the effect bleed as a % of node size) and place with a fixed slot + `.overlay` + `.offset` to center the real content.

## 5. Verify with the parity harness (the loop)

Harness: `VultisigAppTests/FigmaParity/` (`FigmaParityComparator` + `assertFigmaParity`). It renders the SwiftUI view at exact px via `ImageRenderer(scale:3)`, diffs it against the local Figma export in `FigmaParityReferences/<name>.png`, and writes `<name>.actual.png` + `<name>.diff.png` (red heatmap) to `__Output__/`, plus **alignment** (`bestAlign`) and **per-band** similarity diagnostics.

1. Export the frame at exact px: `download_assets(fileKey, nodeId, format:"png", defaultScale:3)` → save to `FigmaParityReferences/<name>.png` (frame_pt × 3). Figma references are **local-only (gitignored)**; a missing one makes the test **skip**, not fail. (`FIGMA_PARITY_REFS` points the loader outside the repo.)
2. Build the SwiftUI frame at the same point size; mask OS-drawn regions (status bar).
3. Add a test: `assertFigmaParity(view, reference:"<name>", pointSize:…, maskRects:[statusBar])`.
4. Run (from `VultisigApp/`):
   ```sh
   xcodebuild test -project VultisigApp.xcodeproj -scheme VultisigApp \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
     -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
     -only-testing:VultisigAppTests/<Class>
   ```
5. Read the printed diagnostics + open `*.actual.png` / `*.diff.png`:
   - `bestAlign shift(dx,dy)` ≠ 0 → uniform misalignment; fix top inset / paddings.
   - Worst `bands` → which section to fix first.
   - Red on an element → wrong gradient/shadow/color/asset there.
6. Fix the biggest delta, re-run, repeat.

**Interpreting the score.** Pixel-exact parity is impossible: the OS status-bar clock and — critically — **text antialiasing differs between Figma's renderer and iOS CoreText**, so dense text floors strict per-pixel coverage in the mid-90s even when the screen is visually perfect. Judge with **perceptual precision (`1−meanDelta`)** and the heatmap, not just "% pixels within tolerance": aim for **~0.97+ on a tuned screen**; `assertFigmaParity`'s default gate of **0.95 is the regression floor**, not the target. Gate CI on perceptual precision + human sign-off on the side-by-side.

## 6. Property mapping (still required)

Before writing code, map every value to a token:

| Figma | Value | SwiftUI token | Match? |
|-------|-------|---------------|--------|
| Background | #061b3a | `Theme.colors.bgSurface1` | ✅ |
| Title | Brockmann Medium 28 | `Theme.fonts.title1` | ✅ |
| Corner | 24 | `24` | ✅ |

Rules: `Theme.colors.*` / `Theme.fonts.*` only (add a token if a needed value is missing); `.foregroundStyle()` not `.foregroundColor()`; `PrimaryButton` for buttons; localize all user-facing strings in every locale under `Core/Localizables/` + run `sort_localizable.py`; SwiftLint clean.

## In-repo usage example

`VultisigAppTests/FigmaParity/FigmaParitySelfTests.swift` is the harness's hermetic self-test and the canonical usage example: a test-only fixture view checked with `assertFigmaParity` against a committed reference, exercising the perceptual gate, degradation scoring, and `bestAlign` offset recovery (plus a record-mode test that regenerates the reference). `VultisigAppTests/FigmaParity/FigmaParityReferences/README.md` documents reference naming/export and the `FIGMA_PARITY_REFS` / `FIGMA_PARITY_OUT` overrides.

Background: this workflow was proven on the VULT Tiers detail-screen family (7 states, converged to ~96–97% perceptual; text antialiasing was the residual floor). That experimental screen and its Figma exports intentionally stayed out of the repo — only the reusable harness ships here.
