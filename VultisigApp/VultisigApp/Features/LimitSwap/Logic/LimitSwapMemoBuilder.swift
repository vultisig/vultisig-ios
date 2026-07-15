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
    return composeLimitSwapMemo(limString: compressLim(lim), inputs: inputs, interval: interval)
}

/// Assemble the `=<` memo string from a (pre-formatted) LIM field and the order
/// inputs. Single source of the wire layout so the exact-precision path and the
/// byte-fitting path (`buildFittedLimitSwapMemo`) can't drift.
private func composeLimitSwapMemo(limString: String, inputs: LimitSwapInputs, interval: Int) -> String {
    "=<:\(inputs.targetAsset):\(inputs.destAddress):\(limString)/\(interval)/0:\(inputs.affiliate):\(inputs.affiliateBps)"
}

/// Maximum the minimum-output (LIM) may be rounded UP to make an over-long memo
/// fit its source-chain byte budget, in basis points. 50 bps = 0.5%. Rounding
/// UP only ever RAISES the guaranteed floor, so the user can never receive less
/// than their target — the order just needs a fractionally better price to fill.
let limitLimRoundingMaxBps = 50

/// Per-tx memo byte budget for a limit deposit on a given source chain. UTXO
/// chains cap `OP_RETURN` at 80 bytes; everything else aligns with THORChain's
/// 250-byte memo limit. Single source shared by `assertMemoByteLength` and the
/// byte-fitting builder.
func limitMemoByteLimit(for sourceChainKind: ChainType) -> Int {
    (sourceChainKind == .UTXO) ? 80 : 250
}

/// Build the `=<` memo, shrinking it to fit the source chain's byte budget when
/// the exact-precision memo overflows (only bites for UTXO sources at 80 bytes —
/// a 42-char L2 destination + a referral affiliate tail + a non-round LIM).
///
/// The ONLY field with slack is the LIM, and `compressLim` is lossless so it
/// can't shrink a precise value. So when the exact memo overflows, the LIM is
/// rounded UP to progressively fewer significant figures (which gives it trailing
/// zeros that `compressLim` collapses to `111e6`-style) until the memo fits —
/// bounded by `limitLimRoundingMaxBps`. Rounding UP is the safe direction: it can
/// only RAISE the minimum-output floor, so the user never receives less than
/// their target (the order may just fill at a fractionally better price, or not
/// at all — never worse). Returns the memo AND the effective LIM actually
/// encoded, so the Verify/Done "min payout" display and the signed order agree
/// exactly (what you see is what you sign).
///
/// Throws `LimitSwapMemoError.memoExceedsByteLimit` when not even the
/// tolerance-bounded rounding fits — the caller surfaces the clear error rather
/// than silently over-rounding the price.
func buildFittedLimitSwapMemo(
    _ inputs: LimitSwapInputs,
    sourceChainKind: ChainType
) throws -> (memo: String, effectiveLim: BigInt) {
    let lim = try computeLim(
        sourceAmount: inputs.sourceAmount,
        sourceDecimals: inputs.sourceDecimals,
        targetPrice: inputs.targetPrice
    )
    let interval = computeExpiryBlocks(hours: inputs.expiryHours)
    let limit = limitMemoByteLimit(for: sourceChainKind)

    // Common case: the exact (lossless) memo already fits — no rounding.
    let exactMemo = composeLimitSwapMemo(limString: compressLim(lim), inputs: inputs, interval: interval)
    if exactMemo.utf8.count <= limit {
        return (exactMemo, lim)
    }

    // Overflow: round the LIM UP to the fewest significant figures that fit,
    // within the tolerance cap. Iterate most-precise → coarsest; the first fit is
    // the least rounding. Stop once the rounding would exceed the tolerance
    // (it only grows as precision drops).
    let digits = lim.description.count
    for significantFigures in stride(from: digits - 1, through: 1, by: -1) {
        let rounded = roundUpToSignificantFigures(lim, significantFigures: significantFigures)
        // (rounded - lim) / lim <= maxBps / 10_000, as integers.
        if (rounded - lim) * 10_000 > lim * BigInt(limitLimRoundingMaxBps) {
            break
        }
        let candidate = composeLimitSwapMemo(limString: compressLim(rounded), inputs: inputs, interval: interval)
        if candidate.utf8.count <= limit {
            return (candidate, rounded)
        }
    }

    throw LimitSwapMemoError.memoExceedsByteLimit(actual: exactMemo.utf8.count, limit: limit)
}

/// Round `value` UP to `significantFigures` significant digits (i.e. toward
/// +infinity), producing a value with trailing zeros. Used to make a LIM
/// `compressLim`-friendly when a memo must be shortened. A no-op when
/// `significantFigures` already covers every digit or the value is non-positive.
func roundUpToSignificantFigures(_ value: BigInt, significantFigures: Int) -> BigInt {
    guard value > 0, significantFigures >= 1 else { return value }
    let digits = value.description.count
    guard significantFigures < digits else { return value }
    let factor = BigInt(10).power(digits - significantFigures)
    let (quotient, remainder) = value.quotientAndRemainder(dividingBy: factor)
    let rounded = remainder == 0 ? quotient : quotient + 1
    return rounded * factor
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
    let limit = limitMemoByteLimit(for: sourceChainKind)
    let actual = memo.utf8.count
    if actual > limit {
        throw LimitSwapMemoError.memoExceedsByteLimit(actual: actual, limit: limit)
    }
}
