//
//  TonStakeWithdrawalPendingTests.swift
//  VultisigAppTests
//
//  Pins the TON nominator "withdrawal pending" locked state on the DeFi staked
//  card: while a withdrawal is in progress (carried as `withdrawalUnlockTime`),
//  both staking and unstaking are gated and an explanatory message is surfaced.
//  A normal position (no pending withdrawal) stays fully actionable.
//

@testable import VultisigApp
import XCTest

@MainActor
final class TonStakeWithdrawalPendingTests: XCTestCase {
    private var storeToken: TestContextToken!
    private var vault: Vault!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
        vault = TestStore.makeVault()
    }

    override func tearDown() async throws {
        vault = nil
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    private func makePosition(withdrawalUnlockTime: TimeInterval?) -> StakePosition {
        let meta = CoinMeta.make(chain: .ton, ticker: "TON")
        let dto = StakePositionData(
            coin: meta,
            type: .stake,
            amount: 5,
            canStake: withdrawalUnlockTime == nil,
            withdrawalUnlockTime: withdrawalUnlockTime
        )
        return StakePosition(dto, vault: vault)
    }

    func testWithdrawalPendingLocksBothActionsAndExplains() {
        // Unlock roughly a day out — a pending withdrawal awaiting the cycle end.
        let unlock = Date().timeIntervalSince1970 + 86_400
        let position = makePosition(withdrawalUnlockTime: unlock)

        XCTAssertFalse(position.canStake, "Pending withdrawal must block staking more.")
        XCTAssertFalse(position.canUnstake, "Pending withdrawal must block a second unstake.")
        XCTAssertNotNil(position.unstakeMessage, "Pending withdrawal must explain the locked state.")
        XCTAssertTrue(
            position.unstakeMessage?.contains("TON") ?? false,
            "Message should name the locked ticker."
        )
    }

    func testNormalPositionIsUnaffected() {
        let position = makePosition(withdrawalUnlockTime: nil)

        XCTAssertTrue(position.canStake, "A normal position can still stake more.")
        XCTAssertTrue(position.canUnstake, "A normal nominator position can unstake.")
        XCTAssertNil(position.unstakeMessage, "No pending withdrawal ⇒ no pending message.")
    }
}
