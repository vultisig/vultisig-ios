//
//  WidgetWatchlistSettingsViewModel.swift
//  VultisigApp
//

import Foundation
import WidgetKit

@MainActor
final class WidgetWatchlistSettingsViewModel: ObservableObject {
    @Published private(set) var selectedAssets: [WidgetWatchlistAsset]
    @Published private(set) var catalogAssets: [WidgetWatchlistAsset]
    @Published private(set) var isSearching = false
    @Published private(set) var searchFailed = false
    @Published var isLoading = false
    @Published var searchText = "" {
        didSet { searchTextDidChange() }
    }
    @Published private(set) var loadFailed = false

    private let marketService: WidgetMarketService
    private let searchClient: (any WidgetAssetSearching)?
    private let defaults: UserDefaults?
    private let searchDebounceNanoseconds: UInt64
    private var remoteSearchAssets: [WidgetWatchlistAsset] = []
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = 0
    private var hasLoaded = false
    private var hasStoredSelection: Bool

    init(
        marketClient: any WidgetMarketRemote = WidgetMarketClient(),
        searchClient: (any WidgetAssetSearching)? = nil,
        marketCache: WidgetMarketCache = WidgetMarketCache(),
        defaults: UserDefaults? = WidgetSharedStorage.defaults,
        searchDebounceNanoseconds: UInt64 = 300_000_000
    ) {
        self.marketService = WidgetMarketService(remote: marketClient, cache: marketCache)
        self.searchClient = searchClient ?? (marketClient as? any WidgetAssetSearching)
        self.defaults = defaults
        self.searchDebounceNanoseconds = searchDebounceNanoseconds
        self.selectedAssets = WidgetSharedStorage.watchlistAssets(in: defaults)
        self.catalogAssets = LocalWidgetWatchlistCatalog.assets
        self.hasStoredSelection = WidgetSharedStorage.hasStoredWatchlist(in: defaults)
    }

    deinit {
        searchTask?.cancel()
    }

    var assets: [WidgetWatchlistAsset] {
        let catalogIDs = Set(catalogAssets.map(\.id))
        return selectedAssets.filter { !catalogIDs.contains($0.id) } + catalogAssets
    }

    var filteredAssets: [WidgetWatchlistAsset] {
        let query = normalizedSearchText
        guard !query.isEmpty else { return assets }

        let localMatches = assets.filter { $0.matchesSearch(query) }
        let remoteMatches = remoteSearchAssets.filter { $0.matchesSearch(query) }
        return mergedAssets(localMatches + remoteMatches)
    }

    var selectionCount: Int { selectedAssets.count }

    var canSelectMore: Bool {
        selectionCount < WidgetSharedStorage.maximumWatchlistAssets
    }

    func isSelected(_ asset: WidgetWatchlistAsset) -> Bool {
        selectedAssets.contains(where: { $0.id == asset.id })
    }

    func iconLogo(for asset: WidgetWatchlistAsset) -> String {
        LocalWidgetWatchlistCatalog.logo(for: asset.id) ?? asset.iconLogo
    }

    func load(force: Bool = false) async {
        guard force || !hasLoaded else { return }
        hasLoaded = true
        let query = WidgetMarketQuery.catalog(limit: 50)
        let currency = WidgetSharedStorage.currencyCode

        isLoading = assets.isEmpty
        loadFailed = false
        defer { isLoading = false }

        async let cachedResult = marketService.cachedResult(query: query, currency: currency)
        async let refreshedResult = marketService.load(
            query: query,
            currency: currency,
            downloadsIcons: false
        )

        if let cachedResult = await cachedResult {
            apply(cachedResult.assets, seedDefaultSelection: false)
            isLoading = false
        }

        do {
            let refreshedResult = try await refreshedResult
            apply(
                refreshedResult.assets,
                seedDefaultSelection: !refreshedResult.isStale
            )
            loadFailed = refreshedResult.isStale
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            loadFailed = true
        }
    }

