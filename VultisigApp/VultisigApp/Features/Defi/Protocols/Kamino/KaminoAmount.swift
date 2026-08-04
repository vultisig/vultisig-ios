//
//  KaminoAmount.swift
//  VultisigApp
//

import BigInt
import Foundation

/// Locale-independent parsing for Kamino's numeric JSON, which arrives as decimal
/// strings (`"0.03994268764493801732"`, `"1.0536041812651029025"`).
///
/// `String.toDecimal()` is deliberately NOT used on these. It routes through
/// `NumberFormatter`, which is Double-backed — so a 20-significant-digit rate
/// truncates to ~16 — and locale-sensitive: on a `de_DE` device `"1.0536"` parses
/// as one thousand and change, because `.` reads as a grouping separator. Both
/// failure modes are silent and both mis-price a position.
///
/// What this guarantees: the *format* is validated, so grouping separators,
/// exponents and whitespace are rejected rather than coerced. What it does not
/// guarantee is exactness — `Decimal` holds 38 significant digits and Kamino
/// publishes longer values (`prevAum` runs past 50). That is acceptable for the
/// display values this is used on (APY, PnL, prices). Anything that sizes a
/// transaction must use `KaminoRate`, which is exact.
enum KaminoDecimal {

    private static let posix = Locale(identifier: "en_US_POSIX")

    static func parse(_ raw: String) -> Decimal? {
        guard isPlainDecimal(raw) else { return nil }
        return Decimal(string: raw, locale: posix)
    }

    /// Validates the character set and shape: optional leading `-`, digits, at
    /// most one `.`, at least one digit.
    static func isPlainDecimal(_ raw: String) -> Bool {
        guard !raw.isEmpty else { return false }

        var hasDigit = false
        var hasSeparator = false
        for (index, character) in raw.enumerated() {
            switch character {
            case "-":
                guard index == 0 else { return false }
            case ".":
                guard !hasSeparator else { return false }
                hasSeparator = true
            default:
                guard character.isASCII, character.isNumber else { return false }
                hasDigit = true
            }
        }
        return hasDigit
    }

    /// Renders an integral `Decimal` as plain digits under a fixed POSIX locale,
    /// so the separator can never follow the device locale.
    static func integralString(_ value: Decimal) -> String {
        var copy = value
        return NSDecimalString(&copy, posix)
    }
}

/// An exact decimal value from the API, held as `numerator / 10^scale`.
///
/// This exists because `Decimal` arithmetic rounds. A share rate drives how many
/// shares a withdraw burns, and the API does not validate amounts — it rewrites
/// an over-sized withdraw to `u64::MAX`, meaning *withdraw everything*. A
/// division that rounded up at the 38th significant digit could therefore turn a
/// partial withdraw into a full exit. Integer arithmetic removes the question.
struct KaminoRate: Hashable {
    let numerator: BigInt
    /// Denominator exponent: the value is `numerator / 10^scale`.
    let scale: Int

    /// Parses Kamino's decimal-string form exactly, with no intermediate binary
    /// or `Decimal` representation.
    init?(apiString raw: String) {
        guard KaminoDecimal.isPlainDecimal(raw) else { return nil }

        let parts = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let whole = String(parts[0])
        let fraction = parts.count > 1 ? String(parts[1]) : ""

        guard let numerator = BigInt(whole + fraction) else { return nil }
        self.numerator = numerator
        self.scale = fraction.count
    }

    var isPositive: Bool { numerator > 0 }

    /// Display-only projection. Loses precision past 38 significant digits, which
    /// is why conversions never go through it.
    var decimalValue: Decimal? {
        KaminoDecimal.parse(apiStringValue)
    }

    private var apiStringValue: String {
        KaminoBaseUnits.render(baseUnits: numerator, decimals: scale)
    }
}

/// Rendering and scaling helpers shared by the amount types.
enum KaminoBaseUnits {

    /// Solana instruction arguments are `u64`; anything above that cannot be
    /// expressed on-chain regardless of what the API would accept.
    static let maxBaseUnits = BigInt(UInt64.max)

