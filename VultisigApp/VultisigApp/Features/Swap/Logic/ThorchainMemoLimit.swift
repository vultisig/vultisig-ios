//
//  ThorchainMemoLimit.swift
//  VultisigApp
//
//  Shrinks the minimum-output floor (`LIM`) inside a node-returned THORChain /
//  Maya swap memo into scientific notation so a large UTXO swap's memo fits its
//  source chain's `OP_RETURN` byte cap. THORChain and Maya both parse
//  `<mantissa>e<exponent>` (mantissa followed by `exponent` trailing zeros) in
//  the LIM field at execution, so rewriting the memo before signing keeps the
//  floor on every route without changing what the chain reads.
//
//  Rounding is always DOWN. For a market swap a lower floor is strictly more
//  permissive: it can never wrongfully reject a fillable swap, only accept one
//  at a fractionally worse price. (This is the opposite direction from
//  `LimitSwapMemoBuilder`, which rounds a limit order's LIM UP — there raising
//  the floor is the safe direction because the user must never receive less
//  than their resting target.)
//

import BigInt
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "thorchain-memo-limit")

enum ThorchainMemoLimit {

    /// Never round the floor to fewer than this many significant digits. 5 sig
    /// figs is a ~0.001% precision loss on the LIM — negligible against the 1%
    /// liquidity tolerance the floor already carries.
    private static let minSignificantDigits = 5

    /// The UTF-8 byte budget a chain's THORChain / Maya swap memo must fit, or
    /// `nil` when the source chain carries no such cap.
    ///
    /// UTXO sources embed the memo in an 80-byte `OP_RETURN` (Bitcoin's consensus
    /// data cap, shared by LTC / BCH / DOGE / DASH / ZEC). Every other source
    /// (EVM via a contract call, Cosmos / THORChain via `MsgDeposit`) has no
    /// 80-byte constraint, so no compression is applied there.
    static func memoByteLimit(for chain: Chain) -> Int? {
        chain.chainType == .UTXO ? 80 : nil
    }

    /// Rewrites the LIM field of a THORChain / Maya swap memo into scientific
    /// notation so the whole memo fits `maxBytes`, rounding the floor DOWN.
    ///
    /// Returns `memo` unchanged — byte-for-byte — when any of the following hold,
    /// so a memo we don't fully understand or don't need to touch is never
    /// corrupted:
    /// - `maxBytes` is `nil` (source chain has no memo cap), or
    /// - the memo already fits `maxBytes` (compress only on overflow), or
    /// - the memo isn't a recognised swap shape (fewer than 4 `:`-fields), or
    /// - the LIM isn't a canonical positive integer (no floor, or already
    ///   scientific / signed / zero-padded), or
    /// - even the 5-significant-digit floor still overflows `maxBytes`.
    ///
    /// Every non-LIM field (function, asset, destination, streaming interval and
    /// quantity, affiliate, fee) is preserved verbatim.
    static func compressed(_ memo: String, maxBytes: Int?) -> String {
        guard let maxBytes else { return memo }
        guard memo.utf8.count > maxBytes else { return memo }

        // THORChain swap memo: `=:ASSET:DEST:LIM/INTERVAL/QUANTITY:AFFILIATE:FEE`.
        // Keep empty subsequences so `joined(separator: ":")` round-trips the
        // input exactly when we haven't touched a field.
        var fields = memo.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        let limFieldIndex = 3
        guard fields.count > limFieldIndex else { return memo }

        // The LIM is the amount before the first `/` in the streaming triple
        // `LIM/INTERVAL/QUANTITY`; the `/INTERVAL/QUANTITY` remainder (if any)
        // travels untouched.
        let limField = fields[limFieldIndex]
        let limString: String
        let limSuffix: String
        if let slashIndex = limField.firstIndex(of: "/") {
            limString = String(limField[..<slashIndex])
            limSuffix = String(limField[slashIndex...])
        } else {
            limString = limField
            limSuffix = ""
        }

        // Only compress a floor we can round exactly: a canonical positive
        // integer. `String(limValue) == limString` rejects a sign, zero-padding,
        // or an already-scientific mantissa; `limValue > 0` skips a "0" (no
        // floor — nothing to compress).
        guard let limValue = BigInt(limString), limValue > 0, String(limValue) == limString else {
            return memo
        }

        let totalDigits = limString.count
        guard totalDigits > minSignificantDigits else { return memo }

        // Keep as many significant digits as still fit — a tighter floor is both
        // safe (still ≤ the original) and more protective — down to the 5-digit
        // floor. Memo length is non-decreasing in `keptDigits`, so the first fit
        // scanning from most-precise is the largest that fits.
        for keptDigits in stride(from: totalDigits - 1, through: minSignificantDigits, by: -1) {
            let droppedDigits = totalDigits - keptDigits
            let scale = BigInt(10).power(droppedDigits)
            let truncated = limValue / scale // integer division rounds DOWN
            fields[limFieldIndex] = "\(truncated)e\(droppedDigits)" + limSuffix
            let candidate = fields.joined(separator: ":")
            if candidate.utf8.count <= maxBytes {
                return candidate
            }
        }

        // Even the 5-significant-digit floor overflows `maxBytes` — not expected
        // for a realistic base-1e8 LIM. Leave the memo for the caller rather than
        // emit one we know is over the cap.
        logger.debug("THORChain swap memo LIM could not be compressed within \(maxBytes) bytes; leaving memo unchanged")
        return memo
    }
}
