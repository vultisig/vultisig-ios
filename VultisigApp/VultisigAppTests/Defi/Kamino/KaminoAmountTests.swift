//
//  KaminoAmountTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

/// Pins the unit discipline the Kamino integration depends on: exact decimal
/// parsing, exact base-unit ↔ human-units rendering, and share/token conversion
/// that always rounds in the safe direction.
final class KaminoAmountTests: XCTestCase {

    // MARK: - Strict decimal parsing

    func test_parse_keepsFullPrecisionBeyondDoubleRange() {
        // A real `tokensPerShare` from the Steakhouse USDC vault: 20 significant
        // digits. Anything Double-backed loses the tail, which silently mis-prices
        // every position that uses this rate.
        let raw = "1.0536041812651029025"
        let parsed = KaminoDecimal.parse(raw)

        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.map { KaminoDecimal.integralString($0 * pow(Decimal(10), 19)) },
                       "10536041812651029025")
    }

    func test_parse_isNotLocaleSensitive() {
        // The bug this guards: a `NumberFormatter` on a grouping-separator locale
        // reads "1.0536" as 10536. The parser must be locale-independent.
        let parsed = KaminoDecimal.parse("1.0536")
        XCTAssertEqual(parsed, Decimal(string: "1.0536", locale: Locale(identifier: "en_US_POSIX")))
    }

    func test_parse_rejectsFormattingRatherThanCoercingIt() {
        XCTAssertNil(KaminoDecimal.parse("1,053.60"), "grouping separators must be rejected")
        XCTAssertNil(KaminoDecimal.parse("1e-5"), "exponent notation must be rejected")
        XCTAssertNil(KaminoDecimal.parse(" 1.5"), "whitespace must be rejected")
        XCTAssertNil(KaminoDecimal.parse("1.5.5"), "a second separator must be rejected")
        XCTAssertNil(KaminoDecimal.parse("."), "a bare separator has no digits")
        XCTAssertNil(KaminoDecimal.parse("abc"))
        XCTAssertNil(KaminoDecimal.parse(""))
    }

    func test_parse_acceptsPlainAndNegativeValues() {
        XCTAssertEqual(KaminoDecimal.parse("0"), 0)
        XCTAssertEqual(KaminoDecimal.parse("100000"), 100_000)
        XCTAssertEqual(KaminoDecimal.parse("-17064.57"),
                       Decimal(string: "-17064.57", locale: Locale(identifier: "en_US_POSIX")))
    }

    // MARK: - Base units ↔ API string

    func test_apiString_rendersHumanUnitsWithoutTrailingZeros() {
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 10_000_000, decimals: 6).apiString, "10")
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 10_500_000, decimals: 6).apiString, "10.5")
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 500_000_000, decimals: 9).apiString, "0.5")
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 100_000, decimals: 6).apiString, "0.1")
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 1, decimals: 9).apiString, "0.000000001")
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 0, decimals: 6).apiString, "0")
    }

    func test_apiString_zeroDecimalsIsPlainInteger() {
        XCTAssertEqual(KaminoTokenAmount(baseUnits: 42, decimals: 0).apiString, "42")
    }

    func test_baseUnitStringInit_matchesLiveVaultMinimums() {
        // Steakhouse USDC `minDepositAmount` and `minWithdrawAmount`, verbatim.
        let minDeposit = KaminoTokenAmount(baseUnitString: "100000", decimals: 6)
        XCTAssertEqual(minDeposit?.apiString, "0.1")

        // The withdraw minimum is in SHARE base units — a distinct type so it can
        // never be compared against a token amount by accident.
        let minWithdraw = KaminoShareAmount(baseUnitString: "1000", decimals: 6)
        XCTAssertEqual(minWithdraw?.apiString, "0.001")
    }

    func test_shareAmountFromDecimalString_parsesLivePositionShares() {
        let shares = KaminoShareAmount(decimalString: "517536.857982", decimals: 6)
        XCTAssertEqual(shares?.baseUnits, BigInt(517_536_857_982))
        XCTAssertEqual(shares?.apiString, "517536.857982")
    }

    // MARK: - Share ↔ token conversion

    // MARK: - Exact rate

    func test_rate_parsesExactlyWithoutGoingThroughDecimal() throws {
        let rate = try XCTUnwrap(KaminoRate(apiString: "1.0536041812651029025"))
        XCTAssertEqual(rate.numerator, BigInt("10536041812651029025"))
        XCTAssertEqual(rate.scale, 19)

        // Past Decimal's 38 significant digits, where a Decimal-backed rate would
        // silently round.
        let long = try XCTUnwrap(
            KaminoRate(apiString: "19929400626900.66071158913974817848691057")
        )
        XCTAssertEqual(long.numerator, BigInt("1992940062690066071158913974817848691057"))
        XCTAssertEqual(long.scale, 26)
    }

    func test_rate_rejectsTheSameFormattingTheParserDoes() {
        XCTAssertNil(KaminoRate(apiString: "1,053.60"))
        XCTAssertNil(KaminoRate(apiString: "1e-5"))
        XCTAssertNil(KaminoRate(apiString: ""))
    }

    // MARK: - Share ↔ token conversion

    func test_tokenValue_usesTokensPerShareNotSharePrice() throws {
        // Allez SOL: tokensPerShare 0.0010749299151180878396 (SOL per share) vs
        // sharePrice 0.079437779653781828774 (USD per share). Using the wrong one
        // overstates the position by ~74x.
        let rate = try XCTUnwrap(KaminoRate(apiString: "0.0010749299151180878396"))
        let shares = KaminoShareAmount(baseUnits: 1_000_000, decimals: 6) // 1 share

        let tokens = try XCTUnwrap(shares.tokenValue(tokensPerShare: rate, tokenDecimals: 9))
        XCTAssertEqual(tokens.apiString, "0.001074929")
    }

    func test_shareAmount_truncatesSoAWithdrawCanNeverExceedTheBalance() throws {
        // 1 USDC at a share rate above parity is less than 1 share. Rounding up
        // would ask for more shares than the amount is worth, and the API rewrites
        // an over-sized withdraw to u64::MAX — a full exit.
        let rate = try XCTUnwrap(KaminoRate(apiString: "1.0536041812651029025"))
        let oneUsdc = KaminoTokenAmount(baseUnits: 1_000_000, decimals: 6)

        let shares = try XCTUnwrap(oneUsdc.shareAmount(tokensPerShare: rate, shareDecimals: 6))
        XCTAssertEqual(shares.apiString, "0.949123")

        // Round-tripping back must never exceed what the user asked to withdraw.
        let backToTokens = try XCTUnwrap(shares.tokenValue(tokensPerShare: rate, tokenDecimals: 6))
        XCTAssertEqual(backToTokens.baseUnits, BigInt(999_999))
        XCTAssertLessThanOrEqual(backToTokens.baseUnits, oneUsdc.baseUnits)
    }

    func test_shareAmount_truncatesExactlyAtABaseUnitBoundary() throws {
        // The case Decimal division could get wrong: an exact quotient of one
        // half a base unit must floor to zero, never round up to one.
        let rate = try XCTUnwrap(KaminoRate(apiString: "2"))
        let oneBaseUnit = KaminoTokenAmount(baseUnits: 1, decimals: 6)

        let shares = try XCTUnwrap(oneBaseUnit.shareAmount(tokensPerShare: rate, shareDecimals: 6))
        XCTAssertEqual(shares.baseUnits, 0)
    }

    func test_shareAmount_honoursDifferingShareAndTokenDecimals() throws {
        // Allez SOL is the (token 9, share 6) case: scaling with the wrong
        // decimals here is a 1000x error.
        let rate = try XCTUnwrap(KaminoRate(apiString: "0.0010749299151180878396"))
        let oneSol = KaminoTokenAmount(baseUnits: 1_000_000_000, decimals: 9)

        let shares = try XCTUnwrap(oneSol.shareAmount(tokensPerShare: rate, shareDecimals: 6))
        XCTAssertEqual(shares.apiString, "930.293208")
    }

    func test_conversions_rejectNonPositiveRate() throws {
        let tokens = KaminoTokenAmount(baseUnits: 1_000_000, decimals: 6)
        let shares = KaminoShareAmount(baseUnits: 1_000_000, decimals: 6)
        let zero = try XCTUnwrap(KaminoRate(apiString: "0"))
        let negative = try XCTUnwrap(KaminoRate(apiString: "-1"))

        XCTAssertNil(tokens.shareAmount(tokensPerShare: zero, shareDecimals: 6))
        XCTAssertNil(shares.tokenValue(tokensPerShare: zero, tokenDecimals: 6))
        XCTAssertNil(tokens.shareAmount(tokensPerShare: negative, shareDecimals: 6))
    }

    func test_conversions_rejectImplausibleDecimalScales() throws {
        let rate = try XCTUnwrap(KaminoRate(apiString: "1.5"))
        let tokens = KaminoTokenAmount(baseUnits: 1_000_000, decimals: 6)

        XCTAssertNil(tokens.shareAmount(tokensPerShare: rate, shareDecimals: 64))
        XCTAssertNil(tokens.shareAmount(tokensPerShare: rate, shareDecimals: -1))
        XCTAssertNil(
            KaminoTokenAmount(baseUnits: 1, decimals: 99).shareAmount(
                tokensPerShare: rate,
                shareDecimals: 6
            )
        )
    }

    // MARK: - Request-amount bounds

    func test_isValidRequestAmount_rejectsWhatCannotBeSent() {
        // Solana instruction arguments are u64; anything larger cannot be
        // expressed on-chain no matter what the API accepts.
        let overU64 = KaminoTokenAmount(baseUnits: BigInt(UInt64.max) + 1, decimals: 6)
        XCTAssertFalse(overU64.isValidRequestAmount)
        XCTAssertTrue(KaminoTokenAmount(baseUnits: BigInt(UInt64.max), decimals: 6).isValidRequestAmount)

        XCTAssertFalse(KaminoTokenAmount(baseUnits: 0, decimals: 6).isValidRequestAmount)
        XCTAssertFalse(KaminoTokenAmount(baseUnits: -1, decimals: 6).isValidRequestAmount)
        XCTAssertFalse(KaminoTokenAmount(baseUnits: 1, decimals: 64).isValidRequestAmount)
        XCTAssertTrue(KaminoTokenAmount(baseUnits: 1, decimals: 6).isValidRequestAmount)
    }
}
