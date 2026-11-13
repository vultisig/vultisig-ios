//
//  PerpsLogicTests.swift
//  VultisigAppTests
//
//  Perps: wire formatting, ticket math, order planning and /info decoding.
//

import XCTest
@testable import VultisigApp

private func dec(_ text: String) -> Decimal { Decimal(string: text)! }

final class PerpsLogicTests: XCTestCase {

    // MARK: - Wire format

    func testDecimalStringStripsTrailingZeros() {
        XCTAssertEqual(HLWireFormat.decimalString(dec("30000.0")), "30000")
        XCTAssertEqual(HLWireFormat.decimalString(dec("0.00100")), "0.001")
        XCTAssertEqual(HLWireFormat.decimalString(dec("1670.1")), "1670.1")
        XCTAssertEqual(HLWireFormat.decimalString(0), "0")
        XCTAssertEqual(HLWireFormat.decimalString(dec("0.000000001")), "0")
    }

    func testPriceRoundsToFiveSignificantFiguresAndMaxDecimals() {
        // BTC szDecimals 5 -> max 1 decimal; 5 sig figs on 71398.57 -> 71399
        XCTAssertEqual(HLWireFormat.price(dec("71398.57"), szDecimals: 5), dec("71399"))
        // ETH szDecimals 4 -> max 2 decimals; 3012.567 -> 3012.6
        XCTAssertEqual(HLWireFormat.price(dec("3012.567"), szDecimals: 4), dec("3012.6"))
        // small coin szDecimals 0 -> max 6 decimals; 0.0123456 -> 0.012346
        XCTAssertEqual(HLWireFormat.price(dec("0.0123456"), szDecimals: 0), dec("0.012346"))
        // szDecimals 2 caps decimals at 4 even under 5 sig figs: 1.234567 -> 1.2346
        XCTAssertEqual(HLWireFormat.price(dec("1.234567"), szDecimals: 2), dec("1.2346"))
        XCTAssertEqual(HLWireFormat.price(dec("0.00012345678"), szDecimals: 2), dec("0.0001"))
    }

    func testSizeRoundsDown() {
        XCTAssertEqual(HLWireFormat.size(dec("0.0019999"), szDecimals: 3), dec("0.001"))
        XCTAssertEqual(HLWireFormat.size(dec("12.99"), szDecimals: 0), dec("12"))
    }

    func testMarketPriceAddsSlippageInTradeDirection() {
        XCTAssertEqual(HLWireFormat.marketPrice(mid: 100, isBuy: true, slippage: dec("0.01"), szDecimals: 2), 101)
        XCTAssertEqual(HLWireFormat.marketPrice(mid: 100, isBuy: false, slippage: dec("0.01"), szDecimals: 2), 99)
    }

    // MARK: - Math

    func testLiquidationPriceLongIsolated() throws {
        // entry 100, 10x, max 50x -> maintenance 1%, margin 10, available 9 -> 100 - 9 / 0.99
        let liq = try XCTUnwrap(PerpsMath.liquidationPrice(side: .long, entryPrice: 100, size: 1, collateral: 10, maxLeverage: 50))
        XCTAssertEqual(NSDecimalNumber(decimal: liq).doubleValue, 90.90909, accuracy: 0.0001)
        // At the liquidation price, equity equals maintenance margin.
        let equity = 10 + PerpsMath.unrealizedPnl(side: .long, entryPrice: 100, markPrice: liq, size: 1)
        XCTAssertEqual(NSDecimalNumber(decimal: equity).doubleValue, NSDecimalNumber(decimal: liq * dec("0.01")).doubleValue, accuracy: 1e-9)
    }

    func testLiquidationPriceShortIsolated() throws {
        // 100 + 9 / 1.01
        let liq = try XCTUnwrap(PerpsMath.liquidationPrice(side: .short, entryPrice: 100, size: 1, collateral: 10, maxLeverage: 50))
        XCTAssertEqual(NSDecimalNumber(decimal: liq).doubleValue, 108.91089, accuracy: 0.0001)
    }

