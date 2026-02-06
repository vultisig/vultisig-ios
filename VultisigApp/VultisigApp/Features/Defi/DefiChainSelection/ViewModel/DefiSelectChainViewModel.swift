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
    @Published var isCircleEnabled: Bool = true
    
    /// Indicates if Ethereum is available in the vault (required for Circle)
    private var hasEthereum: Bool = false

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
    
    /// Returns true if Circle should be visible (vault has Ethereum and matches search filter)
    var shouldShowCircle: Bool {
        // Circle requires Ethereum chain in the vault
        guard hasEthereum else { return false }
        
        guard !searchText.isEmpty else { return true }
        let circleTitle = NSLocalizedString("circleTitle", comment: "Circle")
        return circleTitle.lowercased().contains(searchText.lowercased()) ||
               "usdc".contains(searchText.lowercased())
    }

    func setData(for vault: Vault) {
        setupChains(for: vault)
        checkSelected(for: vault)
    }

    private func checkSelected(for vault: Vault) {
        // Filter Defi enabled chains for selection
        selection = Set(vault.defiChains)
        isCircleEnabled = vault.isCircleEnabled
    }

    private func setupChains(for vault: Vault) {
        chains = vault.availableDefiChains
            .sorted(by: { $0.name < $1.name })
        
        // Check if vault has Ethereum (required for Circle)
        hasEthereum = vault.chains.contains(.ethereum)
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
    
    func handleCircleSelection(isSelected: Bool) {
        isCircleEnabled = isSelected
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
            
            // Save Circle enabled state
            vault.isCircleEnabled = isCircleEnabled

            try Storage.shared.save()
        } catch {
            print("Error while saving defi chains", error.localizedDescription)
        }
    }
}

