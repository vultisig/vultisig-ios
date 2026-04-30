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

    // MARK: - fetchStakePositions early-return paths
    //
    // Branching tests for TCY/RUJI/STCY/YRUNE/default require injecting
    // `THORChainStakingService` and `ThorchainService` (currently global singletons).
    // Tracked under [[projects/vultisig/defi-tab-fixes/architecture-review]] as the next
    // testability win — extract a protocol for the staking service.

    func testFetchStakePositionsReturnsEmptyWithoutRuneCoin() async throws {
        let token = try DefiTestStore.installInMemoryContainer()
        defer { DefiTestStore.restore(token) }
        let vault = DefiTestStore.makeVault()
        // No RUNE coin in vault → guard short-circuits.
        let result = await THORChainStakeInteractor().fetchStakePositions(vault: vault)
        XCTAssertTrue(result.isEmpty)
            }
}
