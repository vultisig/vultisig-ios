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

    return "=<:\(inputs.targetAsset):\(inputs.destAddress):\(compressLim(lim))/\(interval)/0:\(inputs.affiliate):\(inputs.affiliateBps)"
}

/// Encode a LIM integer using THORChain's `<mantissa>e<exponent>` shorthand
/// (base-10: `mantissa` followed by `exponent` trailing zeros) when that is
/// **strictly shorter** than the plain decimal — otherwise the plain decimal.
/// This shrinks the signed memo to better fit tight budgets, most importantly
/// the 80-byte UTXO `OP_RETURN` cap.
///
/// **LOSSLESS.** The exponent is exactly the trailing-zero count, so the encoded
/// value equals the plain integer bit-for-bit. It never rounds, so it can never
/// round UP and never overstate the minimum-output guarantee (`compressLim(x)`
/// always decodes back to `x`). Verified against the protocol's own examples:
/// `1e8`=100000000, `51e7`=510000000, `544e6`=544000000.
///
/// Non-positive / trailing-zero-free LIMs (nothing to compress) return the plain
/// decimal unchanged, as does any value whose sci-form isn't strictly shorter
/// (e.g. `X00` → `Xe2` is the same length, so the plain form wins).
func compressLim(_ lim: BigInt) -> String {
    let plain = lim.description
    guard lim > 0 else { return plain }

    var mantissa = lim
    var exponent = 0
    let ten = BigInt(10)
    while mantissa % ten == 0 {
        mantissa /= ten
        exponent += 1
    }
    guard exponent > 0 else { return plain }

    let sci = "\(mantissa)e\(exponent)"
    return sci.count < plain.count ? sci : plain
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
