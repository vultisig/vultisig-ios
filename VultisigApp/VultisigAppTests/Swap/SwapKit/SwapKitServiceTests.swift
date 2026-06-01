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

    // MARK: - noRoutesFound surfacing

    /// SwapKit's `/v3/quote` 404 `noRoutesFound` envelope carries no
    /// minimum/amount metadata, so it must surface as `noRoutesFound`
    /// ("No routes available for this pair") even when the cached providers
    /// snapshot reports the pair as structurally supported. The previous
    /// behaviour re-classified this to `amountBelowProviderMinimum` and showed
    /// "Amount Too Small" for genuinely unroutable pairs (e.g. TRX→SUI).
    func testFetchBestRoute_noRoutesFoundOnSupportedPair_keepsNoRoutesFound() async throws {
        let body = #"{"error":"noRoutesFound","message":"No routes found for BCH.BCH -> ETH.ETH","data":{"sellAsset":"BCH.BCH","buyAsset":"ETH.ETH"}}"#
        let data = try XCTUnwrap(body.data(using: .utf8))
        let client = NoRoutesHTTPClient(payload: data)
        let cache = await Self.makeCacheWithSupportedPair(fromChain: .bitcoinCash, toChain: .ethereum)
        let service = SwapKitService(httpClient: client, providerCache: cache)

        do {
            _ = try await service.fetchBestRoute(
                fromCoin: Self.makeNativeCoin(.bitcoinCash, ticker: "BCH", decimals: 8),
                toCoin: Self.makeNativeCoin(.ethereum, ticker: "ETH", decimals: 18),
                amount: Decimal(string: "0.0115") ?? .zero,
                affiliateFeeBps: 50
            )
            XCTFail("Expected SwapKitError.noRoutesFound")
        } catch let error as SwapKitError {
            XCTAssertEqual(error, .noRoutesFound)
            XCTAssertNotEqual(error, .amountBelowProviderMinimum)
        }
    }

    /// Pair the cache reports as unsupported must also surface `noRoutesFound`.
    func testFetchBestRoute_noRoutesFoundOnUnsupportedPair_keepsNoRoutesFound() async throws {
        let body = #"{"error":"noRoutesFound","message":"No routes found","data":{}}"#
        let data = try XCTUnwrap(body.data(using: .utf8))
        let client = NoRoutesHTTPClient(payload: data)
        // Snapshot contains a non-filtered provider that enables ONLY
        // bitcoincash — never ethereum — so the pair predicate returns false.
        let cache = SwapKitProviderCache()
        await cache.setSnapshot(SwapKitProvidersSnapshot(
            providers: [
                SwapKitProvider(
                    name: "NARROW",
                    provider: "NARROW",
                    displayName: nil,
                    displayNameLong: nil,
                    count: 1,
                    enabledChainIds: [SwapKitChainIDMapper.swapKitChainId(for: .bitcoinCash)],
                    supportedChainIds: nil,
                    supportedActions: nil
                )
            ],
            fetchedAt: Date()
        ))
        let service = SwapKitService(httpClient: client, providerCache: cache)

        do {
            _ = try await service.fetchBestRoute(
                fromCoin: Self.makeNativeCoin(.bitcoinCash, ticker: "BCH", decimals: 8),
                toCoin: Self.makeNativeCoin(.ethereum, ticker: "ETH", decimals: 18),
                amount: Decimal(string: "0.5") ?? .zero,
                affiliateFeeBps: 50
            )
            XCTFail("Expected SwapKitError.noRoutesFound")
        } catch let error as SwapKitError {
            XCTAssertEqual(error, .noRoutesFound)
        }
    }

    /// Fail-open path: when the provider cache can't load (empty snapshot via
    /// the actor's `nil` providers fallback), `noRoutesFound` must NOT degrade
    /// into "Amount Too Small". An unroutable pair on an unavailable cache
    /// surfaces `noRoutesFound`.
    func testFetchBestRoute_noRoutesFoundWithUnavailableCache_keepsNoRoutesFound() async throws {
        let body = #"{"error":"noRoutesFound","message":"No routes found"}"#
        let data = try XCTUnwrap(body.data(using: .utf8))
        let client = NoRoutesHTTPClient(payload: data)
        // No snapshot set and the HTTP client always 404s, so the cache's
        // `providers()` returns nil → `isPairSupported` would fail open to
        // `true`. The service must not consult that heuristic any more.
        let cache = SwapKitProviderCache(httpClient: client)
        let service = SwapKitService(httpClient: client, providerCache: cache)

        do {
            _ = try await service.fetchBestRoute(
                fromCoin: Self.makeNativeCoin(.tron, ticker: "TRX", decimals: 6),
                toCoin: Self.makeNativeCoin(.sui, ticker: "SUI", decimals: 9),
                amount: Decimal(string: "1") ?? .zero,
                affiliateFeeBps: 50
            )
            XCTFail("Expected SwapKitError.noRoutesFound")
        } catch let error as SwapKitError {
            XCTAssertEqual(error, .noRoutesFound)
            XCTAssertNotEqual(error, .amountBelowProviderMinimum)
        }
    }

    /// Non-`noRoutesFound` SwapKit errors are surfaced verbatim.
    func testFetchBestRoute_otherErrorsPassThroughUnchanged() async throws {
        let body = #"{"error":"apiKeyInvalid","message":"API key invalid"}"#
        let data = try XCTUnwrap(body.data(using: .utf8))
        let client = NoRoutesHTTPClient(payload: data)
        let cache = await Self.makeCacheWithSupportedPair(fromChain: .bitcoinCash, toChain: .ethereum)
        let service = SwapKitService(httpClient: client, providerCache: cache)

        do {
            _ = try await service.fetchBestRoute(
                fromCoin: Self.makeNativeCoin(.bitcoinCash, ticker: "BCH", decimals: 8),
                toCoin: Self.makeNativeCoin(.ethereum, ticker: "ETH", decimals: 18),
                amount: Decimal(string: "0.5") ?? .zero,
                affiliateFeeBps: 50
            )
            XCTFail("Expected SwapKitError.apiKeyInvalid")
        } catch let error as SwapKitError {
            XCTAssertEqual(error, .apiKeyInvalid)
        }
    }

    // MARK: - Fixtures

    private static func makeNativeCoin(_ chain: Chain, ticker: String, decimals: Int) -> Coin {
        let meta = CoinMeta.make(chain: chain, ticker: ticker, decimals: decimals, isNativeToken: true)
        return Coin(asset: meta, address: "test-address-\(ticker)", hexPublicKey: "")
    }

    private static func makeCacheWithSupportedPair(fromChain: Chain, toChain: Chain) async -> SwapKitProviderCache {
        let cache = SwapKitProviderCache()
        let snapshot = SwapKitProvidersSnapshot(
            providers: [
                SwapKitProvider(
                    name: "NEAR",
                    provider: "NEAR",
                    displayName: nil,
                    displayNameLong: nil,
                    count: 1,
                    enabledChainIds: [
                        SwapKitChainIDMapper.swapKitChainId(for: fromChain),
                        SwapKitChainIDMapper.swapKitChainId(for: toChain)
                    ],
                    supportedChainIds: nil,
                    supportedActions: nil
                )
            ],
            fetchedAt: Date()
        )
        await cache.setSnapshot(snapshot)
        return cache
    }

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

// MARK: - Test doubles

/// HTTPClient stub that always throws `HTTPError.statusCode(404, payload)` —
/// simulates SwapKit's `/v3/quote` returning an error envelope. Mirrors the
/// shape `SwapKitService.fetchBestRoute` catches.
private final class NoRoutesHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private let payload: Data

    init(payload: Data) {
        self.payload = payload
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        _ = target
        await Task.yield()
        throw HTTPError.statusCode(404, payload)
    }

    func request<T: Decodable>(_ target: TargetType, responseType: T.Type) async throws -> HTTPResponse<T> {
        _ = target
        _ = responseType
        await Task.yield()
        throw HTTPError.statusCode(404, payload)
    }
}