    func testOneXLongHasNoLiquidationAboveZero() {
        XCTAssertNil(PerpsMath.liquidationPrice(side: .long, entryPrice: 100, size: 1, collateral: 100, maxLeverage: 50))
    }

    func testEstimateFromMargin() {
        let estimate = PerpsMath.estimate(side: .long, margin: 100, leverage: 5, price: 2000, szDecimals: 4,
                                          maxLeverage: 25, marginMode: .isolated)
        XCTAssertEqual(estimate.size, dec("0.25"))
        XCTAssertEqual(estimate.notional, 500)
        XCTAssertEqual(estimate.margin, 100)
        XCTAssertEqual(estimate.fee, dec("0.225"))
        XCTAssertNotNil(estimate.liquidationPrice)
    }

    func testFundingAnnualisation() {
        XCTAssertEqual(PerpsMath.annualizedFunding(hourlyRate: dec("0.0000125")), dec("0.1095"))
    }

    // MARK: - Planner

    private let eth = PerpsMarket(assetIndex: 1, coin: "ETH", szDecimals: 4, maxLeverage: 25, onlyIsolated: false,
                                  markPrice: 3000, midPrice: 3000, previousDayPrice: 2900, hourlyFunding: dec("0.0000125"),
                                  openInterest: 1000, dayVolume: 1_000_000)

    func testPlanMarketLongEmitsLeverageThenIocOrder() throws {
        let ticket = PerpsTicket(side: .long, margin: 100, leverage: 5, marginMode: .cross, limitPrice: nil, takeProfit: nil, stopLoss: nil)
        let plan = try PerpsOrderPlanner.plan(market: eth, ticket: ticket, nonce: 1000)
        XCTAssertEqual(plan.steps.map(\.kind), [.updateLeverage, .order])
        XCTAssertEqual(plan.steps.map(\.nonce), [1000, 1001])
        XCTAssertEqual(plan.steps[0].action, HLActions.updateLeverage(asset: 1, isCross: true, leverage: 5))
        let expected = HLActions.order([HLOrderWire(asset: 1, isBuy: true, price: "3030", size: "0.1666", reduceOnly: false, type: .limit(.ioc))])
        XCTAssertEqual(plan.steps[1].action, expected)
    }

    func testPlanLimitShortWithBracket() throws {
        let ticket = PerpsTicket(side: .short, margin: 300, leverage: 3, marginMode: .isolated, limitPrice: dec("3100.123"),
                                 takeProfit: 2800, stopLoss: 3300)
        let plan = try PerpsOrderPlanner.plan(market: eth, ticket: ticket, nonce: 1)
        guard case let .array(orders)? = plan.steps[1].action["orders"] else { return XCTFail("orders") }
        XCTAssertEqual(orders.count, 3)
        XCTAssertEqual(plan.steps[1].action["grouping"], .string("normalTpsl"))
        XCTAssertEqual(orders[0]["p"], .string("3100.1"))
        XCTAssertEqual(orders[0]["b"], .bool(false))
        XCTAssertEqual(orders[1]["r"], .bool(true))
        XCTAssertEqual(orders[1]["b"], .bool(true))
        XCTAssertEqual(plan.steps[0].action["isCross"], .bool(false))
    }

    func testPlanRejectsTinyAndOverLeveraged() {
        let tiny = PerpsTicket(side: .long, margin: 1, leverage: 2, marginMode: .cross, limitPrice: nil, takeProfit: nil, stopLoss: nil)
        XCTAssertThrowsError(try PerpsOrderPlanner.plan(market: eth, ticket: tiny, nonce: 1)) {
            XCTAssertEqual($0 as? PerpsOrderPlannerError, .minimumNotional)
        }
        let wild = PerpsTicket(side: .long, margin: 100, leverage: 50, marginMode: .cross, limitPrice: nil, takeProfit: nil, stopLoss: nil)
        XCTAssertThrowsError(try PerpsOrderPlanner.plan(market: eth, ticket: wild, nonce: 1)) {
            XCTAssertEqual($0 as? PerpsOrderPlannerError, .leverageOutOfRange)
        }
    }