    func setSelected(_ selected: Bool, asset: WidgetWatchlistAsset) {
        if selected {
            guard !isSelected(asset), canSelectMore else { return }
            selectedAssets.append(asset)
        } else {
            selectedAssets.removeAll(where: { $0.id == asset.id })
        }

        persistSelection(reloadWidget: true)
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func searchTextDidChange() {
        searchGeneration += 1
        let generation = searchGeneration
        let query = normalizedSearchText
        searchTask?.cancel()
        searchFailed = false

        guard !query.isEmpty else {
            remoteSearchAssets = []
            isSearching = false
            return
        }

        guard let searchClient else {
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task { [weak self, searchDebounceNanoseconds] in
            if searchDebounceNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: searchDebounceNanoseconds)
            }
            guard !Task.isCancelled else { return }
            await self?.performRemoteSearch(
                query: query,
                generation: generation,
                searchClient: searchClient
            )
        }
    }

    private func performRemoteSearch(
        query: String,
        generation: Int,
        searchClient: any WidgetAssetSearching
    ) async {
        do {
            let identities = try await searchClient.searchAssets(matching: query)
            guard generation == searchGeneration, query == normalizedSearchText else { return }
            remoteSearchAssets = identities.map { WidgetWatchlistAsset(identity: $0) }
            searchFailed = false
            isSearching = false
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard generation == searchGeneration, query == normalizedSearchText else { return }
            remoteSearchAssets = []
            searchFailed = true
            isSearching = false
        }
    }

    private func persistSelection(reloadWidget: Bool) {
        WidgetSharedStorage.setWatchlistAssets(selectedAssets, in: defaults)
        hasStoredSelection = true
        guard reloadWidget else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedStorage.watchlistWidgetKind)
    }

    private func apply(
        _ marketAssets: [WidgetMarketAsset],
        seedDefaultSelection: Bool
    ) {
        let fetched = marketAssets.map(WidgetWatchlistAsset.init)
        let catalog = mergedMarketCatalog(fetched: fetched, local: LocalWidgetWatchlistCatalog.assets)
        let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
        let refreshedSelection = selectedAssets.map { catalogByID[$0.id] ?? $0 }

        catalogAssets = catalog
        if seedDefaultSelection && !hasStoredSelection {
            selectedAssets = Array(fetched.prefix(WidgetSharedStorage.maximumWatchlistAssets))
            persistSelection(reloadWidget: true)
        } else if refreshedSelection != selectedAssets {
            selectedAssets = refreshedSelection
            persistSelection(reloadWidget: false)
        }
    }

    private func mergedMarketCatalog(
        fetched: [WidgetWatchlistAsset],
        local: [WidgetWatchlistAsset]
    ) -> [WidgetWatchlistAsset] {
        let localByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        let fetchedIDs = Set(fetched.map(\.id))
        let mergedFetched = fetched.map { localByID[$0.id] ?? $0 }
        let localOnly = local.filter { !fetchedIDs.contains($0.id) }
        return mergedAssets(mergedFetched + localOnly)
    }

    private func mergedAssets(_ assets: [WidgetWatchlistAsset]) -> [WidgetWatchlistAsset] {
        assets.reduce(into: [WidgetWatchlistAsset]()) { result, asset in
            guard !result.contains(where: { $0.id == asset.id }) else { return }
            result.append(asset)
        }
    }
}

private extension WidgetWatchlistAsset {
    init(identity: WidgetAssetIdentity) {
        self.init(
            id: identity.id.lowercased(),
            symbol: identity.symbol.uppercased(),
            name: identity.name,
            imageURL: identity.imageURL
        )
    }

    func matchesSearch(_ query: String) -> Bool {
        id.localizedCaseInsensitiveContains(query) ||
            symbol.localizedCaseInsensitiveContains(query) ||
            name.localizedCaseInsensitiveContains(query)
    }
}
