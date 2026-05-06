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
    if inputs.destAddress.trimmingCharacters(in: .whitespaces).isEmpty {
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
    let parts = asset.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    return !parts[0].isEmpty && !parts[1].isEmpty
}
