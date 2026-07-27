//
//  RippleIssuedCurrency.swift
//  VultisigApp
//

import BigInt
import Foundation

/// XRPL issued-currency (IOU) helpers, ported verbatim from the SDK
/// (`packages/core/chain/chains/ripple/issuedCurrency.ts`). Used by the
/// `signRipple` fail-closed binding to compare a dApp-supplied `Payment`
/// `Amount` object against the reviewed coin's token id and amount.
///
/// Every function is throwing. The signing binding treats any throw as an
/// amount mismatch (fail closed) rather than crashing the signer, so none of
/// these may trap: bad input becomes a rejected transaction, never a fatal.
enum RippleIssuedCurrency {

    enum ParseError: Error {
        case currencyCodeTooLong
        case invalidTokenId
        case invalidValue
        case exponentOutOfRange
        case decimalsOutOfRange
    }

    /// XRPL carries issued-currency amounts as a decimal value string with 15
    /// significant digits of precision. We normalize both sides of the
    /// fail-closed comparison into base units at this scale.
    static let issuedCurrencyDecimals = 15

    private static let standardCurrencyCodeLength = 3
    private static let hexCurrencyCodeLength = 40

    /// Bounds the base-10 shift applied while parsing a value string so an
    /// adversarial exponent (e.g. `1e999999999`) can't drive an unbounded
    /// BigInt power. XRPL issued-currency exponents live in roughly
    /// [-96, +80], so after trailing-zero normalization the shift for any real
    /// value stays well inside this window; anything outside it is not a valid
    /// XRPL amount and is rejected (→ mismatch, fail closed).
    private static let maxShiftMagnitude = 1024

    /// Caps the number of significant coefficient digits parsed from a value
    /// string, so an adversarial value can't build a giant BigInt (CPU/memory
    /// exhaustion) before failing closed. No real XRPL value approaches this
    /// (15 significant digits, at most ~96 written-out fraction/integer zeros);
    /// anything larger is rejected.
    private static let maxCoefficientDigits = 1024

    /// Guards `formatIssuedCurrencyValue` against a hostile `coin.decimals`
    /// (proto-relayed, so untrusted): negative would index out of bounds and an
    /// astronomically large value would try to allocate gigabytes of padding.
    /// No real coin approaches this; anything beyond it fails closed.
    private static let maxSupportedDecimals = 100

    private static func isAsciiHexDigit(_ char: Character) -> Bool {
        guard let ascii = char.asciiValue else { return false }
        return (ascii >= 0x30 && ascii <= 0x39) // 0-9
            || (ascii >= 0x41 && ascii <= 0x46) // A-F
            || (ascii >= 0x61 && ascii <= 0x66) // a-f
    }

    private static func isHexCurrencyCode(_ value: String) -> Bool {
        // UTF-16 count + ASCII-only hex mirrors the SDK's JS string-length and
        // `/^[0-9a-fA-F]{40}$/` semantics (a non-BMP char must not slip through
        // a grapheme count of 40).
        guard value.utf16.count == hexCurrencyCodeLength else { return false }
        return value.allSatisfy(isAsciiHexDigit)
    }

    /// ASCII bytes of `currency`, right-padded to 20 bytes, hex-encoded and
    /// uppercased. Throws when the code exceeds the 20-byte XRPL limit.
    private static func asciiToHexCurrencyCode(_ currency: String) throws -> String {
        let bytes = Array(currency.utf8)
        guard bytes.count <= 20 else { throw ParseError.currencyCodeTooLong }
        var padded = bytes
        padded.append(contentsOf: Array(repeating: 0, count: 20 - bytes.count))
        return padded.map { String(format: "%02x", $0) }.joined().uppercased()
    }

    /// Normalize a ticker / currency code to its on-ledger representation: a
    /// 3-character standard code is returned as-is, a 40-char hex code is
    /// uppercased, anything else is ASCII-encoded to the 40-char hex form.
    static func toXrplCurrencyCode(_ currency: String) throws -> String {
        let value = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.utf16.count == standardCurrencyCodeLength {
            return value
        }
        if isHexCurrencyCode(value) {
            return value.uppercased()
        }
        return try asciiToHexCurrencyCode(value)
    }

    /// Printable-ASCII window used to decide whether a decoded hex currency code
    /// is a human-readable ticker.
    private static let printableAscii: ClosedRange<UInt8> = 0x20...0x7E

    /// Human-readable ticker for an on-ledger currency code.
    ///
    /// A 3-character standard code (`USD`) is already a ticker. The 40-char
    /// (160-bit) form encodes ASCII right-padded with NUL bytes, so decoding it
    /// recovers the ticker a user recognizes (`524C555344…00` → `RLUSD`). A hex
    /// code whose bytes are not all printable ASCII is not a ticker at all — an
    /// arbitrary 160-bit code, or one of the reserved `0x00`-prefixed forms — so
    /// the hex is kept verbatim rather than rendered as mojibake.
    ///
    /// Unlike the SDK's Node `ascii` decode, a byte with the high bit set is NOT
    /// masked down into the ASCII range: an arbitrary code must stay hex rather
    /// than be dressed up as a plausible ticker.
    static func toIssuedCurrencyTicker(_ currency: String) -> String {
        guard isHexCurrencyCode(currency), let bytes = hexBytes(currency) else {
            return currency
        }
        var decoded = bytes
        while decoded.last == 0 { decoded.removeLast() }
        guard !decoded.isEmpty,
              decoded.allSatisfy({ printableAscii.contains($0) }),
              let ticker = String(bytes: decoded, encoding: .utf8) else {
            return currency
        }
        return ticker
    }

