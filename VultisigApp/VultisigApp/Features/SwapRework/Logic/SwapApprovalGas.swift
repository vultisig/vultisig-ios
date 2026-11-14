//
//  SwapApprovalGas.swift
//  VultisigApp
//
//  Gas for the ERC-20 approve legs ahead of a swap. Each leg is signed with
//  the swap payload's own fee fields (`getPreSignedApproveInputData`), which is
//  also what the review's approve fee shows, so a leg costs the swap's
//  displayed network fee.
//

import Foundation

enum SwapApprovalGas {
    static func legs(for requirement: ERC20ApprovalRequirement) -> Int {
        switch requirement {
        case .notRequired: return 0
        case .approve: return 1
        case .resetThenApprove: return 2
        }
    }

    static func fiat(legs: Int, perLegFiat: Decimal) -> Decimal {
        Decimal(max(legs, 0)) * perLegFiat
    }

    /// Swap gas plus every approve leg, in the fee coin.
    static func totalGas(swapGas: Decimal, legs: Int) -> Decimal {
        swapGas * Decimal(1 + max(legs, 0))
    }
}

/// What the fee coin has to cover, in the fee coin: the funding fee the
/// existing balance gate checks (signed bond, Solana headroom, storage
/// reserve), every approve leg, and the amount itself when it is the fee coin.
/// One value feeds the gas check, the shortfall card and the Add ETH sheet, so
/// they always agree.
struct SwapGasRequirement: Equatable {
    let gas: Decimal
    let spend: Decimal
    let have: Decimal

    var needed: Decimal { gas + spend }
    var shortfall: Decimal { max(needed - have, 0) }
    var isShort: Bool { have < needed }

    /// Share of the gas added on top when asking the user to top up, so a fee
    /// that moves while they wait does not leave them short again.
    static let topUpMargin: Decimal = Decimal(string: "0.1") ?? 0

    /// What the Add ETH sheet asks for: the shortfall plus the margin. Zero
    /// when nothing is short.
    var topUp: Decimal {
        shortfall > 0 ? shortfall + gas * Self.topUpMargin : 0
    }
}
