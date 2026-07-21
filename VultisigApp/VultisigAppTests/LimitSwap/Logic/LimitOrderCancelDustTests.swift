//
//  LimitOrderCancelDustTests.swift
//  VultisigAppTests
//

import BigInt
import XCTest
@testable import VultisigApp

final class LimitOrderCancelDustTests: XCTestCase {

    /// Generous by default so the ceiling only participates where a test is
    /// specifically about it.
    private func dust(
        walletCore: BigInt,
        inbound: String?,
        ceiling: BigInt = BigInt(10).power(30),
        chain: String = "BTC"
    ) throws -> BigInt {
        try limitOrderCancelDustAmount(
            walletCoreDustFloor: walletCore,
            inboundDustThreshold: inbound,
            ceiling: ceiling,
            chainSymbol: chain
        )
    }

    /// THORChain's threshold is the one Bifrost enforces, and it is the one this
    /// codebase previously ignored entirely.
    func testUsesTheInboundThresholdWhenItExceedsTheLocalFloor() throws {
        // BTC: WalletCore floor 546 sats, THORChain threshold 1,000 sats.
        XCTAssertEqual(try dust(walletCore: 546, inbound: "1000"), BigInt(2000))
    }

    /// …and the local floor when IT is larger, because the signer refuses the
    /// output before anything is broadcast.
    func testUsesTheLocalFloorWhenItExceedsTheInboundThreshold() throws {
        XCTAssertEqual(try dust(walletCore: 10_000, inbound: "1000"), BigInt(20_000))
    }

    /// DOGE is the outlier — a whole 1 DOGE minimum — and it comes from the
    /// inbound row, not from WalletCore's much smaller floor.
    func testDogeTakesItsLargeThresholdFromTheInboundRow() throws {
        let amount = try dust(walletCore: 1_000_000, inbound: "100000000", chain: "DOGE")

        XCTAssertEqual(amount, BigInt(200_000_000))
    }

    func testAppliesTheSafetyMultiple() throws {
        let amount = try dust(walletCore: 0, inbound: "7")

        XCTAssertEqual(amount, BigInt(7) * limitOrderCancelDustSafetyMultiple)
    }

    /// A zero-value L1 transaction carries no inbound for Bifrost to observe, so
    /// even a chain reporting no floors at all needs a non-zero output.
    func testNeverReturnsZero() throws {
        XCTAssertEqual(try dust(walletCore: 0, inbound: "0"), BigInt(1))
    }