    /// Raw bytes of a hex string. Returns `nil` on an odd length or a non-hex
    /// digit; callers pass a code already validated by `isHexCurrencyCode`.
    private static func hexBytes(_ hex: String) -> [UInt8]? {
        let characters = Array(hex)
        guard characters.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        for index in stride(from: 0, to: characters.count, by: 2) {
            guard let byte = UInt8(String(characters[index...index + 1]), radix: 16) else {
                return nil
            }
            bytes.append(byte)
        }
        return bytes
    }

    /// Composite identifier for an XRPL issued currency: `<currencyCode>.<issuer>`.
    /// XRPL keys tokens by the (currency, issuer) pair rather than by a single
    /// contract address, so both are encoded into `Coin.contractAddress`. Inverse
    /// of `parseRippleTokenId`.
    static func rippleTokenId(currency: String, issuer: String) throws -> String {
        let code = try toXrplCurrencyCode(currency)
        return "\(code).\(issuer)"
    }

    /// Split a `"<currencyCode>.<issuer>"` Ripple token id into its parts.
    /// Throws when the separator is missing, leading, or trailing.
    static func parseRippleTokenId(_ id: String) throws -> (currency: String, issuer: String) {
        guard let separatorIndex = id.firstIndex(of: ".") else {
            throw ParseError.invalidTokenId
        }
        let currency = String(id[id.startIndex..<separatorIndex])
        let issuer = String(id[id.index(after: separatorIndex)...])
        guard !currency.isEmpty, !issuer.isEmpty else {
            throw ParseError.invalidTokenId
        }
        return (currency, issuer)
    }

    /// Render `amount` base units (at `decimals`) as a trimmed XRPL value
    /// string. Mirror of the SDK `formatIssuedCurrencyValue`. Throws (rather
    /// than trapping) on a hostile `decimals` so the fail-closed caller treats
    /// it as a mismatch.
    static func formatIssuedCurrencyValue(amount: BigInt, decimals: Int) throws -> String {
        guard decimals >= 0, decimals <= maxSupportedDecimals else {
            throw ParseError.decimalsOutOfRange
        }
        let negative = amount < 0
        let magnitudeDigits = String((negative ? -amount : amount))
        let padWidth = decimals + 1
        let digits = magnitudeDigits.count >= padWidth
            ? magnitudeDigits
            : String(repeating: "0", count: padWidth - magnitudeDigits.count) + magnitudeDigits

        let splitIndex = digits.index(digits.endIndex, offsetBy: -decimals)
        let intPartRaw = String(digits[digits.startIndex..<splitIndex])
        let intPart = intPartRaw.isEmpty ? "0" : intPartRaw

        var fracPart = ""
        if decimals > 0 {
            var frac = String(digits[splitIndex...])
            while frac.hasSuffix("0") { frac.removeLast() }
            fracPart = frac
        }

        let magnitude = fracPart.isEmpty ? intPart : "\(intPart).\(fracPart)"
        return negative && magnitude != "0" ? "-\(magnitude)" : magnitude
    }

    /// Parse an XRPL value string into base units at `issuedCurrencyDecimals`
    /// (15). Truncates toward zero, never rounds. Mirror of the SDK
    /// `parseIssuedCurrencyValue`; throws on malformed input or an
    /// out-of-range exponent.
    static func parseIssuedCurrencyValue(_ value: String) throws -> BigInt {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = "^([+-]?)([0-9]+)(?:\\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            throw ParseError.invalidValue
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range) else {
            throw ParseError.invalidValue
        }

        func group(_ index: Int) -> String {
            guard let r = Range(match.range(at: index), in: trimmed) else { return "" }
            return String(trimmed[r])
        }

        let sign = group(1)
        let intPart = group(2)
        // Trailing fraction zeros don't change the value; dropping them keeps
        // the base-10 shift small, so a zero-padded spelling (e.g. "1.000…0")
        // stays within the safety bound instead of being false-rejected.
        var fracPart = group(3)
        while fracPart.hasSuffix("0") { fracPart.removeLast() }
        let exponentString = group(4)

        // Cap the coefficient length before building any BigInt, so an
        // adversarial value (e.g. a million-digit coefficient) can't exhaust
        // CPU/memory before the checks below fail it closed.
        guard intPart.count + fracPart.count <= maxCoefficientDigits else {
            throw ParseError.invalidValue
        }

        // Validate the exponent and shift BEFORE the zero short-circuit, so an
        // out-of-range exponent is rejected even for a zero coefficient (e.g.
        // "0e999999" fails closed rather than passing as zero). Bound WITHOUT
        // `abs` (which would trap on Int.min) and reject an exponent that
        // doesn't fit in Int, so the shift arithmetic can't overflow.
        let exponent: Int
        if exponentString.isEmpty {
            exponent = 0
        } else {
            guard let parsed = Int(exponentString),
                  parsed >= -maxShiftMagnitude, parsed <= maxShiftMagnitude else {
                throw ParseError.exponentOutOfRange
            }
            exponent = parsed
        }

        // exponent is bounded and fracPart is normalized (short), so this
        // subtraction cannot overflow.
        let shift = exponent - fracPart.count + issuedCurrencyDecimals
        guard shift >= -maxShiftMagnitude, shift <= maxShiftMagnitude else {
            throw ParseError.exponentOutOfRange
        }

        guard let digits = BigInt(intPart + fracPart) else { throw ParseError.invalidValue }
        // A zero coefficient is zero at any scale — short-circuit before
        // computing any power (the exponent is already validated above).
        if digits == 0 { return 0 }

        let magnitude: BigInt = shift >= 0
            ? digits * BigInt(10).power(shift)
            : digits / BigInt(10).power(-shift)

        return sign == "-" ? -magnitude : magnitude
    }
}
