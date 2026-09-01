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
        let target = try WidgetMarketAPI.markets(query: .top(limit: 5), currency: "USD")
        let items = try requestParameters(from: target)

        XCTAssertEqual(target.baseURL.absoluteString, "https://api.vultisig.com")
        XCTAssertEqual(target.path, "/coingeicko/api/v3/coins/markets")
        XCTAssertEqual(target.method, .get)
        XCTAssertEqual(target.timeoutInterval, 12)
        XCTAssertEqual(items["vs_currency"], "usd")
        XCTAssertEqual(items["order"], "market_cap_desc")
        XCTAssertEqual(items["per_page"], "5")
        XCTAssertEqual(items["sparkline"], "true")
        XCTAssertEqual(items["price_change_percentage"], "24h")
        XCTAssertFalse(items.keys.contains("ids"))
    }

    func testCatalogRequestSupportsSettingsAssetListWithoutChangingWidgetCap() throws {
        let target = try WidgetMarketAPI.markets(query: .catalog(limit: 100), currency: "USD")
        let catalogItems = try requestParameters(from: target)

        XCTAssertEqual(catalogItems["per_page"], "50")
        XCTAssertEqual(catalogItems["sparkline"], "false")
        XCTAssertNil(catalogItems["price_change_percentage"])
        XCTAssertEqual(WidgetMarketQuery.top(limit: 100).limit, 5)
    }

    func testSelectedAssetRequestNormalizesIDsAndPreservesSelectionOrder() throws {
        let query = WidgetMarketQuery.ids([" Ethereum ", "BITCOIN"])
        let target = try WidgetMarketAPI.markets(query: query, currency: "eur")
        let ids = try requestParameters(from: target)["ids"]
        let assets = try WidgetMarketClient.decode(data: Self.responseData, query: query)

        XCTAssertEqual(ids, "ethereum,bitcoin")
        XCTAssertEqual(assets.map(\.id), ["ethereum", "bitcoin"])
        XCTAssertEqual(assets.map(\.symbol), ["ETH", "BTC"])
    }

    func testSearchRequestUsesSharedProxyAndEncodesSpacesOnce() async throws {
        WidgetURLCapturingProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WidgetURLCapturingProtocol.self]
        let httpClient = HTTPClient(session: URLSession(configuration: configuration))

        _ = try await httpClient.request(WidgetMarketAPI.search(query: "bitcoin cash"))

        let url = try XCTUnwrap(WidgetURLCapturingProtocol.capturedURL)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/coingeicko/api/v3/search")
        XCTAssertEqual(components.queryItems, [URLQueryItem(name: "query", value: "bitcoin cash")])
        XCTAssertEqual(url.absoluteString, "https://api.vultisig.com/coingeicko/api/v3/search?query=bitcoin%20cash")
    }

    func testIconURLAcceptsOnlyCoinGeckoHTTPSCDN() throws {
        let approved = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")
        )
        let unapproved = try XCTUnwrap(URL(string: "https://example.com/bitcoin.png"))
        let insecure = try XCTUnwrap(
            URL(string: "http://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")
        )

        XCTAssertEqual(try WidgetMarketAPI.validatedImageURL(approved), approved)
        XCTAssertThrowsError(try WidgetMarketAPI.validatedImageURL(unapproved)) { error in
            XCTAssertEqual(error as? WidgetMarketError, .unapprovedImageURL)
        }
        XCTAssertThrowsError(try WidgetMarketAPI.validatedImageURL(insecure)) { error in
            XCTAssertEqual(error as? WidgetMarketError, .unapprovedImageURL)
        }
    }

    func testEmptyAssetSelectionDoesNotFallThroughToTopMarkets() {
        XCTAssertThrowsError(
            try WidgetMarketAPI.markets(query: .ids([" "]), currency: "usd")
        ) { error in
            XCTAssertEqual(error as? WidgetMarketError, .emptySelection)
        }
    }

    func testMarketClientUsesInjectedHTTPClient() async throws {
        let httpClient = WidgetHTTPClientStub(data: Self.responseData)
        let client = WidgetMarketClient(httpClient: httpClient)

        let assets = try await client.markets(query: .top(limit: 2), currency: "EUR")
        let targets = await httpClient.targets

        XCTAssertEqual(assets.map(\.id), ["ethereum", "bitcoin"])
        let target = try XCTUnwrap(targets.first)
        guard case .marketData(let query, let currency) = target else {
            return XCTFail("Expected a market-data target")
        }
        XCTAssertEqual(query, .top(limit: 2))
        XCTAssertEqual(currency, "eur")
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
        XCTAssertFalse(WidgetSharedStorage.hasStoredWatchlist(in: defaults))
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
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults
        )
        await defaultViewModel.load()

        XCTAssertEqual(defaultViewModel.selectedAssets.map(\.id), assets.prefix(5).map(\.id))
        XCTAssertTrue(WidgetSharedStorage.hasStoredWatchlist(in: defaults))

        WidgetSharedStorage.setWatchlistAssets([], in: defaults)
        let clearedViewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults
        )
        await clearedViewModel.load()

        XCTAssertTrue(clearedViewModel.selectedAssets.isEmpty)

        defaults.set(Data("not-json".utf8), forKey: WidgetSharedStorage.watchlistKey)
        let corruptViewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults
        )
        await corruptViewModel.load()

        XCTAssertEqual(corruptViewModel.selectedAssets.map(\.id), assets.prefix(5).map(\.id))
    }

    @MainActor
    func testWatchlistSettingsShowsCacheWhileRemoteRefreshIsInFlight() async throws {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let query = WidgetMarketQuery.catalog(limit: 50)
        let currency = WidgetSharedStorage.currencyCode
        let cachedAsset = marketAsset(id: "cached", symbol: "OLD")
        let freshAsset = marketAsset(id: "fresh", symbol: "NEW")
        try await cache.store(
            [cachedAsset],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            for: "\(currency.lowercased())-\(query.cacheKey)"
        )
        let remote = WidgetMarketGateStub(assets: [freshAsset])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            marketCache: cache,
            defaults: defaults
        )

        let loadTask = Task { await viewModel.load() }
        await remote.waitUntilStarted()
        for _ in 0..<100 where viewModel.assets.isEmpty {
            await Task.yield()
        }

        XCTAssertEqual(viewModel.assets.map(\.id), ["cached"])
        XCTAssertTrue(viewModel.selectedAssets.isEmpty)
        XCTAssertFalse(WidgetSharedStorage.hasStoredWatchlist(in: defaults))
        XCTAssertFalse(viewModel.isLoading)

        await remote.resume()
        await loadTask.value

        XCTAssertEqual(viewModel.assets.map(\.id), ["fresh"])
        XCTAssertEqual(viewModel.selectedAssets.map(\.id), ["fresh"])
        XCTAssertTrue(WidgetSharedStorage.hasStoredWatchlist(in: defaults))
        XCTAssertFalse(viewModel.loadFailed)
    }

    @MainActor
    func testWatchlistSettingsRetainsCachedAssetsWhenRefreshFails() async throws {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        WidgetSharedStorage.setWatchlistAssets([], in: defaults)

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let cache = WidgetMarketCache(fileURL: directory.appendingPathComponent("cache.json"))
        let query = WidgetMarketQuery.catalog(limit: 50)
        let currency = WidgetSharedStorage.currencyCode
        let cachedAsset = marketAsset(id: "cached", symbol: "OLD")
        try await cache.store(
            [cachedAsset],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            for: "\(currency.lowercased())-\(query.cacheKey)"
        )
        let remote = WidgetMarketRemoteStub()
        await remote.setShouldFail(true)
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            marketCache: cache,
            defaults: defaults
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.assets.map(\.id), ["cached"])
        XCTAssertTrue(viewModel.loadFailed)
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

    private func marketAsset(id: String, symbol: String) -> WidgetMarketAsset {
        WidgetMarketAsset(
            id: id,
            symbol: symbol,
            name: id.capitalized,
            imageURL: nil,
            iconData: nil,
            currentPrice: 1,
            priceChangePercentage24h: nil,
            marketCapRank: nil,
            sparkline: []
        )
    }

    private func requestParameters(from target: WidgetMarketAPI) throws -> [String: String] {
        guard case .requestParameters(let parameters, .urlEncoding) = target.task else {
            throw WidgetMarketError.invalidResponse
        }
        return parameters.mapValues { String(describing: $0) }
    }
}

