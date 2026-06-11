//
//  LimitMath.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Scales `targetPrice` to THORChain's 1e8 fixed-point and derives the LIM
/// (minimum amount out) for the memo.
///
/// **Fund-safety: overflow MUST fail loud.** If `targetPrice` is large enough
/// that scaling it by 1e8 overflows `Decimal` (max ~1e127), the multiply yields
/// a `Decimal` NaN whose `stringValue` is `"NaN"`. `BigInt("NaN")` is `nil`. A
/// silent `?? 0` fallback would emit `LIM=0` in the memo, which THORChain reads
/// as "fill at ANY price" — the exact opposite of a limit order. We throw
/// `LimitSwapMemoError.targetPriceOverflow` instead so the place-order flow
/// surfaces the error rather than placing a price-blind swap.
func computeLim(sourceAmount: BigInt, sourceDecimals: Int, targetPrice: Decimal) throws -> BigInt {
    var price = targetPrice
    var scaled = Decimal()
    NSDecimalMultiplyByPowerOf10(&scaled, &price, 8, .plain)

    var truncated = Decimal()
    NSDecimalRound(&truncated, &scaled, 0, .down)

    // `Decimal.isNaN` catches an overflowed multiply; the explicit BigInt parse
    // guard is belt-and-suspenders for any other unrepresentable result.
    guard !truncated.isNaN,
          let priceBig = BigInt(NSDecimalNumber(decimal: truncated).stringValue) else {
        throw LimitSwapMemoError.targetPriceOverflow
    }
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
