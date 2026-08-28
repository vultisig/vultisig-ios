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

    /// When true, MLDSA-backed chains (e.g. QBTC) are visible in the list even
    /// if the vault has no MLDSA key yet. Callers handle the keygen prompt
    /// before the user can actually persist the chain.
    var showMldsaChainsWithoutKey: Bool = false

    func setData(for vault: Vault, checkForSelected: Bool = true) {
        if checkForSelected {
            checkSelected(for: vault)
        } else {
            selection = []
        }
        groupAssets(vault: vault)
    }

    func requiresQuantumKeygen(for asset: CoinMeta, vault: Vault) -> Bool {
        guard asset.chain.signingKeyType == .MLDSA else { return false }
        // Defense-in-depth: with QBTC gated out of `filteredChains`, MLDSA
        // assets cannot reach this code path with the flag off. Guarding
        // here too means a future code path that hands an MLDSA asset
        // straight to the keygen prompt still respects the feature flag.
        guard QBTCConfig.isFeatureEnabled else { return false }
        return vault.publicKeyMLDSA44 == nil || vault.publicKeyMLDSA44?.isEmpty == true
    }

    private func checkSelected(for vault: Vault) {
        selection = Set(vault.coins.map { $0.toCoinMeta() })
    }

    private func groupAssets(vault: Vault) {
        // Curated tokens now come through the catalog's bundled provider rather
        // than reading `TokensStore.TokenSelectionAssets` directly, so the preset
        // list and its chain-visibility gates (sepolia / thorchain-chainnet /
        // QBTC-MLDSA, plus the Sepolia-native injection) live in one place.
        // The vault-specific MLDSA-key gate stays here because the provider is
        // vault-independent: QBTC (the only MLDSA chain today) is hidden unless
        // the feature flag is on AND the vault has an MLDSA key (or the caller
        // opted into showing it before keygen).
        let defaults = UserDefaults.standard
        let hasMLDSAKey = !(vault.publicKeyMLDSA44 ?? "").isEmpty

        let filteredAssets: [CoinMeta] = Chain.supportedCases.flatMap { chain -> [CoinMeta] in
            if chain.signingKeyType == .MLDSA, !(hasMLDSAKey || showMldsaChainsWithoutKey) {
                return []
            }
            return BundledTokensProvider.curatedTokens(for: chain, defaults: defaults)
        }

        groupedAssets = Dictionary(grouping: filteredAssets.sorted(by: { first, _ in
            first.isNativeToken
        })) { $0.chain }
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
                .filter { vault.availableChains.contains($0) }
        case .send:
            return filteredChains
                .filter { vault.chains.contains($0) }
        }
    }
}
