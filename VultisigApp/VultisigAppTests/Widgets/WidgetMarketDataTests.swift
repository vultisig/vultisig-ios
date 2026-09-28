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

    func testSearchResponseDecodesValidatedThumbnailURLAndRejectsUnsafeURL() async throws {
        let data = Data(#"""
        {
          "coins": [
            {
              "id": "akash-network",
              "symbol": "akt",
              "name": "Akash Network",
              "thumb": "https://coin-images.coingecko.com/coins/images/12785/thumb/akash-logo.png",
              "large": "https://coin-images.coingecko.com/coins/images/12785/large/akash-logo.png"
            },
            {
              "id": "fallback-large",
              "symbol": "safe",
              "name": "Fallback Large",
              "thumb": "http://coin-images.coingecko.com/coins/images/2/thumb/unsafe.png",
              "large": "https://coin-images.coingecko.com/coins/images/2/large/safe.png"
            },
            {
              "id": "unsafe-coin",
              "symbol": "bad",
              "name": "Unsafe Coin",
              "thumb": "http://coin-images.coingecko.com/coins/images/1/thumb/bad.png"
            }
          ]
        }
        """#.utf8)
        let client = WidgetMarketClient(httpClient: WidgetHTTPClientStub(data: data))

        let assets = try await client.searchAssets(matching: "akash")

        XCTAssertEqual(assets.first?.id, "akash-network")
        XCTAssertEqual(
            assets.first?.imageURL?.absoluteString,
            "https://coin-images.coingecko.com/coins/images/12785/thumb/akash-logo.png"
        )
        XCTAssertEqual(
            assets[1].imageURL?.absoluteString,
            "https://coin-images.coingecko.com/coins/images/2/large/safe.png"
        )
        XCTAssertNil(assets.last?.imageURL)
    }

    func testIconURLAcceptsHTTPSHostsAndRejectsInsecureURLs() throws {
        let approved = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")
        )
        let otherHost = try XCTUnwrap(URL(string: "https://example.com/bitcoin.png"))
        let unapproved = try XCTUnwrap(URL(string: "https://user:password@example.com/bitcoin.png"))
        let insecure = try XCTUnwrap(
            URL(string: "http://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")
        )

        XCTAssertEqual(try WidgetMarketAPI.validatedImageURL(approved), approved)
        XCTAssertEqual(try WidgetMarketAPI.validatedImageURL(otherHost), otherHost)
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

    func testLocalWatchlistCatalogIncludesNativeRune() {
        XCTAssertTrue(LocalWidgetWatchlistCatalog.assets.contains { asset in
            asset.id == "thorchain" && asset.symbol == "RUNE"
        })
        XCTAssertEqual(LocalWidgetWatchlistCatalog.logo(for: "thorchain"), "rune")
    }

    func testLocalWatchlistCatalogDeduplicatesByCoinGeckoID() {
        let assets = LocalWidgetWatchlistCatalog.assets(from: [
            coinMeta(chain: .ethereum, ticker: "ETH", priceProviderId: "ethereum"),
            coinMeta(chain: .base, ticker: "ETH", priceProviderId: "ethereum")
        ])

        XCTAssertEqual(assets.map(\.id), ["ethereum"])
        XCTAssertEqual(assets.map(\.symbol), ["ETH"])
    }

    func testLocalWatchlistCatalogExcludesEmptyPriceIDsAndNonProductionNetworks() {
        let assets = LocalWidgetWatchlistCatalog.assets(from: [
            coinMeta(chain: .ethereum, ticker: "NOPE", priceProviderId: ""),
            coinMeta(chain: .ethereumSepolia, ticker: "ETH", priceProviderId: "ethereum"),
            coinMeta(chain: .thorChainStagenet, ticker: "RUNE", priceProviderId: "thorchain"),
            coinMeta(chain: .thorChainChainnet, ticker: "RUNE", priceProviderId: "thorchain"),
            coinMeta(chain: .thorChain, ticker: "RUNE", priceProviderId: "thorchain")
        ])

        XCTAssertEqual(assets.map(\.id), ["thorchain"])
    }

    func testLocalWatchlistCatalogReportsLogoByCoinGeckoIDWithoutMutatingSharedMeta() {
        let metas = [
            coinMeta(chain: .thorChain, ticker: "RUNE", priceProviderId: "thorchain")
        ]
        let assets = LocalWidgetWatchlistCatalog.assets(from: metas)

        XCTAssertEqual(assets.first?.imageURL, nil)
        XCTAssertEqual(LocalWidgetWatchlistCatalog.logo(for: "thorchain", in: metas), "rune")
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
        XCTAssertFalse(defaultViewModel.selectedAssets.contains { $0.id == "thorchain" })
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
    func testWatchlistSettingsPrefersLocalRuneRowWhenRemoteMarketDuplicatesID() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let imageURL = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/6595/large/rune.png")
        )
        let remote = WidgetMarketListStub(assets: [
            marketAsset(id: "thorchain", symbol: "REMOTE", imageURL: imageURL)
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults
        )

        await viewModel.load()
        let rune = try XCTUnwrap(viewModel.assets.first { $0.id == "thorchain" })

        XCTAssertEqual(rune.symbol, "RUNE")
        XCTAssertNil(rune.imageURL)
        XCTAssertEqual(viewModel.iconLogo(for: rune), "rune")
        XCTAssertEqual(viewModel.selectedAssets.map(\.id), ["thorchain"])
        XCTAssertEqual(viewModel.selectedAssets.first?.imageURL, imageURL)
    }

    @MainActor
    func testWatchlistSettingsUsesRemoteURLForRemoteOnlyTopMarket() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let imageURL = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/1234/large/remote.png")
        )
        let remote = WidgetMarketListStub(assets: [
            marketAsset(id: "remote-only-token", symbol: "ROT", imageURL: imageURL)
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults
        )

        await viewModel.load()
        let asset = try XCTUnwrap(viewModel.assets.first { $0.id == "remote-only-token" })

        XCTAssertEqual(asset.imageURL, imageURL)
        XCTAssertEqual(viewModel.iconLogo(for: asset), imageURL.absoluteString)
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

        XCTAssertEqual(viewModel.assets.first?.id, "cached")
        XCTAssertTrue(viewModel.assets.contains { $0.id == "thorchain" })
        XCTAssertTrue(viewModel.selectedAssets.isEmpty)
        XCTAssertFalse(WidgetSharedStorage.hasStoredWatchlist(in: defaults))
        XCTAssertFalse(viewModel.isLoading)

        await remote.resume()
        await loadTask.value

        XCTAssertEqual(viewModel.assets.first?.id, "fresh")
        XCTAssertTrue(viewModel.assets.contains { $0.id == "thorchain" })
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

        XCTAssertEqual(viewModel.assets.first?.id, "cached")
        XCTAssertTrue(viewModel.assets.contains { $0.id == "thorchain" })
        XCTAssertTrue(viewModel.loadFailed)
    }

    @MainActor
    func testWatchlistSearchFiltersLocalFirstAndDeduplicatesRemoteResults() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [
            marketAsset(id: "ethereum", symbol: "ETH"),
            marketAsset(id: "bitcoin", symbol: "BTC")
        ])
        let remoteOnlyURL = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/12345/thumb/ether-fi.png")
        )
        let duplicateURL = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/1027/thumb/ethereum.png")
        )
        let search = WidgetMarketSearchStub(results: [
            "eth": [
                WidgetAssetIdentity(id: "ethereum", symbol: "ETH", name: "Ethereum", imageURL: duplicateURL),
                WidgetAssetIdentity(id: "ether-fi", symbol: "ETHFI", name: "ether.fi", imageURL: remoteOnlyURL)
            ]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "eth"
        await waitForSearchToFinish(viewModel)

        XCTAssertEqual(viewModel.filteredAssets.first?.id, "ethereum")
        XCTAssertEqual(viewModel.filteredAssets.filter { $0.id == "ethereum" }.count, 1)
        let remoteOnly = try XCTUnwrap(viewModel.filteredAssets.first { $0.id == "ether-fi" })
        XCTAssertEqual(remoteOnly.imageURL, remoteOnlyURL)
        XCTAssertEqual(viewModel.iconLogo(for: remoteOnly), remoteOnlyURL.absoluteString)
    }

    @MainActor
    func testWatchlistSearchPrefersLocalRuneOverDuplicateRemoteResult() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let imageURL = try XCTUnwrap(
            URL(string: "https://coin-images.coingecko.com/coins/images/6595/thumb/rune.png")
        )
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchStub(results: [
            "rune": [WidgetAssetIdentity(id: "thorchain", symbol: "REMOTE", name: "Remote Rune", imageURL: imageURL)]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "rune"
        await waitForSearchToFinish(viewModel)
        let rune = try XCTUnwrap(viewModel.filteredAssets.first { $0.id == "thorchain" })

        XCTAssertEqual(viewModel.filteredAssets.filter { $0.id == "thorchain" }.count, 1)
        XCTAssertEqual(rune.symbol, "RUNE")
        XCTAssertNil(rune.imageURL)
        XCTAssertEqual(viewModel.iconLogo(for: rune), "rune")
    }

    @MainActor
    func testWatchlistSearchIgnoresStaleCancelledResponses() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchGateStub(results: [
            "old": [WidgetAssetIdentity(id: "old-coin", symbol: "OLD", name: "Old Coin")],
            "new": [WidgetAssetIdentity(id: "new-coin", symbol: "NEW", name: "New Coin")]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "old"
        await search.waitUntilStarted("old")
        viewModel.searchText = "new"
        await search.waitUntilStarted("new")
        await search.resume("new")
        await waitForSearchToFinish(viewModel)
        await search.resume("old")
        await Task.yield()

        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["new-coin"])
    }

    @MainActor
    func testWatchlistSearchRetainsMatchingRemoteResultWhileShorterQueryIsPending() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchGateStub(results: [
            "plughcoin": [WidgetAssetIdentity(id: "plughcoin-token", symbol: "PLUGHCOIN", name: "Plughcoin Token")],
            "plugh": [WidgetAssetIdentity(id: "plughcoin-token", symbol: "PLUGHCOIN", name: "Plughcoin Token")]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "plughcoin"
        await search.waitUntilStarted("plughcoin")
        await search.resume("plughcoin")
        await waitForSearchToFinish(viewModel)

        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["plughcoin-token"])

        viewModel.searchText = "plugh"
        await search.waitUntilStarted("plugh")

        XCTAssertTrue(viewModel.isSearching)
        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["plughcoin-token"])

        await search.resume("plugh")
        await waitForSearchToFinish(viewModel)
    }

    @MainActor
    func testWatchlistSearchHidesUnrelatedRemoteResultWhileDivergentQueryIsPending() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchGateStub(results: [
            "plugh": [WidgetAssetIdentity(id: "plugh-token", symbol: "PLUGH", name: "Plugh Token")],
            "zzz": [WidgetAssetIdentity(id: "zebra-coin", symbol: "ZZZ", name: "Zebra Coin")]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "plugh"
        await search.waitUntilStarted("plugh")
        await search.resume("plugh")
        await waitForSearchToFinish(viewModel)

        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["plugh-token"])

        viewModel.searchText = "zzz"
        await search.waitUntilStarted("zzz")

        XCTAssertTrue(viewModel.isSearching)
        XCTAssertFalse(viewModel.filteredAssets.contains { $0.id == "plugh-token" })
        XCTAssertTrue(viewModel.filteredAssets.isEmpty)

        await search.resume("zzz")
        await waitForSearchToFinish(viewModel)

        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["zebra-coin"])
    }

    @MainActor
    func testWatchlistSearchClearsRemoteResultsForEmptyQueryAndFinalEmptyResponse() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchGateStub(results: [
            "plugh": [WidgetAssetIdentity(id: "plugh-token", symbol: "PLUGH", name: "Plugh Token")],
            "zzzz": []
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "plugh"
        await search.waitUntilStarted("plugh")
        await search.resume("plugh")
        await waitForSearchToFinish(viewModel)

        XCTAssertEqual(viewModel.filteredAssets.map(\.id), ["plugh-token"])

        viewModel.searchText = ""

        XCTAssertEqual(viewModel.filteredAssets.first?.id, "bitcoin")
        XCTAssertFalse(viewModel.filteredAssets.contains { $0.id == "plugh-token" })
        XCTAssertFalse(viewModel.isSearching)

        viewModel.searchText = "zzzz"
        await search.waitUntilStarted("zzzz")
        await search.resume("zzzz")
        await waitForSearchToFinish(viewModel)

        XCTAssertTrue(viewModel.filteredAssets.isEmpty)
        XCTAssertFalse(viewModel.searchFailed)
        XCTAssertFalse(viewModel.isSearching)
    }

    @MainActor
    func testWatchlistSearchKeepsOfflineLocalResults() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchStub(error: URLError(.notConnectedToInternet))
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "bit"
        await waitForSearchToFinish(viewModel)

        XCTAssertEqual(viewModel.filteredAssets.first?.id, "bitcoin")
        XCTAssertTrue(viewModel.searchFailed)
    }

    @MainActor
    func testWatchlistSearchReportsEmptySuccessfulResults() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchStub(results: ["zzzz": []])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "zzzz"
        await waitForSearchToFinish(viewModel)

        XCTAssertTrue(viewModel.filteredAssets.isEmpty)
        XCTAssertFalse(viewModel.searchFailed)
    }

    @MainActor
    func testWatchlistSearchPersistsSelectedRemoteIdentityWithoutPrice() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        WidgetSharedStorage.setWatchlistAssets([], in: defaults)
        let remote = WidgetMarketListStub(assets: [marketAsset(id: "bitcoin", symbol: "BTC")])
        let search = WidgetMarketSearchStub(results: [
            "aka": [WidgetAssetIdentity(id: "akash-network", symbol: "AKT", name: "Akash Network")]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "aka"
        await waitForSearchToFinish(viewModel)
        let asset = try XCTUnwrap(viewModel.filteredAssets.first)
        viewModel.setSelected(true, asset: asset)
        viewModel.searchText = ""

        XCTAssertEqual(viewModel.selectedAssets.map(\.id), ["akash-network"])
        XCTAssertEqual(WidgetSharedStorage.watchlistAssets(in: defaults).map(\.id), ["akash-network"])
        XCTAssertTrue(viewModel.assets.contains { $0.id == "akash-network" })
    }

    @MainActor
    func testWatchlistSearchRespectsFiveSelectionCapForRemoteResults() async throws {
        let (suiteName, defaults) = try temporaryDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let assets = (1...5).map { marketAsset(id: "asset-\($0)", symbol: "A\($0)") }
        let remote = WidgetMarketListStub(assets: assets)
        let search = WidgetMarketSearchStub(results: [
            "six": [WidgetAssetIdentity(id: "asset-six", symbol: "SIX", name: "Asset Six")]
        ])
        let viewModel = WidgetWatchlistSettingsViewModel(
            marketClient: remote,
            searchClient: search,
            marketCache: WidgetMarketCache(fileURL: nil),
            defaults: defaults,
            searchDebounceNanoseconds: 0
        )

        await viewModel.load()
        viewModel.searchText = "six"
        await waitForSearchToFinish(viewModel)
        let asset = try XCTUnwrap(viewModel.filteredAssets.first)
        viewModel.setSelected(true, asset: asset)

        XCTAssertEqual(viewModel.selectedAssets.map(\.id), assets.map(\.id))
        XCTAssertFalse(viewModel.canSelectMore)
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

    @MainActor
    private func waitForSearchToFinish(_ viewModel: WidgetWatchlistSettingsViewModel) async {
        for _ in 0..<100 where viewModel.isSearching {
            await Task.yield()
        }
    }

    private func temporaryDefaults() throws -> (String, UserDefaults) {
        let suiteName = "WidgetMarketDataTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (suiteName, defaults)
    }

    private func watchlistAsset(id: String, symbol: String) -> WidgetWatchlistAsset {
        WidgetWatchlistAsset(id: id, symbol: symbol, name: id.capitalized, imageURL: nil)
    }

    private func coinMeta(
        chain: Chain,
        ticker: String,
        priceProviderId: String,
        isNativeToken: Bool = true
    ) -> CoinMeta {
        CoinMeta(
            chain: chain,
            ticker: ticker,
            logo: ticker.lowercased(),
            decimals: 8,
            priceProviderId: priceProviderId,
            contractAddress: isNativeToken ? "" : "contract-\(ticker.lowercased())",
            isNativeToken: isNativeToken
        )
    }

    private func marketAsset(id: String, symbol: String, imageURL: URL? = nil) -> WidgetMarketAsset {
        WidgetMarketAsset(
            id: id,
            symbol: symbol,
            name: id.capitalized,
            imageURL: imageURL,
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

private actor WidgetMarketSearchStub: WidgetAssetSearching {
    private let results: [String: [WidgetAssetIdentity]]
    private let error: Error?

    init(results: [String: [WidgetAssetIdentity]] = [:], error: Error? = nil) {
        self.results = results
        self.error = error
    }

    func searchAssets(matching query: String) async throws -> [WidgetAssetIdentity] {
        await Task.yield()
        if let error { throw error }
        return results[query.lowercased()] ?? []
    }
}

private actor WidgetMarketSearchGateStub: WidgetAssetSearching {
    private let results: [String: [WidgetAssetIdentity]]
    private var startedQueries: Set<String> = []
    private var continuations: [String: CheckedContinuation<Void, Never>] = [:]

    init(results: [String: [WidgetAssetIdentity]]) {
        self.results = results
    }

    func searchAssets(matching query: String) async throws -> [WidgetAssetIdentity] {
        let normalized = query.lowercased()
        startedQueries.insert(normalized)
        await withCheckedContinuation { continuation in
            continuations[normalized] = continuation
        }
        return results[normalized] ?? []
    }

    func waitUntilStarted(_ query: String) async {
        while !startedQueries.contains(query.lowercased()) {
            await Task.yield()
        }
    }

    func resume(_ query: String) {
        let normalized = query.lowercased()
        continuations[normalized]?.resume()
        continuations[normalized] = nil
    }
}