    /// Widest decimal scale we are willing to handle. SPL mints are a `u8`, but
    /// nothing legitimate approaches this, and an absurd scale would make the
    /// `10^decimals` factors below unbounded.
    static let maxDecimals = 18

    /// Renders base units as a plain human-units decimal string: no grouping, no
    /// trailing zeros, no exponent.
    static func render(baseUnits: BigInt, decimals: Int) -> String {
        let isNegative = baseUnits.sign == .minus
        let digits = String(baseUnits.magnitude)
        guard decimals > 0 else { return isNegative ? "-" + digits : digits }

        let padded = String(repeating: "0", count: max(0, decimals + 1 - digits.count)) + digits
        let splitIndex = padded.index(padded.endIndex, offsetBy: -decimals)
        let whole = String(padded[padded.startIndex..<splitIndex])

        var fraction = String(padded[splitIndex...])
        while fraction.hasSuffix("0") { fraction.removeLast() }

        let magnitude = fraction.isEmpty ? whole : whole + "." + fraction
        return isNegative ? "-" + magnitude : magnitude
    }
}

/// Shared behaviour for the two Kamino amount units. Base units are the exact
/// on-chain integer; every other form is derived from it, so no value round-trips
/// through a binary float.
protocol KaminoBaseUnitAmount: Hashable {
    var baseUnits: BigInt { get }
    var decimals: Int { get }
}

extension KaminoBaseUnitAmount {

    var isZero: Bool { baseUnits.isZero }

    /// Whether this amount may be sent to Kamino. A request amount must be
    /// strictly positive, expressible as a `u64`, and carry a sane scale.
    var isValidRequestAmount: Bool {
        baseUnits > 0
            && baseUnits <= KaminoBaseUnits.maxBaseUnits
            && (0...KaminoBaseUnits.maxDecimals).contains(decimals)
    }

    var decimalValue: Decimal {
        KaminoDecimal.parse(apiString) ?? .zero
    }

    /// The value as Kamino's request bodies want it.
    var apiString: String {
        KaminoBaseUnits.render(baseUnits: baseUnits, decimals: decimals)
    }
}

/// An amount denominated in a vault's **underlying token** (USDC, SOL).
///
/// This is what `POST /ktx/kvault/deposit` expects. Deposit and withdraw take the
/// same `amount` JSON field with inverted units — deposit in tokens, withdraw in
/// shares — so the two are separate types on purpose: passing one where the other
/// belongs is a compile error rather than a silently mis-sized transaction.
struct KaminoTokenAmount: KaminoBaseUnitAmount {
    let baseUnits: BigInt
    let decimals: Int

    init(baseUnits: BigInt, decimals: Int) {
        self.baseUnits = baseUnits
        self.decimals = decimals
    }

    /// Parses a base-unit string as it appears in `VaultState` (e.g.
    /// `minDepositAmount = "100000"` for 0.1 USDC).
    init?(baseUnitString: String, decimals: Int) {
        guard let baseUnits = BigInt(baseUnitString) else { return nil }
        self.init(baseUnits: baseUnits, decimals: decimals)
    }
}

/// An amount denominated in a vault's **share token** (kTokens).
///
/// This is what `POST /ktx/kvault/withdraw` expects — see `KaminoTokenAmount` for
/// why the units are two distinct types.
struct KaminoShareAmount: KaminoBaseUnitAmount {
    let baseUnits: BigInt
    let decimals: Int

    init(baseUnits: BigInt, decimals: Int) {
        self.baseUnits = baseUnits
        self.decimals = decimals
    }

    /// Parses a base-unit string as it appears in `VaultState` (e.g.
    /// `minWithdrawAmount = "1000"`, which is in SHARE base units, not token ones).
    init?(baseUnitString: String, decimals: Int) {
        guard let baseUnits = BigInt(baseUnitString) else { return nil }
        self.init(baseUnits: baseUnits, decimals: decimals)
    }

