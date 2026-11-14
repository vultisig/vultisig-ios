//
//  PerpsReviewGuardTests.swift
//  VultisigAppTests
//
//  Guards from the adversarial review: the vault-type gate, sheets that
//  follow the poll, no ticket on top of an open position, margin removal
//  that would liquidate, and one VULT tier per review.
//

import XCTest
@testable import VultisigApp

@MainActor
final class PerpsReviewGuardTests: XCTestCase {
    private let mainAddress = "0x9d7c000000000000000000000000000000003003"

    private func market(mark: Decimal = 66_969, coin: String = "BTC") -> PerpsMarket {
        PerpsMarket(assetIndex: 0, coin: coin, szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: mark,
                    midPrice: mark, previousDayPrice: 66_000, hourlyFunding: 0, openInterest: 1, dayVolume: 1, marginTiers: [])
    }

    private func position(entry: String = "67074", size: String = "0.00298", marginUsed: String = "112.34", pnl: String = "12.4",
                          liquidation: String? = "33908") throws -> HLPosition {
        let liq = liquidation.map { "\"\($0)\"" } ?? "null"
        let json = #"{"coin":"BTC","szi":"\#(size)","leverage":{"type":"isolated","value":2},"entryPx":"\#(entry)","#
            + #""positionValue":"200","unrealizedPnl":"\#(pnl)","returnOnEquity":"0.1","liquidationPx":\#(liq),"marginUsed":"\#(marginUsed)","maxLeverage":40}"#
        return try JSONDecoder().decode(HLPosition.self, from: Data(json.utf8))
    }

    private func account(positions: [HLPosition] = [], available: Decimal = 250) -> PerpsAccountSnapshot {
        PerpsAccountSnapshot(address: "0x1", accountValue: available + 100, withdrawable: available, marginUsed: 100,
                             totalNotional: 200, positions: positions, openOrders: [], fills: [])
    }

    private func context(supported: Bool, usdc: Decimal = 500) -> PerpsVaultContext {
        PerpsVaultContext(name: "Main", address: mainAddress, arbitrumUsdcBalance: usdc,
                          tradingAddress: supported ? "0x1185000000000000000000000000000000007ce0" : nil, isSupported: supported)
    }

    // MARK: - 1. Vault type

    func testOnlyDKLSVaultsWithAChainCodeAreSupported() {
        let dkls = Vault(name: "dkls", libType: .DKLS)
        dkls.hexChainCode = "c9f3a1b2d4e5f60718293a4b5c6d7e8f9011223344556677889900aabbccddee"
        XCTAssertTrue(PerpsConfig.isSupported(vault: dkls))
        let noChainCode = Vault(name: "dkls-no-chain-code", libType: .DKLS)
        XCTAssertFalse(PerpsConfig.isSupported(vault: noChainCode))
        for libType in [LibType.GG20, .KeyImport] {
            let vault = Vault(name: "\(libType)", libType: libType)
            vault.hexChainCode = dkls.hexChainCode
            XCTAssertFalse(PerpsConfig.isSupported(vault: vault), "\(libType)")
            XCTAssertNil(PerpsConfig.tradingAccountAddress(vault: vault), "no trading address for \(libType)")
            let context = PerpsVaultContext(vault: vault)
            XCTAssertFalse(context.isSupported)
            XCTAssertNil(context.tradingAddress)
        }
    }

    func testUnsupportedVaultGetsNoDepositOrOrderReview() throws {
        let unsupported = context(supported: false)
        let deposit = PerpsFlows.addFunds(amount: 100, vault: unsupported)
        XCTAssertEqual(deposit.blockingIssue, "perpsUnsupportedVault".localized)
        XCTAssertNil(deposit.deposit, "no CCTP authorization is built for a vault that can't use it")
        XCTAssertEqual(PerpsFlows.fundingIssue(amount: 10, vault: unsupported), "perpsUnsupportedVault".localized)

        let ticket = PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated, limitPrice: nil, takeProfit: nil, stopLoss: nil)
        let plan = try PerpsOrderPlanner.plan(market: market(), ticket: ticket, nonce: 1)
        let costs = PerpsFlows.costs(plan: plan, availableToTrade: 0, tier: nil)
        let order = PerpsFlows.order(plan: plan, costs: costs, vault: unsupported)
        XCTAssertEqual(order.blockingIssue, "perpsUnsupportedVault".localized)
        XCTAssertTrue(order.requests.isEmpty)
        XCTAssertNil(order.deposit)

