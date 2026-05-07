//
//  LimitSwapErrors.swift
//  VultisigApp
//

import Foundation

enum LimitSwapValidationError: Error, Equatable {
    case sourceAmountNotPositive
    case targetPriceNotPositive
    case expiryHoursUnsupported(Int)
    case destAddressEmpty
    case sourceAssetMalformed(String)
    case targetAssetMalformed(String)
}

enum LimitSwapMemoError: Error, Equatable {
    case memoExceedsByteLimit(actual: Int, limit: Int)
}

enum LimitSwapQuoteError: Error, Equatable {
    /// THORChain returned an `expected_amount_out` that didn't parse as Decimal.
    case invalidExpectedAmount(String)
    /// The source amount couldn't be expressed as Decimal — typically a
    /// programmer error (BigInt → string round-trip should always succeed).
    case invalidSourceAmount(String)
    /// Source amount resolved to zero in natural units; no quote is meaningful.
    case zeroSourceAmount
}

enum LimitSwapWarning: Equatable {
    case priceAtOrBelowMarket
    case priceFarAboveMarket
}
