//
//  WidgetWatchlistSettingsViewModel.swift
//  VultisigApp
//

import Foundation
import WidgetKit

@MainActor
final class WidgetWatchlistSettingsViewModel: ObservableObject {
    @Published private(set) var selectedAssets: [WidgetWatchlistAsset]
    @Published private(set) var catalogAssets: [WidgetWatchlistAsset] = []
    @Published var isLoading = false
    @Published private(set) var loadFailed = false

    private let marketService: WidgetMarketService
    private let defaults: UserDefaults?
    private var hasLoaded = false
    private var hasStoredSelection: Bool

    init(
        marketClient: any WidgetMarketRemote = WidgetMarketClient(),
        marketCache: WidgetMarketCache = WidgetMarketCache(),
        defaults: UserDefaults? = WidgetSharedStorage.defaults
    ) {
        self.marketService = WidgetMarketService(remote: marketClient, cache: marketCache)
        self.defaults = defaults
        self.selectedAssets = WidgetSharedStorage.watchlistAssets(in: defaults)
        self.hasStoredSelection = WidgetSharedStorage.hasStoredWatchlist(in: defaults)
    }

    var assets: [WidgetWatchlistAsset] {
        let catalogIDs = Set(catalogAssets.map(\.id))
        return selectedAssets.filter { !catalogIDs.contains($0.id) } + catalogAssets
    }

    var selectionCount: Int { selectedAssets.count }

    var canSelectMore: Bool {
        selectionCount < WidgetSharedStorage.maximumWatchlistAssets
    }

    func isSelected(_ asset: WidgetWatchlistAsset) -> Bool {
        selectedAssets.contains(where: { $0.id == asset.id })
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
        let fetchedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        let refreshedSelection = selectedAssets.map { fetchedByID[$0.id] ?? $0 }

        catalogAssets = fetched
        if seedDefaultSelection && !hasStoredSelection {
            selectedAssets = Array(fetched.prefix(WidgetSharedStorage.maximumWatchlistAssets))
            persistSelection(reloadWidget: true)
        } else if refreshedSelection != selectedAssets {
            selectedAssets = refreshedSelection
            persistSelection(reloadWidget: false)
        }
    }
}
