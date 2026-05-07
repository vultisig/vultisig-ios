//
//  LimitSwapValidation.swift
//  VultisigApp
//

import Foundation

func validateLimitSwapInputs(_ inputs: LimitSwapInputs) -> [LimitSwapValidationError] {
    var errors: [LimitSwapValidationError] = []

    if inputs.sourceAmount <= 0 {
        errors.append(.sourceAmountNotPositive)
    }
    if inputs.targetPrice <= 0 {
        errors.append(.targetPriceNotPositive)
    }
    if ![12, 24, 72].contains(inputs.expiryHours) {
        errors.append(.expiryHoursUnsupported(inputs.expiryHours))
    }
    if inputs.destAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errors.append(.destAddressEmpty)
    }
    if !isValidAssetFormat(inputs.sourceAsset) {
        errors.append(.sourceAssetMalformed(inputs.sourceAsset))
    }
    if !isValidAssetFormat(inputs.targetAsset) {
        errors.append(.targetAssetMalformed(inputs.targetAsset))
    }

    return errors
}

private func isValidAssetFormat(_ asset: String) -> Bool {
    // Asset memo strings are exactly two dot-separated parts: `<CHAIN>.<TICKER>`
    // for native and `<CHAIN>.<TICKER-SUFFIX>` for tokens (the dash sits inside
    // the second part, not as another separator). `BTC.BTC.EXTRA` should fail.
    let parts = asset.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    return !parts[0].isEmpty && !parts[1].isEmpty
}