    // MARK: - /info decoding (shapes captured from api.hyperliquid.xyz on 2026-11-12)

    func testDecodesMetaAndAssetContexts() throws {
        let json = """
        [{"universe":[{"szDecimals":5,"name":"BTC","maxLeverage":40,"marginTableId":56},
                      {"szDecimals":4,"name":"OLD","maxLeverage":3,"isDelisted":true}],
          "marginTables":[],"collateralToken":0},
         [{"funding":"0.0000125","openInterest":"38917.66126","prevDayPx":"73890.0","dayNtlVlm":"3115551564.8245787621",
           "premium":"-0.0002100428","oraclePx":"71414.0","markPx":"71391.0","midPx":"71398.5","impactPxs":["71398.0","71399.0"],
           "dayBaseVlm":"42565.1151300001"},
          {"funding":"0","openInterest":"0","prevDayPx":"1","dayNtlVlm":"0","oraclePx":"1","markPx":"1","midPx":null}]]
        """
        let decoded = try JSONDecoder().decode(HLMetaAndAssetContexts.self, from: Data(json.utf8))
        let markets = HyperliquidPerpsRepository.markets(from: decoded)
        XCTAssertEqual(markets.map(\.coin), ["BTC"])
        XCTAssertEqual(markets[0].markPrice, dec("71391.0"))
        XCTAssertEqual(markets[0].maxLeverage, 40)
        XCTAssertEqual(markets[0].assetIndex, 0)
    }

    func testDecodesClearinghouseStateWithPosition() throws {
        let json = """
        {"marginSummary":{"accountValue":"1234.5","totalNtlPos":"500.0","totalRawUsd":"734.5","totalMarginUsed":"100.0"},
         "crossMarginSummary":{"accountValue":"1234.5","totalNtlPos":"500.0","totalRawUsd":"734.5","totalMarginUsed":"100.0"},
         "crossMaintenanceMarginUsed":"10.0","withdrawable":"1134.5",
         "assetPositions":[{"type":"oneWay","position":{"coin":"ETH","szi":"-0.1666","leverage":{"type":"cross","value":5},
           "entryPx":"3001.2","positionValue":"499.8","unrealizedPnl":"0.2","returnOnEquity":"0.002","liquidationPx":null,
           "marginUsed":"99.96","maxLeverage":25,"cumFunding":{"allTime":"0","sinceOpen":"0","sinceChange":"0"}}}],
         "time":1794497992427}
        """
        let state = try JSONDecoder().decode(HLClearinghouseState.self, from: Data(json.utf8))
        let snapshot = HyperliquidPerpsRepository.snapshot(address: "0xabc", state: state, orders: [], fills: [])
        XCTAssertEqual(snapshot.accountValue, dec("1234.5"))
        XCTAssertEqual(snapshot.positions.first?.isLong, false)
        XCTAssertNil(snapshot.positions.first?.liquidationPx)
        XCTAssertEqual(snapshot.unrealizedPnl, dec("0.2"))
    }

    func testDecodesCandles() throws {
        let json = """
        [{"t":1776484800000,"T":1776488399999,"s":"BTC","i":"1h","o":"76955.0","c":"77073.0","h":"77115.0","l":"76850.0","v":"474.4232","n":11541}]
        """
        let candles = try JSONDecoder().decode([HLCandle].self, from: Data(json.utf8))
        XCTAssertEqual(candles.first?.close.value, dec("77073.0"))
        XCTAssertEqual(candles.first?.openTimeMs, 1_776_484_800_000)
    }

    func testInfoRequestBodies() {
        XCTAssertEqual(HyperliquidInfoAPI.metaAndAssetContexts.body["type"] as? String, "metaAndAssetCtxs")
        XCTAssertEqual(HyperliquidInfoAPI.clearinghouseState(user: "0xABC").body["user"] as? String, "0xabc")
        XCTAssertEqual(HyperliquidInfoAPI.metaAndAssetContexts.method, .post)
    }
}
