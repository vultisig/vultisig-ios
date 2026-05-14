//
//  THORChainLPsInteractorTests.swift
//  VultisigAppTests
//
//  Note: branching tests for `convertToLPPositions` (asset-format parsing,
//  RUNE/asset coin lookup) need either a protocol extraction over
//  `THORChainAPIService.getLPPositions` or fixture injection. For now we
//  assert the early-return guard and document the gap in
//  [[projects/vultisig/defi-tab-fixes/architecture-review]].
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class THORChainLPsInteractorTests: XCTestCase {

    func testFetchLPPositionsReturnsEmptyWithoutRuneCoin() async throws {
        let token = try TestStore.installInMemoryContainer()
        defer { TestStore.restore(token) }
        let vault = TestStore.makeVault()
        // No RUNE coin → early-return guard returns [] without an API call.
        let result = await THORChainLPsInteractor().fetchLPPositions(vault: vault)
        XCTAssertTrue(result.isEmpty)
    }
}
