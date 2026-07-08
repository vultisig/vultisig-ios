//
//  LimitSwapMemoBuilderTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import BigInt
import XCTest

final class LimitSwapMemoBuilderTests: XCTestCase {

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
