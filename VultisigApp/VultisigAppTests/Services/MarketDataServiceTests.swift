//
//  MarketDataServiceTests.swift
//  VultisigAppTests
//
//  Routing (CoinGecko id vs asset-platform contract vs unsupported), the
//  case-sensitivity fix on `/coins/{id}`, TTL caching per (source, range,
//  currency), fail-open to the last-good series, and the sparse-series floor.
//

@testable import VultisigApp
import Foundation
import XCTest

final class MarketDataServiceTests: XCTestCase {

    // MARK: - Fixtures

    private static let bitcoin = CoinMeta(
        chain: .bitcoin,
        ticker: "BTC",
        logo: "btc",
        decimals: 8,
        priceProviderId: "bitcoin",
        contractAddress: "",
        isNativeToken: true
    )

    /// `Coin.example` ships a capitalised `priceProviderId`, and the upstream
    /// `/coins/{id}` route is case-sensitive.
    private static let capitalisedBitcoin = CoinMeta(
        chain: .bitcoin,
        ticker: "BTC",
        logo: "btc",
        decimals: 8,
        priceProviderId: "Bitcoin",
        contractAddress: "",
        isNativeToken: true
    )

    /// EVM token with no price-provider id — charts by contract.
    private static let evmToken = CoinMeta(
        chain: .ethereum,
        ticker: "USDC",
        logo: "usdc",
        decimals: 6,
        priceProviderId: "",
        contractAddress: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        isNativeToken: false
    )

    /// Solana SPL token with no price-provider id. Solana has no CoinGecko
    /// asset platform in the table, so it is pool-priced and unsupported here.
    private static let poolPricedToken = CoinMeta(
        chain: .solana,
        ticker: "POOL",
        logo: "pool",
        decimals: 6,
        priceProviderId: "",
        contractAddress: "So11111111111111111111111111111111111111112",
        isNativeToken: false
    )

    private static let suiToken = CoinMeta(
        chain: .sui,
        ticker: "CUSTOM",
        logo: "",
        decimals: 9,
        priceProviderId: "",
        contractAddress: "0x000A::custom::CUSTOM",
        isNativeToken: false
    )

    private static func seriesJSON(count: Int, startingAt price: Double = 100) -> Data {
        let pairs = (0..<count)
            .map { "[\(1_700_000_000_000 + $0 * 300_000),\(price + Double($0))]" }
            .joined(separator: ",")
        return Data("{\"prices\":[\(pairs)]}".utf8)
    }

