//
//  SwapKitServiceTests.swift
//  VultisigAppTests
//
//  Route-filter behaviour for the SwapKit fetcher. Asserts that
//  THORChain/Maya routes and multi-hop legs are dropped before ranking, and
//  that single-hop non-filtered routes flow through unchanged. The wire-
//  fetching path is exercised separately (live API) — these tests pin the
//  client-side invariants documented in design §3.
//

import XCTest
@testable import VultisigApp

final class SwapKitServiceTests: XCTestCase {

    // MARK: - Route filtering

    func testFilterDropsThorchainRoutes() {
        let routes = [
            makeRoute(routeId: "thor", providers: ["THORCHAIN"]),
            makeRoute(routeId: "thor-streaming", providers: ["THORCHAIN_STREAMING"]),
            makeRoute(routeId: "chainflip", providers: ["CHAINFLIP"])
        ]
        let filtered = SwapKitService.filterRoutes(routes)
        XCTAssertEqual(filtered.map(\.routeId), ["chainflip"])
    }

    func testFilterDropsMayachainRoutes() {
        let routes = [
            makeRoute(routeId: "maya", providers: ["MAYACHAIN"]),
            makeRoute(routeId: "maya-streaming", providers: ["MAYACHAIN_STREAMING"]),
            makeRoute(routeId: "near", providers: ["NEAR"])
        ]
        let filtered = SwapKitService.filterRoutes(routes)
        XCTAssertEqual(filtered.map(\.routeId), ["near"])
    }

    func testFilterDropsMultiHopRoutes() {
        let routes = [
            makeRoute(routeId: "multi", providers: ["ONEINCH", "CHAINFLIP"]),
            makeRoute(routeId: "single", providers: ["CHAINFLIP"])
        ]
        let filtered = SwapKitService.filterRoutes(routes)
        XCTAssertEqual(
            filtered.map(\.routeId),
            ["single"],
            "Phase 1 design ships single-hop only — see design §3"
        )
    }

    func testFilterKeepsAllSingleHopNonFilteredProviders() {
        let providers = ["NEAR", "CHAINFLIP", "ONEINCH", "GARDEN", "FLASHNET", "HARBOR", "MAYAN"]
        let routes = providers.map { makeRoute(routeId: $0.lowercased(), providers: [$0]) }
        let filtered = SwapKitService.filterRoutes(routes)
        XCTAssertEqual(filtered.count, providers.count)
    }

    // MARK: - Best-route ranking

    func testBestRoutePicksHighestExpectedBuyAmount() {
        let routes = [
            makeRoute(routeId: "low", providers: ["CHAINFLIP"], expectedBuy: "20.0"),
            makeRoute(routeId: "high", providers: ["NEAR"], expectedBuy: "30.0"),
            makeRoute(routeId: "mid", providers: ["ONEINCH"], expectedBuy: "25.0")
        ]
        let best = SwapKitService.bestRoute(in: routes)
        XCTAssertEqual(best?.routeId, "high")
    }

    func testBestRouteReturnsNilForEmptyInput() {
        XCTAssertNil(SwapKitService.bestRoute(in: []))
    }

    // MARK: - End-to-end with a fixture quote

    func testFixtureQuoteSurvivesFilterWithSingleHopRoutes() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitQuoteResponse.self,
            from: "01b-quote-v3"
        )
        let filtered = SwapKitService.filterRoutes(response.routes)
        XCTAssertEqual(filtered.count, response.routes.count)
        let best = try XCTUnwrap(SwapKitService.bestRoute(in: filtered))
        XCTAssertEqual(best.providers, ["ONEINCH"])
    }

    /// BTC routes returned by the spike are all single-hop NEAR / FLASHNET /
    /// GARDEN. None carry THORChain/Maya, so the client-side filter keeps
    /// every one and the best-net-output ranking picks the NEAR route
    /// (highest `expectedBuyAmount`).
    func testBitcoinFixtureQuoteSurvivesFilter() throws {
        let response = try SwapKitFixtureLoader.decode(
            SwapKitQuoteResponse.self,
            from: "v3-real-btc-all-quote"
        )
        let filtered = SwapKitService.filterRoutes(response.routes)
        XCTAssertEqual(filtered.count, response.routes.count)
        XCTAssertEqual(
            Set(filtered.flatMap(\.providers)),
            Set(["NEAR", "FLASHNET", "GARDEN"])
        )
        let best = try XCTUnwrap(SwapKitService.bestRoute(in: filtered))
        XCTAssertEqual(best.providers, ["NEAR"])
    }

    // MARK: - Fixtures

    private func makeRoute(
        routeId: String,
        providers: [String],
        expectedBuy: String = "0"
    ) -> SwapKitRoute {
        SwapKitRoute(
            routeId: routeId,
            providers: providers,
            sellAsset: "ETH.ETH",
            sellAmount: "1.0",
            buyAsset: "ETH.USDC",
            expectedBuyAmount: expectedBuy,
            expectedBuyAmountMaxSlippage: expectedBuy,
            fees: [],
            estimatedTime: nil,
            totalSlippageBps: nil,
            meta: SwapKitQuoteMeta(
                assets: nil,
                tags: nil,
                priceImpact: nil,
                approvalAddress: nil,
                streamingInterval: nil,
                maxStreamingQuantity: nil,
                txType: nil
            ),
            expiration: nil
        )
    }
}
