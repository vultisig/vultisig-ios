//
//  AssetSelectionListViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import OSLog
import SwiftUI

/// Throwing on purpose: a data source that flattens a failed fetch to `[]` is
/// indistinguishable from one reporting that the user holds nothing, and every
/// screen downstream then disables itself with nothing on it to explain why.
protocol AssetSelectionDataSource {
    func fetchAssets() async throws -> [THORChainAsset]
}

class AssetSelectionListViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    /// Distinguishes "the fetch failed" from "there is nothing to show", which
    /// the list renders as two different messages.
    @Published private(set) var didFailToLoad: Bool = false
    @Published private var assets: [THORChainAsset] = []
    private let dataSource: AssetSelectionDataSource

    var filteredAssets: [THORChainAsset] {
        guard searchText.isNotEmpty else { return assets }
        return assets.filter { $0.asset.ticker.localizedCaseInsensitiveContains(searchText) }
    }

    init(dataSource: AssetSelectionDataSource) {
        self.dataSource = dataSource
    }

    func setup() async {
        await MainActor.run {
            isLoading = true
            didFailToLoad = false
        }
        do {
            let assets = try await dataSource.fetchAssets()
            await MainActor.run {
                self.assets = assets
                isLoading = false
            }
        } catch {
            Log.send.viewModel.error("Error fetching selectable assets: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.assets = []
                didFailToLoad = true
                isLoading = false
            }
        }
    }
}
