//
//  WidgetMarketDataTests.swift
//  VultisigAppTests
//

@testable import VultisigApp
import Foundation
import XCTest

final class WidgetMarketDataTests: XCTestCase {
    fileprivate static let responseData = Data(#"""
    [
      {
        "id":"ethereum",
        "symbol":"eth",
        "name":"Ethereum",
        "image":"https://example.com/eth.png",
        "current_price":4200,
        "market_cap_rank":2,
        "price_change_percentage_24h":-1.25,
        "sparkline_in_7d":{"price":[1,2,3,4,5,6]}
      },
      {
        "id":"bitcoin",
        "symbol":"btc",
        "name":"Bitcoin",
        "image":"https://example.com/btc.png",
        "current_price":79910,
        "market_cap_rank":1,
        "price_change_percentage_24h":3.54,
        "sparkline_in_7d":{"price":[10,11,12,13,14,15]}
      }
    ]
    """#.utf8)

    func testTopRequestIncludesOneBulkMarketQuery() throws {
        let url = try WidgetMarketEndpoint.url(query: .top(limit: 5), currency: "USD")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.path, "/coingeicko/api/v3/coins/markets")
        XCTAssertEqual(items["vs_currency"], "usd")
        XCTAssertEqual(items["order"], "market_cap_desc")
        XCTAssertEqual(items["per_page"], "5")
        XCTAssertEqual(items["sparkline"], "true")
        XCTAssertEqual(items["price_change_percentage"], "24h")
        XCTAssertNil(items["ids"])
    }

    func testWatchlistRequestNormalizesIDsAndPreservesSelectionOrder() throws {
        let query = WidgetMarketQuery.ids([" Ethereum ", "BITCOIN"])
        let url = try WidgetMarketEndpoint.url(query: query, currency: "eur")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let ids = components.queryItems?.first(where: { $0.name == "ids" })?.value
        let assets = try WidgetMarketClient.decode(data: Self.responseData, query: query)

        XCTAssertEqual(ids, "ethereum,bitcoin")
        XCTAssertEqual(assets.map(\.id), ["ethereum", "bitcoin"])
        XCTAssertEqual(assets.map(\.symbol), ["ETH", "BTC"])
    }

    func testEmptyWatchlistDoesNotFallThroughToTopMarkets() {
        XCTAssertThrowsError(
            try WidgetMarketEndpoint.url(query: .ids([" "]), currency: "usd")
        ) { error in
            XCTAssertEqual(error as? WidgetMarketError, .emptySelection)
        }
    }

    func testSparklineSamplerKeepsEndpointsAndRequestedCount() {
        let source = (0..<100).map(Double.init)
        let sampled = WidgetSparklineSampler.resample(source, to: 28)

        XCTAssertEqual(sampled.count, 28)
        XCTAssertEqual(sampled.first, source.first)
        XCTAssertEqual(sampled.last, source.last)
    }

    func testCacheRoundTripRetainsIconData() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let asset = try XCTUnwrap(
            WidgetMarketClient.decode(data: Self.responseData, query: .top(limit: 1)).first
        ).withIconData(Data([1, 2, 3]))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        try await cache.store([asset], updatedAt: date, for: "usd-top-1")
        let cached = await cache.entry(for: "usd-top-1")

        XCTAssertEqual(cached?.assets.first?.iconData, Data([1, 2, 3]))
        XCTAssertEqual(cached?.updatedAt, date)
    }

    func testServiceFallsBackToLastGoodCache() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let remote = WidgetMarketRemoteStub()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let service = WidgetMarketService(remote: remote, cache: cache, now: { now })

        let fresh = try await service.load(query: .top(limit: 2), currency: "usd")
        await remote.setShouldFail(true)
        let stale = try await service.load(query: .top(limit: 2), currency: "usd")

        XCTAssertFalse(fresh.isStale)
        XCTAssertTrue(stale.isStale)
        XCTAssertEqual(stale.assets, fresh.assets)
        XCTAssertEqual(stale.updatedAt, now)
    }
}

private actor WidgetMarketRemoteStub: WidgetMarketRemote {
    private var shouldFail = false

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func markets(query: WidgetMarketQuery, currency _: String) throws -> [WidgetMarketAsset] {
        if shouldFail { throw WidgetMarketError.httpStatus(503) }
        return try WidgetMarketClient.decode(data: WidgetMarketDataTests.responseData, query: query)
    }

    func iconData(from url: URL) throws -> Data {
        Data(url.absoluteString.utf8)
    }
}
