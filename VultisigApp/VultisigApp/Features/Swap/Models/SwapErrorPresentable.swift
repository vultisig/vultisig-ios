//
//  SwapErrorPresentable.swift
//  VultisigApp
//

import Foundation

/// User-facing presentation of a swap-flow error: the title and body the swap
/// form's error tooltip renders.
///
/// Deliberately separate from `LocalizedError.errorDescription`. That stays the
/// *diagnostic* text and may carry a raw upstream provider string (a node body
/// with an uppercased contract address, a 500 page, an aggregator's internal
/// wording) which is useful in a log and hostile on screen. `errorMessage` is
/// always localized app copy.
///
/// Conforming an error type here is what keeps it out of the tooltip's generic
/// "Unexpected Error" fallback: title and body resolve through this one
/// protocol, so a type can never end up with a domain-correct body under a
/// generic title.
protocol SwapErrorPresentable: Error {
    /// Tooltip heading — a short domain verdict ("No Liquidity Pool").
    var errorTitle: String { get }
    /// Tooltip body. Localized app copy, never a raw upstream string.
    var errorMessage: String { get }
}
