//
//  SwapQuotes.swift
//  VultisigApp
//
//  The outcome of a multi-provider quote fetch: the auto-selected winner plus
//  the full ranked candidate set (best→worst by net output). The winner is the
//  default; `ranked` lets the provider-selection UI surface the alternatives
//  without re-fetching. `ranked` always contains `best`.
//

import Foundation

struct SwapQuotes: Equatable {
    /// Auto-selected winner — net output plus the banded provider-preference layer.
    let best: SwapQuote

    /// All rankable quotes sorted best→worst by `expectedNetToAmount`. Used by the
    /// provider-selection list; the displayed amounts are monotonically decreasing.
    let ranked: [SwapQuote]
}
