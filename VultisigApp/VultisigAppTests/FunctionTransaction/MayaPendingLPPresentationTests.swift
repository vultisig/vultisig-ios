//
//  MayaPendingLPPresentationTests.swift
//  VultisigAppTests
//
//  What the pending half-deposit card says, and whether it can offer to
//  complete the missing side.
//

import XCTest
@testable import VultisigApp

@MainActor
final class MayaPendingLPPresentationTests: XCTestCase {

    private var storeToken: TestContextToken?

    override func setUpWithError() throws {
        try super.setUpWithError()
        storeToken = try TestStore.installInMemoryContainer()
    }

    override func tearDownWithError() throws {
        TestStore.restore(storeToken)
        storeToken = nil
        try super.tearDownWithError()
    }

    private func deposit(
        pool: String = "ETH.ETH",
        pendingCacao: Decimal = 0,
        pendingAsset: Decimal = 100_000,
        blocks: Int64? = 100_800
    ) -> MayaPendingLPDeposit {
        MayaPendingLPDeposit(
            pool: pool,
            pendingCacao: pendingCacao,
            pendingAsset: pendingAsset,
            pendingTxId: "TX",
            pairedAddress: "maya1vaultaddress",
            blocksUntilRefund: blocks
        )
    }

    // MARK: - Refund countdown

    /// 100,800 blocks at 5.8 s is a little over a week; rounded down so the card
    /// never promises more time than the deposit has.
    func testTheCountdownUsesTheMayaBlockTime() {
        XCTAssertEqual(MayaPendingLPPresentation.refundSeconds(blocks: 100_800), 584_640)
    }

    func testDaysAndHoursShowWhileADayOrMoreRemains() {
        XCTAssertEqual(
            MayaPendingLPPresentation.refundText(seconds: 6 * 86_400 + 18 * 3600 + 59),
            String(format: "lpPendingDurationDaysHours".localized, 6, 18)
        )
    }

    /// Someone half an hour from losing a deposit needs the minutes, not "0h".
    func testHoursAndMinutesShowInTheLastDay() {
        XCTAssertEqual(
            MayaPendingLPPresentation.refundText(seconds: 30 * 60),
            String(format: "lpPendingDurationHoursMinutes".localized, 0, 30)
        )
    }

    func testAnUnknownCountdownSaysSo() {
        XCTAssertEqual(MayaPendingLPPresentation.refundText(blocks: nil), "lpPendingRefundTimeUnknown".localized)
    }

    // MARK: - Awaited side

    func testAPendingAssetAwaitsCacao() {
        let pending = deposit(pendingCacao: 0, pendingAsset: 100)
        XCTAssertEqual(MayaPendingLPPresentation.awaitedSide(of: pending), .coin1)
    }

    func testAPendingCacaoAwaitsTheAsset() {
        let pending = deposit(pendingCacao: 5, pendingAsset: 0)
        XCTAssertEqual(MayaPendingLPPresentation.awaitedSide(of: pending), .coin2)
    }

    // MARK: - Can it be completed

    func testAPairedPoolWithTheMissingSideInTheVaultCanBeCompleted() {
        let vault = FunctionActionFixture.makeVault(coins: [AddLPFixture.ether(), AddLPFixture.cacao()])
        XCTAssertTrue(MayaPendingLPPresentation.canComplete(deposit(), in: vault))
    }

    func testAPoolTheAppDoesNotPairCannotBeCompleted() {
        let vault = FunctionActionFixture.makeVault(coins: [AddLPFixture.cacao()])
        XCTAssertFalse(MayaPendingLPPresentation.canComplete(deposit(pool: "ADA.ADA"), in: vault))
    }

    func testTheMissingCacaoSideNeedsACacaoAccount() {
        let vault = FunctionActionFixture.makeVault(coins: [AddLPFixture.ether()])
        XCTAssertFalse(MayaPendingLPPresentation.canComplete(deposit(), in: vault))
    }

    func testTheMissingAssetSideNeedsTheAssetInTheVault() {
        let vault = FunctionActionFixture.makeVault(coins: [AddLPFixture.cacao()])
        let pending = deposit(pendingCacao: 5, pendingAsset: 0)
        XCTAssertFalse(MayaPendingLPPresentation.canComplete(pending, in: vault))
    }

    // MARK: - Card

    func testTheCardNamesWhatIsMissingAndWhatWasDeposited() {
        let card = MayaPendingLPPresentation.card(for: deposit(pendingAsset: 100_000))

        XCTAssertEqual(card.awaitedTicker, "CACAO")
        XCTAssertEqual(card.depositedAmount.contains("ETH"), true)
        XCTAssertEqual(card.title, String(format: "lpPendingTitle".localized, "CACAO"))
    }

    func testTheCardDepositedAmountConvertsFixedPointAndCacaoUnits() {
        // 100,000 in 1e8 fixed point is 0.001 of the asset.
        XCTAssertEqual(MayaPendingLPPresentation.assetAmount(fixedPoint: 100_000), Decimal(string: "0.001"))
        // CACAO's own base unit is 1e10.
        XCTAssertEqual(MayaPendingLPPresentation.cacaoAmount(baseUnits: 5_000_000_000), Decimal(string: "0.5"))
    }
}
