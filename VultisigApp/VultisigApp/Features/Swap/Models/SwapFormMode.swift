//
//  SwapFormMode.swift
//  VultisigApp
//

import Foundation

/// Which tab the swap form is on: a market swap or a resting limit order.
/// Purely form/UI state — the placed transaction's equivalent discriminator is
/// `SwapKind`, which also carries the quote / limit record.
///
/// Distinct from `SwapMode`, which is how a market swap *settles* (pool swap vs
/// SECURE+ mint) and is orthogonal to this.
enum SwapFormMode: Hashable {
    case market
    case limit
}
