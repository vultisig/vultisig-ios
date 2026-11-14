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
        exits.refresh(PerpsExitInputs(side: .long, entry: 67_074, reference: 64_000, size: Decimal(string: "0.00298") ?? 0,
                                      liquidation: 33_908, takeProfit: nil, stopLoss: nil))
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
                                             vault: context(supported: true), vultTier: VultDiscountTier.gold)
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
                                            vault: context(supported: true), vultTier: VultDiscountTier.ultimate)
        let waived = try XCTUnwrap(ultimate.reviewDocument()?.requests.last)
        XCTAssertFalse(waived.action.jsonString.contains("builder"))
        XCTAssertEqual(ultimate.costs.map { $0.builderFee - $0.vultDiscount }, 0)
    }
    // MARK: - Stale prices (codex round on a7ecc9a4f)

    func testPositionSheetsRefuseAReviewWhilePricesAreUpdating() throws {
        let position = try position()
        let close = PerpsCloseViewModel(position: position, market: market(), vultTier: nil)
        close.setPricesFresh(false)
        XCTAssertEqual(close.issue, "perpsPricesUpdating".localized)
        XCTAssertNil(close.reviewDocument())
        close.setPricesFresh(true)
        XCTAssertNotNil(close.reviewDocument())

        let margin = PerpsMarginViewModel(position: position, market: market(), account: account())
        margin.amountText = "5"
        margin.setPricesFresh(false)
        XCTAssertFalse(margin.canReview)
        XCTAssertNil(margin.reviewDocument())

        let exits = PerpsAutoCloseViewModel(side: .long, entry: 67_074, reference: 66_969, size: Decimal(string: "0.00298") ?? 0,
                                            liquidation: 33_908, szDecimals: 5, takeProfit: nil, stopLoss: 62_000)
        exits.stopText = "63000"
        exits.setPricesFresh(false)
        XCTAssertEqual(exits.issue, "perpsPricesUpdating".localized)
        XCTAssertNil(exits.exitsReview(position: position, market: market(), existing: [], tier: nil, nonce: 1))
    }

    func testConnectionIsFreshOnlyAfterARecentGoodTick() async {
        let viewModel = PerpsMarketViewModel(coin: "BTC", repository: StubRepository(market: market()))
        XCTAssertFalse(viewModel.connection.isFresh(), "no tick yet")
        await viewModel.refreshPrices()
        XCTAssertTrue(viewModel.connection.isFresh())
        XCTAssertFalse(viewModel.connection.isFresh(now: Date().addingTimeInterval(PerpsConnection.freshFor + 1)), "an old tick expires")
        let failing = PerpsMarketViewModel(coin: "BTC", repository: StubRepository(market: market(), fails: true))
        await failing.refreshPrices()
        XCTAssertTrue(failing.connection.isOffline)
        XCTAssertFalse(failing.connection.isFresh())
    }

    // MARK: - Stop editor follows the position

    func testStopEditorFollowsDirectionAndUntouchedTriggers() throws {
        let exits = PerpsAutoCloseViewModel(side: .long, entry: 100, reference: 100, size: 1, liquidation: 60, szDecimals: 2,
                                            takeProfit: 120, stopLoss: 90)
        // Another client moved the stop; the take profit was typed here and stays.
        exits.takeText = "125"
        exits.refresh(PerpsExitInputs(side: .long, entry: 100, reference: 100, size: 1, liquidation: 60, takeProfit: 120, stopLoss: 92))
        XCTAssertEqual(exits.stopText, "92", "an untouched field follows the venue")
        XCTAssertEqual(exits.stopLoss, 92)
        XCTAssertEqual(exits.takeText, "125", "a typed field is kept")

        // The position flipped to a short: nothing typed for the long applies.
        exits.refresh(PerpsExitInputs(side: .short, entry: 100, reference: 100, size: 1, liquidation: 140, takeProfit: nil, stopLoss: 110))
        XCTAssertEqual(exits.side, .short)
        XCTAssertEqual(exits.takeText, "")
        XCTAssertEqual(exits.stopText, "110")
        XCTAssertNil(exits.issue)

        // A document is only built for the side the editor validated.
        let long = try position()
        XCTAssertNil(exits.exitsReview(position: long, market: market(), existing: [], tier: nil, nonce: 1))
    }

    // MARK: - Tier per vault, newest lookup wins

    func testTierIsKeptPerVaultAndAnOlderLookupNeverLandsLast() async throws {
        addTeardownBlock { await PerpsVultTier.refresh(vaultKey: "guard-reset") { nil } }
        await PerpsVultTier.refresh(vaultKey: "guard-vault-a") { .gold }
        await PerpsVultTier.refresh(vaultKey: "guard-vault-b") { .silver }
        XCTAssertEqual(PerpsVultTier.tier(for: "guard-vault-a"), .gold, "switching vault keeps each vault's own tier")
        XCTAssertEqual(PerpsVultTier.tier(for: "guard-vault-b"), .silver)

        // Two lookups for the same vault: the older one finishes last and is dropped.
        await PerpsVultTier.refresh(vaultKey: "guard-vault-a") {
            await PerpsVultTier.refresh(vaultKey: "guard-vault-a") { .platinum }
            return .bronze
        }
        XCTAssertEqual(PerpsVultTier.tier(for: "guard-vault-a"), .platinum)

        // A ticket for vault A prices with vault A's tier, whatever the active vault.
        await PerpsVultTier.refresh(vaultKey: "guard-vault-b") { .silver }
        var vault = context(supported: true)
        vault.tierKey = "guard-vault-a"
        let ticket = PerpsTicketViewModel(side: .long, market: market(), account: account(), vault: vault)
        XCTAssertEqual(ticket.vultTier, .platinum)

        // The stop-loss edit carries the tier it is given, not the global one.
        let edit = try PerpsFlows.editExits(position: try position(), market: market(), existing: [], stopLoss: 60_000, takeProfit: nil,
                                            tier: .platinum, nonce: 1)
        let platinum = PerpsConfig.builderFeeTenthsBp(tier: .platinum)
        XCTAssertTrue(try XCTUnwrap(edit.requests.last).action.jsonString.contains(#""f":\#(platinum)"#))
    }

    // MARK: - Overlapping refreshes

    func testAnOlderAccountRefreshFinishingLastIsDropped() async throws {
        let open = try position()
        let repository = StubRepository(market: market(), accounts: [account(), account(positions: [open])], gateFirstAccount: true)
        let viewModel = PerpsMarketViewModel(coin: "BTC", repository: repository, address: "0x1")
        // The first refresh (no position yet) stalls; the second (position open) completes.
        let older = Task { await viewModel.refreshPrices() }
        while repository.accountCalls < 1 { await Task.yield() }
        await viewModel.refreshPrices()
        XCTAssertNotNil(viewModel.position)
        repository.releaseFirst()
        await older.value
        XCTAssertNotNil(viewModel.position, "the stale snapshot without the position never lands")
    }
}

// The protocol is async; the stub answers at once.
// swiftlint:disable async_without_await
/// Markets and accounts on demand; the first account call can be held back.
private final class StubRepository: PerpsRepository, @unchecked Sendable {
    private let lock = NSLock()
    private let market: PerpsMarket
    private let accounts: [PerpsAccountSnapshot]
    private let fails: Bool
    private let gateFirstAccount: Bool
    private var calls = 0
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    init(market: PerpsMarket, accounts: [PerpsAccountSnapshot] = [], fails: Bool = false, gateFirstAccount: Bool = false) {
        self.market = market
        self.accounts = accounts
        self.fails = fails
        self.gateFirstAccount = gateFirstAccount
    }

    var accountCalls: Int { lock.withLock { calls } }

    func releaseFirst() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            released = true
            defer { gate = nil }
            return gate
        }
        continuation?.resume()
    }

    func markets() async throws -> [PerpsMarket] {
        if fails { throw URLError(.notConnectedToInternet) }
        return [market]
    }

    func account(address _: String) async throws -> PerpsAccountSnapshot {
        let index: Int = lock.withLock {
            defer { calls += 1 }
            return calls
        }
        if index == 0, gateFirstAccount {
            await withCheckedContinuation { continuation in
                let resumeNow: Bool = lock.withLock {
                    if released { return true }
                    gate = continuation
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        }
        return accounts[min(index, accounts.count - 1)]
    }

    func activity(address _: String, fills _: [HLFill]) async throws -> [PerpsActivityItem] { [] }
    func candles(coin _: String, interval _: HLCandleInterval, since _: Date, until _: Date) async throws -> [HLCandle] { [] }
}
// swiftlint:enable async_without_await
