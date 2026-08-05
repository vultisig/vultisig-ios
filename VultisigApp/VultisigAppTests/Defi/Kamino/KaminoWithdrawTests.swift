//
//  KaminoWithdrawTests.swift
//  VultisigAppTests
//
//  The arithmetic and the state machine a withdraw form is built on, tested
//  without the form.
//
//  One property carries the whole flow: **the share amount a withdraw requests
//  can never exceed the balance the user holds.** It matters because the API
//  validates nothing — a withdraw naming more shares than the user has is
//  silently rewritten to `u64::MAX`, which means withdraw everything — so an
//  over-request by a single base unit is the difference between a partial
//  withdraw and a full exit.
//
//  The second property is a refusal rather than a number: a position staked in
//  the vault's farm produces no transaction at all, because that transaction has
//  never been observed.
//

import BigInt
@testable import VultisigApp
import XCTest

final class KaminoWithdrawTests: XCTestCase {

    // MARK: - The maximum is never converted

    /// A withdraw at the maximum sends the exact share balance that was read,
    /// not a number derived from the asset amount on screen.
    func testAFullWithdrawSendsTheExactHeldShareBalance() throws {
        let held = Self.usdcHeld
        let maximum = try XCTUnwrap(Self.usdcMaximum)

        let shares = KaminoWithdrawMath.shares(
            forTokens: maximum,
            held: held,
            maximumTokens: maximum,
            tokensPerShare: Self.usdcRate,
            shareDecimals: 6
        )

        XCTAssertEqual(shares, held)
    }

    /// The round trip is what the conversion branch would do with the same
    /// number, and it loses a base unit — the dust that would be left behind if
    /// a full withdraw were converted like a partial one.
    func testConvertingTheMaximumWouldLeaveSharesBehind() throws {
        let maximum = try XCTUnwrap(Self.usdcMaximum)

        let converted = try XCTUnwrap(
            maximum.shareAmount(tokensPerShare: Self.usdcRate, shareDecimals: 6)
        )

        XCTAssertLessThan(converted.baseUnits, Self.usdcHeld.baseUnits)
    }

    /// The dangerous direction. An amount that arrived above the position —
    /// rounded up for display, typed with an extra digit, or left over from a
    /// balance that has since moved — converts to MORE shares than the user
    /// holds, which is exactly what the API turns into a full exit.
    ///
    /// The first assertion proves the hazard is real with these numbers. The
    /// second is the fix, and it is a refusal rather than a clamp: reading "more
    /// than the position" as "the position" would make one mistyped digit a full
    /// exit, and the button that reaches this is tappable whatever the form's
    /// validators concluded.
    func testAnAmountAboveTheMaximumIsRefusedRatherThanClamped() throws {
        let held = Self.usdcHeld
        let maximum = try XCTUnwrap(Self.usdcMaximum)
        // 5.794822 USDC displayed to four decimals and rounded away from zero.
        let roundedUp = KaminoTokenAmount(baseUnits: maximum.baseUnits + 78, decimals: 6)

        let naive = try XCTUnwrap(roundedUp.shareAmount(tokensPerShare: Self.usdcRate, shareDecimals: 6))
        XCTAssertGreaterThan(naive.baseUnits, held.baseUnits, "the hazard this refusal exists for")

        for over in [BigInt(1), BigInt(78), BigInt(1_000_000_000)] {
            XCTAssertNil(
                KaminoWithdrawMath.shares(
                    forTokens: KaminoTokenAmount(baseUnits: maximum.baseUnits + over, decimals: 6),
                    held: held,
                    maximumTokens: maximum,
                    tokensPerShare: Self.usdcRate,
                    shareDecimals: 6
                ),
                "over by \(over)"
            )
        }
    }

