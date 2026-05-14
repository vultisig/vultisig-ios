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
    let quote: SwapQuote
    let vultDiscountBps: Int
    let referralDiscountBps: Int
}
