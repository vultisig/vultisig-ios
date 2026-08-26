# Crypto Market Widgets — Design QA

## Evidence

- Source visual truth: `/Users/gaston/Downloads/Screenshot 2026-08-24 at 19.56.17.png` (Medium) and `/Users/gaston/Downloads/Screenshot 2026-08-24 at 19.56.36.png` (Large)
- Implementation screenshots: `/tmp/vultisig-top-cryptos-medium-qa.jpeg` and `/tmp/vultisig-top-cryptos-large-qa.jpeg`
- Combined focused comparisons: `/tmp/vultisig-top-cryptos-comparison.png` and `/tmp/vultisig-top-cryptos-large-comparison.png`
- State: iOS widget gallery, Vultisig `Top Cryptos`, medium and large families, dark appearance, static gallery preview data
- Viewport: iPhone Air simulator on iOS 26.4; implementation capture is `341 × 792` px
- Source pixels: `1206 × 2622` px (`@2x` iPhone screenshot)
- Density normalization: compared widget content regions rather than device chrome. Medium used a `1048 × 494` physical-pixel source crop (`524 × 247` image points) and a `282 × 132` implementation crop. Large used approximately `1048 × 1094` physical source pixels and a `282 × 296` implementation crop. Each side was scaled to `840` px width; resulting paired heights differ by less than 1%.

## Findings

- No actionable P0, P1, or P2 differences remain.
- Fonts and typography: both use a compact two-line asset hierarchy with bold tickers, secondary names, and right-aligned price/change values. Vultisig retains the system locale's `US$` presentation, which is intentional dynamic formatting rather than design drift.
- Spacing and layout rhythm: the three-row, headerless medium layout, row separators, equal edge columns, centered chart track, and rounded widget surface follow the CoinMarketCap reference structure.
- Colors and visual tokens: Vultisig intentionally keeps its dark navy theme and existing green/red chart gradients while preserving the reference's semantic gain/loss treatment.
- Image quality and asset fidelity: the visible BTC, ETH, and USDT previews reuse Vultisig's shared token artwork through `AsyncImageView`; runtime entries prioritize downloaded CoinGecko image data. No widget-only token copies or placeholder initials are visible in the verified preview.
- Copy and content: ticker, name, price, and percentage change match the requested information hierarchy. The title and explanatory copy remain outside the widget in Apple's gallery UI.
- Icons: gain/loss direction glyphs and token artwork are aligned and visually consistent at preview size.
- Accessibility and resilience: the row layout uses fixed equal asset/value columns around a flexible chart column, preventing the chart midpoint from drifting when prices vary in width.

## Open Questions

- None blocking. The CoinMarketCap screenshot uses different live market values and currency-locale formatting, which were treated as dynamic-data differences.

## Full-view and Focused Comparison

- Full-view evidence confirms the medium and large widgets are exposed correctly in Apple's widget gallery and render three/five rows without clipping.
- The focused side-by-side comparison was required because typography, token artwork, separators, and sparkline centering are too small to judge reliably in the full simulator screenshot.

## Comparison History

- Pass 1: no actionable P0/P1/P2 differences were found in the post-change implementation. Before this formal pass, the requested scope refinements removed Watchlist, removed the medium header, centered the chart column, and replaced placeholder preview icons with real token artwork.

## Implementation Checklist

- [x] Remove Watchlist widget and configuration intent from the extension bundle.
- [x] Match the reference's headerless medium three-row composition.
- [x] Keep sparklines centered while preserving the existing gradients.
- [x] Use real token artwork in gallery previews and downloaded CoinGecko artwork at runtime.
- [x] Verify medium and large Top Cryptos previews in the iOS widget gallery.

## Follow-up Polish

- None required for this iteration.

final result: passed
