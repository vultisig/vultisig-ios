//
//  SettingsDefaultChainViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-07-25.
//

import SwiftUI

class SettingsDefaultChainViewModel: ObservableObject {
    @Published var searchText: String = ""
    @Published var filteredAssets = [CoinMeta]()
    @Published var baseChains = [CoinMeta]()
    @Published var showLoader: Bool = false
    
    @Published var defaultChains = [CoinMeta]()
    @AppStorage("savedDefaultChains") var savedDefaultChains: String = ""

    func setData(_ assets: [String: [CoinMeta]]) {
        baseChains = assets.values.compactMap({ value in
            value.first
        })
        resetData()
    }

    func resetData() {
        filteredAssets = baseChains
        defaultChains = []
        extractDefaultValues()
    }

    func extractDefaultValues() {
        let chains = savedDefaultChains.components(separatedBy: "$")

        for chain in chains {
            for baseChain in baseChains {
                if baseChain.chain.name == chain {
                    defaultChains.append(baseChain)
                }
            }
        }
    }

    func search() {
        guard !searchText.isEmpty else {
            resetData()
            return
        }

        filteredAssets = baseChains.filter { chain in
            chain.chain.name.lowercased().contains(searchText.lowercased()) ||
            chain.ticker.lowercased().contains(searchText.lowercased())
        }
    }

    func addChain(_ chain: CoinMeta) {
        savedDefaultChains = savedDefaultChains + chain.chain.name+"$"
        defaultChains.append(chain)
        print(savedDefaultChains)
        toggleLoader()
    }

    func removeChain(_ chain: CoinMeta) {
        savedDefaultChains = savedDefaultChains.replacingOccurrences(of: chain.chain.name+"$", with: "")

        for index in 0..<defaultChains.count {
            if defaultChains[index] == chain {
                defaultChains.remove(at: index)
                print(savedDefaultChains)
                toggleLoader()
                return
            }
        }
    }
    
    private func toggleLoader() {
        showLoader = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.showLoader = false
        }
    }
}
