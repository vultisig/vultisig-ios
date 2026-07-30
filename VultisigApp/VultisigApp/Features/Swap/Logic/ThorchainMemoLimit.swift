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

private let logger = Log.swap.other

enum ThorchainMemoLimit {

    /// Never round the floor to fewer than this many significant digits. 5 sig
    /// figs is a ~0.001% precision loss on the LIM — negligible against the 1%
    /// liquidity tolerance the floor already carries.
    private static let minSignificantDigits = 5

    /// Largest `e<exponent>` a LIM may carry before it is treated as unreadable.
    /// `compressed` never emits more than the digit count of a base-1e8 amount,
    /// and a node-returned LIM is a plain integer, so anything beyond this is a
    /// memo we don't understand — and expanding it would mean raising 10 to an
    /// attacker-chosen power.
    private static let maxLimitExponent = 64

    /// THORNode parses the LIM as a `cosmos.Uint` and rejects a memo whose value
    /// does not fit 256 bits. A wider number is therefore a memo the chain will
    /// refuse outright — no swap, no floor — so we must not read a guarantee out
    /// of it. Exclusive upper bound.
    private static let limitUpperBound = BigInt(2).power(256)

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

    /// The memo a THORChain / Maya swap out of `sourceChain` is actually signed
    /// with: the node's memo after whatever `OP_RETURN` compression this app
    /// applies on the way to the signer. One definition so the payload builder
    /// and the verify/co-sign display can never disagree about what gets signed.
    static func signedMemo(_ memo: String, sourceChain: Chain) -> String {
        compressed(memo, maxBytes: memoByteLimit(for: sourceChain))
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

    /// THORChain and MayaChain both spell the swap action `SWAP`, `=` or `s`,
    /// case-insensitively. Every other action (`ADD`, `WITHDRAW`, `DONATE`,
    /// `LOAN+`, …) lays its fields out differently, so its 4th field is not a
    /// `LIM/INTERVAL/QUANTITY` triple and must not be read as one.
    static func isSwapAction(_ field: some StringProtocol) -> Bool {
        switch field.lowercased() {
        case "swap", "=", "s":
            return true
        default:
            return false
        }
    }

    /// The minimum output a THORChain / Maya swap memo asserts (`LIM`), in the
    /// node's own base units — the same units as `expected_amount_out`.
    ///
    /// Read this off the memo that will actually be **signed**, not off
    /// `quote.memo`: for a UTXO source `compressed(_:maxBytes:)` rewrites the
    /// floor into `<mantissa>e<exponent>` and rounds it DOWN, so the quote's memo
    /// overstates what the chain will enforce. Both spellings are accepted here
    /// for that reason — the plain integer the node returns, and the scientific
    /// form we may have substituted.
    ///
    /// Returns `nil` — never a guess — when the memo is not a swap memo, when any
    /// term of the `LIM/INTERVAL/QUANTITY` triple is not something we can read,
    /// or when the floor is `0` (a swap that asserts no minimum, which is what a
    /// user-set 0% slippage produces). Callers must then show no minimum at all
    /// rather than a number the signed transaction does not back.
    static func assertedLimit(in memo: String) -> BigInt? {
        let fields = memo.split(separator: ":", omittingEmptySubsequences: false)
        guard fields.count >= 4, isSwapAction(fields[0]) else { return nil }

        // All-or-nothing on the whole triple, matching the sibling parser that
        // feeds the proto. THORNode reads `LIM/INTERVAL/QUANTITY` as one field
        // and rejects the memo outright if any term is malformed — so a LIM
        // salvaged from a triple we could not fully read is a floor the chain
        // would never get as far as enforcing.
        let terms = fields[3].split(separator: "/", omittingEmptySubsequences: false)
        guard let limTerm = terms.first, terms.count <= 3 else { return nil }
        // Only the LIM is ever rewritten into scientific notation; the streaming
        // terms are plain integers in both the node's spelling and our own.
        guard terms.dropFirst().allSatisfy({ isCanonicalDigits($0) }) else { return nil }

        guard let limit = parseLimitTerm(limTerm), limit > 0 else { return nil }
        return limit
    }

    /// `1234` or `1234e5` (mantissa followed by `exponent` trailing zeros) — the
    /// only two spellings a LIM we are willing to vouch for can take. ASCII
    /// digits only: `Character.isNumber` alone also accepts non-ASCII numerals
    /// and fractions, which `BigInt` would then read as something the node never
    /// wrote. Values wider than the node's own `cosmos.Uint` are refused too.
    private static func parseLimitTerm(_ term: some StringProtocol) -> BigInt? {
        let parts = term.split(separator: "e", omittingEmptySubsequences: false)
        guard let mantissaText = parts.first, isCanonicalDigits(mantissaText),
              let mantissa = BigInt(String(mantissaText)) else {
            return nil
        }

        let value: BigInt
        switch parts.count {
        case 1:
            value = mantissa
        case 2:
            guard isCanonicalDigits(parts[1]),
                  let exponent = Int(parts[1]), exponent <= maxLimitExponent else {
                return nil
            }
            value = mantissa * BigInt(10).power(exponent)
        default:
            return nil
        }

        guard value < limitUpperBound else { return nil }
        return value
    }

    private static func isCanonicalDigits(_ text: some StringProtocol) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
