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
