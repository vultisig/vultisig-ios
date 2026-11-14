//
//  SwapPriceMove.swift
//  VultisigApp
//
//  A refresh can change the payout under the user's thumb. A better amount
//  just updates; a worse one beyond `SwapReworkConfig.priceMoveThreshold`
//  holds review until the user confirms the new amount, so nobody signs a
//  number they did not see.
//

import Foundation

enum SwapPriceMove: Equatable {
    case unchanged
    case improved(change: Decimal)
    /// `change` is the drop as a positive share (0.004 = 0.40%).
    case worsened(change: Decimal)

    /// Compares the payout the user acknowledged with the refreshed one.
    static func evaluate(
        acknowledged: Decimal?,
        current: Decimal?,
        threshold: Decimal = SwapReworkConfig.priceMoveThreshold
    ) -> SwapPriceMove {
        guard let acknowledged, let current, acknowledged > 0, current > 0 else { return .unchanged }
        let change = (current - acknowledged) / acknowledged
        if change > 0 { return .improved(change: change) }
        let drop = -change
        return drop > threshold ? .worsened(change: drop) : .unchanged
    }

    var needsConfirmation: Bool {
        if case .worsened = self { return true }
        return false
    }

    /// "0.40%"
    var changeText: String {
        switch self {
        case .unchanged:
            return "0.00%"
        case .improved(let change), .worsened(let change):
            return SwapFeeBreakdown.percent(bps: NSDecimalNumber(decimal: (change * 10_000).rounded(scale: 0)).intValue)
        }
    }
}
