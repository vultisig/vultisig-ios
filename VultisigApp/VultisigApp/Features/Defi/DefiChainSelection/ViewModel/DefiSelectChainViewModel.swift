//
//  DefiSelectChainViewModel.swift
//  VultisigApp
//
//  Created by Gaston Mazzeo on 16/10/2025.
//

import Foundation
import OSLog

private let logger = Logger(subsystem: "com.vultisig.app", category: "defi-select-chain")

@MainActor
class DefiSelectChainViewModel: ObservableObject {

    @Published var searchText: String = .empty
    @Published var selection = Set<Chain>()
    /// Yield providers enabled in this sheet (committed to the vault on save).
    @Published var enabledProviders = Set<DefiYieldProviderID>()
    @Published var chains: [Chain] = []

    /// Providers eligible for this vault (Ethereum present + account provisioned),
    /// recomputed in `setData`; `visibleProviders` applies the search filter.
    @Published private var eligibleProviders: [DefiYieldProviderID] = []

    var filteredChains: [Chain] {
        if searchText.isEmpty {
            return chains.sorted(by: { $0.name < $1.name })
        } else {
            return chains
                .filter { $0.name.lowercased().contains(searchText.lowercased()) }
                .sorted(by: { $0.name < $1.name })
        }
    }

    /// Eligible yield providers matching the current search text.
    var visibleProviders: [DefiYieldProviderID] {
        eligibleProviders.filter { matchesSearch($0) }
    }

    func isEnabled(_ id: DefiYieldProviderID) -> Bool {
        enabledProviders.contains(id)
    }

    func setEnabled(_ id: DefiYieldProviderID, _ isOn: Bool) {
        if isOn {
            enabledProviders.insert(id)
        } else {
            enabledProviders.remove(id)
        }
    }

    func setData(for vault: Vault) {
        setupChains(for: vault)
        checkSelected(for: vault)
    }

    private func checkSelected(for vault: Vault) {
        selection = Set(vault.defiChains)
        enabledProviders = Set(DefiYieldProviderID.allCases.filter { vault.isDefiProviderEnabled($0) })
    }

    private func setupChains(for vault: Vault) {
        chains = vault.availableDefiChains.sorted(by: { $0.name < $1.name })

        // A yield provider is eligible when the vault has Ethereum and the
        // provider's account is provisioned (account-less providers always are).
        let hasEthereum = vault.chains.contains(.ethereum)
        eligibleProviders = DefiYieldProviderID.allCases.filter { id in
            hasEthereum && DefiYieldProviderFactory.make(id).isAccountProvisioned(vault: vault)
        }
    }

    func isSelected(asset: CoinMeta) -> Bool {
        selection.contains(asset.chain)
    }

    func handleSelection(isSelected: Bool, chain: Chain) {
        if isSelected {
            selection.insert(chain)
        } else {
            selection.remove(chain)
        }
    }

    func save(for vault: Vault) async throws {
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

            // Persist each yield provider's enabled state into the provider array.
            for id in DefiYieldProviderID.allCases {
                vault.setDefiProvider(id, enabled: enabledProviders.contains(id))
            }

            try Storage.shared.save()
        } catch {
            // Surface the failure so the caller can keep the sheet open instead of
            // silently dropping the user's chain / provider toggle changes.
            logger.error("Error while saving defi chains: \(error.localizedDescription)")
            throw error
        }
    }

    private func matchesSearch(_ id: DefiYieldProviderID) -> Bool {
        guard !searchText.isEmpty else { return true }
        let name = DefiYieldProviderFactory.make(id).presentation.providerNameKey.localized
        return name.localizedCaseInsensitiveContains(searchText)
            || "usdc".localizedCaseInsensitiveContains(searchText)
    }
}
