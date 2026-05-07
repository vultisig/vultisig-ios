//
//  LimitMath.swift
//  VultisigApp
//

import BigInt
import Foundation

func computeLim(sourceAmount: BigInt, sourceDecimals: Int, targetPrice: Decimal) -> BigInt {
    var price = targetPrice
    var scaled = Decimal()
    NSDecimalMultiplyByPowerOf10(&scaled, &price, 8, .plain)

    var truncated = Decimal()
    NSDecimalRound(&truncated, &scaled, 0, .down)

    let priceBig = BigInt(NSDecimalNumber(decimal: truncated).stringValue) ?? 0
    let denominator = BigInt(10).power(sourceDecimals)
    return (sourceAmount * priceBig) / denominator
}

func computeExpiryBlocks(hours: Int) -> Int {
    return THORChainConstants.blocks(forHours: hours)
}

func computePresetPrice(marketPrice: Decimal, pctAboveMarket pct: Int) -> Decimal {
    let multiplier = (Decimal(100) + Decimal(pct)) / Decimal(100)
    return marketPrice * multiplier
}

func computePctFromMarket(targetPrice: Decimal, marketPrice: Decimal) -> Decimal {
    guard marketPrice != 0 else { return 0 }
    return (targetPrice - marketPrice) / marketPrice * Decimal(100)
}

func evaluateWarning(targetPrice: Decimal, marketPrice: Decimal) -> LimitSwapWarning? {
    if targetPrice <= marketPrice {
        return .priceAtOrBelowMarket
    }
    let upperBound = marketPrice * Decimal(12) / Decimal(10)
    if targetPrice > upperBound {
        return .priceFarAboveMarket
    }
    return nil
}
