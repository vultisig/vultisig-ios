# Crypto market widgets — Signal Flow visual specification

This document translates the approved Signal Flow concept into native WidgetKit rules. The reference image is [signal-flow-reference.png](signal-flow-reference.png). The image is a hierarchy reference, not a bitmap that ships in the widget.

## Supported families

| Widget kind | systemSmall | systemMedium | systemLarge |
|---|---:|---:|---:|
| Crypto Ticker | Yes | Yes | No |
| Top Cryptos | No | Three rows | Five rows |

Views use `widgetContentMargins` and the system container corner radius. They must not assume one fixed pixel canvas or draw an inner rounded card.

## Shared visual tokens

| Element | Specification |
|---|---|
| Container | `Theme.colors.bgPrimary` in full-colour rendering through `.containerBackground(for: .widget)` |
| Primary text | `Theme.colors.textPrimary` |
| Secondary text | `Theme.colors.textSecondary`; tertiary metadata may use `textTertiary` |
| Positive | `Theme.colors.alertSuccess`; always accompanied by a leading `+` and the `24H` label |
| Negative | `Theme.colors.alertError`; always accompanied by a minus sign and the `24H` label |
| Neutral/missing | `textTertiary`; never infer direction from a missing value |
| Separators | `Theme.colors.borderLight`, 1 physical pixel where possible |
| Asset names | Brockmann Medium, normally 12–14 pt |
| Prices | Satoshi Medium with monospaced digits, 14–22 pt by family |
| Metadata | Brockmann Medium, 10–12 pt |
| Vultisig mark | Real template-capable `logo-outline` vector, top-trailing, 18 pt in small/medium and 20 pt in large |
| Token icon | 28 pt in small/list rows; 30 pt in Medium Ticker |
| Sparkline stroke | 1.5 pt in lists, 2 pt in Medium Ticker, round caps/joins, monotone interpolation |
| Sparkline fill | Direction colour at 20% opacity at the top fading to 0%; 28% is the maximum for Medium Ticker |
| Endpoint | 5 pt filled direction colour with a 1.5 pt primary-text ring; hide when the series is unavailable |

The widget extension must bundle Brockmann Medium and Satoshi Medium rather than relying on the main application bundle. If font registration cannot be made reliable in the extension, use system rounded medium for labels and system monospaced medium for prices as an explicit fallback.

## Shared structure

- Keep the Vultisig mark at the far top-trailing edge. When a `7D` label is present, it sits immediately to the mark's leading side with at least 8 pt separation.
- Token identity is always icon, ticker, then full name. The ticker survives before the full name when space is constrained.
- Prices are trailing-aligned. Use monospaced digits so timeline updates do not visibly shift the column.
- `24H` is part of every visible percentage. Colour is redundant information, never the only direction signal.
- `7D` appears once per chart-bearing widget, not once per row.
- List rows share one surface and use separators. Rows are never individual cards.
- Sparklines use their own padded min/max domain. A flat stablecoin series remains a centred horizontal line.
- Widget views render immutable timeline snapshots only; loading spinners and interactive chart scrubbing are not used.

## Small Crypto Ticker

- Top row: 28 pt token icon, ticker/full name stack, then the 18 pt Vultisig mark.
- Price is the hero at 20–22 pt and may scale down to 17 pt before truncating.
- The 24H change sits directly below the price at 12 pt.
- Freshness is normally accessibility-only. Show a 10 pt `Updated …` line visually once the snapshot is older than two hours.
- No sparkline. A chart at this size competes with the price and implies precision it cannot show.

## Medium Crypto Ticker

- Header: 30 pt token icon and identity leading; `7D` plus the 18 pt mark trailing.
- Price and 24H change occupy the upper-left hierarchy below the identity row.
- The chart fills the lower half, with a target height of 62–68 pt after system margins.
- The chart may run behind open space but never behind text. Keep at least 8 pt between the value group and the line.
- Freshness uses 10 pt tertiary text at the lower-leading edge when it can remain clear of the chart; otherwise it is accessibility-only until stale.

## Medium three-row list

- Render exactly three records, or fewer when fewer valid records exist.
- Target each row at 39–43 pt, using the remaining height after system margins.
- Columns: 28 pt icon; flexible identity column; sparkline with a preferred width of 78–96 pt; trailing value column with price above 24H change.
- The trailing value column is 82–98 pt depending on available width. It has layout priority over the full name and sparkline.
- Reserve the first row's far top-trailing corner for the 18 pt Vultisig mark; move that row's price/change group down or leading enough that the mark never overlaps it.
- Hide the full name before hiding price, percentage, ticker, or icon. Reduce sparkline width before scaling price text below 13 pt.

## Large five-row list

- Render up to five records with uniform rows and four lightweight separators.
- Top Cryptos adds a 16–20 pt rank column.
- Columns: optional rank; 30 pt icon; flexible identity column; sparkline with a preferred width of 110–150 pt; trailing value column with price above 24H change.
- Reserve the far top-trailing corner for the 20 pt Vultisig mark, with `7D` immediately to its leading side.
- The five rows share all remaining vertical space equally; do not add a separate title bar that compresses the rows.
- Updated time is shown at 10 pt along the lower-leading edge only when it does not reduce the fifth row's minimum readable height. It remains in the widget accessibility label in every state.

## Rendering modes

- **Full colour:** use Vultisig navy, turquoise and coral exactly as above.
- **Accented/tinted:** make the logo, text and chart shapes template-compatible. Use luminance, line shape, plus/minus signs and labels to preserve hierarchy when system tint replaces brand colours.
- **Vibrant:** remove area fills if they collapse into the background; retain the line, endpoint ring and text hierarchy.
- **Increased contrast:** strengthen separators and secondary text, but keep the chart subordinate to values.
- **Without colour differentiation:** positive/negative meaning must remain complete through signs, `24H`, and accessibility wording.

## Content stress rules

- Tickers stay on one line and truncate at the tail only after four visible characters.
- Full names are one line and may disappear at accessibility sizes before prices or percentages.
- Prices use Vultisig's significant-digit formatter and scale down before truncating; never horizontally scroll or marquee.
- Missing icons use a deterministic token-initial circle.
- Missing percentages render `— 24H` in neutral styling.
- Missing or unusable sparklines reserve the column and show no invented line.
- Fewer Top Cryptos records render naturally; never duplicate or pad records.
- Stale last-good data remains readable and retains its original update time.

## Accessibility

Each asset row is one accessibility element announcing, in order: asset name and ticker, formatted price and currency, 24-hour direction/change, 7-day trend availability, and freshness. Decorative token artwork, the endpoint and the Vultisig mark are hidden from VoiceOver.

Dynamic Type validation must cover the default size and accessibility sizes. When the system family cannot fit every secondary label, remove the full name and freshness before shrinking the primary price/ticker below the minimums above.

## Preview and snapshot matrix

Every widget kind/family must include previews for:

- positive, negative, neutral and missing change;
- long name/ticker and very small/large price;
- missing icon and missing chart;
- fresh, stale and unavailable-without-cache states;
- full-colour dark, accented/tinted, vibrant and increased-contrast rendering;
- default Dynamic Type and the largest layout that remains supported without clipping.
