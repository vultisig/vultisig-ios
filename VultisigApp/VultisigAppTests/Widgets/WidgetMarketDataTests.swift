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
        "image":"https://coin-images.coingecko.com/coins/images/279/large/ethereum.png",
        "current_price":4200,
        "market_cap_rank":2,
        "price_change_percentage_24h":-1.25,
        "sparkline_in_7d":{"price":[1,2,3,4,5,6]}
      },
      {
        "id":"bitcoin",
        "symbol":"btc",
        "name":"Bitcoin",
        "image":"https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png",
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
        XCTAssertFalse(items.keys.contains("ids"))
    }

    func testCatalogRequestSupportsSettingsAssetListWithoutChangingWidgetCap() throws {
        let catalogURL = try WidgetMarketEndpoint.url(query: .catalog(limit: 100), currency: "USD")
        let catalogComponents = try XCTUnwrap(URLComponents(url: catalogURL, resolvingAgainstBaseURL: false))
        let catalogItems = Dictionary(
            uniqueKeysWithValues: (catalogComponents.queryItems ?? []).map { ($0.name, $0.value) }
        )

        XCTAssertEqual(catalogItems["per_page"], "50")
        XCTAssertEqual(catalogItems["sparkline"], "false")
        XCTAssertNil(catalogItems["price_change_percentage"])
        XCTAssertEqual(WidgetMarketQuery.top(limit: 100).limit, 5)
    }

    func testSelectedAssetRequestNormalizesIDsAndPreservesSelectionOrder() throws {
        let query = WidgetMarketQuery.ids([" Ethereum ", "BITCOIN"])
        let url = try WidgetMarketEndpoint.url(query: query, currency: "eur")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let ids = components.queryItems?.first(where: { $0.name == "ids" })?.value
        let assets = try WidgetMarketClient.decode(data: Self.responseData, query: query)

        XCTAssertEqual(ids, "ethereum,bitcoin")
        XCTAssertEqual(assets.map(\.id), ["ethereum", "bitcoin"])
        XCTAssertEqual(assets.map(\.symbol), ["ETH", "BTC"])
    }

    func testSearchRequestUsesSharedProxyBasePath() throws {
        let url = try WidgetMarketEndpoint.searchURL(query: "bitcoin cash")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.path, "/coingeicko/api/v3/search")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "query", value: "bitcoin cash")])
    }

    func testIconURLAcceptsOnlyCoinGeckoHTTPSCDN() throws {
        let approved = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")
        )
        let unapproved = try XCTUnwrap(URL(string: "https://example.com/bitcoin.png"))
        let insecure = try XCTUnwrap(
            URL(string: "http://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")
        )

        XCTAssertEqual(try WidgetMarketEndpoint.validatedImageURL(approved), approved)
        XCTAssertThrowsError(try WidgetMarketEndpoint.validatedImageURL(unapproved)) { error in
            XCTAssertEqual(error as? WidgetMarketError, .unapprovedImageURL)
        }
        XCTAssertThrowsError(try WidgetMarketEndpoint.validatedImageURL(insecure)) { error in
            XCTAssertEqual(error as? WidgetMarketError, .unapprovedImageURL)
        }
    }

    func testEmptyAssetSelectionDoesNotFallThroughToTopMarkets() {
        XCTAssertThrowsError(
            try WidgetMarketEndpoint.url(query: .ids([" "]), currency: "usd")
        ) { error in
            XCTAssertEqual(error as? WidgetMarketError, .emptySelection)
        }
    }

    func testAssetSelectionDeduplicatesAndCapsAtFiveIDs() {
        let query = WidgetMarketQuery.ids([
            "bitcoin", "ethereum", "bitcoin", "solana", "tether", "usd-coin", "dogecoin"
        ])

        XCTAssertEqual(
            query.normalizedIDs,
            ["bitcoin", "ethereum", "solana", "tether", "usd-coin"]
        )
        XCTAssertEqual(query.limit, 5)
    }

    func testWatchlistStoragePreservesEnableOrderDeduplicatesAndCapsAtFive() throws {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let assets = [
            watchlistAsset(id: "bitcoin", symbol: "btc"),
            watchlistAsset(id: "ethereum", symbol: "eth"),
            watchlistAsset(id: "bitcoin", symbol: "BTC"),
            watchlistAsset(id: "solana", symbol: "sol"),
            watchlistAsset(id: "tether", symbol: "usdt"),
            watchlistAsset(id: "usd-coin", symbol: "usdc"),
            watchlistAsset(id: "dogecoin", symbol: "doge")
        ]

        WidgetSharedStorage.setWatchlistAssets(assets, in: defaults)
        let stored = WidgetSharedStorage.watchlistAssets(in: defaults)

        XCTAssertEqual(stored.map(\.id), ["bitcoin", "ethereum", "solana", "tether", "usd-coin"])
        XCTAssertEqual(stored.map(\.symbol), ["BTC", "ETH", "SOL", "USDT", "USDC"])
    }

    func testWatchlistStorageRejectsCorruptPayload() throws {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not-json".utf8), forKey: WidgetSharedStorage.watchlistKey)

        XCTAssertTrue(WidgetSharedStorage.watchlistAssets(in: defaults).isEmpty)
    }

    func testWatchlistStorageDistinguishesDefaultFromExplicitlyEmptySelection() throws {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(WidgetSharedStorage.hasStoredWatchlist(in: defaults))

        WidgetSharedStorage.setWatchlistAssets([], in: defaults)

        XCTAssertTrue(WidgetSharedStorage.hasStoredWatchlist(in: defaults))
        XCTAssertTrue(WidgetSharedStorage.watchlistAssets(in: defaults).isEmpty)
    }

    @MainActor
    func testWatchlistSettingsSeedsTopFiveOnlyWithoutStoredSelection() async throws {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let assets = (1...6).map { index in
            WidgetMarketAsset(
                id: "asset-\(index)",
                symbol: "A\(index)",
                name: "Asset \(index)",
                imageURL: nil,
                iconData: nil,
                currentPrice: Double(index),
                priceChangePercentage24h: nil,
                marketCapRank: index,
                sparkline: []
            )
        }
        let remote = WidgetMarketListStub(assets: assets)

        let defaultViewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            defaults: defaults
        )
        await defaultViewModel.load()

        XCTAssertEqual(defaultViewModel.selectedAssets.map(\.id), assets.prefix(5).map(\.id))
        XCTAssertTrue(WidgetSharedStorage.hasStoredWatchlist(in: defaults))

        WidgetSharedStorage.setWatchlistAssets([], in: defaults)
        let clearedViewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            defaults: defaults
        )
        await clearedViewModel.load()

        XCTAssertTrue(clearedViewModel.selectedAssets.isEmpty)
    }

    func testSparklineSamplerKeepsEndpointsAndRequestedCount() {
        let source = (0..<100).map(Double.init)
        let sampled = WidgetSparklineSampler.resample(source, to: 28)

        XCTAssertEqual(sampled.count, 28)
        XCTAssertEqual(sampled.first, source.first)
        XCTAssertEqual(sampled.last, source.last)
    }

    func testPreviewAssetsReuseSharedAppIconNames() {
        let expectedIcons = [
            "bitcoin": "btc",
            "ethereum": "eth",
            "tether": "usdt",
            "binancecoin": "bsc",
            "solana": "solana"
        ]

        for (id, iconName) in expectedIcons {
            let asset = WidgetMarketAsset(
                id: id,
                symbol: iconName.uppercased(),
                name: id,
                imageURL: nil,
                iconData: nil,
                currentPrice: 1,
                priceChangePercentage24h: nil,
                marketCapRank: nil,
                sparkline: []
            )
            XCTAssertEqual(asset.iconLogo, iconName)
        }
    }

    func testRemoteIconURLIsNotExposedToAsyncImageView() throws {
        let imageURL = try XCTUnwrap(URL(string: "https://example.com/bitcoin.png"))
        let asset = WidgetMarketAsset(
            id: "bitcoin",
            symbol: "BTC",
            name: "Bitcoin",
            imageURL: imageURL,
            iconData: nil,
            currentPrice: 1,
            priceChangePercentage24h: nil,
            marketCapRank: nil,
            sparkline: []
        )

        XCTAssertEqual(asset.iconLogo, "btc")

        let unknownAsset = WidgetMarketAsset(
            id: "chainlink",
            symbol: "LINK",
            name: "Chainlink",
            imageURL: imageURL,
            iconData: nil,
            currentPrice: 1,
            priceChangePercentage24h: nil,
            marketCapRank: nil,
            sparkline: []
        )
        XCTAssertEqual(unknownAsset.iconLogo, "")
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

    func testCacheEvictsOldestConfigurationBeyondBound() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let asset = try XCTUnwrap(
            WidgetMarketClient.decode(data: Self.responseData, query: .top(limit: 1)).first
        )

        for index in 0..<7 {
            try await cache.store(
                [asset],
                updatedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                for: "configuration-\(index)"
            )
        }

        let oldest = await cache.entry(for: "configuration-0")
        let newest = await cache.entry(for: "configuration-6")
        XCTAssertNil(oldest)
        XCTAssertNotNil(newest)
    }

    func testSeparateCachesPreserveConcurrentWrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let asset = try XCTUnwrap(
            WidgetMarketClient.decode(data: Self.responseData, query: .top(limit: 1)).first
        )

        for index in 0..<20 {
            let fileURL = directory.appendingPathComponent("cache-\(index).json")
            let firstCache = WidgetMarketCache(fileURL: fileURL)
            let secondCache = WidgetMarketCache(fileURL: fileURL)
            async let firstWrite: Void = firstCache.store(
                [asset],
                updatedAt: Date(timeIntervalSince1970: 1),
                for: "first"
            )
            async let secondWrite: Void = secondCache.store(
                [asset],
                updatedAt: Date(timeIntervalSince1970: 2),
                for: "second"
            )

            _ = try await (firstWrite, secondWrite)

            let verifier = WidgetMarketCache(fileURL: fileURL)
            let first = await verifier.entry(for: "first")
            let second = await verifier.entry(for: "second")
            XCTAssertNotNil(first, "Missing first write at iteration \(index)")
            XCTAssertNotNil(second, "Missing second write at iteration \(index)")
        }
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

    func testServiceDoesNotUseStaleCacheForCancelledRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let remote = WidgetMarketRemoteStub()
        let service = WidgetMarketService(remote: remote, cache: cache)

        _ = try await service.load(query: .top(limit: 2), currency: "usd")
        await remote.setShouldCancel(true)

        do {
            _ = try await service.load(query: .top(limit: 2), currency: "usd")
            XCTFail("Expected cancellation to propagate")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        }
    }

    func testServiceAttachesDownloadedIconsToFreshAssets() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let remote = WidgetMarketRemoteStub()
        let service = WidgetMarketService(remote: remote, cache: cache)

        let result = try await service.load(query: .top(limit: 2), currency: "usd")

        XCTAssertEqual(result.assets.count, 2)
        XCTAssertTrue(result.assets.allSatisfy { asset in
            guard let imageURL = asset.imageURL else { return false }
            return asset.iconData == Data(imageURL.absoluteString.utf8)
        })
    }

    private func watchlistAsset(id: String, symbol: String) -> WidgetWatchlistAsset {
        WidgetWatchlistAsset(id: id, symbol: symbol, name: id.capitalized, imageURL: nil)
    }
}

private actor WidgetMarketRemoteStub: WidgetMarketRemote {
    private var shouldFail = false
    private var shouldCancel = false

    func setShouldFail(_ value: Bool) {
        shouldFail = value
    }

    func setShouldCancel(_ value: Bool) {
        shouldCancel = value
    }

    func markets(query: WidgetMarketQuery, currency _: String) throws -> [WidgetMarketAsset] {
        if shouldCancel { throw URLError(.cancelled) }
        if shouldFail { throw WidgetMarketError.httpStatus(503) }
        return try WidgetMarketClient.decode(data: WidgetMarketDataTests.responseData, query: query)
    }

    func iconData(from url: URL) throws -> Data {
        Data(url.absoluteString.utf8)
    }
}

private actor WidgetMarketListStub: WidgetMarketRemote {
    let assets: [WidgetMarketAsset]

    init(assets: [WidgetMarketAsset]) {
        self.assets = assets
    }

    func markets(query _: WidgetMarketQuery, currency _: String) -> [WidgetMarketAsset] {
        assets
    }

    func iconData(from _: URL) -> Data {
        Data()
    }
}
