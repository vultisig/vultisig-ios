//
//  PreferredAssetSelectionViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 06/08/2025.
//

import SwiftUI

class PreferredAssetSelectionViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published private var assets: [THORChainAsset] = []
    private let thorchainService: THORChainAPIService

    var filteredAssets: [THORChainAsset] {
        guard searchText.isNotEmpty else { return assets }
        return assets.filter { $0.asset.ticker.localizedCaseInsensitiveContains(searchText) }
    }

    init(thorchainService: THORChainAPIService = .init()) {
        self.thorchainService = thorchainService
    }

    func setup() async {
        await MainActor.run { isLoading = true }
        do {
            let pools = try await thorchainService.getPools()
            let assets: [THORChainAsset] = pools.compactMap { pool -> THORChainAsset? in
                PreferredAssetFactory.createCoin(from: pool.asset, decimals: pool.decimals)
            }

            await MainActor.run { self.assets = assets }
        } catch {
            // Will show empty state
            print("No pools found: \(error)")
        }
        await MainActor.run { isLoading = false }
    }
}
