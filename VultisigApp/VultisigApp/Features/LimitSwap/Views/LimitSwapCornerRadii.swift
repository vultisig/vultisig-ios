//
//  LimitSwapCornerRadii.swift
//  VultisigApp
//
//  The two radii the limit form's own surfaces share. They live here, at module
//  visibility, only because the form is split across a file per component and
//  several of them draw the same shapes — a card and a notice must not drift
//  apart just because they stopped being neighbours in one file. They are
//  `limit`-prefixed for that reason: they are this feature's vocabulary, not a
//  general-purpose one. Anything reusable beyond it belongs in `Theme.radius`.
//

import SwiftUI

/// Corner radius for the limit form's standalone peer sections (price card,
/// expiry card). This is the OUTER radius of the market swap's reusable section
/// (`SwapFromToField`), so the limit form speaks the same radius language as the
/// rest of swap. `SwapFromToField`'s uneven 24/12 shape exists only because its
/// from/to fields are a stacked PAIR that must read as one unit (24 outside, 12
/// where they meet) — a standalone card has no neighbour to meet, so it takes the
/// outer 24 on all corners. The paired Sell/Buy rows below keep the uneven
/// pairing shape via `NotchedRectangle` (24 outside / 12 where they meet), so the
/// shared toggle seats in a real cutout instead of page-colored paint.
let limitSectionCornerRadius = Theme.radius.xl

/// Corner radius for the inline notice/warning rows. Deliberately NOT the section
/// radius: these rows are single-line annotations (~39pt tall), and a 24pt radius
/// exceeds half their height, degenerating the shape into a capsule and making
/// them read as pills rather than as messages.
let limitNoticeCornerRadius: CornerRadius = Theme.radius.md
