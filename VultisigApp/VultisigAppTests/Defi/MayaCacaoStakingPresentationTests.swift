//
//  MayaCacaoStakingPresentationTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class MayaCacaoStakingPresentationTests: XCTestCase {
    private var storeToken: TestContextToken!

    override func setUp() async throws {
        try await super.setUp()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDown() async throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try await super.tearDown()
    }

    func testHaltDisablesBothCacaoActionsAndShowsWarning() {
        let view = makeView(availability: .halted)

        XCTAssertTrue(view.stakeDisabled)
        XCTAssertTrue(view.unstakeDisabled)
        XCTAssertEqual(view.actionWarningMessage, "mayaCacaoStakingHaltedWarning".localized)
    }

    func testAvailableNetworkLeavesBothCacaoActionsEnabled() {
        let view = makeView(availability: .available)

        XCTAssertFalse(view.stakeDisabled)
        XCTAssertFalse(view.unstakeDisabled)
        XCTAssertNil(view.actionWarningMessage)
    }

    func testUnknownNetworkStateFailsClosedWithWarning() {
        let view = makeView(availability: .unavailable)

        XCTAssertTrue(view.stakeDisabled)
        XCTAssertTrue(view.unstakeDisabled)
        XCTAssertEqual(view.actionWarningMessage, "mayaCacaoStakingUnavailableWarning".localized)
    }

    private func makeView(availability: StakeActionAvailability) -> DefiChainStakedPositionView {
        let vault = TestStore.makeVault()
        let position = StakePosition(
            coin: TokensStore.cacao,
            type: .stake,
            amount: 10,
            availableToUnstake: 10,
            vault: vault
        )
        return DefiChainStakedPositionView(
            position: position,
            fiatAmount: "$10.00",
            actionAvailability: availability,
            onStake: {},
            onUnstake: {},
            onWithdraw: {},
            onTransfer: {}
        )
    }
}
