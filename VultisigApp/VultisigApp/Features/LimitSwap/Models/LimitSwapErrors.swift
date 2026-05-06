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

enum LimitSwapWarning: Equatable {
    case priceAtOrBelowMarket
    case priceFarAboveMarket
}
