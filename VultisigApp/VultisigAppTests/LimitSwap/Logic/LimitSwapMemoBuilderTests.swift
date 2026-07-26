//
//  LimitSwapMemoBuilderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class LimitSwapMemoBuilderTests: XCTestCase {

    // MARK: - isLimitSwapMemo
    //
    // The memo prefix is the ONLY on-the-wire signal that separates a resting
    // limit order from a market swap, and it is what a co-signer keys off to
    // decide whether the row needs limit tracking. A false negative there puts
    // the order back under the native poller, which reports it Successful while
    // it is still resting.

    func testIsLimitSwapMemoAcceptsABuiltLimitMemo() throws {
        let memo = try buildLimitSwapMemo(
            LimitSwapInputs(
                sourceAsset: "THOR.RUNE",
                sourceAmount: BigInt(100_000_000),
                sourceDecimals: 8,
                targetAsset: "BTC.BTC",
                destAddress: "bc1qexample",
                targetPrice: Decimal(string: "0.015")!,
                expiryHours: 24,
                affiliate: "va",
                affiliateBps: "50"
            )
        )

        XCTAssertTrue(memo.hasPrefix("=<:"), "fixture guard: expected a limit memo, got \(memo)")
        XCTAssertTrue(isLimitSwapMemo(memo))
    }

    /// The market prefix (`=>`) differs from the limit prefix (`=<`) by a single
    /// character. Misreading one as the other is the whole risk of prefix
    /// sniffing, so pin it.
    func testIsLimitSwapMemoRejectsAMarketSwapMemo() {
        XCTAssertFalse(isLimitSwapMemo("=>:BTC.BTC:bc1qexample:1e6:va:50"))
    }

    func testIsLimitSwapMemoRejectsNilAndEmpty() {
        XCTAssertFalse(isLimitSwapMemo(nil))
        XCTAssertFalse(isLimitSwapMemo(""))
    }

    func testIsLimitSwapMemoRejectsOtherThorchainMemos() {
        XCTAssertFalse(isLimitSwapMemo("SWAP:BTC.BTC:bc1qexample"))
        XCTAssertFalse(isLimitSwapMemo("=:BTC.BTC:bc1qexample"))
        XCTAssertFalse(isLimitSwapMemo("+:BTC.BTC:bc1qexample"))
    }

    /// Must match the prefix, not merely contain it — a memo that happens to
    /// carry `=<:` inside a field is not a limit order.
    func testIsLimitSwapMemoRequiresThePrefixNotASubstring() {
        XCTAssertFalse(isLimitSwapMemo("SWAP:BTC.BTC:=<:not-an-order"))
    }

    /// `=<` without the separating colon is not the limit prefix.
    func testIsLimitSwapMemoRejectsTheBarePrefixWithoutSeparator() {
        XCTAssertFalse(isLimitSwapMemo("=<"))
    }

    func testAllVectorsInLimitSwapMemosFixture() throws {
        let fixture = try loadMemoFixture()

        XCTAssertEqual(fixture.vectors.count, 24, "Expected 24 reference vectors (4 pairs × 3 expiries × 2 referred)")

        for vector in fixture.vectors {
            guard let sourceAmount = BigInt(vector.inputs.source_amount) else {
                XCTFail("Vector \(vector.name): invalid source_amount '\(vector.inputs.source_amount)'")
                continue
            }
            guard let targetPrice = Decimal(string: vector.inputs.target_price) else {
                XCTFail("Vector \(vector.name): invalid target_price '\(vector.inputs.target_price)'")
                continue
            }

            let inputs = LimitSwapInputs(
                sourceAsset: vector.inputs.source_asset,
                sourceAmount: sourceAmount,
                sourceDecimals: vector.inputs.source_decimals,
                targetAsset: vector.inputs.target_asset,
                destAddress: vector.inputs.dest_addr,
                targetPrice: targetPrice,
                expiryHours: vector.inputs.expiry_hours,
                affiliate: vector.inputs.affiliate,
                affiliateBps: vector.inputs.affiliate_bps
            )

            let memo = try buildLimitSwapMemo(inputs)

            XCTAssertEqual(memo, vector.expected_memo, "Vector \(vector.name) failed")
        }
    }

    // MARK: - compressLim (sci-notation) — spec-anchored, NOT tautological
    //
    // These vectors come from THORChain's own memo-length-reduction docs, not
    // from re-running the builder against itself, so they pin the encoding to an
    // external oracle. `<mantissa>e<exp>` = mantissa followed by `exp` zeros.

    func testCompressLimMatchesProtocolSpecExamples() {
        XCTAssertEqual(compressLim(BigInt(100_000_000)), "1e8")   // 1e8 = 100000000
        XCTAssertEqual(compressLim(BigInt(510_000_000)), "51e7")  // 51e7 = 510000000
        XCTAssertEqual(compressLim(BigInt(544_000_000)), "544e6") // 544e6 = 544000000
    }

    func testCompressLimIsLosslessAndNeverRoundsUp() {
        // Every compressed form must decode back to EXACTLY the input — it must
        // never exceed the plain LIM (which would overstate the guarantee).
        for value in ["1", "10", "100", "6250000", "1600000000", "600000000000",
                      "123456789", "999999999", "1000000000000000000"] {
            let lim = BigInt(value)!
            let encoded = compressLim(lim)
            XCTAssertEqual(decodeSci(encoded), lim, "compressLim(\(value)) = \(encoded) must be lossless")
            XCTAssertLessThanOrEqual(decodeSci(encoded), lim, "compressed LIM must never exceed the plain LIM")
        }
    }

    func testCompressLimOnlyUsesSciWhenStrictlyShorter() {
        // No trailing zeros → plain form.
        XCTAssertEqual(compressLim(BigInt(123)), "123")
        // `X00` (`Xe2`) is the same length → plain form wins.
        XCTAssertEqual(compressLim(BigInt(700)), "700")
        // `X000` (`Xe3`) is one shorter → sci form.
        XCTAssertEqual(compressLim(BigInt(7000)), "7e3")
        // Non-positive → plain.
        XCTAssertEqual(compressLim(BigInt(0)), "0")
    }

    // MARK: - roundUpToSignificantFigures

    func testRoundUpToSignificantFiguresRoundsTowardPlusInfinity() {
        XCTAssertEqual(roundUpToSignificantFigures(BigInt(123_456_789), significantFigures: 3), BigInt(124_000_000))
        XCTAssertEqual(roundUpToSignificantFigures(BigInt(123_456_789), significantFigures: 5), BigInt(123_460_000))
        XCTAssertEqual(roundUpToSignificantFigures(BigInt(999), significantFigures: 1), BigInt(1000))
        // Already exact at that precision (trailing zeros) → unchanged.
        XCTAssertEqual(roundUpToSignificantFigures(BigInt(110_000_000), significantFigures: 3), BigInt(110_000_000))
        // sig figs ≥ digit count, or non-positive → no-op.
        XCTAssertEqual(roundUpToSignificantFigures(BigInt(123), significantFigures: 5), BigInt(123))
        XCTAssertEqual(roundUpToSignificantFigures(BigInt(0), significantFigures: 3), BigInt(0))
    }

    // MARK: - buildFittedLimitSwapMemo (bounded LIM round-up to fit the byte cap)

    /// LIM = 100000000 × floor(1.23456789 × 1e8) / 1e8 = 123456789 — nine
    /// non-round digits `compressLim` can't shrink. A 42-char ETH destination
    /// plus a referral affiliate pushes the exact BTC-source memo over 80 bytes.
    private func overflowInputs(affiliate: String) -> LimitSwapInputs {
        LimitSwapInputs(
            sourceAsset: "BTC.BTC",
            sourceAmount: BigInt(100_000_000),
            sourceDecimals: 8,
            targetAsset: "ETH.ETH",
            destAddress: "0x" + String(repeating: "a", count: 40),
            targetPrice: Decimal(string: "1.23456789")!,
            expiryHours: 24,
            affiliate: affiliate,
            affiliateBps: "10/35"
        )
    }

    func testFittedMemoLeavesAFittingMemoExact() throws {
        // EVM source (250-byte cap) never overflows → byte-identical to the
        // lossless builder, and the effective LIM is the exact LIM.
        let inputs = overflowInputs(affiliate: "vlt/vi")
        let (memo, effectiveLim) = try buildFittedLimitSwapMemo(inputs, sourceChainKind: .EVM)
        XCTAssertEqual(memo, try buildLimitSwapMemo(inputs))
        XCTAssertEqual(effectiveLim, BigInt(123_456_789))
    }

    func testFittedMemoRoundsLimUpToFitUtxoCap() throws {
        let inputs = overflowInputs(affiliate: "vlt/vi")
        // Exact memo overflows the 80-byte UTXO OP_RETURN cap.
        XCTAssertGreaterThan(try buildLimitSwapMemo(inputs).utf8.count, 80)

        let (memo, effectiveLim) = try buildFittedLimitSwapMemo(inputs, sourceChainKind: .UTXO)
        XCTAssertLessThanOrEqual(memo.utf8.count, 80, "fitted memo must fit the 80-byte cap")
        // Rounded UP (never a lower floor) and within the 0.5% tolerance.
        XCTAssertGreaterThanOrEqual(effectiveLim, BigInt(123_456_789))
        XCTAssertLessThanOrEqual(
            (effectiveLim - BigInt(123_456_789)) * 10_000,
            BigInt(123_456_789) * BigInt(limitLimRoundingMaxBps)
        )
        // The memo carries the compressed EFFECTIVE LIM (display == memo).
        XCTAssertTrue(memo.contains(compressLim(effectiveLim)))
    }

    func testFittedMemoThrowsWhenEvenBoundedRoundingCannotFit() {
        // A long referral affiliate leaves no slack — even max-tolerance round-up
        // can't reach 80 bytes, so the clear error is surfaced rather than
        // silently over-rounding the price floor.
        let inputs = overflowInputs(affiliate: "referralpartner/vi")
        XCTAssertThrowsError(try buildFittedLimitSwapMemo(inputs, sourceChainKind: .UTXO)) { error in
            guard case LimitSwapMemoError.memoExceedsByteLimit = error else {
                return XCTFail("Expected memoExceedsByteLimit, got \(error)")
            }
        }
    }

    /// Decode `<mantissa>e<exp>` (or a plain integer) back to a BigInt, for the
    /// lossless round-trip assertions above.
    private func decodeSci(_ encoded: String) -> BigInt {
        guard let eIndex = encoded.firstIndex(of: "e") else {
            return BigInt(encoded) ?? -1
        }
        let mantissa = String(encoded[encoded.startIndex..<eIndex])
        let expString = String(encoded[encoded.index(after: eIndex)...])
        guard let m = BigInt(mantissa), let exp = Int(expString) else { return -1 }
        return m * BigInt(10).power(exp)
    }

    // MARK: - Fixture loading

    private func loadMemoFixture() throws -> MemoFixture {
        let bundle = Bundle(for: type(of: self))
        guard let url = bundle.url(forResource: "LimitSwapMemos", withExtension: "json") else {
            throw FixtureError.fileNotFound("LimitSwapMemos.json")
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MemoFixture.self, from: data)
    }
}

// MARK: - Fixture types (snake_case to match the JSON schema)
// swiftlint:disable identifier_name

private struct MemoFixture: Decodable {
    let vectors: [Vector]
}

private struct Vector: Decodable {
    let name: String
    let inputs: VectorInputs
    let expected_memo: String
}

private struct VectorInputs: Decodable {
    let source_asset: String
    let source_amount: String
    let source_decimals: Int
    let target_asset: String
    let dest_addr: String
    let target_price: String
    let expiry_hours: Int
    let affiliate: String
    let affiliate_bps: String
}

// swiftlint:enable identifier_name

private enum FixtureError: Error {
    case fileNotFound(String)
}
