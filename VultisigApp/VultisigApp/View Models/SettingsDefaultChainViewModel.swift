//
//  SettingsDefaultChainViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-18.
//

import SwiftUI

class SettingsDefaultChainViewModel: ObservableObject {
    @Published var filteredAssets: [String: [CoinMeta]] = [:]
    @Published var searchText: String = ""
    
    func setData(_ assets: [String: [CoinMeta]]) {
        filteredAssets = assets
    }
    
    func search(_ assets: [String: [CoinMeta]]) {
        guard !searchText.isEmpty else {
            setData(assets)
            return
        }
        
        filteredAssets = assets.filter { (key, coinMetaList) in
            let asset = coinMetaList.first
            return asset?.chain.name.lowercased().contains(searchText.lowercased()) ?? true ||
            asset?.ticker.lowercased().contains(searchText.lowercased()) ?? true
        }
    }
}
