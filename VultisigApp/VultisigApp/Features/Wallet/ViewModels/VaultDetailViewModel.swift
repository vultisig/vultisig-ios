//
//  VaultDetailViewModel.swift
//  VultisigApp
//
//  Created by Amol Kumar on 2024-03-09.
//

import Foundation
import SwiftUI

class VaultDetailViewModel: ObservableObject {
    @Published var selectedChain: Chain? = nil
    @Published var chains = [Chain]()
    @Published var searchText: String = ""
    @Published var vaultBanners: [VaultBannerType] = []

    private let logic = VaultDetailLogic()
    private var updateBalanceTask: Task<Void, Never>?
    // Identity tracker for the vault `chains` was last sorted against. Used to
    // re-seed `chains` synchronously when `updateBalance(vault:)` is called
    // against a different vault than the cached list belongs to — the
    // vault-switch case. Without this, the `chains.isEmpty` guard below skips
    // the synchronous seed and the user sees the previous vault's chain list
    // until the async refresh lands (~250ms debounce + network round trip).
    private var chainsVaultPubKeyECDSA: String?

    @AppStorage("appClosedBanners") private var appClosedBanners: [String] = []

    func filteredChains(in vault: Vault) -> [Chain] {
        logic.filteredChains(searchText: searchText, chains: chains, vault: vault)
    }

    var availableActions: [CoinAction] {
        [.swap, .send, .buy, .receive].filtered
    }

    func updateBalance(vault: Vault) {
        // Seed `chains` synchronously when the cached list is empty (first
        // call) OR when the cached list was sorted against a different vault
        // than the one we're now refreshing — the vault-switch case. The
        // same-vault refresh path (post-swap, balance cascade) still skips
        // the seed, leaving the existing order in place until the async sort
        // below replaces it. That preserves the fix for the "stale-then-fresh"
        // double reorder while ensuring the list flips instantly on a vault
        // identity flip instead of waiting on the debounce + fetch window.
        if chains.isEmpty || chainsVaultPubKeyECDSA != vault.pubKeyECDSA {
            chains = logic.sortedChains(vault: vault)
            chainsVaultPubKeyECDSA = vault.pubKeyECDSA
        }

        updateBalanceTask?.cancel()
        updateBalanceTask = Task { [weak self] in
            // Leading debounce — `refresh()` fires from ~6 entry points
            // (onLoad, vault switch, shouldRefresh, vault.coins count change,
            // throttledOnAppear, pull-to-refresh). Post-swap they can stack
            // 2–3 deep within a second; without this sleep each call kicks
            // off a full price + per-coin balance refresh and the resulting
            // reorders are visible as flicker.
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let updated = await self.logic.updateBalance(vault: vault)
            if !Task.isCancelled {
                await MainActor.run {
                    self.chains = updated
                    self.chainsVaultPubKeyECDSA = vault.pubKeyECDSA
                }
            }
        }
    }

    func groupChains(vault: Vault) {
        chains = logic.sortedChains(vault: vault)
        chainsVaultPubKeyECDSA = vault.pubKeyECDSA
    }

    func getGroupAsync(_ viewModel: CoinSelectionViewModel) {
        let currentChains = chains
        Task { @MainActor in
            selectedChain = await logic.preferredChain(chains: currentChains, viewModel: viewModel)
        }
    }

    func setupBanners(for vault: Vault) {
        vaultBanners = logic.setupBanners(for: vault, appClosedBanners: appClosedBanners)
    }

    @MainActor
    func removeBanner(for vault: Vault, banner: VaultBannerType) {
        guard !banner.isAppBanner else {
            appClosedBanners.append(banner.rawValue)
            setupBanners(for: vault)
            return
        }

        vault.closedBanners = Array(Set(vault.closedBanners + [banner.rawValue]))
        do {
            try Storage.shared.save()
            setupBanners(for: vault)
        } catch {
            print("Error while saving closedBanners for vault", error.localizedDescription)
        }
    }

    func canShowChainSelection(vault: Vault) -> Bool {
        // Vault cannot change chains for KeyImport for now
        vault.libType != .KeyImport
    }
}

// MARK: - VaultDetailLogic

struct VaultDetailLogic {
    private let balanceService = BalanceService.shared

    func filteredChains(searchText: String, chains: [Chain], vault: Vault) -> [Chain] {
        guard !searchText.isEmpty else {
            return chains
        }
        return chains.filter { chain in
            let nameMatches = chain.name.localizedCaseInsensitiveContains(searchText)
            let tickerMatches = vault.nativeCoin(for: chain)?.ticker
                .localizedCaseInsensitiveContains(searchText) ?? false
            return nameMatches || tickerMatches
        }
    }

    func updateBalance(vault: Vault) async -> [Chain] {
        await balanceService.updateBalances(vault: vault)
        return await MainActor.run { sortedChains(vault: vault) }
    }

    func sortedChains(vault: Vault) -> [Chain] {
        sortedChains(
            chains: vault.chainsWithCoins,
            value: { vault.coins(for: $0).totalBalanceInFiatDecimal }
        )
    }

    func preferredChain(chains: [Chain], viewModel: CoinSelectionViewModel) async -> Chain? {
        for chain in chains {
            let actions = await viewModel.actionResolver.resolveActions(for: chain)
            if actions.contains(.swap) {
                return chain
            }
        }
        return chains.first
    }

    func setupBanners(for vault: Vault, appClosedBanners: [String]) -> [VaultBannerType] {
        return VaultBannerType.allCases
            .filter { banner in
                if banner.isAppBanner && appClosedBanners.contains(banner.rawValue) {
                    return false
                } else if vault.closedBanners.contains(banner.rawValue) {
                    return false
                }

                switch banner {
                case .backupVault:
                    return !vault.isBackedUp
                case .upgradeVault:
                    return vault.libType == .GG20
                case .buyVult:
                    return true
                case .followVultisig:
                    return true
                }
            }
    }

    func sortedChains<T: Comparable>(
        chains: [Chain],
        ascending: Bool = false,
        value: (Chain) -> T
    ) -> [Chain] {
        chains.sorted { lhs, rhs in
            let lhsValue = value(lhs)
            let rhsValue = value(rhs)
            if lhsValue == rhsValue {
                return lhs.index < rhs.index
            }
            return ascending ? lhsValue < rhsValue : lhsValue > rhsValue
        }
    }
}
