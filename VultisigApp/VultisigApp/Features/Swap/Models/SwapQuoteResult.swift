//
//  SwapQuoteResult.swift
//  VultisigApp
//
//  Bundles the outputs of a quote fetch — the SwapQuote itself plus the
//  discount basis-points that today are written back into SwapTransaction
//  as side effects. Callers fold the bps values into their draft store.
//

import Foundation

struct SwapQuoteResult: Equatable {
    let quote: SwapQuote
    let vultDiscountBps: Int
    let referralDiscountBps: Int
}
