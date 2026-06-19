//
//  NativePoolEligibilityCacheTests.swift
//  VultisigAppTests
//
//  TTL + fail-open behaviour of the native-pool eligibility cache, plus the
//  Maya inbound-address decode (Decision 2). Fixtures land at `__fixtures__/`
//  in the test bundle (folder reference in project.yml).
//

import XCTest
@testable import VultisigApp

final class NativePoolEligibilityCacheTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let bundle = Bundle(for: NativePoolEligibilityCacheTests.self)
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "NativePoolFixtures") else {
            throw NSError(domain: "fixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(name)"])
        }
        return try Data(contentsOf: url)
    }

    private func makeStub() throws -> StubHTTPClient {
        StubHTTPClient(responses: [
            "/thorchain/pools": try fixtureData("thorchain-pools"),
            "/mayachain/pools": try fixtureData("mayachain-pools"),
            "/mayachain/inbound_addresses": try fixtureData("mayachain-inbound-addresses")
        ])
    }

    // MARK: - Normalization

    func testFetchFiltersToAvailableOnly() async throws {
        let cache = NativePoolEligibilityCache(httpClient: try makeStub())
        let thor = await cache.pools(.thorchain)
        XCTAssertNotNil(thor)
        // The Staged ETH.WSTETH pool is excluded.
        XCTAssertFalse(thor!.contains { $0.ticker == "WSTETH" })
        XCTAssertTrue(thor!.contains { $0.ticker == "ETH" && $0.contract == nil })
        XCTAssertTrue(thor!.contains { $0.ticker == "USDC" })
        // The BTC.BTC pool's chain prefix is unsupported (UTXO not array-gated)
        // and is dropped at normalization.
        XCTAssertFalse(thor!.contains { $0.ticker == "BTC" })
    }

    func testMayaFetchSurfacesUsdtAndMoca() async throws {
        let cache = NativePoolEligibilityCache(httpClient: try makeStub())
        let maya = await cache.pools(.mayachain)
        XCTAssertNotNil(maya)
        XCTAssertTrue(maya!.contains { $0.ticker == "USDT" && $0.poolChain == .ethereum })
        XCTAssertTrue(maya!.contains { $0.ticker == "MOCA" && $0.poolChain == .ethereum })
    }

    // MARK: - TTL

    func testCacheHitWithinTTLDoesNotRefetch() async throws {
        let stub = try makeStub()
        let cache = NativePoolEligibilityCache(httpClient: stub)
        let now = Date()
        _ = await cache.pools(.thorchain, now: now)
        _ = await cache.pools(.thorchain, now: now.addingTimeInterval(60))
        let count = await stub.requestCount
        XCTAssertEqual(count, 1)
    }

    func testCacheRefreshesAfterTTL() async throws {
        let stub = try makeStub()
        let cache = NativePoolEligibilityCache(httpClient: stub)
        let now = Date()
        _ = await cache.pools(.thorchain, now: now)
        _ = await cache.pools(.thorchain, now: now.addingTimeInterval(6 * 60))
        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }

    // MARK: - Fail-open

    func testFetchFailureWithPriorSnapshotReturnsLastGood() async throws {
        let stub = try makeStub()
        let cache = NativePoolEligibilityCache(httpClient: stub)
        let now = Date()
        let good = await cache.pools(.thorchain, now: now)
        XCTAssertNotNil(good)
        await stub.setFailing(true)
        // Past TTL → tries to refetch, fails, falls back to last-good.
        let lastGood = await cache.pools(.thorchain, now: now.addingTimeInterval(6 * 60))
        XCTAssertEqual(lastGood?.count, good?.count)
    }

    func testFetchFailureWithNoSnapshotReturnsNil() async {
        let cache = NativePoolEligibilityCache(httpClient: FailingHTTPClient())
        let result = await cache.pools(.thorchain)
        XCTAssertNil(result)
    }

    // MARK: - setSnapshot seam

    func testSetSnapshotIsConsulted() async {
        let cache = NativePoolEligibilityCache(httpClient: FailingHTTPClient())
        let pool = NativePoolAsset(poolChain: .ethereum, ticker: "USDT", contract: "0xdac17f958d2ee523a2206206994597c13d831ec7", isAvailable: true, isTradingHalted: false)
        await cache.setSnapshot(.mayachain, NativePoolSnapshot(pools: [pool], fetchedAt: Date()))
        let pools = await cache.pools(.mayachain)
        XCTAssertEqual(pools?.count, 1)
    }

    // MARK: - Maya inbound (Decision 2)

    func testMayaInboundDecodesHaltFlags() async throws {
        let service = MayachainService(httpClient: try makeStub())
        let inbound = await service.fetchInboundAddress()
        let arb = inbound.first { $0.chain == "ARB" }
        XCTAssertEqual(arb?.halted, true)
        XCTAssertEqual(arb?.chain_trading_paused, true)
        let eth = inbound.first { $0.chain == "ETH" }
        XCTAssertEqual(eth?.halted, false)
    }

    func testMayaInboundBypassCacheIssuesFreshRequest() async throws {
        let stub = try makeStub()
        let service = MayachainService(httpClient: stub)
        _ = await service.fetchInboundAddress()
        _ = await service.fetchInboundAddress(bypassCache: true)
        let count = await stub.requestCount
        XCTAssertEqual(count, 2)
    }
}

// MARK: - Test doubles

/// HTTP client stub keyed by request path. Optionally flips to always-failing
/// to exercise the cache's fail-open path.
private actor StubHTTPClient: HTTPClientProtocol {
    private let responses: [String: Data]
    private var failing = false
    private(set) var requestCount: Int = 0

    init(responses: [String: Data]) {
        self.responses = responses
    }

    func setFailing(_ value: Bool) {
        failing = value
    }

    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        await Task.yield()
        requestCount += 1
        if failing {
            throw HTTPError.statusCode(503, nil)
        }
        guard let data = responses[target.path] else {
            throw HTTPError.statusCode(501, nil)
        }
        let url = target.baseURL.appendingPathComponent(target.path)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return HTTPResponse(data: data, response: response)
    }
}

private final class FailingHTTPClient: HTTPClientProtocol, @unchecked Sendable {
    private enum TestError: Error { case unavailable }
    func request(_ target: TargetType) async throws -> HTTPResponse<Data> {
        _ = target
        await Task.yield()
        throw TestError.unavailable
    }
}