        // The same flows for a DKLS vault are not blocked by the gate.
        XCTAssertNotEqual(PerpsFlows.addFunds(amount: 100, vault: context(supported: true)).blockingIssue, "perpsUnsupportedVault".localized)
    }

    // MARK: - 2. Sheets follow the poll

    func testCloseSheetFollowsThePoll() throws {
        let position = try position()
        let viewModel = PerpsCloseViewModel(position: position, market: market(mark: 66_969), vultTier: nil)
        XCTAssertEqual(viewModel.estimate.price, 66_969)
        viewModel.refresh(position: position, market: market(mark: 70_000))
        XCTAssertEqual(viewModel.estimate.price, 70_000)
        let document = try XCTUnwrap(viewModel.reviewDocument())
        XCTAssertTrue(document.rows.contains { $0.value == PerpsFormat.price(70_000) }, "the review quotes the latest price")
    }

    func testModifySheetsFollowThePoll() throws {
        let position = try position()
        let margin = PerpsMarginViewModel(position: position, market: market(), account: account(available: 10))
        margin.amountText = "20"
        XCTAssertEqual(margin.change.issue, .moreThanAvailable)
        margin.refresh(position: position, market: market(), account: account(available: 50))
        XCTAssertNil(margin.change.issue, "the new available balance is used")

        let exits = PerpsAutoCloseViewModel(side: .long, entry: 67_074, reference: 66_969, size: Decimal(string: "0.00298") ?? 0,
                                            liquidation: 33_908, szDecimals: 5, takeProfit: nil, stopLoss: nil)
        exits.stopText = "65000"
        XCTAssertNil(exits.issue)
        // The price fell under the typed stop: the check follows it.
        exits.refresh(PerpsExitInputs(entry: 67_074, reference: 64_000, size: Decimal(string: "0.00298") ?? 0, liquidation: 33_908))
        XCTAssertEqual(exits.issue, "perpsStopBelowPrice".localized)
        XCTAssertEqual(exits.stopText, "65000", "what was typed stays")
    }

    // MARK: - 3. Open position

    func testNoTicketOnTopOfAnOpenPosition() throws {
        let open = try position()
        let ticket = PerpsTicket(side: .short, margin: 100, leverage: 5, marginMode: .isolated, limitPrice: nil, takeProfit: nil, stopLoss: nil)
        XCTAssertThrowsError(try PerpsOrderPlanner.plan(market: market(), ticket: ticket, nonce: 1, openPosition: open)) { error in
            XCTAssertEqual(error as? PerpsOrderPlannerError, .positionOpen)
        }
        // Another market's position does not block.
        XCTAssertNoThrow(try PerpsOrderPlanner.plan(market: market(coin: "ETH"), ticket: ticket, nonce: 1, openPosition: open))

        let viewModel = PerpsTicketViewModel(side: .long, market: market(), account: account(positions: [open]),
                                             vault: context(supported: true), vultTier: nil)
        XCTAssertEqual(viewModel.issue, PerpsFlows.positionOpenMessage(open))
        XCTAssertFalse(viewModel.canReview)
        XCTAssertNil(viewModel.reviewDocument(), "no leverage step is ever built against the open position")
    }

    // MARK: - 4. Margin removal

    func testRemovingMarginFromAnOverCollateralisedPositionShowsTheNewLiquidation() throws {
        // Entry 100, 1 coin at 2×, 120 in: no liquidation price yet.
        let position = try position(entry: "100", size: "1", marginUsed: "120", pnl: "0", liquidation: nil)
        let change = PerpsMarginFlows.change(position: position, market: market(mark: 100), account: account(), delta: -60)
        XCTAssertNil(change.issue)
        XCTAssertNil(change.liquidationBefore)
        // (100 - 60) / (1 - 1/80) = 40.51
        let after = try XCTUnwrap(change.liquidationAfter, "never 'None' once margin comes out")
        XCTAssertEqual(NSDecimalNumber(decimal: after).doubleValue, 40.506, accuracy: 0.01)
        let review = try PerpsMarginFlows.review(position: position, market: market(mark: 100), change: change, nonce: 1)
        let row = try XCTUnwrap(review.rows.first { $0.label == "perpsLiquidation".localized })
        XCTAssertEqual(row.value, PerpsMarginFlows.arrow("perpsNone".localized, PerpsFormat.price(after)))
    }

    func testRemovingMarginThatWouldLiquidateIsRefused() throws {
        // The venue already shows liquidation at 95 with the price at 100; the
        // formula step for taking 10 out pushes it past the price.
        let position = try position(entry: "100", size: "1", marginUsed: "60", pnl: "0", liquidation: "95")
        let change = PerpsMarginFlows.change(position: position, market: market(mark: 100), account: account(), delta: -10)
        XCTAssertEqual(change.issue, .liquidatesNow)
        let review = try PerpsMarginFlows.review(position: position, market: market(mark: 100), change: change, nonce: 1)
        XCTAssertEqual(review.blockingIssue, "perpsMarginWouldLiquidate".localized)
        // Adding margin is never refused for this reason.
        XCTAssertNil(PerpsMarginFlows.change(position: position, market: market(mark: 100), account: account(), delta: 10).issue)
    }

    // MARK: - 5. One tier per review

    func testFeeShownAndFeeSignedUseTheTicketsTier() async throws {
        // The global tier moves to Bronze; this ticket priced with Gold keeps Gold end to end.
        let viewModel = PerpsTicketViewModel(side: .long, market: market(), account: account(),
                                             vault: context(supported: true), vultTier: .gold)
        addTeardownBlock { await PerpsVultTier.refresh(vaultKey: "guard-tests-reset") { nil } }
        await PerpsVultTier.refresh(vaultKey: "guard-tests") { .bronze }
        XCTAssertEqual(viewModel.costs?.vultTier, .gold)
        let document = try XCTUnwrap(viewModel.reviewDocument())
        let order = try XCTUnwrap(document.requests.last)
        let gold = PerpsConfig.builderFeeTenthsBp(tier: .gold)
        XCTAssertTrue(order.action.jsonString.contains(#""f":\#(gold)"#), "the order carries the Gold builder fee")
        XCTAssertNotEqual(gold, PerpsConfig.builderFeeTenthsBp(tier: .bronze))

        // Ultimate waives the fee: no builder field at all, and no fee shown.
        let ultimate = PerpsTicketViewModel(side: .long, market: market(), account: account(),
                                            vault: context(supported: true), vultTier: .ultimate)
        let waived = try XCTUnwrap(ultimate.reviewDocument()?.requests.last)
        XCTAssertFalse(waived.action.jsonString.contains("builder"))
        XCTAssertEqual(ultimate.costs.map { $0.builderFee - $0.vultDiscount }, 0)
    }
}
