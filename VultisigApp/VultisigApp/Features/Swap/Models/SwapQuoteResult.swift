//
//  SwapQuoteResult.swift
//  VultisigApp
//
//  Bundles the outputs of a quote fetch — the SwapQuote itself plus the
//  discount basis-points the caller needs to display alongside it. The
//  details ViewModel folds the bps values into its own published state.
//

import Foundation

struct SwapQuoteResult: Equatable {
    /// Auto-selected winner. Stays the default the rest of the flow reads.
    let quote: SwapQuote
    /// Full ranked candidate set (best→worst), surfaced to the provider-selection
    /// UI. Contains `quote`. With a single eligible provider this holds one entry.
    let allQuotes: [SwapQuote]
    let vultDiscountBps: Int
    let referralDiscountBps: Int
    /// Whether a referral code was active for this fetch (`!referredCode.isEmpty`).
    /// Kept as a clean bit rather than inferred from `referralDiscountBps`, which
    /// collapses to 0 in DEBUG (base affiliate rate is 0) even when a code is
    /// present. Drives the route-aware affiliate-percentage label so the shown %
    /// matches the `affiliate_bps` the request builder actually sent.
    let isReferred: Bool

    init(
        quote: SwapQuote,
        allQuotes: [SwapQuote]? = nil,
        vultDiscountBps: Int,
        referralDiscountBps: Int,
        isReferred: Bool = false
    ) {
        self.quote = quote
        self.allQuotes = allQuotes ?? [quote]
        self.vultDiscountBps = vultDiscountBps
        self.referralDiscountBps = referralDiscountBps
        self.isReferred = isReferred
    }
}
