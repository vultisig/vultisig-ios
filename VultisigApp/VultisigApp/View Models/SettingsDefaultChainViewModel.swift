//
//  SettingsDefaultChainViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

class SettingsDefaultChainViewModel: ObservableObject {
    @Published var filteredAssets: [CoinMeta] = []
    @Published var searchText: String = ""
    
    func setData(_ assets: [CoinMeta]) {
        filteredAssets = assets
    }
    
    func search(for keyword: String, within assets: [CoinMeta]) {
        guard !keyword.isEmpty else {
            setData(assets)
            return
        }
        
        filteredAssets = assets.filter {
            $0.chain.name.lowercased().contains(keyword.lowercased()) ||
            $0.ticker.lowercased().contains(keyword.lowercased())
        }
    }
}
