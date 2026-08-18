//
//  StakePositionCeilingMigrationTests.swift
//  VultisigAppTests
//
//  Rows written before the withdrawable amount was required carry none, and
//  nothing corrects them until a refresh both runs and succeeds — which for an
//  offline user may be never, while the cached card keeps offering Unstake.
//

@testable import VultisigApp
import SwiftData
import XCTest

@MainActor
final class StakePositionCeilingMigrationTests: XCTestCase {

    private var token: TestContextToken?

    override func setUpWithError() throws {
        token = try TestStore.installInMemoryContainer()
    }

    override func tearDown() {
        TestStore.restore(token)
        token = nil
        super.tearDown()
    }

    private func makePosition(vault: Vault, amount: Decimal, ceiling: Decimal?) -> StakePosition {
        let position = StakePosition(
            coin: TokensStore.tcy,
            type: .stake,
            amount: amount,
            availableToUnstake: ceiling,
            vault: vault
        )
        Storage.shared.insert(position)
        return position
    }

    func testALegacyRowGetsTheWithdrawableAmountItAlwaysMeant() throws {
        let vault = TestStore.makeVault(pubKey: "ceiling-backfill")
        let position = makePosition(vault: vault, amount: 42, ceiling: nil)

        try StakePositionCeilingMigration().migrate()

        XCTAssertEqual(position.availableToUnstake, 42,
                       "the size was the withdrawable amount when the row was written")
    }

    /// The backfill is a repair, not a rewrite: a row that already states a
    /// ceiling different from its size keeps it. Maya's positions are the case
    /// that matters — the two are deliberately distinct quantities there.
    func testAStatedCeilingIsNotOverwritten() throws {
        let vault = TestStore.makeVault(pubKey: "ceiling-stated")
        let position = makePosition(vault: vault, amount: 100, ceiling: 30)

        try StakePositionCeilingMigration().migrate()

        XCTAssertEqual(position.availableToUnstake, 30)
    }

    func testRunningItTwiceChangesNothingFurther() throws {
        let vault = TestStore.makeVault(pubKey: "ceiling-idempotent")
        let position = makePosition(vault: vault, amount: 7, ceiling: nil)

        try StakePositionCeilingMigration().migrate()
        try StakePositionCeilingMigration().migrate()

        XCTAssertEqual(position.availableToUnstake, 7)
    }
}
