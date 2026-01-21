//
//  DefiSelectChainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation

@MainActor
class DefiSelectChainViewModel: ObservableObject {
    
    @Published var searchText: String = .empty
    @Published var selection = Set<Chain>()

    @Published var chains: [Chain] = []
    
    var filteredChains: [Chain] {
        if searchText.isEmpty {
            return chains.sorted(by: { $0.name < $1.name })
        } else {
            let assets = chains
                .filter { chain in
                    chain.name.lowercased().contains(searchText.lowercased())
                }
                .sorted(by: { $0.name < $1.name })
            
            return assets
        }
    }
    
    func setData(for vault: Vault) {
        setupChains()
        checkSelected(for: vault)
    }
    
    private func checkSelected(for vault: Vault) {
        // Filter Defi enabled chains for selection
        selection = Set(vault.defiChains)
    }
    
    private func setupChains() {
        chains = CoinAction.defiChains
            .sorted(by: { $0.name < $1.name })
    }

    func isSelected(asset: CoinMeta) -> Bool {
        return selection.contains(asset.chain)
    }

    func handleSelection(isSelected: Bool, chain: Chain) {
        if isSelected {
            selection.insert(chain)
        } else {
            selection.remove(chain)
        }
    }
    
    func save(for vault: Vault) async {
        do {
            let coinsMeta = TokensStore.TokenSelectionAssets
                .filter { $0.isNativeToken && selection.contains($0.chain) }
            
            let vaultCoinsMeta = vault.coins.map { $0.toCoinMeta() }
            // Enable chains that are not included in vault yet
            let vaultChainsToEnable: [CoinMeta] = coinsMeta.filter { !vaultCoinsMeta.contains($0) }
            
            // Enable chains on vault
            try await CoinService.addNewlySelectedCoins(vault: vault, selection: Set(vaultChainsToEnable))
            
            vault.defiChains = Array(selection)
                .filter { CoinAction.defiChains.contains($0) }
            
            try Storage.shared.save()
        } catch {
            print("Error while saving defi chains", error.localizedDescription)
        }
    }
}
