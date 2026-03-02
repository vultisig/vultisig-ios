//
//  TokenSelectionViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-11.
//

import Foundation

class CoinSelectionViewModel: ObservableObject {

    @Published var groupedAssets: [Chain: [CoinMeta]] = [:]
    @Published var searchText: String = .empty
    @Published var selection = Set<CoinMeta>()

    var chains: [Chain] {
        groupedAssets
            .map { $0.key }
            .sorted(by: { $0.name < $1.name })
    }

    var filteredChains: [Chain] {
        if searchText.isEmpty {
            return groupedAssets.keys.sorted(by: { $0.name < $1.name })
        } else {
            let assets = groupedAssets
                .filter { (chain, tokens) in
                    chain.name.lowercased().contains(searchText.lowercased()) ||
                    tokens.contains { $0.ticker.lowercased().contains(searchText.lowercased()) }
                }
                .map { $0.key }
                .sorted(by: { $0.name < $1.name })

            return assets
        }
    }

    let actionResolver = CoinActionResolver()
    let balanceService = BalanceService.shared

    func loadData(coin: Coin) async {
        await balanceService.updateBalance(for: coin)
    }

    func setData(for vault: Vault, checkForSelected: Bool = true) {
        if checkForSelected {
            checkSelected(for: vault)
        } else {
            selection = []
        }
        groupAssets()
    }

    private func checkSelected(for vault: Vault) {
        selection = Set(vault.coins.map { $0.toCoinMeta() })
    }

    private func groupAssets() {
        groupedAssets = [:]

        // Filter out Sepolia and Thorchain Stagenet based on settings
        let enableETHSepolia = UserDefaults.standard.bool(forKey: "sepolia")
        let enableThorchainChainnet = UserDefaults.standard.bool(forKey: "thorchainChainnet")

        let filteredAssets = TokensStore.TokenSelectionAssets.filter { asset in
            if asset.chain == .ethereumSepolia {
                return enableETHSepolia
            }
            if asset.chain == .thorChainChainnet {
                return enableThorchainChainnet
            }
            if asset.chain == .thorChainStagenet {
                return enableThorchainChainnet
            }
            return true
        }

        groupedAssets = Dictionary(grouping: filteredAssets.sorted(by: { first, _ in
            if first.isNativeToken {
                return true
            }
            return false
        })) { $0.chain }

        // Add Sepolia if enabled (it's not in TokenSelectionAssets)
        if enableETHSepolia {
            groupedAssets[TokensStore.Token.ethSepolia.chain] = [TokensStore.Token.ethSepolia]
        }
    }

    func isSelected(asset: CoinMeta) -> Bool {
        return selection.contains(asset)
    }

    func handleSelection(isSelected: Bool, asset: CoinMeta) {
        if isSelected {
            selection.insert(asset)
        } else {
            // If removing a native token, also remove all tokens from that chain
            if asset.isNativeToken {
                let tokensToRemove = selection.filter { $0.chain == asset.chain }
                for token in tokensToRemove {
                    selection.remove(token)
                }
            } else {
                selection.remove(asset)
            }
        }
    }

    func filterChains(type: ChainFilterType, vault: Vault) -> [Chain] {
        switch type {
        case .swap:
            return filteredChains
                .filter(\.isSwapAvailable)
                .filter { vault.chains.contains($0) }
        case .send:
            return filteredChains
                .filter { vault.chains.contains($0) }
        }
    }
}
