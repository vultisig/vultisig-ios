//
//  LimitSwapMemoBuilder.swift
//  VultisigApp
//

import BigInt
import Foundation

/// - Throws: `LimitSwapMemoError.targetPriceOverflow` if `targetPrice` is too
///   large to scale into a valid LIM (see `computeLim`). Failing loud here
///   prevents a `LIM=0` ("fill at any price") memo from ever being built.
func buildLimitSwapMemo(_ inputs: LimitSwapInputs) throws -> String {
    let lim = try computeLim(
        sourceAmount: inputs.sourceAmount,
        sourceDecimals: inputs.sourceDecimals,
        targetPrice: inputs.targetPrice
    )
    let interval = computeExpiryBlocks(hours: inputs.expiryHours)

    return "=<:\(inputs.targetAsset):\(inputs.destAddress):\(lim)/\(interval)/0:\(inputs.affiliate):\(inputs.affiliateBps)"
}

/// Assert that a limit-swap memo fits the byte budget for its source chain.
///
/// **80-byte cap on UTXO source chains.** Bitcoin's `OP_RETURN` consensus rule
/// caps embedded data at 80 bytes. The same effective limit applies to the
/// other UTXO source chains we support: LTC, BCH, DOGE, DASH (all share
/// Bitcoin's `OP_RETURN` rule). `Cardano` is a separate `ChainType`
/// (Ed25519, not secp256k1 OP_RETURN) and is **not** subject to the 80B cap.
/// Non-UTXO chains have a 250-byte cap aligned with THORChain's memo length
/// limit.
///
/// **Decision: reject when the cap is exceeded.** Three fallbacks were
/// considered for the case where a Vultisig-affiliated limit memo overflows
/// 80 bytes on a UTXO source (a realistic scenario for token targets like
/// `ETH.USDC-EC7` or referred users with `myref/vi` + `10/35`):
///
/// - **(a) Drop the Vultisig affiliate fragment** when the memo is too long.
///   Loses attribution and revenue silently; the user signs a memo that
///   differs from what the UI showed; bad protocol incentive.
/// - **(b) Reject with a clear error (this implementation).** User-visible
///   failure; no silent affiliate revenue loss; the user can adjust inputs
///   (shorter destination address, different asset, switch to a non-UTXO
///   source).
/// - **(c) Downgrade referred → non-referred** so the memo fits. Hides intent
///   from the referrer; same silent-divergence problem as (a).
///
/// **Reject was chosen** because: (1) silent affiliate dropping has both
/// revenue and incentive problems; (2) the user has agency to adjust; (3) loud
/// failure surfaces the issue for fix or fallback in a future Phase. Changes
/// to this decision require deliberate review — not silent edits.
///
/// - Parameters:
///   - memo: The constructed limit-swap memo string (UTF-8 bytes are counted,
///     not Swift `Character` units).
///   - sourceChainKind: The source coin's `ChainType`. `.UTXO` gets the 80B
///     cap; everything else gets 250B.
/// - Throws: `LimitSwapMemoError.memoExceedsByteLimit(actual:limit:)` when
///   the memo's UTF-8 byte count exceeds the applicable cap.
func assertMemoByteLength(_ memo: String, sourceChainKind: ChainType) throws {
    let limit = (sourceChainKind == .UTXO) ? 80 : 250
    let actual = memo.utf8.count
    if actual > limit {
        throw LimitSwapMemoError.memoExceedsByteLimit(actual: actual, limit: limit)
    }
}
