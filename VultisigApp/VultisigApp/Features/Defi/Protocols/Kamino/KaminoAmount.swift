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

    /// This value's numerator at `target` decimal places, or `nil` when `target`
    /// is too coarse to hold it without loss.
    func numerator(atScale target: Int) -> BigInt? {
        guard target >= scale else { return nil }
        return numerator * BigInt(10).power(target - scale)
    }

    /// The exact sum of two API decimal strings, or `nil` when either is not one.
    ///
    /// Exists so two reported figures can be added at the precision they were
    /// reported at, rather than after each has been truncated to a mint's scale.
    /// See `KaminoSharePosition.accountsForItsTotal` for why that distinction is
    /// the difference between a guard and a false refusal.
    static func sum(_ lhs: String, _ rhs: String) -> KaminoRate? {
        guard let left = KaminoRate(apiString: lhs), let right = KaminoRate(apiString: rhs) else { return nil }
        let scale = max(left.scale, right.scale)
        guard let a = left.numerator(atScale: scale), let b = right.numerator(atScale: scale) else { return nil }
        return KaminoRate(numerator: a + b, scale: scale)
    }

    /// Whether `value` names exactly this number. `false` when it is not a plain
    /// decimal at all — an unreadable figure is never equal to a readable one.
    static func isEqual(_ lhs: KaminoRate, _ rhs: String) -> Bool {
        guard let right = KaminoRate(apiString: rhs) else { return false }
        let scale = max(lhs.scale, right.scale)
        guard let a = lhs.numerator(atScale: scale), let b = right.numerator(atScale: scale) else { return false }
        return a == b
    }

    private init(numerator: BigInt, scale: Int) {
        self.numerator = numerator
        self.scale = scale
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

    /// Parses a human-units token string as returned by the metrics endpoint
    /// (e.g. `tokensAvailable = "9581.812345"`), exactly.
    init?(decimalString: String, decimals: Int) {
        guard let rate = KaminoRate(apiString: decimalString),
              let baseUnits = KaminoAmountMath.scale(rate: rate, toDecimals: decimals)
        else { return nil }
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

/// Turns what the user typed into an exact base-unit amount.
///
/// The amount fields are locale-formatted — `1.234,56` on a German device,
/// `1,234.56` on a US one — and the percentage buttons write a grouped string
/// through `Decimal.formatToDecimal`, so grouping has to be accepted. It is not
/// merely stripped, though: `1,23` under `en_US` is not a number, and removing
/// its separator would turn a user who meant one-and-a-bit into a deposit of a
/// hundred and twenty-three. Groups are validated against the locale's own
/// grouping sizes first, and anything ambiguous is refused rather than guessed.
///
/// Deliberately not `NumberFormatter.number(from:)` for the value itself: that
/// hands back a Double-backed `NSNumber`, and an amount that sizes a transaction
/// must not pass through binary floating point.
///
/// Truncating toward zero is the safe direction for a deposit: the user is never
/// charged for a base unit they did not type.
enum KaminoAmountInput {

    static func tokenAmount(
        _ value: String,
        decimals: Int,
        locale: Locale = .current
    ) -> KaminoTokenAmount? {
        guard let baseUnits = baseUnits(value, decimals: decimals, locale: locale) else { return nil }
        return KaminoTokenAmount(baseUnits: baseUnits, decimals: decimals)
    }

    private static func baseUnits(_ value: String, decimals: Int, locale: Locale) -> BigInt? {
        // Trim everything whitespace-like EXCEPT the characters this locale
        // groups with. Several locales group with a no-break or thin space, and
        // trimming those first would quietly swallow a dangling separator —
        // turning a half-typed `1 ` into a clean `1` instead of the refusal the
        // rest of this parser is built to give.
        var trimmable = CharacterSet.whitespacesAndNewlines
        trimmable.subtract(CharacterSet(charactersIn: groupingSeparators(for: locale).joined()))
        let trimmed = value.trimmingCharacters(in: trimmable)
        guard !trimmed.isEmpty else { return nil }

        // Decimal separator first, so the split below can be done on a single
        // known character. On a German locale the grouping separator is "." and
        // the decimal separator is ",", so the order matters: replacing grouping
        // first would turn "1.234,56" into "1234,56" and then into "1234.56",
        // which is right — but it would also silently accept "1.23,4".
        let decimalSeparator = locale.decimalSeparator ?? "."
        let parts = trimmed.components(separatedBy: decimalSeparator)
        guard parts.count <= 2 else { return nil }

        guard let whole = ungrouped(parts[0], locale: locale) else { return nil }
        // A grouping separator has no meaning after the decimal point, so the
        // fraction is digits or nothing.
        let rawFraction = parts.count > 1 ? parts[1] : ""
        guard let fraction = rawFraction.isEmpty ? "" : asciiDigits(rawFraction) else { return nil }

        let normalized = fraction.isEmpty ? whole : whole + "." + fraction
        guard let rate = KaminoRate(apiString: normalized), rate.numerator >= 0 else { return nil }
        return KaminoAmountMath.scale(rate: rate, toDecimals: decimals)
    }

    /// The integer part with its grouping separators removed, or `nil` when they
    /// are not where this locale would put them.
    ///
    /// Sizes come from the locale's own formatter rather than an assumed three,
    /// so a locale that groups differently is read correctly instead of refused.
    private static func ungrouped(_ whole: String, locale: Locale) -> String? {
        var body = whole
        var sign = ""
        if body.hasPrefix("-") {
            sign = "-"
            body.removeFirst()
        }
        guard !body.isEmpty else { return nil }

        let separators = groupingSeparators(for: locale)
        let rawGroups = body.components(separatedBy: CharacterSet(charactersIn: separators.joined()))
        let groups = rawGroups.compactMap { asciiDigits($0) }
        guard groups.count == rawGroups.count else { return nil }
        guard groups.count > 1 else { return sign + groups[0] }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        let primary = max(formatter.groupingSize, 1)
        let secondary = formatter.secondaryGroupingSize > 0 ? formatter.secondaryGroupingSize : primary

        // Right to left: the last group is the primary size, every group above it
        // the secondary size, and the leading group anything that fits.
        for (offset, group) in groups.enumerated().reversed() {
            let expected = offset == groups.count - 1 ? primary : secondary
            if offset == 0 {
                guard (1...expected).contains(group.count) else { return nil }
            } else {
                guard group.count == expected else { return nil }
            }
        }

        return sign + groups.joined()
    }

    /// Characters this locale may have grouped with.
    ///
    /// Its own separator, plus the space characters that "thin space" locales
    /// use: `Locale.groupingSeparator` and what `NumberFormatter` actually writes
    /// have disagreed between the no-break and narrow-no-break space across OS
    /// versions, and a separator we failed to recognise would land inside a group
    /// and refuse the user's own formatted balance. Widening this is safe because
    /// the group sizes are validated separately.
    private static func groupingSeparators(for locale: Locale) -> Set<String> {
        Set(
            [locale.groupingSeparator, "\u{00A0}", "\u{202F}", "\u{2009}"]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
        )
    }

    /// The digits of a non-empty run, rewritten as ASCII, or `nil` if anything in
    /// it is not a decimal digit.
    ///
    /// `NumberFormatter` writes a locale's own numbering system, so on a device
    /// set to `ar_EG` the percentage buttons produce Eastern Arabic numerals —
    /// and a keyboard there can type them. Requiring ASCII would refuse those
    /// users' own amounts. `wholeNumberValue` is defined for every Unicode
    /// decimal digit, so this normalises rather than rejects.
    private static func asciiDigits(_ run: String) -> String? {
        guard !run.isEmpty else { return nil }
        var digits = ""
        digits.reserveCapacity(run.count)
        for character in run {
            guard character.isNumber, let value = character.wholeNumberValue, (0...9).contains(value)
            else { return nil }
            digits.append(Character(String(value)))
        }
        return digits
    }
}

enum KaminoAmountMath {

    /// Rescales an exact rate to base units at `decimals`, truncating toward zero.
    static func scale(rate: KaminoRate, toDecimals decimals: Int) -> BigInt? {
        scaleReportingExactness(rate: rate, toDecimals: decimals)?.baseUnits
    }

    /// The same rescale, plus whether anything was truncated away.
    ///
    /// The flag exists for one caller and one reason. `/positions` reports share
    /// balances at up to 14 decimal places while a share mint has 6, so the
    /// truncated figure is *strictly below* the real balance whenever there were
    /// extra digits — and exactly equal to it when there were not. The withdraw
    /// maximum has to be strictly below, so it needs to know which of the two
    /// happened. See `KaminoSharePosition.spendable`.
    static func scaleReportingExactness(
        rate: KaminoRate,
        toDecimals decimals: Int
    ) -> (baseUnits: BigInt, isExact: Bool)? {
        guard (0...KaminoBaseUnits.maxDecimals).contains(decimals),
              (0...KaminoBaseUnits.maxDecimals * 4).contains(rate.scale),
              rate.numerator >= 0
        else { return nil }

        if decimals >= rate.scale {
            return (rate.numerator * BigInt(10).power(decimals - rate.scale), true)
        }
        let divisor = BigInt(10).power(rate.scale - decimals)
        let (quotient, remainder) = rate.numerator.quotientAndRemainder(dividingBy: divisor)
        return (quotient, remainder.isZero)
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
        tokenValue(tokensPerShare: rate, tokenDecimals: tokenDecimals, roundingUp: false)
    }

    /// The same conversion rounded **up**.
    ///
    /// Used for one thing only: rendering a share-denominated *minimum* as an
    /// asset amount. `minWithdrawAmount` is in share base units, and a form
    /// denominated in the asset has to name a figure that, converted back, still
    /// clears it — so the displayed minimum rounds away from the user rather
    /// than toward them. Never use this to size a transaction: rounding up is
    /// exactly the direction that turns a partial withdraw into an over-request.
    func tokenValueRoundedUp(tokensPerShare rate: KaminoRate, tokenDecimals: Int) -> KaminoTokenAmount? {
        tokenValue(tokensPerShare: rate, tokenDecimals: tokenDecimals, roundingUp: true)
    }

    private func tokenValue(
        tokensPerShare rate: KaminoRate,
        tokenDecimals: Int,
        roundingUp: Bool
    ) -> KaminoTokenAmount? {
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
        let quotient = roundingUp
            ? (numerator + denominator - 1) / denominator
            : numerator / denominator
        return KaminoTokenAmount(baseUnits: quotient, decimals: tokenDecimals)
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
