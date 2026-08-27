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

    private let marketClient: any WidgetMarketRemote
    private let defaults: UserDefaults?
    private var hasLoaded = false
    private var hasStoredSelection: Bool

    init(
        marketClient: any WidgetMarketRemote = WidgetMarketClient(),
        defaults: UserDefaults? = WidgetSharedStorage.defaults
    ) {
        self.marketClient = marketClient
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
        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            let marketAssets = try await marketClient.markets(
                query: .catalog(limit: 50),
                currency: WidgetSharedStorage.currencyCode
            )
            let fetched = marketAssets.map(WidgetWatchlistAsset.init)
            let fetchedByID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            let refreshedSelection = selectedAssets.map { fetchedByID[$0.id] ?? $0 }

            catalogAssets = fetched
            if !hasStoredSelection {
                selectedAssets = Array(fetched.prefix(WidgetSharedStorage.maximumWatchlistAssets))
                persistSelection(reloadWidget: true)
            } else if refreshedSelection != selectedAssets {
                selectedAssets = refreshedSelection
                persistSelection(reloadWidget: false)
            }
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
}
