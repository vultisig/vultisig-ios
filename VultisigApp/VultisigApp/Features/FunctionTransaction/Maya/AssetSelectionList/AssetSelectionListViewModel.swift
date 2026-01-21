//
//  AssetSelectionListViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 24/11/2025.
//

import SwiftUI

protocol AssetSelectionDataSource {
    func fetchAssets() async -> [THORChainAsset]
}

class AssetSelectionListViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
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
        await MainActor.run { isLoading = true }
        let assets = await dataSource.fetchAssets()
        await MainActor.run { self.assets = assets }
        await MainActor.run { isLoading = false }
    }
}
