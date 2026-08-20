//
//  THORChainWasmStakingPresentationTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import XCTest

@MainActor
final class THORChainWasmStakingPresentationTests: XCTestCase {
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

    func testHaltDisablesRujiActionsAndShowsAppLayerWarning() {
        let view = makeView(coin: TokensStore.ruji, availability: .halted)

        XCTAssertTrue(view.stakeDisabled)
        XCTAssertTrue(view.unstakeDisabled)
        XCTAssertEqual(view.actionWarningMessage, "thorchainWasmStakingHaltedWarning".localized)
    }

    func testUnavailablePolicyDisablesRujiActionsAndShowsVerificationWarning() {
        let view = makeView(coin: TokensStore.ruji, availability: .unavailable)

        XCTAssertTrue(view.stakeDisabled)
        XCTAssertTrue(view.unstakeDisabled)
        XCTAssertEqual(view.actionWarningMessage, "thorchainWasmStakingUnavailableWarning".localized)
    }

    func testAvailableNativeTcyHasNoAppLayerWarning() {
        let view = makeView(coin: TokensStore.tcy, availability: .available)

        XCTAssertFalse(view.stakeDisabled)
        XCTAssertFalse(view.unstakeDisabled)
        XCTAssertNil(view.actionWarningMessage)
    }

    private func makeView(
        coin: CoinMeta,
        availability: StakeActionAvailability
    ) -> DefiChainStakedPositionView {
        let vault = TestStore.makeVault()
        let position = StakePosition(
            coin: coin,
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