    /// The exact-maximum branch has to be *reachable* through the rendering the
    /// 100% button actually performs, or the safe path would be dead code and
    /// every full withdraw would take the refusing one.
    ///
    /// `AmountTextField` writes `availableAmount.formatToDecimal(digits:)` and
    /// the parser reads it back, so this drives the whole round trip at
    /// balances far larger than either launch vault holds — thirteen and
    /// fifteen significant digits. `formatToDecimal` rounds `.down`, so the
    /// worst a precision limit could do is present a maximum BELOW the true
    /// one, which leaves dust rather than over-requesting; this pins that the
    /// round trip is in fact exact at these magnitudes.
    func testThePercentageButtonsRenderingRoundTripsToTheExactMaximum() throws {
        let cases: [(shares: BigInt, shareDecimals: Int, tokenDecimals: Int, rate: KaminoRate)] = [
            (BigInt(9_876_543_210_987), 6, 6, Self.usdcRate),
            (BigInt(12_345_678_901), 6, 9, Self.solRate)
        ]

        for (shares, shareDecimals, tokenDecimals, rate) in cases {
            let held = KaminoShareAmount(baseUnits: shares, decimals: shareDecimals)
            let maximum = try XCTUnwrap(
                KaminoWithdrawMath.maximumTokens(shares: held, tokensPerShare: rate, tokenDecimals: tokenDecimals)
            )

            // Exactly what the 100% button writes into the field.
            let rendered = maximum.decimalValue.formatToDecimal(digits: tokenDecimals)
            let parsed = try XCTUnwrap(KaminoAmountInput.tokenAmount(rendered, decimals: tokenDecimals))

            XCTAssertEqual(parsed.baseUnits, maximum.baseUnits, rendered)
            XCTAssertEqual(
                KaminoWithdrawMath.shares(
                    forTokens: parsed,
                    held: held,
                    maximumTokens: maximum,
                    tokensPerShare: rate,
                    shareDecimals: shareDecimals
                ),
                held,
                rendered
            )
        }
    }

    /// Below the maximum the conversion truncates, and truncation on both sides
    /// means it can never even reach the balance. Sampled across the top of the
    /// range, which is where an off-by-one would live.
    func testAPartialWithdrawNeverReachesTheHeldBalance() throws {
        let held = Self.usdcHeld
        let maximum = try XCTUnwrap(Self.usdcMaximum)

        for delta in 1...400 {
            let tokens = KaminoTokenAmount(baseUnits: maximum.baseUnits - BigInt(delta), decimals: 6)
            let shares = try XCTUnwrap(
                KaminoWithdrawMath.shares(
                    forTokens: tokens,
                    held: held,
                    maximumTokens: maximum,
                    tokensPerShare: Self.usdcRate,
                    shareDecimals: 6
                )
            )
            XCTAssertLessThan(shares.baseUnits, held.baseUnits, "delta \(delta)")
        }
    }

    /// The share and token scales differ on the SOL vault — 6 against 9 — and
    /// the rate is three orders of magnitude away from one. A conversion that
    /// assumed either would be wrong by ~930×.
    func testTheSolVaultScalesAndRateAreHonoured() throws {
        let held = KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6)

        let maximum = try XCTUnwrap(
            KaminoWithdrawMath.maximumTokens(shares: held, tokensPerShare: Self.solRate, tokenDecimals: 9)
        )