    /// Parses a human-units share string as returned by
    /// `GET /kvaults/users/{owner}/positions` (e.g. `"517536.857982"`), exactly.
    init?(decimalString: String, decimals: Int) {
        guard let rate = KaminoRate(apiString: decimalString),
              let baseUnits = KaminoAmountMath.scale(rate: rate, toDecimals: decimals)
        else { return nil }
        self.init(baseUnits: baseUnits, decimals: decimals)
    }
}

enum KaminoAmountMath {

    /// Rescales an exact rate to base units at `decimals`, truncating toward zero.
    static func scale(rate: KaminoRate, toDecimals decimals: Int) -> BigInt? {
        guard (0...KaminoBaseUnits.maxDecimals).contains(decimals),
              (0...KaminoBaseUnits.maxDecimals * 4).contains(rate.scale),
              rate.numerator >= 0
        else { return nil }

        if decimals >= rate.scale {
            return rate.numerator * BigInt(10).power(decimals - rate.scale)
        }
        return rate.numerator / BigInt(10).power(rate.scale - decimals)
    }
}

extension KaminoShareAmount {

    /// The position's value in the underlying token: `shares × tokensPerShare`,
    /// computed in exact integer arithmetic and truncated.
    ///
    /// `tokensPerShare` is the correct rate — `metrics.sharePrice` is
    /// USD-denominated and only coincides with it on dollar-pegged vaults (Allez
    /// SOL: `sharePrice` 0.0794 vs `tokensPerShare` 0.0010749).
    func tokenValue(tokensPerShare rate: KaminoRate, tokenDecimals: Int) -> KaminoTokenAmount? {
        guard rate.isPositive,
              baseUnits >= 0,
              (0...KaminoBaseUnits.maxDecimals).contains(tokenDecimals),
              (0...KaminoBaseUnits.maxDecimals).contains(decimals),
              (0...KaminoBaseUnits.maxDecimals * 4).contains(rate.scale)
        else { return nil }

        // tokens = shares × rate, in base units:
        //   tokensBase = sharesBase × numerator × 10^tokenDecimals
        //                ÷ (10^shareDecimals × 10^rateScale)
        let numerator = baseUnits * rate.numerator * BigInt(10).power(tokenDecimals)
        let denominator = BigInt(10).power(decimals + rate.scale)
        return KaminoTokenAmount(baseUnits: numerator / denominator, decimals: tokenDecimals)
    }
}

extension KaminoTokenAmount {

    /// Converts a user-entered token amount into the share amount a withdraw
    /// actually burns: `shares = tokens / tokensPerShare`, truncated.
    ///
    /// Exact integer arithmetic, never `Decimal` division. Rounding down is a
    /// safety property, not a preference: the API does not validate the amount,
    /// and a withdraw larger than the user's share balance is silently rewritten
    /// to `u64::MAX` — "withdraw everything". A division that rounded up, even by
    /// one base unit at the far end of the mantissa, could turn a partial
    /// withdraw into a full exit. For the same reason a 100% withdraw must send
    /// the held share balance directly and never a number derived from here.
    func shareAmount(tokensPerShare rate: KaminoRate, shareDecimals: Int) -> KaminoShareAmount? {
        guard rate.isPositive,
              baseUnits >= 0,
              (0...KaminoBaseUnits.maxDecimals).contains(shareDecimals),
              (0...KaminoBaseUnits.maxDecimals).contains(decimals),
              (0...KaminoBaseUnits.maxDecimals * 4).contains(rate.scale)
        else { return nil }

        // shares = tokens ÷ rate, in base units:
        //   sharesBase = tokensBase × 10^rateScale × 10^shareDecimals
        //                ÷ (10^tokenDecimals × numerator)
        let numerator = baseUnits * BigInt(10).power(rate.scale + shareDecimals)
        let denominator = BigInt(10).power(decimals) * rate.numerator
        return KaminoShareAmount(baseUnits: numerator / denominator, decimals: shareDecimals)
    }
}
