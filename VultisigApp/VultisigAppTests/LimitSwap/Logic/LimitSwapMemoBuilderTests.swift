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
