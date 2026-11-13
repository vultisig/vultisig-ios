//
//  PerpsPositionFlowsTests.swift
//  VultisigAppTests
//
//  withdraw quote and withdraw3, isolated margin
//  add / remove, partial close by fraction, and position outcomes.
//

import XCTest
@testable import VultisigApp

final class PerpsPositionFlowsTests: XCTestCase {
    private let vault = PerpsVaultContext(name: "Main Vault", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: 0,
                                          tradingAddress: "0x1185000000000000000000000000000000007ce0")

    private func market(mark: Decimal = 66_969) -> PerpsMarket {
        PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: mark,
                    midPrice: mark, previousDayPrice: 66_000, hourlyFunding: 0, openInterest: 1, dayVolume: 1, marginTiers: [])
    }

    /// The design fixture's BTC long: 0.00298 BTC 2× isolated, $99.94 in, +$12.40.
    private func position(isolated: Bool = true) throws -> HLPosition {
        let json = #"{"coin":"BTC","szi":"0.00298","leverage":{"type":"\#(isolated ? "isolated" : "cross")","value":2},"entryPx":"67074","#
            + #""positionValue":"212.3","unrealizedPnl":"12.4","returnOnEquity":"0.124","liquidationPx":"33908","marginUsed":"112.34","maxLeverage":40}"#
        return try JSONDecoder().decode(HLPosition.self, from: Data(json.utf8))
    }

    private func account(equity: Decimal = Decimal(string: "262.15") ?? 0, withdrawable: Decimal = Decimal(string: "149.81") ?? 0,
                         positions: [HLPosition] = [], hasWithdrawn: Bool? = false) -> PerpsAccountSnapshot {
        var snapshot = PerpsAccountSnapshot(address: "0x1", accountValue: equity, withdrawable: withdrawable,
                                            marginUsed: equity - withdrawable, totalNotional: 212, positions: positions, openOrders: [], fills: [])
        snapshot.hasWithdrawnBefore = hasWithdrawn
        return snapshot
    }

    private func close(_ lhs: Decimal?, _ rhs: Decimal, _ tolerance: Double = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        guard let lhs else { return XCTFail("nil", file: file, line: line) }
        XCTAssertEqual(NSDecimalNumber(decimal: lhs).doubleValue, NSDecimalNumber(decimal: rhs).doubleValue, accuracy: tolerance, file: file, line: line)
    }

    // MARK: - Withdraw

    func testWithdrawQuoteUsesWithdrawableAndChargesActivationOnce() {
        let first = PerpsWithdrawQuote.make(amount: 100, account: account())
        XCTAssertEqual(first.totalFees, 2, "$1 withdraw3 fee + $1 one-time activation")
        XCTAssertEqual(first.receive, 98)
        XCTAssertNil(first.issue)
        let later = PerpsWithdrawQuote.make(amount: 100, account: account(hasWithdrawn: true))
        XCTAssertEqual(later.receive, 99)
        XCTAssertEqual(PerpsWithdrawQuote.make(amount: 100, account: account(hasWithdrawn: nil)).activationFee, 1, "unknown history counts as first")
        XCTAssertEqual(PerpsWithdrawQuote.make(amount: 200, account: account()).issue, .moreThanWithdrawable, "200 is under equity, over withdrawable")
        XCTAssertEqual(PerpsWithdrawQuote.make(amount: 2, account: account()).issue, .belowFees)
    }

    func testWithdrawReviewAndWithdraw3Wire() throws {
        let document = try PerpsFlows.withdraw(amount: 100, account: account(), vault: vault, nonce: 1_731_400_000_123)
        XCTAssertEqual(document.amount, "$100")
        XCTAssertEqual(document.caption, "perpsUsdcOnArbitrum".localized, "the vault is never in the subtitle")
        XCTAssertEqual(document.rows.first?.style, .vault)
        XCTAssertEqual(document.rows.first?.value, "Main Vault")
        XCTAssertEqual(document.rows.dropFirst().map(\.value), ["$98.00", "$2.00", "perpsAboutFiveMin".localized])
        XCTAssertNotNil(document.footer)
        XCTAssertNil(document.fees, "fees are a row, not repeated in Details")
        let request = try XCTUnwrap(document.requests.first)
        XCTAssertEqual(request.kind, .withdraw3)
        XCTAssertEqual(request.action.jsonString,
                       #"{"type":"withdraw3","signatureChainId":"0xa4b1","hyperliquidChain":"Mainnet","#
                       + #""destination":"0x9d7c000000000000000000000000000000003003","amount":"100","time":1731400000123}"#)
        XCTAssertEqual(request.typedData.primaryType, "HyperliquidTransaction:Withdraw")
        XCTAssertNil(request.vaultAddress)
        XCTAssertNil(request.expiresAfter)
        let repeatWithdrawal = try PerpsFlows.withdraw(amount: Decimal(string: "49.5") ?? 0, account: account(hasWithdrawn: true), vault: vault, nonce: 2)
        XCTAssertNil(repeatWithdrawal.footer)
        XCTAssertEqual(repeatWithdrawal.requests.first?.action["amount"], .string("49.5"))
    }

    @MainActor
    func testTradingAccountSummaryAddsUpToEquityAndMaxIsWithdrawable() throws {
        let snapshot = account(positions: [try position()])
        let summary = PerpsAccountSummary.make(snapshot)
        XCTAssertEqual(summary.available, Decimal(string: "149.81"))
        XCTAssertEqual(summary.inPositions, Decimal(string: "112.34"), "262.15 − 149.81")
        XCTAssertEqual(summary.available + summary.inPositions, snapshot.equity)
        let viewModel = PerpsWithdrawViewModel(account: snapshot, vault: vault)
        viewModel.applyMax()
        XCTAssertEqual(viewModel.amountText, "149.81")
        XCTAssertEqual(viewModel.quote.receive, Decimal(string: "147.81"))
    }

    func testKeypadKeepsADotAndTwoDecimals() {
        var text = ""
        for key: PerpsKeypadKey in [.digit(0), .digit(1), .dot, .dot, .digit(5), .digit(0), .digit(9)] {
            text = PerpsKeypadKey.apply(key, to: text)
        }
        XCTAssertEqual(text, "1.50")
        XCTAssertEqual(PerpsKeypadKey.apply(.delete, to: text), "1.5")
        XCTAssertEqual(PerpsKeypadKey.apply(.dot, to: ""), "0.")
        XCTAssertEqual(PerpsInput.decimal("1.50"), Decimal(string: "1.5"))
    }

    // MARK: - Margin

    func testAddMarginMovesLiquidationByTheFormulaStep() throws {
        let position = try position()
        let change = PerpsMarginFlows.change(position: position, market: market(), account: account(), delta: 50)
        XCTAssertNil(change.issue)
        XCTAssertEqual(change.liquidationBefore, 33_908, "before is the venue's figure the position screen shows")
        XCTAssertEqual(change.marginBefore, Decimal(string: "99.94"), "margin put in, without the uPnL")
        XCTAssertEqual(change.marginAfter, Decimal(string: "149.94"))
        XCTAssertEqual(change.availableAfter, Decimal(string: "99.81"))
        let size: Decimal = Decimal(string: "0.00298") ?? 0
        let maintenance = Decimal(1) / 80
        // A long's liquidation falls by delta / size / (1 - maintenance rate).
        close(change.liquidationAfter, 33_908 - 50 / size / (1 - maintenance), 0.5)
        let request = try XCTUnwrap(PerpsMarginFlows.review(position: position, market: market(), change: change, nonce: 9).requests.first)
        XCTAssertEqual(request.action.jsonString, #"{"type":"updateIsolatedMargin","asset":0,"isBuy":true,"ntli":50000000}"#)
        XCTAssertEqual(request.expiresAfter, 9 + HLNonceSource.defaultExpiryMs)
    }

    func testRemoveMarginIsCappedAndCrossIsRefused() throws {
        let position = try position()
        // Value 0.00298 × 66,969 = 199.57; keeps max(IM 99.78, 10% 19.96) = 99.78.
        let removable = PerpsMarginFlows.maxRemovable(position: position, markPrice: 66_969)
        XCTAssertEqual(removable, Decimal(string: "12.55"), "112.34 − 99.78, rounded down to the cent")
        let tooMuch = PerpsMarginFlows.change(position: position, market: market(), account: account(), delta: -20)
        XCTAssertEqual(tooMuch.issue, .moreThanRemovable)
        let removal = PerpsMarginFlows.change(position: position, market: market(), account: account(), delta: -10)
        XCTAssertNil(removal.issue)
        XCTAssertGreaterThan(try XCTUnwrap(removal.liquidationAfter), 33_908, "less margin moves a long's liquidation up")
        let request = try PerpsMarginFlows.review(position: position, market: market(), change: removal, nonce: 1).requests[0]
        XCTAssertEqual(request.action["ntli"], .int(-10_000_000))
        XCTAssertEqual(PerpsMarginFlows.change(position: position, market: market(), account: account(), delta: 500).issue, .moreThanAvailable)
        XCTAssertEqual(PerpsMarginFlows.change(position: try self.position(isolated: false), market: market(), account: account(), delta: 5).issue,
                       .crossPosition)
    }

    // MARK: - Close

    func testCloseFractionsRoundDownAndAllIsExact() {
        let total: Decimal = Decimal(string: "0.00298") ?? 0
        XCTAssertEqual(PerpsCloseFraction.quarter.size(of: total, szDecimals: 5), Decimal(string: "0.00074"))
        XCTAssertEqual(PerpsCloseFraction.half.size(of: total, szDecimals: 5), Decimal(string: "0.00149"))
        XCTAssertEqual(PerpsCloseFraction.all.size(of: total, szDecimals: 5), total)
        XCTAssertEqual(PerpsCloseFraction.all.title, "perpsAll".localized)
        XCTAssertEqual(PerpsCloseFraction.quarter.title, "25%")
        // 25% of a 0.00003 position rounds to 0 at 5 decimals: that chip is disabled.
        XCTAssertFalse(PerpsCloseFraction.quarter.isAvailable(total: Decimal(string: "0.00003") ?? 0, szDecimals: 5))
        XCTAssertTrue(PerpsCloseFraction.all.isAvailable(total: Decimal(string: "0.00003") ?? 0, szDecimals: 5))
    }

    // MARK: - Edge states

    func testPartialFillRoundsOnceAndAddsUp() throws {
        let position = try position()
        let fill = PerpsPartialFill.make(position: position, requested: Decimal(string: "0.00074") ?? 0,
                                         filled: Decimal(string: "0.0005") ?? 0, fillPrice: 71_124)
        XCTAssertEqual(fill.notClosed, Decimal(string: "0.00024"))
        XCTAssertEqual(fill.stillOpen, Decimal(string: "0.00248"))
        let gross = (71_124 - 67_074) * (Decimal(string: "0.0005") ?? 0)
        close(fill.netPnl, gross - fill.fees, 0.000_001)
        close(fill.fees, (Decimal(string: "0.0005") ?? 0) * 71_124 * (PerpsMath.baseTakerFeeRate + PerpsConfig.builderFeeRate), 0.000_001)
        // Back = the margin put in for the filled part + profit after fees, rounded once.
        close(fill.returned, PerpsMarginFlows.margin(of: position) * (Decimal(string: "0.0005") ?? 0) / (Decimal(string: "0.00298") ?? 1) + fill.netPnl,
              0.000_001)
        XCTAssertNotEqual(fill.returned.rounded(scale: 2), fill.returned, "kept at full precision until display")
    }

    func testRemainingPositionScalesSizeMarginAndPnl() throws {
        let position = try position()
        let left = PerpsCloseFlows.remaining(after: Decimal(string: "0.0005") ?? 0, of: position)
        XCTAssertEqual(left.szi.value, Decimal(string: "0.00248"))
        XCTAssertEqual(left.entryPx, position.entryPx)
        XCTAssertEqual(left.liquidationPx, position.liquidationPx)
        close(PerpsMarginFlows.margin(of: left), PerpsMarginFlows.margin(of: position) * (Decimal(string: "0.00248") ?? 0) / (Decimal(string: "0.00298") ?? 1),
              0.000_001)
        // "Close the rest" reviews the unfilled part against the remaining position.
        let document = try PerpsFlows.partialClose(position: left, market: market(), size: Decimal(string: "0.00024") ?? 0, nonce: 4)
        XCTAssertEqual(document.amountLabel, String(format: "perpsCloseAmount".localized, "0.00024 BTC"))
    }

    func testTriggerCoverageWarnsOnlyWhenAFixedSizeTriggerIsSmaller() throws {
        func trigger(size: String, positionTpsl: Bool?) throws -> HLFrontendOrder {
            try JSONDecoder().decode(HLFrontendOrder.self, from: Data((#"{"coin":"BTC","oid":7,"side":"A","sz":"\#(size)","limitPx":"62281","#
                + #""triggerPx":"62281","isTrigger":true,"isPositionTpsl":\#(positionTpsl.map { "\($0)" } ?? "null"),"reduceOnly":true,"#
                + #""orderType":"Stop Market","timestamp":1}"#).utf8))
        }
        let remaining = Decimal(string: "0.00248") ?? 0
        XCTAssertNil(PerpsTriggerCoverage.uncovered(triggers: [try trigger(size: "0", positionTpsl: true)], positionSize: remaining),
                     "a position TP/SL follows the position")
        XCTAssertNil(PerpsTriggerCoverage.uncovered(triggers: [try trigger(size: "0.00298", positionTpsl: false)], positionSize: remaining),
                     "reduce-only cannot flip, so a larger trigger is fine")
        XCTAssertNotNil(PerpsTriggerCoverage.uncovered(triggers: [try trigger(size: "0.001", positionTpsl: false)], positionSize: remaining))
    }

    func testPendingWithdrawalPersistsAndTurnsSlowAfterTenMinutes() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "perps-pending-\(UUID().uuidString)"))
        let start = Date(timeIntervalSince1970: 1_000_000)
        PerpsPendingWithdrawalStore.save(PerpsPendingWithdrawal(amount: 100, receive: 98, startedAt: start, account: "0xabc"), defaults)
        XCTAssertNil(PerpsPendingWithdrawalStore.load(account: "0xdef", defaults), "never shown on another trading account")
        let loaded = try XCTUnwrap(PerpsPendingWithdrawalStore.load(account: "0xABC", defaults))
        XCTAssertEqual(loaded.receive, 98)
        XCTAssertFalse(loaded.isSlow(now: start.addingTimeInterval(9 * 60)))
        XCTAssertTrue(loaded.isSlow(now: start.addingTimeInterval(14 * 60)))
        XCTAssertEqual(loaded.minutesAgo(now: start.addingTimeInterval(14 * 60 + 30)), 14)
        PerpsPendingWithdrawalStore.clear(defaults)
        XCTAssertNil(PerpsPendingWithdrawalStore.load(account: "0xabc", defaults))
    }

    func testDemoPendingWithdrawalOnlyComesBackToTheDemo() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "perps-pending-demo-\(UUID().uuidString)"))
        PerpsPendingWithdrawalStore.save(PerpsPendingWithdrawal(amount: 100, receive: 98, startedAt: Date(), account: "0xabc", isDemo: true), defaults)
        XCTAssertNil(PerpsPendingWithdrawalStore.load(account: "0xabc", defaults))
        XCTAssertNotNil(PerpsPendingWithdrawalStore.load(account: "0xabc", includeDemo: true, defaults))
    }

    @MainActor
    func testRemoveMarginBlockedKeepsTheAmountAndNamesTheLimit() throws {
        let position = try position()
        let viewModel = PerpsMarginViewModel(position: position, market: market(), account: account(), isAdding: false, prefill: 20)
        XCTAssertEqual(viewModel.amountText, "20", "the amount stays visible")
        XCTAssertEqual(viewModel.limitLine, String(format: "perpsUpTo".localized, "$12.55"))
        XCTAssertEqual(viewModel.issue, String(format: "perpsEnterOrLess".localized, "$12.55"))
        XCTAssertFalse(viewModel.canReview)
        viewModel.applyMax()
        XCTAssertEqual(viewModel.amountText, "12.55")
        XCTAssertTrue(viewModel.canReview)
    }

    func testPartialCloseIsReduceOnlyInCanonicalOrder() throws {
        let position = try position()
        let order = PerpsFlows.closeOrder(position: position, market: market(), size: Decimal(string: "0.0015") ?? 0)
        XCTAssertEqual(order.wire.jsonString, #"{"a":0,"b":false,"p":"66299","s":"0.0015","r":true,"t":{"limit":{"tif":"Ioc"}}}"#,
                       "a,b,p,s,r,t; sell at mid − 1%; no trailing zeros")
        let document = try PerpsFlows.partialClose(position: position, market: market(), size: Decimal(string: "0.00149") ?? 0, nonce: 3)
        XCTAssertEqual(document.amountLabel, String(format: "perpsCloseAmount".localized, "0.00149 BTC"), "titled by the amount, not 50%")
        let estimate = PerpsFlows.closeEstimate(position: position, market: market(), size: Decimal(string: "0.00149") ?? 0)
        XCTAssertEqual(document.amount, PerpsFormat.usd(estimate.realizedPnl - estimate.fees, signed: true))
        XCTAssertEqual(document.rows.map(\.label), ["perpsValue", "perpsEstPrice", "perpsFees", "perpsBackToTradingAccount"].map(\.localized))
        // Back = half the margin in, minus the half of uPnL already in it, plus the P&L at the price, minus fees.
        close(estimate.returned, Decimal(string: "56.17")! - Decimal(string: "6.2")! + estimate.realizedPnl - estimate.fees, 0.001)
        // So the close sheet adds up on screen: back = half the margin put in + est. profit.
        close(estimate.returned, PerpsMarginFlows.margin(of: position) / 2 + PerpsCloseFlows.netProfit(estimate), 0.0001)
        XCTAssertEqual(document.requests.first?.action["orders"].map { $0.jsonString.contains(#""r":true"#) }, true)
    }

    // MARK: - Outcomes

    func testOutcomesNetFeesAndReturnTheRest() throws {
        let position = try position()
        let stop = PerpsOutcome.make(kind: .stopLoss, position: position, fillPrice: 62_262, triggerPrice: 62_281)
        close(stop.margin, Decimal(string: "99.94") ?? 0, 0.0001)
        let gross = (62_262 - 67_074) * (Decimal(string: "0.00298") ?? 0)
        XCTAssertEqual(stop.netPnl, gross - stop.fees, "full precision, rounded once where shown")
        XCTAssertEqual(stop.returned, stop.margin + stop.netPnl, "what comes back adds up")
        XCTAssertLessThan(stop.netPnl, 0)
        let take = PerpsOutcome.make(kind: .takeProfit, position: position, fillPrice: 74_988, triggerPrice: 75_000)
        XCTAssertGreaterThan(take.netPnl, 0)
        XCTAssertEqual(take.returned, take.margin + take.netPnl)
        let liquidation = PerpsOutcome.make(kind: .liquidated, position: position, fillPrice: 33_908, triggerPrice: nil)
        close(liquidation.fees, (Decimal(string: "0.00298") ?? 0) * 33_908 * PerpsMath.baseTakerFeeRate, 0.006)
        XCTAssertGreaterThanOrEqual(liquidation.returned, 0)
    }

    func testOutcomeFromFillsSumsClosedPnlAndFees() throws {
        let fills = try JSONDecoder().decode([HLFill].self, from: Data((#"[{"coin":"ETH","px":"2463","sz":"0.5","side":"A","time":1,"#
            + #""dir":"Close Long","closedPnl":"-60.0","fee":"0.6","tid":1,"oid":1},{"coin":"ETH","px":"2461","sz":"0.5","side":"A","time":2,"#
            + #""dir":"Close Long","closedPnl":"-61.0","fee":"0.53","tid":2,"oid":1}]"#).utf8))
        let outcome = try XCTUnwrap(PerpsOutcome.fromFills(fills, kind: .liquidated, isLong: true, leverage: 20, margin: Decimal(string: "131.38") ?? 0,
                                                           triggerPrice: nil))
        XCTAssertEqual(outcome.fillPrice, 2_462)
        XCTAssertEqual(outcome.netPnl, Decimal(string: "-122.13"))
        XCTAssertEqual(outcome.returned, Decimal(string: "9.25"))
    }

    func testDemoStatesAddUp() throws {
        let snapshot = PerpsDemoRepository.snapshot(address: "0x0", btcMark: 71_130, entry: 67_074, now: Date())
        let after = PerpsDemoRepository.afterWithdrawal(snapshot)
        XCTAssertEqual(after.availableToWithdraw, snapshot.availableToWithdraw - 100)
        XCTAssertEqual(after.equity, snapshot.equity - 100)
        let position = try XCTUnwrap(snapshot.positions.first)
        let stop = PerpsDemoRepository.outcome(.stopLoss, position: position, triggers: snapshot.triggerOrders, market: market(mark: 71_130))
        XCTAssertEqual(stop.triggerPrice, snapshot.triggerOrders.first?.triggerPx?.value)
        XCTAssertLessThan(stop.fillPrice, try XCTUnwrap(stop.triggerPrice))
        let take = PerpsDemoRepository.outcome(.takeProfit, position: position, triggers: snapshot.triggerOrders, market: market(mark: 71_130))
        XCTAssertEqual(take.triggerPrice, 71_100, "6% over entry, to the nearest $100")
        XCTAssertGreaterThan(take.netPnl, 0)
    }
}
