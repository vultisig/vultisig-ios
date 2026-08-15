//
//  LimitSwapValidation.swift
//  VultisigApp
//

import Foundation

/// - Parameter maxExpiryBlocks: the ceiling THORChain currently enforces, read
///   from the `StreamingLimitSwapMaxAge` mimir by the caller. Injected rather
///   than read here so this stays pure — and so a raised cap widens the accepted
///   range on its own instead of being rejected by a stale constant.
func validateLimitSwapInputs(
    _ inputs: LimitSwapInputs,
    maxExpiryBlocks: Int = THORChainConstants.defaultLimitSwapMaxAgeBlocks
) -> [LimitSwapValidationError] {
    var errors: [LimitSwapValidationError] = []

    if inputs.sourceAmount <= 0 {
        errors.append(.sourceAmountNotPositive)
    }
    if inputs.targetPrice <= 0 {
        errors.append(.targetPriceNotPositive)
    }
    // A RANGE, not the old three-value whitelist: the expiry is now a duration
    // the user picks, so anything the protocol will honour is valid. The ceiling
    // is THORChain's (silently clamped on-chain, so rejecting here is what keeps
    // the memo honest); the floor is ours (see `minLimitSwapAgeBlocks`).
    //
    // The floor comes from the SAME helper the clamp uses. Spelled out separately
    // the two disagreed when a ceiling landed below the app floor: the clamp
    // produced the ceiling and this then rejected it, making every expiry
    // unplaceable.
    let minBlocks = effectiveMinExpiryBlocks(maxBlocks: maxExpiryBlocks)
    if inputs.expiryBlocks < minBlocks || inputs.expiryBlocks > maxExpiryBlocks {
        errors.append(.expiryOutOfRange(
            blocks: inputs.expiryBlocks,
            minBlocks: minBlocks,
            maxBlocks: maxExpiryBlocks
        ))
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
    if inputs.sourceAsset.caseInsensitiveCompare(inputs.targetAsset) == .orderedSame {
        // Swapping an asset for itself is impossible on THORChain — it refunds
        // the deposit minus the network fee. The picker's swap-on-collision and
        // the default-source seeding avoid this, but a single-asset vault can
        // still reach here; reject before building the memo.
        errors.append(.sourceEqualsTarget(inputs.sourceAsset))
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