private actor WidgetHTTPClientStub: HTTPClientProtocol {
    let data: Data
    private(set) var targets: [WidgetMarketAPI] = []

    init(data: Data) {
        self.data = data
    }

    func request(_ target: TargetType) throws -> HTTPResponse<Data> {
        guard let widgetTarget = target as? WidgetMarketAPI,
              let response = HTTPURLResponse(
                url: HTTPClient.url(for: target),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
              ) else {
            throw WidgetMarketError.invalidResponse
        }
        targets.append(widgetTarget)
        return HTTPResponse(data: data, response: response)
    }
}

private final class WidgetURLCapturingProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var storedURL: URL?

    static var capturedURL: URL? {
        lock.lock()
        defer { lock.unlock() }
        return storedURL
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        storedURL = nil
    }

    // swiftlint:disable static_over_final_class
    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    // swiftlint:enable static_over_final_class

    override func startLoading() {
        Self.lock.lock()
        Self.storedURL = request.url
        Self.lock.unlock()

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
              ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"coins":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
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

private actor WidgetMarketGateStub: WidgetMarketRemote {
    let assets: [WidgetMarketAsset]
    private var started = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(assets: [WidgetMarketAsset]) {
        self.assets = assets
    }

    func markets(query _: WidgetMarketQuery, currency _: String) async -> [WidgetMarketAsset] {
        started = true
        await withCheckedContinuation { continuation = $0 }
        return assets
    }

    func iconData(from _: URL) -> Data {
        Data()
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