    /// ⚠️ Fails closed. Guessing low means Bifrost silently ignores the cancel —
    /// fee spent, order untouched, indistinguishable from success.
    func testMissingThresholdThrowsRatherThanDefaulting() {
        XCTAssertThrowsError(try dust(walletCore: 546, inbound: nil)) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .inboundDustThresholdUnavailable(chain: "BTC")
            )
        }
    }

    /// ⚠️ `dust_threshold` is REMOTE and decides an irreversible donation, so a
    /// syntactically valid but absurd value must not be honoured and doubled.
    func testAnAbsurdRemoteThresholdIsRejectedRatherThanDonated() {
        XCTAssertThrowsError(
            try dust(walletCore: 546, inbound: "100000000000000", ceiling: BigInt(100_000))
        ) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .dustAmountExceedsCeiling(
                    chain: "BTC",
                    computed: "200000000000000",
                    ceiling: "100000"
                )
            )
        }
    }

    /// The ceiling is inclusive — a threshold landing exactly on it is fine.
    func testAmountExactlyAtTheCeilingIsAccepted() throws {
        XCTAssertEqual(try dust(walletCore: 0, inbound: "500", ceiling: BigInt(1000)), BigInt(1000))
    }

    /// Every real chain's normal attach must sit comfortably under its ceiling,
    /// or cancelling would fail on the happy path.
    func testVerifiedPerChainMinimaSitUnderTheirCeilings() throws {
        // (chain, decimals, verified minimum attach in smallest units)
        let cases: [(Chain, Int, String)] = [
            (.bitcoin, 8, "1000"),
            (.dogecoin, 8, "100000000"),
            (.litecoin, 8, "10000"),
            (.bitcoinCash, 8, "10000"),
            (.ethereum, 18, "10000000000"),
            (.gaiaChain, 6, "10000")
        ]
        for (chain, decimals, minimum) in cases {
            let ceilingNatural = limitOrderCancelDustCeiling(for: chain)
            var scaled = ceilingNatural
            var raw = Decimal()
            NSDecimalMultiplyByPowerOf10(&raw, &scaled, Int16(decimals), .plain)
            let ceiling = BigInt(NSDecimalNumber(decimal: raw).stringValue) ?? 0

            XCTAssertNoThrow(
                try dust(walletCore: 0, inbound: minimum, ceiling: ceiling, chain: "\(chain)"),
                "\(chain) normal attach must fit under its ceiling"
            )
        }
    }

    func testANegativeLocalFloorFailsClosedRatherThanBeingIgnored() {
        XCTAssertThrowsError(try dust(walletCore: BigInt(-1), inbound: "1000"))
    }

    func testANegativeInboundThresholdThrows() {
        XCTAssertThrowsError(try dust(walletCore: 546, inbound: "-1")) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .malformedInboundDustThreshold(chain: "BTC", value: "-1")
            )
        }
    }

    func testMalformedThresholdThrows() {
        XCTAssertThrowsError(try dust(walletCore: 546, inbound: "not-a-number")) { error in
            XCTAssertEqual(
                error as? LimitOrderCancelDustError,
                .malformedInboundDustThreshold(chain: "BTC", value: "not-a-number")
            )
        }
    }

    // MARK: - Exact natural-units rendering

    /// ⚠️ This string becomes the transaction amount. A display formatter would
    /// round it, and dust rounded below THORChain's threshold is silently
    /// ignored by Bifrost — tx confirms, fee spent, nothing cancelled.
    func testRendersSmallEighteenDecimalAmountsWithoutRounding() {
        // 1e10 wei = 0.00000001 ETH — already at the edge of 8-dp display.
        XCTAssertEqual(exactNaturalUnitsString(BigInt(10).power(10), decimals: 18), "0.00000001")
        // One wei must not vanish.
        XCTAssertEqual(exactNaturalUnitsString(BigInt(1), decimals: 18), "0.000000000000000001")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(3), decimals: 18), "0.000000000000000003")
    }

    func testRendersWholeAndFractionalAmounts() {
        XCTAssertEqual(exactNaturalUnitsString(BigInt(200_000_000), decimals: 8), "2")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(2000), decimals: 8), "0.00002")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(150_000_000), decimals: 8), "1.5")
        XCTAssertEqual(exactNaturalUnitsString(BigInt(0), decimals: 8), "0")
    }

    func testZeroDecimalsPassesThrough() {
        XCTAssertEqual(exactNaturalUnitsString(BigInt(1234), decimals: 0), "1234")
    }

    /// The round trip back to base units must be lossless — that is the whole
    /// point of not going through a formatter.
    func testRoundTripsBackToTheSameBaseUnits() {
        for (raw, decimals) in [(BigInt(1), 18), (BigInt(10).power(10), 18),
                                (BigInt(2000), 8), (BigInt(200_000_000), 8)] {
            let text = exactNaturalUnitsString(raw, decimals: decimals)
            let parts = text.split(separator: ".", maxSplits: 1)
            let whole = BigInt(String(parts[0])) ?? 0
            let fractionText = parts.count > 1 ? String(parts[1]) : ""
            let padded = fractionText + String(repeating: "0", count: decimals - fractionText.count)
            let fraction = padded.isEmpty ? BigInt(0) : (BigInt(padded) ?? 0)
            XCTAssertEqual(whole * BigInt(10).power(decimals) + fraction, raw, "\(text)")
        }
    }

    // MARK: - Memo length

    /// A gas-asset pair is comfortably inside even the 80-byte UTXO cap.
    func testGasAssetCancelMemoFitsAUtxoSource() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(100_000_000),
                targetAsset: "ETH.ETH",
                tradeTarget: BigInt(15_979_057_441)
            )
        )

        XCTAssertLessThanOrEqual(memo.utf8.count, 80)
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: .UTXO))
    }

    /// ⚠️ The combination v1 must block: a contract-suffixed ERC20 target cannot
    /// be shortened (no short codes, no fuzzy matching) and the amounts cannot be
    /// rounded (they define the ratio bucket), so there is no way to make this
    /// fit 80 bytes.
    func testErc20TargetFromAUtxoSourceDoesNotFit() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(123_456_789),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(9_876_543_210)
            )
        )

        XCTAssertGreaterThan(memo.utf8.count, 80)
        XCTAssertFalse(limitOrderCancelMemoFits(memo, sourceChainKind: .UTXO))
        // The same memo is fine from an EVM source, where the budget is 250.
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: .EVM))
    }

    /// ⚠️ The gate has to be handed the memo that will actually be signed.
    ///
    /// The 2026-07-21 rehearsal measured the abbreviated spelling — 49 bytes for
    /// a memo that is 85 — so the difference is not cosmetic: it is 36 bytes per
    /// token leg, which is exactly the margin that decides a UTXO source. Sized
    /// short, the gate passes a cancel it should block, and the user pays a fee
    /// for a truncated `OP_RETURN` that can never match.
    func testTheAbbreviatedSpellingWouldHavePassedAGateTheFullOneFails() throws {
        let abbreviated = "m=<:123456789BTC.BTC:9876543210ETH.USDC-06EB48:0"
        let full = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "BTC.BTC",
                sourceAmount1e8: BigInt(123_456_789),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(9_876_543_210)
            )
        )

        XCTAssertTrue(limitOrderCancelMemoFits(abbreviated, sourceChainKind: .UTXO))
        XCTAssertFalse(limitOrderCancelMemoFits(full, sourceChainKind: .UTXO))
        XCTAssertEqual(full.utf8.count - abbreviated.utf8.count, 36, "one contract, spelled out")
    }

    /// The rehearsal's own pair, from THORChain: 85 bytes is nowhere near the
    /// 250-byte budget a `MsgDeposit` has, so spelling the asset out costs this
    /// route nothing.
    func testTheRehearsalMemoFitsAThorchainSourceComfortably() throws {
        let memo = try buildCancelLimitSwapMemo(
            LimitOrderCancelInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount1e8: BigInt(370_939_666),
                targetAsset: "ETH.USDC-0XA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48",
                tradeTarget: BigInt(167_889_485)
            )
        )

        XCTAssertEqual(memo.utf8.count, 85)
        XCTAssertTrue(limitOrderCancelMemoFits(memo, sourceChainKind: Chain.thorChain.chainType))
    }

    /// The generated-memo tests above prove realistic cases but not the boundary
    /// itself, which is where an off-by-one would actually bite.
    func testTheUtxoBoundaryIsInclusiveAtEightyBytes() {
        let exactly80 = String(repeating: "a", count: 80)
        let exactly81 = String(repeating: "a", count: 81)

        XCTAssertTrue(limitOrderCancelMemoFits(exactly80, sourceChainKind: .UTXO))
        XCTAssertFalse(limitOrderCancelMemoFits(exactly81, sourceChainKind: .UTXO))
    }

    /// Counted in UTF-8 BYTES, not `Character`s — OP_RETURN's cap is on encoded
    /// bytes, and a `count`-based check would let an over-long memo through.
    func testLengthIsCountedInUtf8BytesNotCharacters() {
        // 40 characters, 80 bytes.
        let twoByteChars = String(repeating: "é", count: 40)
        XCTAssertEqual(twoByteChars.count, 40)
        XCTAssertEqual(twoByteChars.utf8.count, 80)
        XCTAssertTrue(limitOrderCancelMemoFits(twoByteChars, sourceChainKind: .UTXO))

        // 41 characters, 82 bytes — under a Character count, over the real cap.
        let overflowing = String(repeating: "é", count: 41)
        XCTAssertLessThan(overflowing.count, 80)
        XCTAssertFalse(limitOrderCancelMemoFits(overflowing, sourceChainKind: .UTXO))
    }
}