    private static let statsJSON = Data(#"""
    [{"id":"bitcoin","current_price":63916,"market_cap":1282270987961,"market_cap_rank":1}]
    """#.utf8)

    // MARK: - Routing

    func testResolvesNativeCoinToItsPriceProviderId() {
        XCTAssertEqual(MarketDataService.resolveSource(for: Self.bitcoin), .id("bitcoin"))
    }

    func testResolvesEvmTokenWithoutIdToItsContract() {
        XCTAssertEqual(
            MarketDataService.resolveSource(for: Self.evmToken),
            .contract(platform: "ethereum", address: Self.evmToken.contractAddress.lowercased())
        )
    }

    func testResolvesSuiTokenUsingRealCaseSensitiveCoinType() {
        XCTAssertEqual(
            MarketDataService.resolveSource(for: Self.suiToken),
            .contract(platform: "sui", address: "0xa::custom::CUSTOM")
        )
    }

    func testSourceIsCaseNormalisedSoOneCoinKeepsOneCacheEntry() {
        XCTAssertEqual(
            MarketDataService.resolveSource(for: Self.capitalisedBitcoin),
            MarketDataService.resolveSource(for: Self.bitcoin)
        )
    }

    func testCapitalisedIdIsFetchedOnlyOnceAcrossSpellings() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)
        _ = await service.chart(for: Self.capitalisedBitcoin, range: .day, currency: .USD)

        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    func testPoolPricedTokenHasNoSource() {
        XCTAssertNil(MarketDataService.resolveSource(for: Self.poolPricedToken))
    }

    func testCoinWithNoIdAndNoPlatformHasNoSource() {
        let thorPoolAsset = CoinMeta(
            chain: .thorChain,
            ticker: "TCY",
            logo: "tcy",
            decimals: 8,
            priceProviderId: "",
            contractAddress: "TCY",
            isNativeToken: false
        )
        XCTAssertNil(MarketDataService.resolveSource(for: thorPoolAsset))
    }

    // MARK: - Request shape

    func testChartRequestLowercasesTheIdInThePath() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let service = MarketDataService(httpClient: stub)

        _ = await service.chart(for: Self.capitalisedBitcoin, range: .day, currency: .USD)

        let paths = await stub.paths
        XCTAssertEqual(paths, ["/coingeicko/api/v3/coins/bitcoin/market_chart"])
    }

    func testCapitalisedIdStillResolvesAChart() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let service = MarketDataService(httpClient: stub)

        let chart = await service.chart(for: Self.capitalisedBitcoin, range: .day, currency: .USD)

        XCTAssertNotNil(chart)
    }

    func testContractChartUsesThePlatformContractPath() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let service = MarketDataService(httpClient: stub)

        _ = await service.chart(for: Self.evmToken, range: .week, currency: .USD)

        let paths = await stub.paths
        XCTAssertEqual(
            paths,
            ["/coingeicko/api/v3/coins/ethereum/contract/\(Self.evmToken.contractAddress.lowercased())/market_chart"]
        )
    }

    func testUnsupportedTokenNeverHitsTheNetwork() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let service = MarketDataService(httpClient: stub)

        let chart = await service.chart(for: Self.poolPricedToken, range: .day, currency: .USD)
        let stats = await service.stats(for: Self.poolPricedToken, currency: .USD)

        XCTAssertNil(chart)
        XCTAssertNil(stats)
        let count = await stub.requestCount
        XCTAssertEqual(count, 0)
    }

    func testContractRoutedTokenHasNoStats() async {
        // `/coins/markets` is keyed by id, so there is nothing to ask for.
        let stub = StubHTTPClient(payload: Self.statsJSON)
        let service = MarketDataService(httpClient: stub)

        let stats = await service.stats(for: Self.evmToken, currency: .USD)

        XCTAssertNil(stats)
        let count = await stub.requestCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Caching

    func testSecondReadInsideTTLIsServedFromCache() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)
        clock.advance(by: 30)
        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)

        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    func testReadAfterTTLRefetches() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)
        clock.advance(by: MarketChartRange.day.cacheTTL + 1)
        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)

        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    func testEachRangeIsCachedSeparately() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)
        _ = await service.chart(for: Self.bitcoin, range: .week, currency: .USD)
        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)

        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    func testEachCurrencyIsCachedSeparately() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)
        _ = await service.chart(for: Self.bitcoin, range: .day, currency: .EUR)

        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    func testStatsAreCachedInsideTTL() async {
        let stub = StubHTTPClient(payload: Self.statsJSON)
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        _ = await service.stats(for: Self.bitcoin, currency: .USD)
        clock.advance(by: 30)
        let second = await service.stats(for: Self.bitcoin, currency: .USD)

        XCTAssertEqual(second?.id, "bitcoin")
        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    // MARK: - Failure behaviour

    func testFailedRefreshServesTheLastGoodSeries() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: 40))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        let first = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)
        XCTAssertNotNil(first)

        await stub.startFailing(HTTPError.statusCode(500, nil))
        clock.advance(by: MarketChartRange.day.cacheTTL + 1)
        let second = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)

        XCTAssertEqual(second?.points.count, first?.points.count)
    }

    func testFirstFetchFailureReturnsNil() async {
        let stub = StubHTTPClient(payload: nil, error: HTTPError.statusCode(404, nil))
        let service = MarketDataService(httpClient: stub)

        let chart = await service.chart(for: Self.bitcoin, range: .day, currency: .USD)

        XCTAssertNil(chart)
    }

    func testEmptyMarketsArrayReturnsNilRatherThanCachingAMiss() async {
        let stub = StubHTTPClient(payload: Data("[]".utf8))
        let clock = ClockBox(start: Date(timeIntervalSince1970: 0))
        let service = MarketDataService(httpClient: stub, now: { clock.now })

        let first = await service.stats(for: Self.bitcoin, currency: .USD)
        let second = await service.stats(for: Self.bitcoin, currency: .USD)

        XCTAssertNil(first)
        XCTAssertNil(second)
        // The miss must not have been stored as a good snapshot: asking again
        // inside the TTL still goes to the network.
        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Sparse + resampling

    func testSeriesBelowTheUsableFloorIsTreatedAsNoChart() async {
        let stub = StubHTTPClient(payload: Self.seriesJSON(count: MarketChart.minimumUsablePoints - 1))
        let service = MarketDataService(httpClient: stub)

        let chart = await service.chart(for: Self.bitcoin, range: .all, currency: .USD)

        XCTAssertNil(chart)
    }

    func testEmptySeriesIsTreatedAsNoChart() async {
        let stub = StubHTTPClient(payload: Data(#"{"prices":[]}"#.utf8))
        let service = MarketDataService(httpClient: stub)

        let chart = await service.chart(for: Self.bitcoin, range: .all, currency: .USD)

        XCTAssertNil(chart)
    }

    func testEveryServedSeriesHasTheSameCardinality() async throws {
        // Both directions: a `days=max` series is thinned down and a `days=7`
        // one is interpolated up, and they meet at the same count. Ranges that
        // disagree on it are what makes a switch ghost instead of morph.
        for count in [MarketChart.minimumUsablePoints, 169, 4838] {
            let stub = StubHTTPClient(payload: Self.seriesJSON(count: count))
            let service = MarketDataService(httpClient: stub)

            let served = await service.chart(for: Self.bitcoin, range: .all, currency: .USD)
            let chart = try XCTUnwrap(served)

            XCTAssertEqual(chart.points.count, MarketChartRendering.pointCount, "source \(count)")
        }
    }

    func testResamplingRunsAfterTheUsabilityFloorNotBefore() async {
        // A one-sample series would interpolate into a full-width flat line if
        // the resample came first; the floor has to see the real count.
        let stub = StubHTTPClient(payload: Data(#"{"prices":[[1000,1.0]]}"#.utf8))
        let service = MarketDataService(httpClient: stub)

        let chart = await service.chart(for: Self.bitcoin, range: .all, currency: .USD)

        XCTAssertNil(chart)
    }
}

// MARK: - Test doubles

/// Records every request's path and answers each with the same payload, so the
/// tests can assert on routing and on how often the cache let a fetch through.
private actor StubHTTPClient: HTTPClientProtocol {
    private var payload: Data?
    private var error: Error?
    private(set) var paths: [String] = []

    var requestCount: Int { paths.count }

    init(payload: Data?, error: Error? = nil) {
        self.payload = payload
        self.error = error
    }

    func startFailing(_ error: Error) {
        self.error = error
    }

    // `async` comes from `HTTPClientProtocol`, not from this body.
    // swiftlint:disable:next async_without_await
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        paths.append(target.path)
        if let error { throw error }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: payload ?? Data(), response: response)
    }
}

/// Movable clock so TTL expiry is exercised without sleeping.
///
/// Locked rather than plain mutable state: the service hands `now` to
/// `TTLCache`, which reads it from inside an actor, so the read genuinely
/// crosses threads even though these tests drive it sequentially.
private final class ClockBox: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(start: Date) {
        current = start
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        current = current.addingTimeInterval(seconds)
    }
}
