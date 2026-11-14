//
//  PerpsFlowsTests.swift
//  VultisigAppTests
//
//  tiered liquidation (the integration spec's worked
//  check), ticket costs, and the review documents each flow builds.
//

import XCTest
@testable import VultisigApp

final class PerpsFlowsTests: XCTestCase {
    private func market(maxLeverage: Int = 40, tiers: [PerpsMarginTier] = [], hourlyFunding: Decimal = 0.0000125) -> PerpsMarket {
        PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: maxLeverage, onlyIsolated: false, markPrice: 66_969,
                    midPrice: 66_969, previousDayPrice: 66_000, hourlyFunding: hourlyFunding, openInterest: 1, dayVolume: 1, marginTiers: tiers)
    }

    private func close(_ lhs: Decimal?, _ rhs: Decimal, _ tolerance: Double = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        guard let lhs else { return XCTFail("nil", file: file, line: line) }
        XCTAssertEqual(NSDecimalNumber(decimal: lhs).doubleValue, NSDecimalNumber(decimal: rhs).doubleValue, accuracy: tolerance, file: file, line: line)
    }

    // MARK: - Liquidation

    /// Spec §7 worked check: BTC isolated 10x, entry 100,000, 0.01 BTC, max 40x.
    func testSpecWorkedCheck() {
        let schedule = PerpsMarginSchedule(tiers: [PerpsMarginTier(lowerBound: 0, maxLeverage: 40),
                                                   PerpsMarginTier(lowerBound: 150_000_000, maxLeverage: 20)], fallbackMaxLeverage: 40)
        close(PerpsMath.liquidationPrice(side: .long, entryPrice: 100_000, size: 0.01, collateral: 100, schedule: schedule), 91_139.24)
        close(PerpsMath.liquidationPrice(side: .short, entryPrice: 100_000, size: 0.01, collateral: 100, schedule: schedule), 108_641.98)
    }

    /// Large enough to sit in the second tier: equity equals tiered maintenance at the result.
    func testTieredLiquidationLandsOnMaintenance() throws {
        let schedule = PerpsMarginSchedule(tiers: [PerpsMarginTier(lowerBound: 0, maxLeverage: 10),
                                                   PerpsMarginTier(lowerBound: 3_000_000, maxLeverage: 5)], fallbackMaxLeverage: 10)
        let entry: Decimal = 50_000
        let size: Decimal = 100
        let collateral: Decimal = 1_000_000
        let price = try XCTUnwrap(PerpsMath.liquidationPrice(side: .long, entryPrice: entry, size: size, collateral: collateral, schedule: schedule))
        XCTAssertEqual(schedule.tierIndex(notional: size * price), 1)
        let equity = collateral + (price - entry) * size
        close(equity, schedule.maintenanceMargin(notional: size * price), 0.001)
        XCTAssertEqual(schedule.deduction(tier: 1), 3_000_000 * (Decimal(1) / 10 - Decimal(1) / 20))
    }

    func testMarginTablesFromMeta() {
        let meta = HLAssetMeta(name: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: nil, isDelisted: nil, marginTableId: 51)
        let tables = [HLMarginTableEntry(id: 51, table: HLMarginTable(description: "tiered 10x", marginTiers: [
            HLMarginTier(lowerBound: HLDecimal(0), maxLeverage: 10), HLMarginTier(lowerBound: HLDecimal(3_000_000), maxLeverage: 5)
        ]))]
        XCTAssertEqual(HyperliquidPerpsRepository.marginTiers(for: meta, tables: tables).map(\.maxLeverage), [10, 5])
        let small = HLAssetMeta(name: "X", szDecimals: 0, maxLeverage: 3, onlyIsolated: nil, isDelisted: nil, marginTableId: 3)
        XCTAssertEqual(HyperliquidPerpsRepository.marginTiers(for: small, tables: nil), [PerpsMarginTier(lowerBound: 0, maxLeverage: 3)])
    }

    func testMetaDecodesMarginTablePairs() throws {
        let json = #"{"universe":[{"szDecimals":5,"name":"BTC","maxLeverage":40,"marginTableId":56}],"#
            + #""marginTables":[[56,{"description":"","marginTiers":[{"lowerBound":"0.0","maxLeverage":40},{"lowerBound":"150000000.0","maxLeverage":20}]}]]}"#
        let meta = try JSONDecoder().decode(HLMeta.self, from: Data(json.utf8))
        XCTAssertEqual(meta.marginTables?.first?.table.marginTiers.count, 2)
    }

    // MARK: - Ticket costs

    func testCostsAddFundingAndMinimumTransfer() throws {
        let market = market()
        let ticket = PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated, limitPrice: nil, takeProfit: nil, stopLoss: 62_500)
        let plan = try PerpsOrderPlanner.plan(market: market, ticket: ticket, nonce: 1, builder: PerpsConfig.builderFee)
        let funded = PerpsFlows.costs(plan: plan, availableToTrade: 500)
        XCTAssertEqual(funded.transfer, 0)
        close(funded.fundingPerDay, plan.estimate.notional * 0.0000125 * 24, 0.000001)
        let short = PerpsFlows.costs(plan: plan, availableToTrade: 98)
        XCTAssertEqual(short.transfer, (plan.estimate.margin + short.tradingFees - 98 + HLCctp.forwardingFee).rounded(scale: 2, mode: .up),
                       "a shortfall is topped up by CCTP, plus its 0.20 forwarding fee")
        let fresh = PerpsFlows.costs(plan: plan, availableToTrade: 0, isNewAccount: true)
        XCTAssertEqual(fresh.transfer, (plan.estimate.margin + fresh.tradingFees + HLCctp.forwardingFee + HLCctp.activationFee)
            .rounded(scale: 2, mode: .up))
    }

    /// Liquidation distance next to every liquidation price (R20): "49% below",
    /// one decimal under 10%, "above" for shorts.
    func testLiquidationDistanceText() {
        XCTAssertEqual(PerpsFormat.liquidationDistance(price: 66_975, liquidation: Decimal(string: "33911.4"), isLong: true),
                       String(format: "perpsPercentBelow".localized, "49%"))
        XCTAssertEqual(PerpsFormat.liquidationDistance(price: 2_510, liquidation: Decimal(string: "2489.39"), isLong: true),
                       String(format: "perpsPercentBelow".localized, "0.8%"))
        XCTAssertEqual(PerpsFormat.liquidationDistance(price: 100, liquidation: 112, isLong: false),
                       String(format: "perpsPercentAbove".localized, "12%"))
        XCTAssertNil(PerpsFormat.liquidationDistance(price: 100, liquidation: nil, isLong: true))
    }

    /// Leverage stops are evenly spaced and end on the market's max; the live
    /// preview matches the ticket's own estimate; quick picks floor to cents.
    @MainActor
    func testLeverageStopsPreviewAndQuickPicks() {
        let vault = PerpsVaultContext(name: "Main", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: 0,
                                      tradingAddress: nil)
        let btc = PerpsTicketViewModel(side: .long, market: market(maxLeverage: 40), account: nil, vault: vault)
        XCTAssertEqual(btc.leverageOptions, [1, 2, 3, 5, 10, 20, 40])
        let eth = PerpsTicketViewModel(side: .long, market: market(maxLeverage: 25), account: nil, vault: vault)
        XCTAssertEqual(eth.leverageOptions, [1, 2, 3, 5, 10, 20, 25])
        btc.leverage = 2
        let preview = btc.preview(leverage: 2)
        XCTAssertEqual(preview.size, btc.estimate?.notional)
        XCTAssertEqual(preview.liquidation, btc.estimate?.liquidationPrice)
        let funded = PerpsVaultContext(name: "Main", address: vault.address, arbitrumUsdcBalance: Decimal(string: "250.07"), tradingAddress: nil)
        let ticket = PerpsTicketViewModel(side: .long, market: market(), account: nil, vault: funded)
        // From the vault: 250.07 less the 0.20 + 1.00 deposit fees, then room for 2x trading fees.
        ticket.applyFraction(Decimal(string: "0.25") ?? 0)
        XCTAssertEqual(ticket.amountText, "62.03")
        ticket.applyMax()
        let margin = PerpsInput.decimal(ticket.amountText) ?? 0
        let fees = margin * 2 * (PerpsMath.baseTakerFeeRate + PerpsConfig.builderFeeRate(tier: nil))
        XCTAssertLessThanOrEqual(margin + fees + HLCctp.forwardingFee + HLCctp.activationFee, Decimal(string: "250.07") ?? 0,
                                 "Max never asks for more than the vault holds")
    }

    /// The explainer tells apart a stop that acts first, one the price already
    /// crossed, one exactly at liquidation and one past it, for both sides.
    func testStopPlacementForExplainer() {
        // Long: mark 100, liquidation 80.
        XCTAssertEqual(PerpsStopPlacement.of(stop: 90, mark: 100, liquidation: 80, isLong: true), .beforeLiquidation)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 100, mark: 100, liquidation: 80, isLong: true), .crossed)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 105, mark: 100, liquidation: 80, isLong: true), .crossed)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 80, mark: 100, liquidation: 80, isLong: true), .atLiquidation)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 75, mark: 100, liquidation: 80, isLong: true), .pastLiquidation)
        // Short: mark 100, liquidation 120.
        XCTAssertEqual(PerpsStopPlacement.of(stop: 110, mark: 100, liquidation: 120, isLong: false), .beforeLiquidation)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 95, mark: 100, liquidation: 120, isLong: false), .crossed)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 120, mark: 100, liquidation: 120, isLong: false), .atLiquidation)
        XCTAssertEqual(PerpsStopPlacement.of(stop: 125, mark: 100, liquidation: 120, isLong: false), .pastLiquidation)
        // Every case has copy in every locale.
        let placements: [PerpsStopPlacement] = [.beforeLiquidation, .crossed, .atLiquidation, .pastLiquidation]
        XCTAssertEqual(Set(placements.map(\.explainKey)).count, 4)
        for placement in placements {
            XCTAssertNotEqual(placement.explainKey.localized, placement.explainKey)
        }
    }

    /// The explainer's rows are always in price order, highest at the top,
    /// including after the price passed the stop or the stop sits at liquidation.
    func testLiquidationLadderIsInPriceOrder() {
        func order(_ isLong: Bool, mark: Decimal, entry: Decimal?, stop: Decimal?, liq: Decimal?) -> [PerpsLadderRow] {
            PerpsLadderRow.ordered(isLong: isLong, mark: mark, entry: entry, stopLoss: stop, liquidation: liq)
        }
        // Long, in profit: now 71,130 > entry 66,975 > stop 62,287 > liquidation 33,911.
        XCTAssertEqual(order(true, mark: 71_130, entry: 66_975, stop: 62_287, liq: 33_911), [.now, .entry, .stopLoss, .distance, .liquidation])
        // Long, price already under the stop: entry > stop > now > liquidation.
        XCTAssertEqual(order(true, mark: 62_000, entry: 66_975, stop: 62_287, liq: 33_911), [.entry, .stopLoss, .now, .distance, .liquidation])
        // Long, stop exactly at liquidation: liquidation is the last row.
        XCTAssertEqual(order(true, mark: 71_130, entry: 66_975, stop: 33_911, liq: 33_911), [.now, .entry, .stopLoss, .distance, .liquidation])
        // Long, stop past liquidation: it sits under liquidation.
        XCTAssertEqual(order(true, mark: 71_130, entry: 66_975, stop: 30_000, liq: 33_911), [.now, .entry, .distance, .liquidation, .stopLoss])
        // Short, mirrored: liquidation 120 on top, then stop 110, entry 100, now 90.
        XCTAssertEqual(order(false, mark: 90, entry: 100, stop: 110, liq: 120), [.liquidation, .distance, .stopLoss, .entry, .now])
        // Short, price already above the stop: liquidation > now > stop > entry.
        XCTAssertEqual(order(false, mark: 112, entry: 100, stop: 110, liq: 120), [.liquidation, .distance, .now, .stopLoss, .entry])
        // No stop, no liquidation: just the prices.
        XCTAssertEqual(order(true, mark: 90, entry: 100, stop: nil, liq: nil), [.entry, .now])
    }

    /// Stop-loss presets (R20): 7% from the entry is the default stop.
    @MainActor
    func testStopPresetsFromEntry() {
        let viewModel = PerpsAutoCloseViewModel(side: .long, entry: 66_975, reference: 66_975, size: Decimal(string: "0.00298") ?? 0,
                                                liquidation: nil, szDecimals: 5, takeProfit: nil, stopLoss: 62_287)
        XCTAssertEqual(viewModel.stopPrice(dropPercent: 7), 62_287)
        XCTAssertEqual(viewModel.selectedStopPreset, 7)
        viewModel.applyStopPreset(10)
        XCTAssertEqual(viewModel.stopLoss, Decimal(string: "60278"))
        XCTAssertEqual(viewModel.selectedStopPreset, 10)
        let short = PerpsAutoCloseViewModel(side: .short, entry: 100, reference: 100, size: 1, liquidation: nil, szDecimals: 2,
                                            takeProfit: nil, stopLoss: nil)
        XCTAssertEqual(short.stopPrice(dropPercent: 5), 105)
    }

    /// The builders themselves refuse a trigger that rounds to 0 (not only the sheet),
    /// and reserve their second nonce.
    func testBuildersRejectSubTickTriggersAndReserveNonces() throws {
        let ticket = PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated, limitPrice: nil,
                                 takeProfit: nil, stopLoss: Decimal(string: "0.000001"))
        XCTAssertThrowsError(try PerpsOrderPlanner.plan(market: market(), ticket: ticket, nonce: 1)) { error in
            XCTAssertEqual(error as? PerpsOrderPlannerError, .invalidTriggerPrice)
        }
        XCTAssertThrowsError(try PerpsFlows.editExits(position: try position(), market: market(), existing: [],
                                                      stopLoss: Decimal(string: "0.000001"), takeProfit: nil, tier: nil, nonce: 1))
        let source = HLNonceSource(clock: { Date(timeIntervalSince1970: 1_000) })
        let first = source.next(count: 2)
        XCTAssertEqual(source.next(), first + 2, "first + 1 was reserved for the second step")
    }

    func testOrderReviewIsMinimalAndFundsTheTradingAccount() throws {
        let plan = try PerpsOrderPlanner.plan(market: market(), ticket: PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated,
                                                                                    limitPrice: nil, takeProfit: nil, stopLoss: 62_500),
                                              nonce: 1, builder: PerpsConfig.builderFee)
        let vault = PerpsVaultContext(name: "Main", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: 1_250,
                                      tradingAddress: "0x1185457adb9913df15c0cfac2441986520827ce0")
        let document = PerpsFlows.order(plan: plan, costs: PerpsFlows.costs(plan: plan, availableToTrade: 0), vault: vault)
        XCTAssertEqual(document.rows.map(\.label), ["perpsPositionSize".localized, "perpsLiquidationPrice".localized,
                                                    "perpsStopLoss".localized, "perpsFromYourVault".localized])
        XCTAssertEqual(document.amount, "$100")
        XCTAssertEqual(document.amountLabel, "perpsMargin".localized)
        XCTAssertEqual(document.fees?.breakdown.count, 3)
        XCTAssertEqual(document.deposit?.tradingAddress, vault.tradingAddress, "deposits credit the trading account, never main")
        XCTAssertEqual(document.signatureCount, 4)
        XCTAssertNil(document.blockingIssue)
        XCTAssertFalse(document.rows.contains { $0.value.contains("-") && $0.value.contains("USDC") }, "no negative balances")
    }

    // MARK: - Flows

    func testEnableTradingIsTwoVaultSignaturesOnArbitrumDomain() throws {
        let now = Date(timeIntervalSince1970: 1_731_400_000)
        let document = try PerpsFlows.enableTrading(agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", nonce: 10, hasDeposited: true, now: now)
        XCTAssertEqual(document.requests.map(\.kind), [.approveAgent, .approveBuilderFee])
        XCTAssertTrue(document.requests.allSatisfy { $0.typedData.domain.chainId == 0xa4b1 && $0.signRequest.isUserSigned })
        guard case .string(let name)? = document.requests[0].action["agentName"] else { return XCTFail("agentName") }
        XCTAssertEqual(name, "vultisig valid_until \(1_731_400_000_000 + PerpsConfig.agentLifetimeMs)")
        XCTAssertEqual(document.caption, "perpsKeyScopeNote".localized)
        XCTAssertNil(document.note)
        XCTAssertTrue(document.amount.isEmpty, "one title only")
        XCTAssertEqual(document.blockingIssue, "perpsNotInPreview".localized, "must sign as the trading account, which keysign cannot yet")
        let fresh = try PerpsFlows.enableTrading(agentAddress: "0x5e9ee1089755c3435139848e47e6635505d5a13a", nonce: 10, hasDeposited: false, now: now)
        XCTAssertEqual(fresh.blockingIssue, "perpsDepositFirst".localized, "an unfunded account rejects approveAgent (testnet q00)")
    }

    func testWithdrawUsesWithdrawableNotEquity() throws {
        let account = PerpsAccountSnapshot(address: "0x1", accountValue: 1_000, withdrawable: 749.58, marginUsed: 250, totalNotional: 1_000,
                                           positions: [], openOrders: [], fills: [])
        let vault = PerpsVaultContext(name: "Main", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: 0)
        let ok = try PerpsFlows.withdraw(amount: 500, account: account, vault: vault, nonce: 5)
        XCTAssertNil(ok.blockingIssue)
        XCTAssertEqual(ok.requests.first?.kind, .withdraw3)
        XCTAssertEqual(ok.requests.first?.action["destination"], .string(vault.address))
        let tooMuch = try PerpsFlows.withdraw(amount: 900, account: account, vault: vault, nonce: 6)
        XCTAssertNotNil(tooMuch.blockingIssue, "900 is under equity but over withdrawable")
    }

    func testUnifiedAccountReadsSpotBalance() {
        var account = PerpsAccountSnapshot(address: "0x1", accountValue: 0, withdrawable: 0, marginUsed: 0, totalNotional: 0,
                                           positions: [], openOrders: [], fills: [])
        account.mode = PerpsAccountMode(raw: "unifiedAccount")
        account.spotUsdcTotal = 400
        account.spotUsdcHold = 80
        XCTAssertTrue(account.mode.isUnified)
        XCTAssertEqual(account.availableToTrade, 320)
        XCTAssertEqual(account.availableToWithdraw, 0, "always the server's withdrawable, never computed")
        XCTAssertEqual(account.crossCollateral, 400, "unified: spot USDC + cross uPnL - isolated margin")
        XCTAssertFalse(PerpsAccountMode(raw: "default").isUnified)
    }

    func testAddFundsIsCctpIntoTheTradingAccount() throws {
        let vault = PerpsVaultContext(name: "Main", address: "0xb98df75e8c9b4de5d3368e95553eb029345b8376", arbitrumUsdcBalance: 100,
                                      tradingAddress: "0x1185457adb9913df15c0cfac2441986520827ce0")
        XCTAssertNotNil(PerpsFlows.addFunds(amount: 1, vault: vault, isNewAccount: true).blockingIssue,
                        "1 USDC does not cover forwarding plus activation")
        let ok = PerpsFlows.addFunds(amount: 50, vault: vault)
        XCTAssertNil(ok.blockingIssue)
        XCTAssertTrue(ok.requests.isEmpty, "a deposit is CCTP on Arbitrum, never an /exchange action")
        let deposit = try XCTUnwrap(ok.deposit)
        XCTAssertEqual(deposit.tradingAddress, vault.tradingAddress)
        XCTAssertEqual(deposit.credited, 50 - HLCctp.forwardingFee)
        let noTrading = PerpsVaultContext(name: "Main", address: "0x1", arbitrumUsdcBalance: 100)
        XCTAssertNotNil(PerpsFlows.addFunds(amount: 50, vault: noTrading).blockingIssue)
    }

    /// Circle's `encodeForwardHookData` and viem `hashTypedData`
    /// (VultisigAppTests/Perps/Vectors/gen_cctp.mjs).
    func testCctpHookDataAndAuthorizationMatchReferences() throws {
        let trading = "0x1185457adb9913df15c0cfac2441986520827ce0"
        XCTAssertEqual(try HLCctp.forwardHookData(recipient: trading).hexString,
                       "636374702d666f727761726400000000000000000000000000000000000000181185457adb9913df15c0cfac2441986520827ce000000000")
        XCTAssertEqual(try HLCctp.forwardHookData(recipient: trading, dex: .spot).hexString,
                       "636374702d666f727761726400000000000000000000000000000000000000181185457adb9913df15c0cfac2441986520827ce0ffffffff")
        let deposit = try HLCctpDeposit.make(from: "0xb98df75e8c9b4de5d3368e95553eb029345b8376", tradingAddress: trading, amount: 250,
                                             validBefore: 1_731_403_600, authNonce: Data(repeating: 0x11, count: 32))
        XCTAssertEqual(deposit.authorization.digest.hexString, "3acfd19ea5f20698827fac62930bab711f94e44d933639666fae39a5448841ee")
    }

    private func position(isolated: Bool = true) throws -> HLPosition {
        let json = #"{"coin":"BTC","szi":"0.002","leverage":{"type":"\#(isolated ? "isolated" : "cross")","value":2},"entryPx":"66000","#
            + #""positionValue":"133.9","unrealizedPnl":"1.94","returnOnEquity":"0.03","liquidationPx":"33500","marginUsed":"67.9","maxLeverage":40}"#
        return try JSONDecoder().decode(HLPosition.self, from: Data(json.utf8))
    }

    func testPartialCloseKeepsIsolatedLiquidationClose() throws {
        let position = try position()
        let estimate = PerpsFlows.closeEstimate(position: position, market: market(), size: 0.001)
        XCTAssertEqual(estimate.size, 0.001)
        close(estimate.releasedMargin, 33.95)
        // Isolated margin already holds the uPnL: half of 1.94 is not paid twice.
        close(estimate.returned, 33.95 - 0.97 + estimate.realizedPnl - estimate.fees)
        let liquidation = try XCTUnwrap(estimate.remainingLiquidation)
        // The formula adds uPnL from the entry itself, so it takes the margin at entry:
        // marginUsed 67.9 minus uPnL 1.94 (counting it twice made winners look safer).
        let full = try XCTUnwrap(PerpsMath.liquidationPrice(side: .long, entryPrice: 66_000, size: 0.002,
                                                            collateral: Decimal(string: "65.96") ?? 0, schedule: .single(maxLeverage: 40)))
        close(liquidation, full, 1)
    }

    func testEditExitsCancelsThenPlacesPositionTpsl() throws {
        let stopJSON = #"{"coin":"BTC","oid":77,"side":"A","sz":"0.0","limitPx":"60000","triggerPx":"60000.0","isTrigger":true,"#
            + #""isPositionTpsl":true,"reduceOnly":true,"orderType":"Stop Market","timestamp":1}"#
        let stop = try JSONDecoder().decode(HLFrontendOrder.self, from: Data(stopJSON.utf8))
        XCTAssertTrue(stop.isStopLoss)
        let document = try PerpsFlows.editExits(position: try position(), market: market(), existing: [stop], stopLoss: 62_000,
                                                takeProfit: 72_000, tier: nil, nonce: 100)
        XCTAssertEqual(document.requests.map(\.kind), [.cancel, .order])
        XCTAssertEqual(document.requests.map(\.nonce), [100, 101])
        XCTAssertEqual(document.requests[1].action["grouping"], .string("positionTpsl"))
        let unchanged = try PerpsFlows.editExits(position: try position(), market: market(), existing: [stop], stopLoss: 60_000,
                                                 takeProfit: nil, tier: nil, nonce: 200)
        XCTAssertNotNil(unchanged.blockingIssue)
    }

    /// An edited trigger is snapped to a valid price before it is validated,
    /// so rounding on the wire can never move it across the mark.
    @MainActor
    func testEditedTriggerIsSnappedBeforeValidation() {
        let viewModel = PerpsAutoCloseViewModel(side: .short, entry: 100_000, reference: Decimal(string: "100000.5") ?? 0, size: 1,
                                                liquidation: nil, szDecimals: 5, takeProfit: nil, stopLoss: nil)
        // Hyperliquid accepts any integer price, so 100001 is kept as typed (above the mark: valid).
        viewModel.stopText = "100001"
        XCTAssertEqual(viewModel.stopLoss, 100_001)
        XCTAssertNil(viewModel.issue)
        // A fractional price is snapped to 5 significant figures first: 100000.4 -> 100000, under the mark.
        viewModel.stopText = "100000.4"
        XCTAssertEqual(viewModel.stopLoss, 100_000, "the price that would be signed")
        XCTAssertNotNil(viewModel.issue, "a short's stop at or under the mark is refused, not signed")
        // Zero, or a sub-tick price that snaps to zero, is refused (blank still removes).
        viewModel.stopText = ""
        viewModel.takeText = "0"
        XCTAssertNotNil(viewModel.issue)
        viewModel.takeText = "0.000001"
        XCTAssertEqual(viewModel.takeProfit, 0)
        XCTAssertNotNil(viewModel.issue)
        viewModel.takeText = ""
        viewModel.stopText = "100060"
        XCTAssertEqual(viewModel.stopLoss, 100_060)
        XCTAssertNil(viewModel.issue)
    }

    func testInputAcceptsCommaDecimals() {
        XCTAssertEqual(PerpsInput.decimal("76,5"), Decimal(string: "76.5"))
        XCTAssertEqual(PerpsInput.decimal("1,250.75"), Decimal(string: "1250.75"))
        XCTAssertEqual(PerpsInput.decimal("100"), 100)
        XCTAssertNil(PerpsInput.decimal(""))
        // A lone comma is always the decimal pad's separator, never grouping:
        // "0,125" and "1,500" typed on a comma-decimal keypad are not 125 / 1,500.
        XCTAssertEqual(PerpsInput.decimal("0,125"), Decimal(string: "0.125"))
        XCTAssertEqual(PerpsInput.decimal("1,500"), Decimal(string: "1.5"))
        XCTAssertEqual(PerpsInput.decimal("75.000,5"), Decimal(string: "75000.5"))
        XCTAssertNil(PerpsInput.decimal("1,2,3"))
        XCTAssertNil(PerpsInput.decimal("1.2.3"))
        XCTAssertNil(PerpsInput.decimal("12a"))
        XCTAssertNil(PerpsInput.decimal("."))
    }

    // MARK: - Ticket numbers come from the same reference price

    @MainActor
    private func ticket(balance: Decimal?) -> PerpsTicketViewModel {
        let vault = PerpsVaultContext(name: "Main", address: "0xb98df75e8c9b4de5d3368e95553eb029345b8376", arbitrumUsdcBalance: balance,
                                      tradingAddress: "0x1185457adb9913df15c0cfac2441986520827ce0")
        return PerpsTicketViewModel(side: .long, market: market(), account: nil, vault: vault)
    }

    /// The default stop is 7% under the price the order is estimated at, so
    /// its percent and its price agree.
    @MainActor
    func testDefaultStopIsSevenPercentUnderTheReference() throws {
        let viewModel = ticket(balance: 1_000)
        let stop = try XCTUnwrap(viewModel.defaultStop)
        close((stop - viewModel.referencePrice) / viewModel.referencePrice * 100, -7, 0.01)
    }

    /// Liquidation follows the spec formula at the same reference price:
    /// 2x isolated long, max 40x, gives entry x (1 - (0.5 - 0.0125) / 0.9875).
    @MainActor
    func testTicketLiquidationMatchesTheSpecFormula() throws {
        let viewModel = ticket(balance: 1_000)
        let liquidation = try XCTUnwrap(viewModel.estimate?.liquidationPrice)
        let expected = viewModel.referencePrice * (1 - (Decimal(string: "0.4875") ?? 0) / (Decimal(string: "0.9875") ?? 1))
        close(liquidation, expected, 0.5)
        close((liquidation - viewModel.referencePrice) / viewModel.referencePrice * 100, Decimal(string: "-49.37") ?? 0, 0.01)
    }

    /// Not enough USDC in the vault: an inline reason and no review, never a negative projection.
    @MainActor
    func testInsufficientVaultBlocksTheTicket() {
        let poor = ticket(balance: Decimal(string: "0.05"))
        XCTAssertEqual(poor.issue, String(format: "perpsShortfallLine".localized,
                                          PerpsFlows.usdc(poor.costs?.transfer ?? 0), PerpsFlows.usdc(Decimal(string: "0.05") ?? 0)))
        XCTAssertFalse(poor.canReview)
        XCTAssertNil(poor.reviewDocument())
        let funded = ticket(balance: 1_000)
        XCTAssertNil(funded.issue)
        XCTAssertTrue(funded.canReview)
    }

    func testPricesShowAtDisplayPrecisionAndParseBack() {
        XCTAssertEqual(PerpsFormat.price(Decimal(string: "91.488") ?? 0), "$91.49")
        XCTAssertEqual(PerpsFormat.price(Decimal(string: "66468.4") ?? 0), "$66,468")
        XCTAssertEqual(PerpsFormat.price(Decimal(string: "0.523412") ?? 0), "$0.52341")
        XCTAssertEqual(PerpsInput.priceText(66_468), "66468")
        XCTAssertEqual(PerpsInput.decimal(PerpsInput.priceText(66_468)), 66_468)
        XCTAssertEqual(PerpsInput.decimal(PerpsInput.priceText(Decimal(string: "72.35") ?? 0)), Decimal(string: "72.35"))
        XCTAssertEqual(PerpsInput.decimal("91,49"), Decimal(string: "91.49"))
    }

    /// Losses use the typographic minus, the same width as "+"; sub-cent is zero.
    func testSignedAmountsUseTypographicMinus() {
        XCTAssertEqual(PerpsFormat.usd(Decimal(string: "-0.02") ?? 0, signed: true), "\u{2212}$0.02")
        XCTAssertEqual(PerpsFormat.usd(Decimal(string: "12.4") ?? 0, signed: true), "+$12.40")
        XCTAssertEqual(PerpsFormat.usd(Decimal(string: "-0.004") ?? 0, signed: true), "$0.00")
        XCTAssertEqual(PerpsFormat.percent(Decimal(string: "-0.58") ?? 0), "\u{2212}0.58%")
        XCTAssertEqual(PerpsFormat.percent(Decimal(string: "1.1") ?? 0), "+1.10%")
    }

    #if DEBUG // PerpsDemoRepository is Debug-only, so Release test builds skip it.
    /// Demo account: available = added - fee - reserved margin, and the stop is 7% under entry.
    func testDemoAccountMathsAgree() throws {
        let snapshot = PerpsDemoRepository.snapshot(address: "0x0", btcMark: 66_969, entry: 66_975, now: Date())
        let position = try XCTUnwrap(snapshot.positions.first)
        XCTAssertEqual(position.szi.value, Decimal(string: "0.00298"))
        let margin = position.szi.value * 66_975 / 2
        let fee = try XCTUnwrap(snapshot.fills.first?.fee.value)
        XCTAssertEqual(fee, Decimal(string: "0.29"), "0.145% of $199.59: Hyperliquid 0.045% + Vultisig 0.1%")
        XCTAssertEqual(snapshot.availableToTrade, PerpsDemoRepository.deposited - fee - margin)
        XCTAssertEqual(snapshot.triggerOrders.first?.triggerPx?.value, 62_287)
        XCTAssertEqual(PerpsDemoRepository.unfunded(address: "0x0").availableToTrade, 250)
    }
    #endif

    /// Details lists the margin actually used, then the fee total;
    /// lot rounding keeps the margin a little under the $100 entered.
    func testOrderReviewDetailsListMarginBeforeFees() throws {
        let plan = try PerpsOrderPlanner.plan(market: market(), ticket: PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated,
                                                                                    limitPrice: nil, takeProfit: nil, stopLoss: 62_287),
                                              nonce: 1, builder: PerpsConfig.builderFee)
        let vault = PerpsVaultContext(name: "Main", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: 0,
                                      tradingAddress: "0x1185457adb9913df15c0cfac2441986520827ce0")
        let document = PerpsFlows.order(plan: plan, costs: PerpsFlows.costs(plan: plan, availableToTrade: 250), vault: vault)
        XCTAssertEqual(document.detailRows.map(\.label), ["perpsMargin".localized])
        XCTAssertEqual(document.detailRows.first?.value, PerpsFormat.usd(plan.estimate.margin))
        XCTAssertLessThan(plan.estimate.margin, 100)
        // 10 bps builder fee: $0.09 Hyperliquid + $0.20 Vultisig = $0.29 on $199.59.
        XCTAssertEqual(document.fees?.total, "$0.29")
    }

    #if DEBUG // PerpsDemoRepository is Debug-only, so Release test builds skip it.
    /// design fixture at the 10 bps builder fee: entry $66,975, mark $71,130.
    func testDemoAccountMatchesTheR18Board() throws {
        let snapshot = PerpsDemoRepository.snapshot(address: "0x0", btcMark: 71_130, entry: 66_975, now: Date())
        let position = try XCTUnwrap(snapshot.positions.first)
        XCTAssertEqual(position.szi.value, Decimal(string: "0.00298"))
        XCTAssertEqual(PerpsFormat.usd(position.unrealizedPnl.value, signed: true), "+$12.38")
        XCTAssertEqual(PerpsFormat.usd(snapshot.equity), "$262.09")
        XCTAssertEqual(PerpsFormat.usd(snapshot.availableToTrade), "$149.92")
        XCTAssertEqual(position.liquidationPx.map { PerpsFormat.price($0.value) }, "$33,911")
        XCTAssertEqual(PerpsFormat.usd(PerpsMarginFlows.margin(of: position)), "$99.79")
        let after = PerpsDemoRepository.afterWithdrawal(snapshot)
        XCTAssertEqual(PerpsFormat.usd(after.equity), "$162.09")
        XCTAssertEqual(PerpsFormat.usd(after.availableToTrade), "$49.92")
        XCTAssertTrue(PerpsDemoRepository.empty(address: "0x0").isEmpty, "the story starts on the first visit")
        // the ETH long near liquidation.
        let eth = try XCTUnwrap(PerpsDemoRepository.nearLiquidation(address: "0x0", ethMark: 2_510).positions.first)
        XCTAssertEqual(eth.szi.value, Decimal(string: "1.0232"))
        XCTAssertEqual(eth.entryPx?.value, 2_568)
        XCTAssertEqual(eth.liquidationPx.map { PerpsFormat.price($0.value) }, "$2,489")
        XCTAssertEqual(PerpsFormat.usd(eth.unrealizedPnl.value, signed: true), "\u{2212}$59.35")
        XCTAssertEqual(PerpsFormat.usd(PerpsMarginFlows.margin(of: eth)), "$131.38")
    }
    #endif

    #if DEBUG // PerpsDemoRepository is Debug-only, so Release test builds skip it.
    /// 10 bps builder fee on the close and the trigger outcomes, at the design marks.
    func testTenBpsFeesOnClosesAndOutcomes() throws {
        let snapshot = PerpsDemoRepository.snapshot(address: "0x0", btcMark: 71_130, entry: 66_975, now: Date())
        let position = try XCTUnwrap(snapshot.positions.first)
        let later = PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: 71_130,
                                midPrice: 71_130, previousDayPrice: 70_347, hourlyFunding: 0, openInterest: 1, dayVolume: 1)
        let quarter = PerpsFlows.closeEstimate(position: position, market: later, size: Decimal(string: "0.00074") ?? 0)
        XCTAssertEqual(PerpsFormat.usd(quarter.fees), "$0.08")
        XCTAssertEqual(PerpsFormat.usd(quarter.realizedPnl - quarter.fees, signed: true), "+$3.00")
        XCTAssertEqual(PerpsFormat.usd(quarter.returned), "$27.78")
        let all = PerpsFlows.closeEstimate(position: position, market: later, size: abs(position.szi.value))
        XCTAssertEqual(PerpsFormat.usd(all.fees), "$0.31")
        XCTAssertEqual(PerpsFormat.usd(all.realizedPnl - all.fees, signed: true), "+$12.07")
        XCTAssertEqual(PerpsFormat.usd(all.returned), "$111.87")
        let stop = PerpsOutcome.make(kind: .stopLoss, position: position, fillPrice: 62_268, triggerPrice: 62_287)
        XCTAssertEqual(PerpsFormat.usd(stop.netPnl, signed: true), "\u{2212}$14.30")
        XCTAssertEqual(PerpsFormat.usd(stop.fees), "$0.27")
        // Rounded once, like the close estimate: 99.79275 - 14.29592 = 85.49683.
        XCTAssertEqual(PerpsFormat.usd(stop.returned), "$85.50")
        let take = PerpsOutcome.make(kind: .takeProfit, position: position, fillPrice: 74_988, triggerPrice: 75_000)
        XCTAssertEqual(PerpsFormat.usd(take.netPnl, signed: true), "+$23.55")
        XCTAssertEqual(PerpsFormat.usd(take.fees), "$0.32")
    }
    #endif

    #if DEBUG // PerpsDemoRepository is Debug-only, so Release test builds skip it.
    /// Demo chart: a falling live day is bent to end on the mark and open
    /// on the previous day's price, so a +1.11% day draws a rising line.
    func testDemoChartEndsOnTheMarkAndFollowsTheDayChange() {
        let hour: Int64 = 3_600_000
        // A live day that fell 6%, with wiggles.
        let live = (0...96).map { index -> HLCandle in
            let price = Decimal(76_000 - index * 47 + (index % 5) * 300)
            return HLCandle(openTimeMs: Int64(index) * hour / 4, open: HLDecimal(price), close: HLDecimal(price),
                            high: HLDecimal(price + 50), low: HLDecimal(price - 50), volume: HLDecimal(1))
        }
        let bent = PerpsDemoRepository.bent(live, mark: 71_130, previousDay: 70_346.77, lookback: 86_400)
        XCTAssertEqual(bent.last?.close.value, 71_130)
        close(bent.first?.close.value, Decimal(string: "70346.77") ?? 0, 0.5)
        let firstHalf = bent.prefix(48).map(\.close.value).reduce(0, +) / 48
        let secondHalf = bent.suffix(48).map(\.close.value).reduce(0, +) / 48
        XCTAssertGreaterThan(secondHalf, firstHalf, "the line rises to the mark")
        XCTAssertTrue(bent.allSatisfy { $0.high.value >= $0.close.value && $0.low.value <= $0.close.value })
    }
    #endif

    /// VULT tiers scale the 10 bps builder fee like swaps scale the 50 bps list fee.
    func testBuilderFeePerVultTier() {
        let expected: [(VultDiscountTier?, Int)] = [(nil, 100), (.bronze, 90), (.silver, 80), (.gold, 60), (.platinum, 50), (.diamond, 30), (.ultimate, 0)]
        for (tier, tenths) in expected {
            XCTAssertEqual(PerpsConfig.builderFeeTenthsBp(tier: tier), tenths, "\(tier?.name ?? "no tier")")
            XCTAssertEqual(PerpsConfig.builderFee(tier: tier)?.tenthsOfBasisPoint, tenths == 0 ? nil : tenths)
            XCTAssertEqual(PerpsConfig.builderFee(tier: tier)?.builder, tenths == 0 ? nil : PerpsConfig.builderAddress)
        }
        XCTAssertNil(HLActions.order([], builder: PerpsConfig.builderFee(tier: .ultimate))["builder"], "Ultimate: no builder field")
        XCTAssertEqual(PerpsConfig.builderMaxFeeRate, "0.1%", "one approval covers every tier")
    }

    /// The order review shows the list fee, the swap-worded VULT line, and the discounted total.
    func testOrderReviewFeesPerVultTier() throws {
        let totals: [(VultDiscountTier?, String, String?)] = [
            (nil, "$0.29", nil), (.bronze, "$0.27", "\u{2212}$0.02"), (.silver, "$0.25", "\u{2212}$0.04"), (.gold, "$0.21", "\u{2212}$0.08"),
            (.platinum, "$0.19", "\u{2212}$0.10"), (.diamond, "$0.15", "\u{2212}$0.14"), (.ultimate, "$0.09", "\u{2212}$0.20")
        ]
        let vault = PerpsVaultContext(name: "Main", address: "0x9d7c000000000000000000000000000000003003", arbitrumUsdcBalance: 0,
                                      tradingAddress: "0x1185457adb9913df15c0cfac2441986520827ce0")
        let pinned = PerpsMarket(assetIndex: 0, coin: "BTC", szDecimals: 5, maxLeverage: 40, onlyIsolated: false, markPrice: 66_975,
                                 midPrice: 66_975, previousDayPrice: 66_237.5, hourlyFunding: 0, openInterest: 1, dayVolume: 1)
        for (tier, total, discount) in totals {
            let plan = try PerpsOrderPlanner.plan(market: pinned, ticket: PerpsTicket(side: .long, margin: 100, leverage: 2, marginMode: .isolated,
                                                                                     limitPrice: nil, takeProfit: nil, stopLoss: 62_287),
                                                  nonce: 1, builder: PerpsConfig.builderFee(tier: tier))
            let document = PerpsFlows.order(plan: plan, costs: PerpsFlows.costs(plan: plan, availableToTrade: 250, tier: tier), vault: vault)
            let breakdown = try XCTUnwrap(document.fees?.breakdown)
            XCTAssertEqual(document.fees?.total, total, "\(tier?.name ?? "no tier")")
            XCTAssertEqual(breakdown[1].value, "$0.20", "Vultisig 0.1% before the discount")
            XCTAssertEqual(document.fees?.showsBreakdown, discount != nil, "Details lists the parts when a discount applies")
            if let tier, let discount {
                XCTAssertEqual(breakdown[2].label, SwapCryptoLogic.vultDiscountLabel(vultDiscountBps: tier.bpsDiscount))
                XCTAssertEqual(breakdown[2].value, discount)
            } else {
                XCTAssertEqual(breakdown.count, 2)
            }
        }
    }

    /// Sizes listed together pad to the lot size: "0.00050 BTC" beside "0.00024 BTC".
    func testSizeTextPadsToLotDecimals() {
        XCTAssertEqual(PerpsCloseFlows.sizeText(Decimal(string: "0.0005") ?? 0, coin: "BTC", szDecimals: 5), "0.00050 BTC")
        XCTAssertEqual(PerpsCloseFlows.sizeText(Decimal(string: "0.0005") ?? 0, coin: "BTC"), "0.0005 BTC")
    }

    #if DEBUG // PerpsDemoRepository is Debug-only, so Release test builds skip it.
    func testDemoNearLiquidationShowsTheWarning() throws {
        let snapshot = PerpsDemoRepository.nearLiquidation(address: "0x0", ethMark: Decimal(string: "2484.5") ?? 0)
        let position = try XCTUnwrap(snapshot.positions.first)
        XCTAssertTrue(PerpsMath.isNearLiquidation(markPrice: Decimal(string: "2484.5") ?? 0, liquidationPrice: position.liquidationPx?.value))
        XCTAssertLessThan(position.unrealizedPnl.value, 0)
    }
    #endif

    /// Activity: fills grouped per order, transfers signed, funding summed per day.
    func testActivityGroupsFillsAndSumsFunding() throws {
        func fill(_ oid: Int64, _ dir: String, _ sz: String, _ pnl: String, _ time: Int64) throws -> HLFill {
            let json = #"{"coin":"BTC","px":"70000","sz":"\#(sz)","side":"B","time":\#(time),"dir":"\#(dir)","closedPnl":"\#(pnl)","#
                + #""fee":"0.1","tid":\#(time),"oid":\#(oid)}"#
            return try JSONDecoder().decode(HLFill.self, from: Data(json.utf8))
        }
        let fills = [try fill(1, "Open Long", "0.001", "0", 1_000), try fill(1, "Open Long", "0.002", "0", 2_000),
                     try fill(2, "Close Long", "0.003", "4.5", 3_000)]
        let ledger = try JSONDecoder().decode([HLLedgerUpdate].self, from: Data(#"[{"time":4000,"hash":"0xa","delta":{"type":"withdraw","usdc":"10"}}]"#.utf8))
        let funding = try JSONDecoder().decode([HLFundingPayment].self, from: Data(
            #"[{"time":5000,"delta":{"coin":"BTC","usdc":"-0.2"}},{"time":6000,"delta":{"coin":"BTC","usdc":"-0.3"}}]"#.utf8))
        let items = HyperliquidPerpsRepository.activity(fills: fills, ledger: ledger, funding: funding)
        XCTAssertEqual(items.filter { $0.kind == .trade }.count, 2, "two orders, three fills")
        XCTAssertEqual(items.first { $0.id == "o1" }?.amount, 210)
        XCTAssertEqual(items.first { $0.id == "o2" }?.amount, Decimal(string: "4.5"))
        XCTAssertEqual(items.first { $0.kind == .transfer }?.amount, -10)
        XCTAssertEqual(items.first { $0.kind == .funding }?.amount, Decimal(string: "-0.5"))
    }

    func testNearLiquidationWithinTwoPercent() {
        XCTAssertTrue(PerpsMath.isNearLiquidation(markPrice: 71_352.5, liquidationPrice: Decimal(string: "72241.47")))
        XCTAssertFalse(PerpsMath.isNearLiquidation(markPrice: 81.7, liquidationPrice: 680.7))
        XCTAssertFalse(PerpsMath.isNearLiquidation(markPrice: 100, liquidationPrice: nil))
    }

    /// "Add 101.02 USDC to trade.": the order's transfer minus what the vault already holds.
    @MainActor
    func testShortfallMessageIsWhatTheVaultIsMissing() throws {
        let poor = ticket(balance: Decimal(string: "0.05"))
        let transfer = try XCTUnwrap(poor.fundingShortfall)
        let missing = PerpsFormat.usd((transfer - (Decimal(string: "0.05") ?? 0)).rounded(scale: 2, mode: .up))
        XCTAssertEqual(poor.shortfallMessage, String(format: "perpsAddToTrade".localized, missing))
        XCTAssertEqual(poor.summaryLine, String(format: "perpsAvailableAmount".localized, PerpsFormat.usd(0)), "nothing to trade: $0.00 available")
        XCTAssertNil(ticket(balance: 1_000).shortfallMessage)
    }
}
