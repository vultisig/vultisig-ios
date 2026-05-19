//
//  THORChainStakeInteractorTests.swift
//  VultisigAppTests
//
//  Created by Gaston Mazzeo on 20/04/2026.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class THORChainStakeInteractorTests: XCTestCase {

    // MARK: - scaledAmount

    func test_scaledAmount_stcyWithEightDecimals() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 344_000_000, decimals: 8)
        XCTAssertEqual(result, Decimal(string: "3.44"))
    }

    func test_scaledAmount_zeroRawAmount() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 0, decimals: 8)
        XCTAssertEqual(result, 0)
    }

    func test_scaledAmount_zeroDecimalsReturnsRawUnchanged() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 42, decimals: 0)
        XCTAssertEqual(result, 42)
    }

    func test_scaledAmount_largeRawAmount() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 100_000_000_000, decimals: 8)
        XCTAssertEqual(result, 1_000)
    }

    func test_scaledAmount_eighteenDecimals() {
        let rawAmount = Decimal(string: "1000000000000000000")!
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: rawAmount, decimals: 18)
        XCTAssertEqual(result, 1)
    }

    func test_scaledAmount_preservesSmallFractions() {
        let result = THORChainStakeInteractor.scaledAmount(rawAmount: 1, decimals: 8)
        XCTAssertEqual(result, Decimal(string: "0.00000001"))
    }

    // MARK: - APR fractionalRate

    /// Per the Rujira GraphQL schema, `Bigint` decimal scalars are scaled to 12 decimal places.
    /// `11623890337` should resolve to `0.011624` (≈ 1.16% when rendered as a percentage).
    func test_aprFractionalRate_scales12Decimals() throws {
        let apr = try decodeAPR(value: "11623890337", status: "AVAILABLE")
        let result = try XCTUnwrap(apr.fractionalRate)
        XCTAssertEqual(result, 0.011623890337, accuracy: 1e-12)
    }

    func test_aprFractionalRate_treatsMissingStatusAsAvailable() throws {
        // Backwards-compat: if the API ever omits `status`, fall back to using the value.
        let apr = try decodeAPR(value: "1000000000000", status: nil)
        let result = try XCTUnwrap(apr.fractionalRate)
        XCTAssertEqual(result, 1.0, accuracy: 1e-12)
    }

    func test_aprFractionalRate_returnsNilForNotApplicable() throws {
        let apr = try decodeAPR(value: "0", status: "NOT_APPLICABLE")
        XCTAssertNil(apr.fractionalRate)
    }

    func test_aprFractionalRate_returnsNilForSoon() throws {
        let apr = try decodeAPR(value: "0", status: "SOON")
        XCTAssertNil(apr.fractionalRate)
    }

    func test_aprFractionalRate_returnsNilForUnparseableValue() throws {
        let apr = try decodeAPR(value: "garbage", status: "AVAILABLE")
        XCTAssertNil(apr.fractionalRate)
    }

    // MARK: - Helpers

    private func decodeAPR(value: String, status: String?) throws -> AccountRootData.ResponseData.AccountNode.APR {
        var json = "{\"value\":\"\(value)\""
        if let status { json += ",\"status\":\"\(status)\"" }
        json += "}"
        return try JSONDecoder().decode(AccountRootData.ResponseData.AccountNode.APR.self, from: Data(json.utf8))
    }

    // MARK: - fetchStakePositions early-return paths
    //
    // Branching tests for TCY/RUJI/STCY/YRUNE/default require injecting
    // `THORChainStakingService` and `ThorchainService` (currently global singletons).
    // Tracked under [[projects/vultisig/defi-tab-fixes/architecture-review]] as the next
    // testability win — extract a protocol for the staking service.

    func testFetchStakePositionsReturnsEmptyWithoutRuneCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        // No RUNE coin in vault → guard short-circuits.
        let result = await THORChainStakeInteractor().fetchStakePositions(vault: vault)
        XCTAssertTrue(result.isEmpty)
    }
}
