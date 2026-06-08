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

    init(
        quote: SwapQuote,
        allQuotes: [SwapQuote]? = nil,
        vultDiscountBps: Int,
        referralDiscountBps: Int
    ) {
        self.quote = quote
        self.allQuotes = allQuotes ?? [quote]
        self.vultDiscountBps = vultDiscountBps
        self.referralDiscountBps = referralDiscountBps
    }
}