        XCTAssertEqual(maximum.baseUnits, BigInt(1_074_900))
        XCTAssertEqual(maximum.decimals, 9)
    }

    func testAZeroOrEmptyRequestConvertsToNothing() throws {
        let maximum = try XCTUnwrap(Self.usdcMaximum)

        XCTAssertNil(
            KaminoWithdrawMath.shares(
                forTokens: KaminoTokenAmount(baseUnits: 0, decimals: 6),
                held: Self.usdcHeld,
                maximumTokens: maximum,
                tokensPerShare: Self.usdcRate,
                shareDecimals: 6
            )
        )
        XCTAssertNil(
            KaminoWithdrawMath.shares(
                forTokens: maximum,
                held: KaminoShareAmount(baseUnits: 0, decimals: 6),
                maximumTokens: maximum,
                tokensPerShare: Self.usdcRate,
                shareDecimals: 6
            )
        )
    }

    // MARK: - The share-denominated minimum

    /// `minWithdrawAmount` is in SHARE base units. Rendering it in the asset has
    /// to round UP, or the number on screen would convert back to fewer shares
    /// than the vault accepts and the form would refuse its own advertised
    /// minimum.
    func testTheDisplayedMinimumConvertsBackToAtLeastTheMinimum() throws {
        let minimumShares = KaminoShareAmount(baseUnits: BigInt(1_000), decimals: 6)

        let minimumTokens = try XCTUnwrap(
            KaminoWithdrawMath.minimumTokens(
                minimumShares: minimumShares,
                tokensPerShare: Self.solRate,
                tokenDecimals: 9
            )
        )

        XCTAssertEqual(minimumTokens.baseUnits, BigInt(1_075))
        let back = try XCTUnwrap(minimumTokens.shareAmount(tokensPerShare: Self.solRate, shareDecimals: 6))
        XCTAssertGreaterThanOrEqual(back.baseUnits, minimumShares.baseUnits)

        // One base unit less does not clear it, which is what makes the rounding
        // load-bearing rather than cosmetic.
        let short = KaminoTokenAmount(baseUnits: minimumTokens.baseUnits - 1, decimals: 9)
        let shortBack = try XCTUnwrap(short.shareAmount(tokensPerShare: Self.solRate, shareDecimals: 6))
        XCTAssertLessThan(shortBack.baseUnits, minimumShares.baseUnits)
    }

    /// The validator judges the minimum after the conversion, through the same
    /// function that sizes the transaction.
    func testTheMinimumValidatorJudgesSharesNotTokens() throws {
        let held = KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6)
        let validator = KaminoMinWithdrawValidator(
            held: held,
            maximumTokens: KaminoTokenAmount(baseUnits: BigInt(1_074_900), decimals: 9),
            minimumShares: KaminoShareAmount(baseUnits: BigInt(1_000), decimals: 6),
            tokensPerShare: Self.solRate,
            tokenDecimals: 9,
            shareDecimals: 6,
            errorMessage: "too small"
        )

        // 0.000001075 SOL is 1000 shares; one lamport less is 999.
        XCTAssertNoThrow(try validator.validate(value: "0.000001075"))
        XCTAssertThrowsError(try validator.validate(value: "0.000001074"))
        // Empty and malformed values belong to the other validators.
        XCTAssertNoThrow(try validator.validate(value: ""))
        XCTAssertNoThrow(try validator.validate(value: "abc"))
    }

    /// A naive comparison against the token amount would pass anything above
    /// 1000 lamports. The share rate is 0.0010749, so the two answers differ by
    /// roughly a factor of a thousand — the mistake this validator exists to
    /// avoid.
    func testATokenDenominatedMinimumWouldHaveBeenWrongByTheShareRate() throws {
        let minimumShares = KaminoShareAmount(baseUnits: BigInt(1_000), decimals: 6)
        let naive = KaminoTokenAmount(baseUnits: minimumShares.baseUnits, decimals: 9)
        let correct = try XCTUnwrap(
            KaminoWithdrawMath.minimumTokens(
                minimumShares: minimumShares,
                tokensPerShare: Self.solRate,
                tokenDecimals: 9
            )
        )

        XCTAssertNotEqual(naive.baseUnits, correct.baseUnits)
    }

    // MARK: - Eligibility

    /// The refusal every one of these positions currently hits. A deposit
    /// auto-stakes, so `stakedShares` is where the whole position is, and the
    /// transaction that spends it has never been observed.
    func testAStakedPositionIsRefusedRatherThanConverted() {
        let eligibility = KaminoWithdrawEligibility.resolve(
            response: Self.position(staked: "5.5", unstaked: "0", total: "5.5"),
            shareDecimals: 6
        )

        XCTAssertEqual(eligibility, .farmStaked(KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)))
        XCTAssertNil(eligibility.withdrawableShares)
    }

    /// A partly staked position is refused whole. Offering to spend only the
    /// unstaked remainder would quietly withdraw less than the user asked for,
    /// and the 100% button would be a lie.
    func testAPartlyStakedPositionIsRefusedWhole() {
        let eligibility = KaminoWithdrawEligibility.resolve(
            response: Self.position(staked: "1", unstaked: "4.5", total: "5.5"),
            shareDecimals: 6
        )

        XCTAssertEqual(eligibility, .farmStaked(KaminoShareAmount(baseUnits: BigInt(1_000_000), decimals: 6)))
    }

    func testAnEntirelyUnstakedPositionIsWithdrawable() {
        let eligibility = KaminoWithdrawEligibility.resolve(
            response: Self.position(staked: "0", unstaked: "5.5", total: "5.5"),
            shareDecimals: 6
        )

        XCTAssertEqual(eligibility, .withdrawable(KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)))
    }

    /// Absent from the response is a real "holds nothing" answer.
    func testAVaultAbsentFromTheResponseHoldsNothing() {
        XCTAssertEqual(KaminoWithdrawEligibility.resolve(response: nil, shareDecimals: 6), .empty)
        XCTAssertEqual(
            KaminoWithdrawEligibility.resolve(
                response: Self.position(staked: "0", unstaked: "0", total: "0"),
                shareDecimals: 6
            ),
            .empty
        )
    }

    /// A value that is present and unreadable is a failed read, not a zero
    /// balance and not a whole one.
    func testAnUnparseableBalanceIsUnreadableRatherThanZero() {
        XCTAssertEqual(
            KaminoWithdrawEligibility.resolve(
                response: Self.position(staked: "0", unstaked: "1,000", total: "1,000"),
                shareDecimals: 6
            ),
            .unreadable
        )
    }

    /// A response claiming more unstaked shares than the user holds in total is
    /// self-contradictory, and its `unstakedShares` is precisely the number that
    /// would be sent as a balance. Refused rather than trusted.
    func testASelfContradictoryPositionIsRefused() {
        XCTAssertEqual(
            KaminoWithdrawEligibility.resolve(
                response: Self.position(staked: "0", unstaked: "9", total: "5.5"),
                shareDecimals: 6
            ),
            .unreadable
        )
    }

    /// `stakedShares: 0` means nothing was *reported* as staked, not that
    /// nothing is. A total larger than the two reported parts has shares the
    /// response did not account for, and an unaccounted share may be a staked
    /// one — so withdrawing the unstaked remainder would present a partial exit
    /// as a complete one. Refused.
    func testAPositionWithUnaccountedSharesIsRefused() {
        XCTAssertEqual(
            KaminoWithdrawEligibility.resolve(
                response: Self.position(staked: "0", unstaked: "4", total: "5"),
                shareDecimals: 6
            ),
            .unreadable
        )
        // And the same holds when the unaccounted part is the whole position:
        // that is not "holds nothing".
        XCTAssertEqual(
            KaminoWithdrawEligibility.resolve(
                response: Self.position(staked: "0", unstaked: "0", total: "5"),
                shareDecimals: 6
            ),
            .unreadable
        )
    }

    // MARK: - Liquidity

    /// A withdraw above the vault's liquid buffer is an ordinary state, and the
    /// buffer it names is the vault's own published figure — not an inference
    /// from a program error, which has never been observed.
    func testLiquidityComparesTheRequestAgainstThePublishedBuffer() {
        let available = KaminoTokenAmount(baseUnits: BigInt(1_000_000), decimals: 6)

        XCTAssertEqual(
            KaminoWithdrawLiquidity.resolve(
                requested: KaminoTokenAmount(baseUnits: BigInt(1_000_000), decimals: 6),
                available: available
            ),
            .instant
        )
        XCTAssertEqual(
            KaminoWithdrawLiquidity.resolve(
                requested: KaminoTokenAmount(baseUnits: BigInt(1_000_001), decimals: 6),
                available: available
            ),
            .delayed(available: available)
        )
    }

    /// A vault whose buffer could not be read says nothing rather than guessing.
    func testAnUnknownBufferMakesNoClaim() {
        XCTAssertEqual(
            KaminoWithdrawLiquidity.resolve(
                requested: KaminoTokenAmount(baseUnits: BigInt(1_000_000), decimals: 6),
                available: nil
            ),
            .instant
        )
    }

    // MARK: - Fixtures

    /// Steakhouse USDC, captured 2026-08-04.
    private static let usdcRate = KaminoRate(apiString: "1.0536041812651029025") ?? KaminoRate(apiString: "1")!
    /// Allez SOL, captured the same day. Three orders of magnitude from one.
    private static let solRate = KaminoRate(apiString: "0.0010749") ?? KaminoRate(apiString: "1")!

    private static let usdcHeld = KaminoShareAmount(baseUnits: BigInt(5_500_000), decimals: 6)

    private static var usdcMaximum: KaminoTokenAmount? {
        KaminoWithdrawMath.maximumTokens(shares: usdcHeld, tokensPerShare: usdcRate, tokenDecimals: 6)
    }

    private static func position(
        staked: String,
        unstaked: String,
        total: String
    ) -> KaminoUserPositionResponse {
        KaminoUserPositionResponse(
            vaultAddress: KaminoVaultRegistry.steakhouseUSDC.address,
            stakedShares: staked,
            unstakedShares: unstaked,
            totalShares: total
        )
    }
}
