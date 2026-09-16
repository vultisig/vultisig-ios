//
//  SwapPayoutModel.swift
//  VultisigApp
//

import Foundation

struct SwapPayoutModel: Equatable {
    /// Destination units per source unit, gross of fees.
    let rate: Decimal
    /// Share of the gross output withheld by fees that scale with trade size.
    let proportionalFeeFraction: Decimal
    /// Destination units withheld regardless of trade size.
    let flatFee: Decimal

    /// Above this the quote is unreadable; caller falls back to spot.
    static let implausibleProportionalFeeFraction: Decimal = 0.5

    static func fit(quote: SwapQuote, fromAmount: Decimal, toCoin: Coin) -> SwapPayoutModel? {
        guard fromAmount > 0 else { return nil }
        let output = SwapCryptoLogic.toAmountDecimal(quote: quote, toCoin: toCoin)
        guard output > 0 else { return nil }

        switch quote {
        case let .thorchain(native),
             let .thorchainChainnet(native),
             let .thorchainStagenet(native),
             let .mayachain(native):
            guard
                let total = Decimal(string: native.fees.total),
                let outbound = Decimal(string: native.fees.outbound),
                total >= 0, outbound >= 0, outbound <= total
            else { return nil }
            let multiplier = toCoin.thorswapMultiplier
            let gross = output + total / multiplier
            let proportionalFeeFraction = (total - outbound) / multiplier / gross
            guard proportionalFeeFraction < implausibleProportionalFeeFraction else { return nil }
            return SwapPayoutModel(
                rate: gross / fromAmount,
                proportionalFeeFraction: proportionalFeeFraction,
                flatFee: outbound / multiplier
            )
        case .oneinch, .kyberswap, .lifi, .jupiter, .swapkit:
            return SwapPayoutModel(rate: output / fromAmount, proportionalFeeFraction: 0, flatFee: 0)
        }
    }

    /// Exact at the fitted amount; floored at zero below the flat fee.
    func estimate(fromAmount: Decimal) -> Decimal {
        max(fromAmount * rate * (1 - proportionalFeeFraction) - flatFee, 0)
    }
}
